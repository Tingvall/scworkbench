# R/promote_analysis.R
# Promote a whole session DAG (analysis) in one go.
#
# Assumes:
# - wb_run objects created by wb_new_run()
# - Each run has:
#     run$run_id, run$op_name, run$inputs, run$params, run$outputs
# - Dependency edges are encoded in:
#     run$inputs$parents : character vector of parent run_ids (optional)
# - Optionally, already-satisfied dependencies can be provided via:
#     run$inputs$parent_artifacts : named list, e.g. list(labels="<artifact_id>")
# - wb_promote_run(bundle, run, ..., parent_artifacts=...) exists and returns
#   a named list of artifact ids keyed by output name (e.g. labels, trajectory)
#
# Export:
# - wb_promote_analysis

.wb_assert <- function(ok, msg) {
  if (!isTRUE(ok)) stop(msg, call. = FALSE)
  invisible(TRUE)
}

wb_is_run <- function(x) inherits(x, "wb_run")

# Normalize 'runs' into a named list keyed by run_id
.wb_norm_runs <- function(runs) {
  .wb_assert(is.list(runs), "runs must be a list of wb_run objects.")
  .wb_assert(length(runs) > 0, "runs is empty.")

  # If already named by run_id, keep; otherwise name by run$run_id
  if (is.null(names(runs)) || any(names(runs) == "")) {
    ids <- vapply(runs, function(r) {
      .wb_assert(wb_is_run(r), "runs must contain wb_run objects.")
      .wb_assert(!is.null(r$run_id) && nzchar(r$run_id), "Each run must have a non-empty run_id.")
      r$run_id
    }, character(1))
    names(runs) <- ids
  } else {
    # verify names align
    for (nm in names(runs)) {
      r <- runs[[nm]]
      .wb_assert(wb_is_run(r), "runs must contain wb_run objects.")
      .wb_assert(!is.null(r$run_id) && nzchar(r$run_id), "Each run must have a non-empty run_id.")
      # allow mismatch but warn-ish? We'll enforce to avoid subtle bugs.
      .wb_assert(identical(nm, r$run_id), "runs list must be named by run_id (names(runs)[[i]] == runs[[i]]$run_id).")
    }
  }

  runs
}

# Get parents vector (run_ids) from a run
.wb_run_parents <- function(run) {
  p <- run$inputs$parents
  if (is.null(p)) character(0) else as.character(p)
}

# DFS to collect subgraph from a head (postorder)
.wb_collect_postorder <- function(runs, head_id) {
  visited <- new.env(parent = emptyenv())
  order <- character(0)

  visit <- function(rid) {
    if (exists(rid, envir = visited, inherits = FALSE)) return(invisible(TRUE))
    assign(rid, TRUE, envir = visited)

    .wb_assert(rid %in% names(runs), paste0("Unknown run_id in DAG: ", rid))
    r <- runs[[rid]]
    parents <- .wb_run_parents(r)
    if (length(parents) > 0) {
      for (p in parents) visit(p)
    }
    order <<- c(order, rid)  # postorder append
    invisible(TRUE)
  }

  visit(head_id)
  order
}

# Merge artifact id pools (named list), preferring existing (do not overwrite)
.wb_merge_pool <- function(pool, incoming) {
  if (is.null(incoming) || length(incoming) == 0) return(pool)
  for (nm in names(incoming)) {
    if (is.null(pool[[nm]]) || !nzchar(pool[[nm]])) {
      pool[[nm]] <- incoming[[nm]]
    }
  }
  pool
}

#' Promote an analysis DAG from session runs
#'
#' Promotes all saveable outputs reachable from head run(s), in dependency order.
#' Uses the op registry via wb_promote_run(), and automatically threads parent
#' artifact ids to downstream promotions.
#'
#' @param bundle Bundle handle
#' @param runs List of wb_run objects. Must be named by run_id (or will be).
#' @param head_run_id Character scalar or vector of head run_id(s) to promote from.
#' @param name_prefix Optional prefix used to auto-generate artifact names when a run promotion needs a name.
#' @param description Optional description applied when promoting runs (can be overridden per run later if you extend)
#' @param created_by Optional actor string (user/agent)
#' @param fail_fast If TRUE, stop on first promotion failure. If FALSE, continue and record errors.
#' @return List with:
#'   - artifact_pool: named list of resolved artifact ids by dependency key (e.g. labels, trajectory)
#'   - promoted: data.frame summary of promoted runs/outputs
#' @export
wb_promote_analysis <- function(bundle,
                                runs,
                                head_run_id,
                                name_prefix = NULL,
                                description = NULL,
                                created_by = NULL,
                                fail_fast = TRUE) {
  runs <- .wb_norm_runs(runs)
  heads <- as.character(head_run_id)
  .wb_assert(length(heads) >= 1, "head_run_id must have length >= 1.")
  .wb_assert(all(heads %in% names(runs)), "One or more head_run_id not present in runs.")

  # Collect union of postorders for all heads (and deduplicate while keeping topo correctness)
  # Strategy: concatenate postorders, then stable-unique.
  postorders <- unlist(lapply(heads, function(h) .wb_collect_postorder(runs, h)), use.names = FALSE)
  # stable unique: keep first occurrence
  keep <- !duplicated(postorders)
  topo <- postorders[keep]

  # artifact_pool accumulates satisfied dependencies across the whole promotion
  artifact_pool <- list()

  # promoted summary
  rows <- list()
  row_i <- 0L

  for (rid in topo) {
    run <- runs[[rid]]

    # Seed pool with any already-satisfied parent artifacts declared on the run
    # e.g. if user loaded a saved Leiden artifact and then ran slingshot, run$inputs$parent_artifacts could contain labels=<id>
    artifact_pool <- .wb_merge_pool(artifact_pool, run$inputs$parent_artifacts)

    # Generate a name for this run's promoted outputs (optional)
    # Downstream functions may reuse it; you can enhance later to generate per-output names.
    nm <- NULL
    if (!is.null(name_prefix) && nzchar(name_prefix)) {
      nm <- paste0(name_prefix, "__", run$op_name, "__", substr(run$run_id, 1, 12))
    }

    # Promote this run (may promote nothing if it has no saveable outputs)
    promoted_ids <- NULL
    err <- NULL

    tryCatch({
      promoted_ids <- wb_promote_run(
        bundle = bundle,
        run = run,
        name = nm,
        description = description,
        created_by = created_by,
        parent_artifacts = artifact_pool
      )
    }, error = function(e) {
      err <<- conditionMessage(e)
      if (isTRUE(fail_fast)) stop(e)
    })

    # Record summary + update pool
    if (!is.null(promoted_ids) && length(promoted_ids) > 0) {
      # Update pool using returned ids.
      # Convention: wb_promote_run returns list keyed by output name (e.g. labels, trajectory),
      # and dependency keys should match these names (e.g. 'labels' is a dependency key).
      artifact_pool <- .wb_merge_pool(artifact_pool, promoted_ids)

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
      # no outputs promoted (either none saveable or promoter not implemented)
      row_i <- row_i + 1L
      rows[[row_i]] <- data.frame(
        run_id = run$run_id,
        op_name = run$op_name,
        output = NA_character_,
        artifact_id = NA_character_,
        status = if (is.null(err)) "skipped" else "error",
        error = if (is.null(err)) NA_character_ else err,
        stringsAsFactors = FALSE
      )
    }
  }

  promoted_df <- do.call(rbind, rows)

  list(
    artifact_pool = artifact_pool,
    promoted = promoted_df
  )
}

wb_migrate_artifacts <- function(bundle) {
  con <- bundle$con

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS artifacts (
      artifact_id TEXT PRIMARY KEY,
      type TEXT NOT NULL,
      name TEXT,
      description TEXT,
      created_at TEXT NOT NULL,
      created_by TEXT,
      source_op TEXT,
      input_space_id TEXT,
      input_matrix_id TEXT,
      cell_set TEXT,
      provenance_json TEXT NOT NULL,
      scworkbench_version TEXT
    );
  ")

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS artifact_labels (
      artifact_id TEXT NOT NULL,
      cell_id TEXT NOT NULL,
      label TEXT NOT NULL,
      PRIMARY KEY (artifact_id, cell_id)
    );
  ")

  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_artifacts_type ON artifacts(type);")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_labels_artifact ON artifact_labels(artifact_id);")

  DBI::dbExecute(con, "
  CREATE TABLE IF NOT EXISTS artifact_pseudotime (
    artifact_id TEXT NOT NULL,
    cell_id TEXT NOT NULL,
    lineage_id TEXT NOT NULL,
    pseudotime REAL NOT NULL,
    PRIMARY KEY (artifact_id, cell_id, lineage_id)
  );
")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_pt_artifact ON artifact_pseudotime(artifact_id);")

  DBI::dbExecute(con, "
  CREATE TABLE IF NOT EXISTS artifact_curves_2d (
    artifact_id TEXT NOT NULL,
    lineage_id TEXT NOT NULL,
    point INTEGER NOT NULL,
    x REAL NOT NULL,
    y REAL NOT NULL,
    PRIMARY KEY (artifact_id, lineage_id, point)
  );
")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_curve_artifact ON artifact_curves_2d(artifact_id);")


  invisible(TRUE)
}


.wb_new_artifact_id <- function(prefix) {
  paste0(prefix, "_", format(Sys.time(), "%Y%m%d_%H%M%S"), "_", paste(sample(c(letters, 0:9), 6, TRUE), collapse = ""))
}


# Promote a Leiden labels output
.wb_promote_labels <- function(bundle, run, name = NULL, description = NULL, created_by = NULL) {
  con <- bundle$con
  wb_migrate_artifacts(bundle)

  labels <- run$outputs$labels
  .wb_assert(is.data.frame(labels) && all(c("cell_id", "cluster") %in% colnames(labels)),
             "Run does not contain labels output as data.frame(cell_id, cluster).")

  artifact_id <- .wb_new_artifact_id("labels")
  if (is.null(name)) name <- paste0("leiden_", run$created_at)

  prov <- list(
    run_id = run$run_id,
    op_name = run$op_name,
    created_at = run$created_at,
    inputs = run$inputs,
    params = run$params,
    notes = run$notes
  )

  prov_json <- jsonlite::toJSON(prov, auto_unbox = TRUE)

  DBI::dbExecute(con, "
  INSERT INTO artifacts(
    artifact_id, type, name, description, created_at, created_by,
    source_op, input_space_id, input_matrix_id, cell_set,
    provenance_json, scworkbench_version
  )
  VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
", params = list(
  .wb_scalar_chr(artifact_id),
  "labels",
  .wb_scalar_chr(name),
  .wb_scalar_chr(description),
  .wb_scalar_chr(format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
  .wb_scalar_chr(created_by),
  .wb_scalar_chr(run$op_name),
  .wb_scalar_chr(run$inputs$space_id),
  .wb_scalar_chr(run$inputs$matrix_id),
  .wb_scalar_chr(run$inputs$cell_set %||% "all"),
  .wb_scalar_chr(prov_json),
  .wb_scalar_chr(as.character(utils::packageVersion("scworkbench")))
))


  # write labels
  df <- data.frame(
    artifact_id = artifact_id,
    cell_id = labels$cell_id,
    label = as.character(labels$cluster),
    stringsAsFactors = FALSE
  )
  DBI::dbWriteTable(con, "artifact_labels", df, append = TRUE)

  artifact_id
}



.wb_promote_trajectory_2d <- function(bundle, run, name = NULL, description = NULL,
                                      created_by = NULL, parent_labels_artifact_id = NULL) {
  con <- bundle$con
  wb_migrate_artifacts(bundle)

  pt <- run$outputs$pseudotime
  cv <- run$outputs$curves

  .wb_assert(is.data.frame(pt) && all(c("cell_id","lineage_id","pseudotime") %in% colnames(pt)),
             "Run must contain pseudotime df: cell_id, lineage_id, pseudotime")
  .wb_assert(is.data.frame(cv) && all(c("lineage_id","point","x","y") %in% colnames(cv)),
             "Run must contain curves df: lineage_id, point, x, y")

  artifact_id <- .wb_new_artifact_id("trajectory")
  if (is.null(name)) name <- paste0("slingshot_", run$created_at)

  prov <- list(
    run_id = run$run_id,
    op_name = run$op_name,
    created_at = run$created_at,
    inputs = run$inputs,
    params = run$params,
    notes = run$notes,
    parent_labels_artifact_id = parent_labels_artifact_id
  )
  prov_json <- jsonlite::toJSON(prov, auto_unbox = TRUE)

  DBI::dbExecute(con, "
  INSERT INTO artifacts(
    artifact_id, type, name, description, created_at, created_by,
    source_op, input_space_id, input_matrix_id, cell_set,
    provenance_json, scworkbench_version
  )
  VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
", params = list(
  .wb_scalar_chr(artifact_id),
  "trajectory",
  .wb_scalar_chr(name),
  .wb_scalar_chr(description),
  .wb_scalar_chr(format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
  .wb_scalar_chr(created_by),
  .wb_scalar_chr(run$op_name),
  .wb_scalar_chr(run$inputs$space_id),
  .wb_scalar_chr(run$inputs$matrix_id),
  .wb_scalar_chr(run$inputs$cell_set %||% "all"),
  .wb_scalar_chr(prov_json),
  .wb_scalar_chr(as.character(utils::packageVersion("scworkbench")))
))


  # pseudotime
  pt_out <- data.frame(
    artifact_id = artifact_id,
    cell_id = pt$cell_id,
    lineage_id = pt$lineage_id,
    pseudotime = as.numeric(pt$pseudotime),
    stringsAsFactors = FALSE
  )
  DBI::dbWriteTable(con, "artifact_pseudotime", pt_out, append = TRUE)

  # curves
  cv_out <- data.frame(
    artifact_id = artifact_id,
    lineage_id = cv$lineage_id,
    point = as.integer(cv$point),
    x = as.numeric(cv$x),
    y = as.numeric(cv$y),
    stringsAsFactors = FALSE
  )
  DBI::dbWriteTable(con, "artifact_curves_2d", cv_out, append = TRUE)

  artifact_id
}

# Generic promote entry point
wb_promote_run <- function(bundle,
                           run,
                           name = NULL,
                           description = NULL,
                           created_by = NULL,
                           parent_artifacts = list()) {

  .wb_assert(wb_is_run(run), "run must be a wb_run object.")

  spec <- .wb_op_spec(run$op_name)
  saveables <- spec$saveable_outputs

  if (is.null(saveables)) {
    stop("Promotion registry missing saveable_outputs for op: ", run$op_name, call. = FALSE)
  }
  if (!is.list(saveables) || is.null(names(saveables)) || any(names(saveables) == "")) {
    stop("saveable_outputs must be a named list for op: ", run$op_name, call. = FALSE)
  }


  promoted <- list()

  for (out_name in names(saveables)) {
    out_spec <- saveables[[out_name]]

    if (!out_name %in% names(run$outputs)) next

    promoter <- get(out_spec$promoter, mode = "function")

    # resolve dependencies (for PoC: labels -> slingshot)
    parent_id <- NULL
    if (!is.null(out_spec$depends_on)) {
      dep <- out_spec$depends_on
      parent_id <- parent_artifacts[[dep]]
      if (is.null(parent_id)) {
        stop(
          "Cannot promote '", out_name,
          "' without parent artifact '", dep, "'.",
          call. = FALSE
        )
      }
    }

    if (out_spec$artifact_type == "labels") {
      promoted[[out_name]] <- promoter(
        bundle = bundle,
        run = run,
        name = name,
        description = description,
        created_by = created_by
      )
    }

    if (out_spec$artifact_type == "trajectory") {
      promoted[[out_name]] <- promoter(
        bundle = bundle,
        run = run,
        name = name,
        description = description,
        created_by = created_by,
        parent_labels_artifact_id = parent_id
      )
    }
  }

  promoted
}




# Methods stub generator (promoted artifacts only)
wb_used_analysis <- function(bundle) {
  arts <- wb_art_list(bundle)

  if (nrow(arts) == 0) {
    return("No promoted artifacts found in this bundle yet.")
  }

  lines <- c()
  lines <- c(lines, "Methods (stub, from promoted scworkbench artifacts)")
  lines <- c(lines, "")

  for (i in seq_len(nrow(arts))) {
    a <- arts[i, ]
    prov <- jsonlite::fromJSON(a$provenance_json)

    if (a$type == "labels" && identical(prov$op_name, "leiden")) {
      # pull key fields if present
      p <- prov$params
      inp <- prov$inputs

      lines <- c(lines,
                 sprintf(
                   "- Leiden clustering was performed on space '%s' using dims %s, k=%s, resolution=%s (seed=%s).",
                   inp$space_id %||% "NA",
                   if (!is.null(p$dims)) paste(p$dims, collapse = ",") else "all",
                   p$k %||% "NA",
                   p$resolution %||% "NA",
                   p$seed %||% "NA"
                 )
      )
    } else {
      lines <- c(lines, sprintf("- %s artifact '%s' created from op '%s'.", a$type, a$name, a$source_op))
    }
  }

  paste(lines, collapse = "\n")
}

