# R/promote_primitives.R
# Promotion v2: primitives-first
#
# - Uses .wb_ops() as the sole op contract
# - Uses run$outputs (wb_primitive) as the sole source of promotable data
# - No .wb_op_spec(), no .wb_op_registry(), no saveable_outputs registry
#
# Output names are the run output names: clusters, pseudotime, curves, space_2d, model, ...
# Artifact type is determined from primitive kind.
# ---- mapping: primitive kind -> promoter function ----
# Keep this small. This is your "promotion kernel".
.wb_promoters_by_kind <- function() {
  list(
    cell_vector         = .wb_promote_cell_vector,
    cell_vector_family  = .wb_promote_cell_vector_family,
    relation_family     = .wb_promote_relation_family,
    path_2d_family      = .wb_promote_path_2d_family,
    space_path_family   = .wb_promote_space_path_family,
    space_2d            = .wb_promote_space_2d_ref,
    model_ref           = .wb_promote_model_ref,
    feature_table       = .wb_promote_feature_table,
    obs_table           = .wb_promote_obs_table
  )
}

.wb_get_promoter_for_kind <- function(kind) {
  regs <- .wb_promoters_by_kind()
  fn <- regs[[kind]]
  .wb_assert(!is.null(fn), paste0("No promoter registered for primitive kind: ", kind))
  fn
}

.wb_db_append_chunked <- function(con, table, df, chunk_size = 1000L) {
  if (is.null(df) || nrow(df) == 0) return(invisible(TRUE))
  chunk_size <- as.integer(chunk_size)
  .wb_assert(chunk_size >= 1L, "chunk_size must be >= 1")

  fields <- names(df)
  quote_ident <- function(x) paste0('"', gsub('"', '""', x, fixed = TRUE), '"')
  sql <- paste0("INSERT INTO ", quote_ident(table), " (", paste(vapply(fields, quote_ident, character(1)), collapse = ", "), ") VALUES (", paste(rep("?", length(fields)), collapse = ", "), ");")
  stmt <- DBI::dbSendStatement(con, sql)
  on.exit(DBI::dbClearResult(stmt), add = TRUE)
  for (i in seq_len(nrow(df))) DBI::dbBind(stmt, unname(as.list(df[i, fields, drop = FALSE])))
  invisible(TRUE)
}

.wb_artifact_lineage_statuses <- function(bundle, promoted_df, snapshot_id) {
  con <- bundle$con
  sid <- as.character(snapshot_id %||% "")[1]
  if (!nzchar(sid) || !is.data.frame(promoted_df) || !nrow(promoted_df)) {
    return(data.frame(
      artifact_id = character(0),
      lineage_status = character(0),
      parent_run_count = integer(0),
      parent_run_promoted_count = integer(0),
      stringsAsFactors = FALSE
    ))
  }

  ok <- promoted_df[
    as.character(promoted_df$status %||% "") == "ok" &
      !is.na(promoted_df$artifact_id %||% NA_character_) &
      nzchar(as.character(promoted_df$artifact_id %||% "")),
    ,
    drop = FALSE
  ]
  if (!nrow(ok)) {
    return(data.frame(
      artifact_id = character(0),
      lineage_status = character(0),
      parent_run_count = integer(0),
      parent_run_promoted_count = integer(0),
      stringsAsFactors = FALSE
    ))
  }

  edges <- DBI::dbGetQuery(
    con,
    "SELECT child_run_id, parent_run_id
     FROM prov_run_edges
     WHERE snapshot_id = ?
       AND edge_type IN ('depends_on_run','input_run_ref');",
    params = list(sid)
  )
  if (!nrow(edges)) {
    out <- data.frame(
      artifact_id = as.character(ok$artifact_id),
      lineage_status = rep("complete", nrow(ok)),
      parent_run_count = integer(nrow(ok)),
      parent_run_promoted_count = integer(nrow(ok)),
      stringsAsFactors = FALSE
    )
    return(out)
  }

  parent_map <- split(as.character(edges$parent_run_id), as.character(edges$child_run_id))
  parent_map <- lapply(parent_map, function(x) unique(x[nzchar(x)]))

  out_rows <- vector("list", nrow(ok))
  for (i in seq_len(nrow(ok))) {
    rid <- as.character(ok$run_id[i] %||% "")[1]
    aid <- as.character(ok$artifact_id[i] %||% "")[1]

    # Artifact must link back to a prov_run_outputs row in this snapshot.
    has_link <- DBI::dbGetQuery(
      con,
      "SELECT COUNT(*) AS n
       FROM prov_run_outputs
       WHERE snapshot_id = ? AND run_id = ? AND artifact_id = ?;",
      params = list(sid, rid, aid)
    )$n[[1]] %||% 0L

    parents <- unique(as.character(parent_map[[rid]] %||% character(0)))
    parents <- parents[nzchar(parents)]
    n_par <- length(parents)

    n_parent_promoted <- 0L
    if (n_par > 0L) {
      qmarks <- paste(rep("?", n_par), collapse = ",")
      qq <- paste0(
        "SELECT COUNT(DISTINCT run_id) AS n
         FROM prov_run_outputs
         WHERE snapshot_id = ?
           AND run_id IN (", qmarks, ")
           AND artifact_id IS NOT NULL
           AND artifact_id <> '';"
      )
      n_parent_promoted <- DBI::dbGetQuery(
        con, qq, params = c(list(sid), as.list(parents))
      )$n[[1]] %||% 0L
      n_parent_promoted <- as.integer(n_parent_promoted)
    }

    n_parent_persisted <- 0L
    if (n_par > 0L) {
      qmarks <- paste(rep("?", n_par), collapse = ",")
      n_parent_persisted <- DBI::dbGetQuery(
        con,
        paste0("SELECT COUNT(DISTINCT run_id) AS n FROM prov_runs WHERE snapshot_id = ? AND run_id IN (", qmarks, ");"),
        params = c(list(sid), as.list(parents))
      )$n[[1]] %||% 0L
    }

    status <- if (!isTRUE(as.integer(has_link) >= 1L)) {
      "detached"
    } else if (n_par == 0L) {
      "complete"
    } else if (n_parent_persisted >= n_par) {
      "complete"
    } else {
      "detached"
    }

    out_rows[[i]] <- data.frame(
      artifact_id = aid,
      lineage_status = as.character(status),
      parent_run_count = as.integer(n_par),
      parent_run_promoted_count = as.integer(n_parent_promoted),
      stringsAsFactors = FALSE
    )
  }

  out <- do.call(rbind, out_rows)
  rownames(out) <- NULL
  out
}

.wb_artifacts_apply_lineage_status <- function(bundle, lineage_df, snapshot_id) {
  con <- bundle$con
  sid <- as.character(snapshot_id %||% "")[1]
  if (!nzchar(sid) || !is.data.frame(lineage_df) || !nrow(lineage_df)) return(invisible(NULL))

  if (!.wb_db_has_column(con, "artifacts", "provenance_snapshot_id")) {
    DBI::dbExecute(con, "ALTER TABLE artifacts ADD COLUMN provenance_snapshot_id TEXT;")
  }
  if (!.wb_db_has_column(con, "artifacts", "lineage_status")) {
    DBI::dbExecute(con, "ALTER TABLE artifacts ADD COLUMN lineage_status TEXT;")
  }

  for (i in seq_len(nrow(lineage_df))) {
    DBI::dbExecute(
      con,
      "UPDATE artifacts
       SET provenance_snapshot_id = ?,
           lineage_status = ?
       WHERE artifact_id = ?;",
      params = list(
        sid,
        as.character(lineage_df$lineage_status[i] %||% NA_character_),
        as.character(lineage_df$artifact_id[i])
      )
    )
  }
  invisible(TRUE)
}

# ---- New promotion entrypoint: promote analysis DAG from runs ----
#' Promote a Session Analysis DAG to Persisted Artifacts
#'
#' Persists promotable outputs from the selected run heads and their ancestors,
#' then records a provenance snapshot. Promotion writes artifact payloads only
#' through registered primitive promoters.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param runs Named list of `wb_run` objects, or a list that can be named by
#'   their `run_id` fields.
#' @param head_run_id One or more run ids to promote as snapshot heads.
#' @param name_prefix Optional prefix for generated artifact names.
#' @param description Optional shared artifact description.
#' @param created_by Optional actor label recorded in artifacts and provenance.
#' @param fail_fast If `TRUE`, stop on the first failed output promotion.
#' @param allow_detached If `TRUE`, allow promotion of runs whose parent lineage
#'   is not fully present in `runs`.
#' @param outputs Optional terminal output names to expose as public artifacts.
#'   Ancestor outputs are committed as internal provenance materializations.
#' @param selected_by_run Internal run-to-terminal selection map used by
#'   [wb_session_promote_current()] for run-qualified selectors.
#' @param staging_bundle Optional session-local bundle overlay containing staged
#'   matrix/space payloads produced by `runs`.
#'
#' @return A data frame with promoted artifact ids, per-output status, and the
#'   persisted provenance `snapshot_id`.
#' @export
wb_promote_analysis <- function(bundle,
                                runs,
                                head_run_id,
                                name_prefix = NULL,
                                description = NULL,
                                created_by = NULL,
                                fail_fast = TRUE,
                                allow_detached = FALSE,
                                outputs = NULL,
                                selected_by_run = NULL,
                                staging_bundle = NULL) {
  .wb_assert_bundle_writable(bundle, "promotion")
  .wb_with_bundle_writer_lock(bundle, operation = "analysis promotion", code = {
    .wb_promote_analysis_locked(
      bundle = bundle, runs = runs, head_run_id = head_run_id,
      name_prefix = name_prefix, description = description, created_by = created_by,
      fail_fast = fail_fast, allow_detached = allow_detached, outputs = outputs,
      selected_by_run = selected_by_run, staging_bundle = staging_bundle
    )
  })
}

.wb_promote_analysis_locked <- function(bundle,
                                        runs,
                                        head_run_id,
                                        name_prefix = NULL,
                                        description = NULL,
                                        created_by = NULL,
                                        fail_fast = TRUE,
                                        allow_detached = FALSE,
                                        outputs = NULL,
                                        selected_by_run = NULL,
                                        staging_bundle = NULL,
                                        target_reproduction_receipts = NULL) {
  .wb_assert_bundle_writable(bundle, "promotion")
  wb_migrate_artifacts(bundle)

  .wb_assert(is.list(runs) && length(runs) > 0, "runs must be a non-empty list.")
  # ensure named by run_id
  if (is.null(names(runs)) || any(names(runs) == "")) {
    ids <- vapply(runs, function(r) r$run_id, character(1))
    names(runs) <- ids
  }
  .wb_assert(all(vapply(runs, wb_is_run, logical(1))), "runs must contain wb_run objects.")
  heads <- as.character(head_run_id)
  .wb_assert(length(heads) >= 1, "head_run_id must have length >= 1.")
  .wb_assert(all(heads %in% names(runs)), "One or more head_run_id not in runs.")

  # topo order by DFS postorder
  visited <- new.env(parent = emptyenv())
  topo <- character(0)
  visit <- function(rid) {
    if (exists(rid, envir = visited, inherits = FALSE)) return(invisible(TRUE))
    assign(rid, TRUE, envir = visited)
    run <- runs[[rid]]
    parents <- run$inputs$parents %||% character(0)
    for (p in parents) visit(p)
    topo <<- c(topo, rid)
    invisible(TRUE)
  }
  for (h in heads) visit(h)

  available <- unique(unlist(lapply(heads, function(rid) {
    op <- .wb_get_op(runs[[rid]]$op_name)
    intersect(as.character(op$promotable %||% character(0)), names(runs[[rid]]$outputs %||% list()))
  }), use.names = FALSE))
  selected_outputs <- as.character(outputs %||% character(0))
  if (!length(selected_outputs)) {
    # Low-level callers historically promote all outputs from the selected head.
    # This remains head-local; ancestor outputs are never selected implicitly.
    selected_outputs <- available
  }
  .wb_assert(all(selected_outputs %in% available),
             paste0("Requested outputs are not promotable terminal outputs: ",
                    paste(setdiff(selected_outputs, available), collapse = ", ")))

  commit_id <- .wb_promotion_commit_id(bundle$con)
  runtime_fingerprint <- .wb_promotion_runtime_fingerprint()
  .wb_migrate_provenance_tables(bundle$con)
  workspace <- .wb_promotion_workspace_new(bundle, commit_id)
  workspace$target_reproduction_atomicity <-
    !is.null(target_reproduction_receipts)
  materializations <- tryCatch({
    if (!is.null(staging_bundle)) {
      .wb_operation_pack_v2_prepare_transition_payloads(
        staging_bundle, bundle, workspace, runs, topo)
      prepared_materializations <- .wb_stage_prepare_materializations(
        staging_bundle, bundle, workspace, runs, topo, commit_id)
      prepared_materializations
    } else {
      .wb_prepare_materialization_payloads(workspace, runs, topo, commit_id)
    }
  }, error = function(e) {
    .wb_promotion_workspace_cleanup(workspace)
    stop(e)
  })

  transaction_open <- FALSE
  promotion_error <- NULL
  on.exit({
    if (transaction_open) try(DBI::dbRollback(bundle$con), silent = TRUE)
    if (!is.null(promotion_error)) .wb_promotion_workspace_cleanup(workspace)
  }, add = TRUE)
  DBI::dbBegin(bundle$con)
  transaction_open <- TRUE
  tryCatch({
    DBI::dbExecute(
      bundle$con,
      "INSERT INTO prov_commits(commit_id, created_at, created_by, state, selected_outputs_json, runtime_fingerprint_json, error_message)
       VALUES(?, ?, ?, ?, ?, ?, ?);",
      params = list(
        commit_id, format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), created_by %||% NA_character_, "pending",
        jsonlite::toJSON(selected_outputs, auto_unbox = FALSE),
        jsonlite::toJSON(runtime_fingerprint, auto_unbox = TRUE, null = "null"), NA_character_
      )
    )
    if (!is.null(staging_bundle)) {
      committed_space_ids <- if (.wb_table_exists(bundle$con, "spaces")) {
        as.character(DBI::dbGetQuery(bundle$con, "SELECT space_id FROM spaces;")$space_id)
      } else character(0)
      copied_new_space_ids <- character(0)
      for (rid in topo) {
        if (.wb_run_is_committed(bundle, rid)) next
        for (prim in unname(runs[[rid]]$outputs %||% list())) {
          if (.wb_is_primitive(prim) && identical(prim$kind, "matrix"))
            .wb_stage_commit_matrix(staging_bundle, bundle, prim$matrix_id,
              prim = prim, workspace = workspace)
          if (.wb_is_primitive(prim) && prim$kind %in% c("space", "space_2d")) {
            space_id <- as.character(prim$space_id)[1]
            if (space_id %in% committed_space_ids || !space_id %in% copied_new_space_ids) {
              .wb_stage_commit_space(staging_bundle, bundle, space_id, prim = prim,
                                     workspace = workspace)
              if (!space_id %in% committed_space_ids) copied_new_space_ids <- c(copied_new_space_ids, space_id)
            }
          }
        }
      }
      registry_events <- .wb_replay_registry_mutations(
        staging_bundle, bundle, topo, commit_id)
      if (is.data.frame(registry_events) && nrow(registry_events) &&
          any(as.character(registry_events$registry_type) ==
            "operation_pack_cell_set_family")) {
        .wb_operation_pack_registry_fault(
          "after_sqlite_writes_before_commit", commit_id = commit_id)
      }
    }

  # Artifact pool: lets downstream promotions reference upstream artifacts if they want
  # (most primitive promoters won't need it, but keep it for provenance)
  artifact_pool <- list()
  promoted_by_run <- list()

  rows <- list()
  row_i <- 0L

  for (rid in topo) {
    run <- runs[[rid]]
    op <- .wb_get_op(run$op_name)

    # Only explicitly selected terminal outputs become public artifacts.
    desired <- if (!is.null(selected_by_run)) selected_by_run[[rid]] %||% character(0) else selected_outputs
    promotable <- if (rid %in% heads) intersect(op$promotable %||% character(0), desired) else character(0)

    # promote each promotable output that exists on the run
    promoted_ids <- list()
    err <- NULL
    parent_artifacts <- list()
    for (parent_run_id in unique(as.character(run$inputs$parents %||% character(0)))) {
      parent_artifacts <- c(parent_artifacts, promoted_by_run[[parent_run_id]] %||% list())
    }

    tryCatch({
      for (out_name in promotable) {
        if (!out_name %in% names(run$outputs)) next

        prim <- run$outputs[[out_name]]
        .wb_assert(.wb_is_primitive(prim),
                   paste0("Run output '", out_name, "' is not a wb_primitive (kind missing)."))

        nm <- .wb_default_artifact_name(
          run = run,
          out_name = out_name,
          prim = prim,
          name_prefix = name_prefix
        )

        promoter <- .wb_get_promoter_for_kind(prim$kind)

        # Each promoter returns an artifact_id
        artifact_id <- promoter(
          bundle = bundle,
          run = run,
          out_name = out_name,
          prim = prim,
          name = nm,
          description = description,
          created_by = created_by,
          parent_artifacts = parent_artifacts,
          workspace = workspace
        )

        if (identical(as.character(prim$kind)[1], "relation_family") &&
            !is.null(staging_bundle)) {
          .wb_operation_pack_v2_fault("relation_family_promoted",
            output = out_name, artifact_id = artifact_id)
          .wb_operation_pack_v3_rf_promoted_assert(bundle, staging_bundle,
            run, out_name, artifact_id)
        }

        promoted_ids[[out_name]] <- artifact_id
      }
    }, error = function(e) {
      err <<- conditionMessage(e)
      if (isTRUE(fail_fast)) stop(e)
    })

    if (length(promoted_ids)) {
      # update pool so later promotions can reference earlier ones
      for (k in names(promoted_ids)) {
        if (is.null(artifact_pool[[k]]) || !nzchar(artifact_pool[[k]])) {
          artifact_pool[[k]] <- promoted_ids[[k]]
        }
      }
      promoted_by_run[[rid]] <- promoted_ids

      for (out_name in names(promoted_ids)) {
        row_i <- row_i + 1L
        rows[[row_i]] <- data.frame(
          run_id = run$run_id,
          op_name = run$op_name,
          output = out_name,
          artifact_id = as.character(promoted_ids[[out_name]]),
          status = "ok",
          error = NA_character_,
          stringsAsFactors = FALSE
        )
      }
    } else {
      row_i <- row_i + 1L
      rows[[row_i]] <- data.frame(
        run_id = run$run_id,
        op_name = run$op_name,
        output = "",
        artifact_id = NA_character_,
        status = if (is.null(err)) "skipped" else "error",
        error = if (is.null(err)) NA_character_ else err,
        stringsAsFactors = FALSE
      )
    }
  }

  promoted_df <- do.call(rbind, rows)
  snapshot_id <- .wb_prov_write_snapshot(
    bundle = bundle,
    runs = runs,
    topo = topo,
    heads = heads,
    promoted_df = promoted_df,
    name_prefix = name_prefix,
    description = description,
    created_by = created_by,
    commit_id = commit_id,
    materializations = materializations,
    runtime_fingerprint = runtime_fingerprint,
    workspace = workspace,
    staging_bundle = staging_bundle,
    transaction_open = TRUE
  )
  DBI::dbExecute(bundle$con, "UPDATE prov_commits SET state = ? WHERE commit_id = ?;", params = list("complete", commit_id))
  promoted_df$snapshot_id <- snapshot_id

  lineage_df <- .wb_artifact_lineage_statuses(bundle, promoted_df = promoted_df, snapshot_id = snapshot_id)
  .wb_artifacts_apply_lineage_status(bundle, lineage_df = lineage_df, snapshot_id = snapshot_id)
  if (nrow(lineage_df)) {
    promoted_df$..row_ix_tmp <- seq_len(nrow(promoted_df))
    promoted_df <- merge(promoted_df, lineage_df, by = "artifact_id", all.x = TRUE, sort = FALSE)
    promoted_df <- promoted_df[order(promoted_df$..row_ix_tmp), , drop = FALSE]
    promoted_df$..row_ix_tmp <- NULL
    rownames(promoted_df) <- NULL
  }

  if (!isTRUE(allow_detached)) {
    bad <- promoted_df[
      as.character(promoted_df$status %||% "") == "ok" &
        as.character(promoted_df$lineage_status %||% "") == "detached",
      ,
      drop = FALSE
    ]
    if (nrow(bad)) {
      labs <- paste0(
        as.character(bad$artifact_id),
        " (run=", as.character(bad$run_id %||% ""), ", output=", as.character(bad$output %||% ""), ")"
      )
      stop(
        "Promotion blocked: detached artifact lineage detected for ",
        nrow(bad), " artifact(s): ",
        paste(utils::head(labs, 10L), collapse = "; "),
        if (nrow(bad) > 10L) " ..." else "",
        ". This indicates unreconstructable lineage. Set allow_detached=TRUE only for expert/dev debugging.",
        call. = FALSE
      )
    }
  }

  atomic_verification <- NULL
  if (!is.null(target_reproduction_receipts)) {
    atomic_verification <- .wb_target_reproduction_receipts_persist(
      bundle = bundle, receipts = target_reproduction_receipts,
      promoted_df = promoted_df, snapshot_id = snapshot_id
    )
  }

  .wb_promotion_workspace_publish(workspace)
  .wb_promotion_transaction_fault(
    "after_payload_move_before_database_commit", commit_id = commit_id,
    workspace = workspace)
  if (!is.null(target_reproduction_receipts)) {
    .wb_target_reproduction_atomicity_hook(
      "after_receipt_insertions_before_sqlite_commit",
      snapshot_id = snapshot_id, workspace = workspace
    )
  }
  DBI::dbCommit(bundle$con)
  transaction_open <- FALSE
  .wb_promotion_workspace_retire(workspace)
  if (dir.exists(workspace$pending_root)) unlink(workspace$pending_root, recursive = TRUE, force = TRUE)
  # Publish authoritative current state only after the scientific-state
  # transaction and payload workspace have both committed.
  .wb_refresh_manifest_committed(bundle)

  list(
    artifact_pool = artifact_pool,
    promoted = promoted_df,
    provenance_snapshot_id = snapshot_id,
    target_reproduction_verification = atomic_verification
  )
  }, error = function(e) {
    promotion_error <<- e
    stop(e)
  })
}

# ------------------------------------------------------------------
# Primitive promoters
# ------------------------------------------------------------------

.wb_new_artifact_id <- function(prefix, bundle = NULL) {
  con <- if (is.null(bundle)) NULL else bundle$con
  .wb_allocate_db_identifier(
    con, "artifacts", "artifact_id",
    paste0(prefix, "_", format(Sys.time(), "%Y%m%d_%H%M%S"), "_"),
    n = 8L, purpose = "artifact"
  )
}

.wb_name_nonempty <- function(x) {
  x <- as.character(x %||% "")[1]
  if (nzchar(x)) x else NULL
}

.wb_name_group_label <- function(x) {
  if (is.null(x)) return(NULL)
  if (is.character(x) && length(x) == 1) return(.wb_name_nonempty(x))
  if (is.list(x) && !is.null(x$ref_type)) {
    if (identical(as.character(x$ref_type)[1], "run")) {
      rid <- .wb_name_nonempty(x$run_id)
      out <- .wb_name_nonempty(x$output)
      if (!is.null(rid) && !is.null(out)) return(paste0("run:", substr(rid, 1, 8), "/", out))
    }
    if (identical(as.character(x$ref_type)[1], "artifact")) {
      aid <- .wb_name_nonempty(x$artifact_id)
      out <- .wb_name_nonempty(x$output)
      if (!is.null(aid) && !is.null(out)) return(paste0("artifact:", substr(aid, 1, 8), "/", out))
    }
  }
  if (is.atomic(x)) {
    n <- length(x)
    if (n == 1L) return(as.character(x)[1])
    return(paste0(n, " ids"))
  }
  NULL
}

.wb_title_compose <- function(..., max_chars = 96L) {
  parts <- unlist(list(...), use.names = FALSE)
  parts <- as.character(parts)
  parts <- parts[nzchar(parts)]
  if (!length(parts)) return(NULL)
  txt <- paste(parts, collapse = " ")
  max_chars <- as.integer(max_chars %||% 96L)
  if (is.finite(max_chars) && nchar(txt, type = "chars") > max_chars) {
    txt <- paste0(substr(txt, 1L, max_chars - 1L), "...")
  }
  txt
}

.wb_default_artifact_name <- function(run, out_name, prim, name_prefix = NULL) {
  prefix <- .wb_name_nonempty(name_prefix)
  params <- run$params %||% list()
  user_inputs <- run$inputs$user_inputs %||% list()
  op_name <- as.character(run$op_name %||% "")[1]
  display_op_name <- sub("^.*::", "", op_name)
  out_name <- as.character(out_name %||% "")[1]

  matrix_id <- .wb_name_nonempty(params$matrix_id %||% user_inputs$matrix %||% user_inputs$matrix_id)
  fit_space_id <- .wb_name_nonempty(params$fit_space_id %||% user_inputs$fit_space %||% user_inputs$fit_space_id)
  plot_space_id <- .wb_name_nonempty(params$plot_space_id %||% user_inputs$plot_space %||% user_inputs$plot_space_id)
  space_id <- .wb_name_nonempty(params$space_id %||% user_inputs$space %||% user_inputs$space_id)
  feature_set <- .wb_name_nonempty(params$feature_set %||% user_inputs$feature_set)
  namespace <- .wb_name_nonempty(params$namespace %||% user_inputs$namespace)
  group_a <- .wb_name_group_label(params$group_a %||% user_inputs$group_a)
  group_b <- .wb_name_group_label(params$group_b %||% user_inputs$group_b)
  n_lineages <- suppressWarnings(as.integer(params$n_lineages %||% params$n_lineages_input %||% NA_integer_))

  base <- switch(
    display_op_name,
    de_wilcox = .wb_title_compose("DE:", group_a %||% "A", "vs", group_b %||% "B",
                                  if (!is.null(matrix_id)) paste0("on ", matrix_id) else NULL),
    markers_topn = .wb_title_compose("Markers",
                                     if (!is.null(matrix_id)) paste0("on ", matrix_id) else NULL,
                                     if (!is.null(params$top_n)) paste0("(top ", as.integer(params$top_n), ")") else NULL),
    pathway_enrich = .wb_title_compose("Pathway Enrichment:",
                                       namespace %||% "pathways",
                                       if (!is.null(params$direction)) paste0("(", params$direction, ")") else NULL),
    leiden = .wb_title_compose("Leiden Clusters",
                               if (!is.null(space_id)) paste0("on ", space_id) else NULL,
                               if (!is.null(params$resolution)) paste0("(res ", as.character(params$resolution), ")") else NULL),
    slingshot_fit = .wb_title_compose("Slingshot Fit",
                                      if (!is.null(fit_space_id)) paste0("on ", fit_space_id) else NULL,
                                      if (is.finite(n_lineages)) paste0("(", n_lineages, " lineages)") else NULL),
    slingshot_project = .wb_title_compose("Slingshot Curves",
                                          if (!is.null(plot_space_id)) paste0("in ", plot_space_id) else NULL,
                                          if (!is.null(fit_space_id)) paste0("(from ", fit_space_id, ")") else NULL),
    monocle3_fit = .wb_title_compose("Monocle3 Fit",
                                     if (!is.null(fit_space_id)) paste0("on ", fit_space_id) else NULL,
                                     if (is.finite(n_lineages)) paste0("(", n_lineages, " lineages)") else NULL),
    monocle3_project = .wb_title_compose("Monocle3 Curves",
                                         if (!is.null(plot_space_id)) paste0("in ", plot_space_id) else NULL,
                                         if (!is.null(fit_space_id)) paste0("(from ", fit_space_id, ")") else NULL),
    palantir_fit = .wb_title_compose("Palantir Fit",
                                     if (!is.null(fit_space_id)) paste0("on ", fit_space_id) else NULL),
    palantir_project = .wb_title_compose("Palantir Trajectories",
                                         if (!is.null(plot_space_id)) paste0("in ", plot_space_id) else NULL),
    trajectory_de = .wb_title_compose("Trajectory DE",
                                      if (!is.null(feature_set)) paste0("for ", feature_set) else NULL,
                                      if (!is.null(matrix_id)) paste0("on ", matrix_id) else NULL),
    trajectory_smooth = .wb_title_compose("Trajectory Smooth",
                                          if (!is.null(feature_set)) paste0("for ", feature_set) else NULL,
                                          if (!is.null(matrix_id)) paste0("on ", matrix_id) else NULL),
    trajectory_signature_smooth = .wb_title_compose("Trajectory Signature Smooth",
                                                    if (!is.null(feature_set)) paste0("for ", feature_set) else NULL,
                                                    if (!is.null(matrix_id)) paste0("on ", matrix_id) else NULL),
    trajectory_geneset_dynamics = .wb_title_compose("Trajectory Gene-Set Dynamics",
                                                    if (!is.null(params$namespace)) paste0("for ", as.character(params$namespace)[1]) else NULL,
                                                    if (!is.null(matrix_id)) paste0("on ", matrix_id) else NULL),
    trajectory_signal_dynamics = .wb_title_compose("Trajectory Signal Dynamics",
                                                   if (!is.null(params$n_signal_keys_input)) paste0("for ", as.integer(params$n_signal_keys_input)[1], " signals") else NULL),
    trajectory_vector_smooth = .wb_title_compose("Trajectory Signal Smooth",
                                                 if (!is.null(params$vector_id)) paste0("for ", as.character(params$vector_id)[1]) else NULL),
    knn_pseudobulk = .wb_title_compose("kNN Pseudobulk",
                                       if (!is.null(matrix_id)) paste0("on ", matrix_id) else NULL),
    knn_neighbors = "kNN Neighbors",
    umap_fit = .wb_title_compose("UMAP",
                                 if (!is.null(space_id)) paste0("from ", space_id) else NULL),
    umap_transform = .wb_title_compose("UMAP Projection",
                                       if (!is.null(space_id)) paste0("from ", space_id) else NULL),
    metadata_cell_vector = .wb_name_nonempty(params$vector_name) %||% .wb_title_compose("Metadata Vector:", params$source_column),
    .wb_title_compose(
      gsub("_", " ", tools::toTitleCase(op_name)),
      if (nzchar(out_name)) paste0("(", out_name, ")") else NULL
    )
  )

  if (is.null(base)) base <- paste0(out_name, " (", op_name, ")")
  if (!is.null(prefix)) {
    .wb_title_compose(prefix, "-", base, max_chars = 120L)
  } else {
    base
  }
}


# ---- cell_vector -> artifacts + artifact_labels ----
# Your existing schema already has artifacts + artifact_labels; we use it.
# pybench-parity: yes (payload contract)
# pybench-counterpart: pybench.artifacts_payload.write_artifact_cell_vector_payload
# contract-note: Python writes payload rows only; bench owns artifacts registry + provenance
.wb_promote_cell_vector <- function(bundle, run, out_name, prim,
                                    name = NULL, description = NULL, created_by = NULL,
                                    parent_artifacts = list(), workspace = NULL) {

  con <- bundle$con
  wb_migrate_artifacts(bundle)

  .wb_assert(prim$kind == "cell_vector", "Expected kind=cell_vector")
  .wb_assert(!is.null(prim$cell_id) && !is.null(prim$value), "cell_vector missing fields")
  .wb_assert(length(prim$cell_id) == length(prim$value), "cell_vector: cell_id/value length mismatch")

  artifact_id <- .wb_new_artifact_id("cell_vector", bundle)
  created_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  prov_json <- .wb_prov_json(
    run,
    parent_artifacts,
    primitive_payload = .wb_object_primitive_payload_descriptor(prim)
  )

  # Write artifact metadata
  DBI::dbExecute(con, "
    INSERT INTO artifacts(
      artifact_id, type, name, description, created_at, created_by,
      source_op, input_space_id, input_matrix_id, cell_set,
      provenance_json, scworkbench_version
    )
    VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
  ", params = list(
    artifact_id,
    "cell_vector",
    name %||% paste0(out_name, " (", run$op_name, ")"),
    description %||% NA_character_,
    created_at,
    created_by %||% NA_character_,
    run$op_name,
    .wb_run_input_space_id(run),
    .wb_run_input_matrix_id(run),
    run$inputs$cell_set %||% "all",
    prov_json,
    as.character(utils::packageVersion("scworkbench"))
  ))

  value_type <- as.character(prim$value_type %||% "categorical")[1]
  if (!nzchar(value_type)) value_type <- "categorical"
  is_cont <- identical(value_type, "continuous")

  # Store as labels table, with typed hints for roundtrip fidelity.
  df <- data.frame(
    artifact_id = artifact_id,
    cell_id = as.character(prim$cell_id),
    label = as.character(prim$value),
    value_type = rep(value_type, length(prim$cell_id)),
    value_num = if (is_cont) suppressWarnings(as.numeric(prim$value)) else rep(NA_real_, length(prim$cell_id)),
    stringsAsFactors = FALSE
  )
  .wb_db_append_chunked(con, "artifact_labels", df, chunk_size = 1000L)

  artifact_id
}

# ---- relation_family -> artifact_relation_rows (generic long relation) ----
# pybench-parity: yes (payload contract)
# pybench-counterpart: pybench.artifacts_payload.write_artifact_relation_family_payload
.wb_promote_relation_family <- function(bundle, run, out_name, prim,
                                        name = NULL, description = NULL, created_by = NULL,
                                        parent_artifacts = list(), workspace = NULL) {
  con <- bundle$con
  wb_migrate_artifacts(bundle)

  .wb_assert(prim$kind == "relation_family", "Expected kind=relation_family")
  .wb_assert(!is.null(prim$key) && !is.null(prim$cell_id), "relation_family missing fields")
  n <- length(prim$key)
  .wb_assert(length(prim$cell_id) == n, "relation_family: key/cell_id length mismatch")
  if (!is.null(prim$weight)) .wb_assert(length(prim$weight) == n, "relation_family: key/weight length mismatch")
  if (!is.null(prim$value)) .wb_assert(length(prim$value) == n, "relation_family: key/value length mismatch")
  if (!is.null(prim$distance)) .wb_assert(length(prim$distance) == n, "relation_family: key/distance length mismatch")

  artifact_id <- .wb_new_artifact_id("relation_family", bundle)
  created_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  prov_json <- .wb_prov_json(
    run,
    parent_artifacts,
    primitive_payload = .wb_object_primitive_payload_descriptor(prim)
  )

  DBI::dbExecute(con, "
    INSERT INTO artifacts(
      artifact_id, type, name, description, created_at, created_by,
      source_op, input_space_id, input_matrix_id, cell_set,
      provenance_json, scworkbench_version
    )
    VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
  ", params = list(
    artifact_id,
    "relation_family",
    name %||% paste0(out_name, " (", run$op_name, ")"),
    description %||% NA_character_,
    created_at,
    created_by %||% NA_character_,
    run$op_name,
    .wb_run_input_space_id(run),
    .wb_run_input_matrix_id(run),
    run$inputs$cell_set %||% "all",
    prov_json,
    as.character(utils::packageVersion("scworkbench"))
  ))

  rel <- data.frame(
    artifact_id = artifact_id,
    relation_key = as.character(prim$key),
    cell_id = as.character(prim$cell_id),
    weight = if (is.null(prim$weight)) rep(NA_real_, n) else as.numeric(prim$weight),
    value = if (is.null(prim$value)) rep(NA_real_, n) else as.numeric(prim$value),
    distance = if (is.null(prim$distance)) rep(NA_real_, n) else as.numeric(prim$distance),
    stringsAsFactors = FALSE
  )
  .wb_db_append_chunked(con, "artifact_relation_rows", rel, chunk_size = 1000L)

  artifact_id
}

# ---- cell_vector_family -> artifact_pseudotime (fits your schema) ----
.wb_promote_cell_vector_family <- function(bundle, run, out_name, prim,
                                           name = NULL, description = NULL, created_by = NULL,
                                           parent_artifacts = list(), workspace = NULL) {

  con <- bundle$con
  wb_migrate_artifacts(bundle)

  .wb_assert(prim$kind == "cell_vector_family", "Expected kind=cell_vector_family")
  .wb_assert(!is.null(prim$key) && !is.null(prim$cell_id) && !is.null(prim$value), "cell_vector_family missing fields")
  .wb_assert(length(prim$key) == length(prim$cell_id) && length(prim$key) == length(prim$value),
             "cell_vector_family: key/cell_id/value length mismatch")

  artifact_id <- .wb_new_artifact_id("cell_vector_family", bundle)
  created_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  prov_json <- .wb_prov_json(
    run,
    parent_artifacts,
    primitive_payload = .wb_object_primitive_payload_descriptor(prim)
  )

  DBI::dbExecute(con, "
    INSERT INTO artifacts(
      artifact_id, type, name, description, created_at, created_by,
      source_op, input_space_id, input_matrix_id, cell_set,
      provenance_json, scworkbench_version
    )
    VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
  ", params = list(
    artifact_id,
    "cell_vector_family",
    name %||% paste0(out_name, " (", run$op_name, ")"),
    description %||% NA_character_,
    created_at,
    created_by %||% NA_character_,
    run$op_name,
    .wb_run_input_space_id(run),
    .wb_run_input_matrix_id(run),
    run$inputs$cell_set %||% "all",
    prov_json,
    as.character(utils::packageVersion("scworkbench"))
  ))

  # For pseudotime: reuse artifact_pseudotime table
  pt <- data.frame(
    artifact_id = artifact_id,
    cell_id = as.character(prim$cell_id),
    lineage_id = as.character(prim$key),
    pseudotime = as.numeric(prim$value),
    stringsAsFactors = FALSE
  )
  .wb_db_append_chunked(con, "artifact_pseudotime", pt, chunk_size = 1000L)

  artifact_id
}

# ---- path_2d_family -> artifact_curves_2d ----
# pybench-parity: yes (payload contract)
# pybench-counterpart: pybench.artifacts_payload.write_artifact_path_2d_family_payload
.wb_promote_path_2d_family <- function(bundle, run, out_name, prim,
                                       name = NULL, description = NULL, created_by = NULL,
                                       parent_artifacts = list(), workspace = NULL) {

  con <- bundle$con
  wb_migrate_artifacts(bundle)

  .wb_assert(prim$kind == "path_2d_family", "Expected kind=path_2d_family")
  .wb_assert(!is.null(prim$key) && !is.null(prim$point) && !is.null(prim$x) && !is.null(prim$y),
             "path_2d_family missing fields")
  .wb_assert(length(prim$key) == length(prim$point) &&
               length(prim$key) == length(prim$x) &&
               length(prim$key) == length(prim$y),
             "path_2d_family: length mismatch")

  artifact_id <- .wb_new_artifact_id("path_2d_family", bundle)
  created_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  prov_json <- .wb_prov_json(
    run,
    parent_artifacts,
    primitive_payload = .wb_object_primitive_payload_descriptor(prim)
  )

  DBI::dbExecute(con, "
    INSERT INTO artifacts(
      artifact_id, type, name, description, created_at, created_by,
      source_op, input_space_id, input_matrix_id, cell_set,
      provenance_json, scworkbench_version
    )
    VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
  ", params = list(
    artifact_id,
    "path_2d_family",
    name %||% paste0(out_name, " (", run$op_name, ")"),
    description %||% NA_character_,
    created_at,
    created_by %||% NA_character_,
    run$op_name,
    .wb_run_input_space_id(run),
    .wb_run_input_matrix_id(run),
    run$inputs$cell_set %||% "all",
    prov_json,
    as.character(utils::packageVersion("scworkbench"))
  ))

  cv <- data.frame(
    artifact_id = artifact_id,
    lineage_id = as.character(prim$key),
    point = as.integer(prim$point),
    x = as.numeric(prim$x),
    y = as.numeric(prim$y),
    stringsAsFactors = FALSE
  )
  .wb_db_append_chunked(con, "artifact_curves_2d", cv, chunk_size = 1000L)

  artifact_id
}

# ---- space_path_family -> artifact_space_path_rows/meta ----
.wb_promote_space_path_family <- function(bundle, run, out_name, prim,
                                          name = NULL, description = NULL, created_by = NULL,
                                          parent_artifacts = list(), workspace = NULL) {

  con <- bundle$con
  wb_migrate_artifacts(bundle)
  .wb_require_pkg("jsonlite", "space_path_family promotion")

  .wb_assert(prim$kind == "space_path_family", "Expected kind=space_path_family")
  .wb_assert(!is.null(prim$space_id) && !is.null(prim$path_id) &&
               !is.null(prim$point) && !is.null(prim$dim) && !is.null(prim$value),
             "space_path_family missing fields")
  n <- length(prim$path_id)
  .wb_assert(length(prim$space_id) == n &&
               length(prim$point) == n &&
               length(prim$dim) == n &&
               length(prim$value) == n,
             "space_path_family: length mismatch")

  artifact_id <- .wb_new_artifact_id("space_path_family", bundle)
  created_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  prov_json <- .wb_prov_json(
    run,
    parent_artifacts,
    primitive_payload = .wb_object_primitive_payload_descriptor(prim)
  )
  meta_json <- jsonlite::toJSON(.wb_json_sanitize(prim$meta %||% list()), auto_unbox = TRUE, null = "null")

  DBI::dbExecute(con, "
    INSERT INTO artifacts(
      artifact_id, type, name, description, created_at, created_by,
      source_op, input_space_id, input_matrix_id, cell_set,
      provenance_json, scworkbench_version
    )
    VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
  ", params = list(
    artifact_id,
    "space_path_family",
    name %||% paste0(out_name, " (", run$op_name, ")"),
    description %||% NA_character_,
    created_at,
    created_by %||% NA_character_,
    run$op_name,
    unique(as.character(prim$space_id))[1],
    .wb_run_input_matrix_id(run),
    run$inputs$cell_set %||% "all",
    prov_json,
    as.character(utils::packageVersion("scworkbench"))
  ))

  DBI::dbExecute(con, "
    INSERT INTO artifact_space_path_meta(artifact_id, meta_json)
    VALUES(?, ?);
  ", params = list(artifact_id, as.character(meta_json)))

  rows <- data.frame(
    artifact_id = artifact_id,
    space_id = as.character(prim$space_id),
    path_id = as.character(prim$path_id),
    point = as.integer(prim$point),
    dim = as.integer(prim$dim),
    value = as.numeric(prim$value),
    stringsAsFactors = FALSE
  )
  .wb_db_append_chunked(con, "artifact_space_path_rows", rows, chunk_size = 1000L)

  artifact_id
}

# ---- space_2d and model_ref promoters (optional snapshot/reference) ----
.wb_promote_space_2d_ref <- function(bundle, run, out_name, prim,
                                     name = NULL, description = NULL, created_by = NULL,
                                     parent_artifacts = list(), workspace = NULL) {

  con <- bundle$con
  wb_migrate_artifacts(bundle)

  .wb_assert(prim$kind == "space_2d", "Expected kind=space_2d")
  space_id <- prim$space_id
  .wb_assert(!is.null(space_id) && nzchar(space_id), "space_2d missing space_id")

  payload <- .wb_space_payload_registry_row(bundle, space_id)
  .wb_assert(as.integer(payload$n_dims[[1L]]) == 2L,
             paste0("space_2d artifact requires a two-dimensional payload: ", space_id))

  artifact_id <- .wb_new_artifact_id("space2d", bundle)
  created_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  prov_json <- .wb_prov_json(run, parent_artifacts)

  DBI::dbExecute(con, "
    INSERT INTO artifacts(
      artifact_id, type, name, description, created_at, created_by,
      source_op, input_space_id, input_matrix_id, cell_set,
      provenance_json, scworkbench_version
    )
    VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
  ", params = list(
    artifact_id,
    "space_2d",
    name %||% paste0(space_id, " (2D coords)"),
    description %||% NA_character_,
    created_at,
    created_by %||% NA_character_,
    run$op_name,
    space_id,
    .wb_run_input_matrix_id(run),
    run$inputs$cell_set %||% "all",
    prov_json,
    as.character(utils::packageVersion("scworkbench"))
  ))

  artifact_id
}

.wb_promote_model_ref <- function(bundle, run, out_name, prim,
                                  name = NULL, description = NULL, created_by = NULL,
                                  parent_artifacts = list(), workspace = NULL) {
  # pybench-parity: yes (payload contract)
  # pybench-counterpart: pybench.artifacts_payload.write_artifact_model_ref_payload
  # contract-note: Python writer fills artifact_model_ref row; file path ownership remains runtime-specific

  con <- bundle$con
  wb_migrate_artifacts(bundle)

  .wb_assert(prim$kind == "model_ref", "Expected kind=model_ref")
  space_id <- prim$space_id %||% prim$model_space_id %||% prim$in_space_id
  .wb_assert(!is.null(space_id) && nzchar(space_id),
    "model_ref must include space_id/model_space_id/in_space_id")
  engine <- as.character(prim$engine %||% "uwot")[1]
  in_space_id <- as.character(prim$in_space_id %||% "")[1]
  model_type <- as.character(prim$model_type %||% "")[1]

  artifact_id <- .wb_new_artifact_id("model_ref", bundle)
  model_path <- as.character(prim$model_path %||% "")[1]
  tree_manifest <- prim$model_tree_manifest %||% NULL
  tree_root <- as.character(prim$model_tree_root %||% model_path)[1]
  primary_path <- as.character(prim$model_primary_path %||% "")[1]
  payload_manifest_identity <- prim$model_payload_manifest_identity %||% NULL
  if (!is.null(prim$model_obj)) {
    .wb_assert(inherits(workspace, "wb_promotion_workspace"), "In-memory model_ref promotion requires a promotion workspace.")
    stored_model_path <- file.path("artifact_models", paste0(artifact_id, ".rds"))
    saveRDS(prim$model_obj, .wb_promotion_workspace_path(workspace, stored_model_path), version = 3)
  } else if (!is.null(tree_manifest)) {
    .wb_assert(inherits(workspace, "wb_promotion_workspace"),
      "Contained model tree promotion requires a promotion workspace.")
    .wb_operation_pack_v3_assert_model_tree_manifest(tree_manifest,
      engine, if (nzchar(model_type)) model_type else engine,
      code = "PYBENCH_OUTPUT_INVALID", phase = "promotion")
    .wb_assert(nzchar(tree_root),
      "Contained model tree promotion requires its authenticated root.")
    mapped_rel <- .wb_promotion_workspace_final_rel_for_source(workspace,
      tree_root)
    if (is.null(mapped_rel) && !.wb_path_is_absolute(tree_root) &&
        !is.null(workspace$mappings[[tree_root]])) mapped_rel <- tree_root
    .wb_assert(!is.null(mapped_rel) && nzchar(mapped_rel),
      "Contained model tree root was not staged into durable storage.")
    pending <- workspace$mappings[[mapped_rel]]$pending %||% NULL
    .wb_assert(!is.null(pending) && dir.exists(pending),
      "Contained model tree pending payload is missing.")
    observed <- .wb_operation_pack_v3_model_tree_manifest(pending, engine,
      if (nzchar(model_type)) model_type else engine,
      tree_manifest$primary_path,
      code = "PYBENCH_OUTPUT_INVALID", phase = "promotion")
    .wb_assert(identical(observed, tree_manifest),
      "Contained model tree changed before durable promotion.")
    observed_payload <- .wb_operation_pack_v3_model_payload_identity(observed)
    .wb_assert(is.null(payload_manifest_identity) || identical(
      observed_payload, payload_manifest_identity),
      "Contained model payload identity changed before durable promotion.")
    stored_model_path <- mapped_rel
    primary_path <- tree_manifest$primary_path
    payload_manifest_identity <- observed_payload
  } else {
    if (!nzchar(model_path) && identical(engine, "uwot") && inherits(workspace, "wb_promotion_workspace")) {
      sm <- DBI::dbGetQuery(con, "SELECT model_path FROM space_models WHERE space_id = ?;", params = list(space_id))
      if (nrow(sm) == 1L) {
        candidate <- as.character(sm$model_path[1])
        mapping <- workspace$mappings[[candidate]]
        .wb_assert(!is.null(mapping) && (file.exists(mapping$pending) || dir.exists(mapping$pending)),
                   paste0("Missing pending workspace model payload for space_id=", space_id))
        model_path <- candidate
      }
    }
    if (!nzchar(model_path) && identical(engine, "uwot")) model_path <- wb_space_model_path(bundle, space_id)
    mapped_rel <- if (inherits(workspace, "wb_promotion_workspace")) {
      .wb_promotion_workspace_final_rel_for_source(workspace, model_path)
    } else NULL
    if (!is.null(mapped_rel)) {
      stored_model_path <- mapped_rel
    } else if (inherits(workspace, "wb_promotion_workspace") && !.wb_path_is_absolute(model_path) && !is.null(workspace$mappings[[model_path]])) {
      stored_model_path <- model_path
    } else if (inherits(workspace, "wb_promotion_workspace") &&
        !.wb_path_is_absolute(model_path) && any(vapply(
          names(workspace$mappings), function(parent)
            startsWith(model_path, paste0(parent, "/")), logical(1)))) {
      # Transition payloads are prepared as one authenticated directory tree.
      # A contained model may point at a file below that mapped tree; retain
      # the same bundle-relative descendant rather than requiring a duplicate
      # file-level workspace mapping.
      stored_model_path <- model_path
    } else {
      .wb_assert(nzchar(model_path) && file.exists(model_path),
                 paste0("model_ref promotion requires an existing model file or in-memory model_obj (engine=", engine, ")."))
      stored_model_path <- .wb_model_ref_bundle_relative_path(bundle, model_path)
      .wb_assert(!.wb_path_is_absolute(stored_model_path),
                 "model_ref promotion cannot retain an external model path; provide model_obj or a durable bundle-owned model path.")
    }
  }
  stored_status <- .wb_path_status(bundle$dir, stored_model_path,
                                   expected_type="either", must_exist=FALSE,
                                   purpose="promoted model_ref")
  .wb_assert(isTRUE(stored_status$ok), paste0(stored_status$code, ": promoted model_ref path is not portable."))
  stored_model_path <- stored_status$relative
  created_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  prov_json <- .wb_prov_json(run, parent_artifacts)

  DBI::dbExecute(con, "
    INSERT INTO artifacts(
      artifact_id, type, name, description, created_at, created_by,
      source_op, input_space_id, input_matrix_id, cell_set,
      provenance_json, scworkbench_version
    )
    VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
  ", params = list(
    artifact_id,
    "model_ref",
    name %||% paste0(space_id, " (", engine, " model)"),
    description %||% NA_character_,
    created_at,
    created_by %||% NA_character_,
    run$op_name,
    if (nzchar(in_space_id)) in_space_id else .wb_run_input_space_id(run),
    .wb_run_input_matrix_id(run),
    run$inputs$cell_set %||% "all",
    prov_json,
    as.character(utils::packageVersion("scworkbench"))
  ))

  .wb_db_append_chunked(con, "artifact_model_ref", data.frame(
    artifact_id = artifact_id,
    engine = engine,
    model_space_id = space_id,
    in_space_id = in_space_id,
    model_type = if (nzchar(model_type)) model_type else engine,
    model_path = stored_model_path,
    linkage_json = if (is.null(prim$model_source_linkage %||%
        prim$model_linkage)) NA_character_ else
      jsonlite::toJSON(prim$model_source_linkage %||% prim$model_linkage,
        auto_unbox = TRUE, null = "null",
        digits = NA),
    model_primary_path = if (is.null(tree_manifest)) NA_character_ else
      primary_path,
    model_tree_manifest_json = if (is.null(tree_manifest)) NA_character_ else
      jsonlite::toJSON(tree_manifest, auto_unbox = TRUE, null = "null",
        digits = NA),
    payload_manifest_identity_json = if (is.null(tree_manifest))
      NA_character_ else jsonlite::toJSON(payload_manifest_identity,
        auto_unbox = TRUE, null = "null", digits = NA),
    stringsAsFactors = FALSE
  ), chunk_size = 1000L)

  artifact_id
}

.wb_promote_feature_table <- function(bundle, run, out_name, prim,
                                      name = NULL, description = NULL, created_by = NULL,
                                      parent_artifacts = list(), workspace = NULL) {
  .wb_assert(prim$kind == "feature_table", "Expected kind=feature_table")
  .wb_assert(is.data.frame(prim$table), "feature_table missing data.frame 'table'")
  if (!("feature_id" %in% names(prim$table))) {
    stop("feature_table requires a 'feature_id' column.", call. = FALSE)
  }

  .wb_promote_tabular_common(
    bundle = bundle,
    run = run,
    out_name = out_name,
    prim = prim,
    artifact_type = "feature_table",
    entity_kind = "feature",
    name = name,
    description = description,
    created_by = created_by,
    parent_artifacts = parent_artifacts
  )
}

.wb_promote_obs_table <- function(bundle, run, out_name, prim,
                                  name = NULL, description = NULL, created_by = NULL,
                                  parent_artifacts = list(), workspace = NULL) {
  .wb_assert(prim$kind == "obs_table", "Expected kind=obs_table")
  .wb_assert(is.data.frame(prim$table), "obs_table missing data.frame 'table'")

  .wb_promote_tabular_common(
    bundle = bundle,
    run = run,
    out_name = out_name,
    prim = prim,
    artifact_type = "obs_table",
    entity_kind = prim$entity_kind %||% "generic",
    name = name,
    description = description,
    created_by = created_by,
    parent_artifacts = parent_artifacts
  )
}

.wb_promote_tabular_common <- function(bundle, run, out_name, prim,
                                       artifact_type, entity_kind,
                                       name = NULL, description = NULL, created_by = NULL,
                                       parent_artifacts = list()) {
  # pybench-parity: planned (payload contract)
  # pybench-counterpart: pybench.artifacts_payload.write_artifact_table_payload (planned)
  .wb_require_pkg("jsonlite", "tabular artifact promotion")
  con <- bundle$con
  wb_migrate_artifacts(bundle)

  artifact_id <- .wb_new_artifact_id(artifact_type, bundle)
  created_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  prov_json <- .wb_prov_json(run, parent_artifacts)

  DBI::dbExecute(con, "
    INSERT INTO artifacts(
      artifact_id, type, name, description, created_at, created_by,
      source_op, input_space_id, input_matrix_id, cell_set,
      provenance_json, scworkbench_version
    )
    VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
  ", params = list(
    artifact_id,
    artifact_type,
    name %||% paste0(out_name, " (", run$op_name, ")"),
    description %||% NA_character_,
    created_at,
    created_by %||% NA_character_,
    run$op_name,
    .wb_run_input_space_id(run),
    .wb_run_input_matrix_id(run),
    run$inputs$cell_set %||% "all",
    prov_json,
    as.character(utils::packageVersion("scworkbench"))
  ))

  tbl <- prim$table
  meta <- prim$meta %||% list()
  meta_json <- jsonlite::toJSON(.wb_json_sanitize(meta), auto_unbox = TRUE, null = "null")

  DBI::dbExecute(con, "
    INSERT INTO artifact_tables(
      artifact_id, table_type, entity_kind, meta_json
    ) VALUES(?, ?, ?, ?);
  ", params = list(
    artifact_id,
    as.character(prim$table_type %||% "generic")[1],
    as.character(entity_kind %||% "generic")[1],
    as.character(meta_json)
  ))

  row_df <- data.frame(
    artifact_id = rep(artifact_id, nrow(tbl)),
    row_idx = seq_len(nrow(tbl)),
    row_json = vapply(
      seq_len(nrow(tbl)),
      function(i) {
        jsonlite::toJSON(
          .wb_json_sanitize(as.list(tbl[i, , drop = FALSE])),
          auto_unbox = TRUE,
          null = "null"
        )
      },
      character(1)
    ),
    stringsAsFactors = FALSE
  )
  .wb_db_append_chunked(con, "artifact_table_rows", row_df, chunk_size = 1000L)
  artifact_id
}

#' Migrate Artifact Registry Tables
#'
#' Ensure the artifact registry schema exists and has the columns expected by
#' current promotion and artifact-loading code.
#'
#' @param bundle Open `scworkbench_bundle`.
#'
#' @return Invisibly returns `TRUE`.
#'
#' @export
wb_migrate_artifacts <- function(bundle) {
  if (isTRUE(bundle$read_only)) return(invisible(FALSE))
  wb_migrate_bundle(bundle)
}

.wb_migrate_artifacts_locked <- function(bundle) {
  .wb_schema_migrate_connection(bundle$con, bundle_dir = bundle$dir, backup = TRUE)
}

#' @keywords internal
.wb_run_input_space_id <- function(run) {
  # 1) Prefer op params (best canonical)
  x <- run$params$space_id %||% NULL
  if (!is.null(x) && length(x) == 1 && nzchar(x)) return(as.character(x))

  # 2) Fall back to user_inputs (covers old runs / ops that didn't set params)
  ui <- run$inputs$user_inputs %||% list()
  x <- ui$space_id %||% ui$space %||% ui$space_2d %||% ui$in_space %||% ui$in_space_id %||% NULL
  if (!is.null(x) && length(x) == 1 && nzchar(x)) return(as.character(x))

  NA_character_
}

#' @keywords internal
.wb_run_input_matrix_id <- function(run) {
  x <- run$params$matrix_id %||% NULL
  if (!is.null(x) && length(x) == 1 && nzchar(x)) return(as.character(x))

  ui <- run$inputs$user_inputs %||% list()
  x <- ui$matrix_id %||% ui$matrix %||% NULL
  if (!is.null(x) && length(x) == 1 && nzchar(x)) return(as.character(x))

  NA_character_
}
