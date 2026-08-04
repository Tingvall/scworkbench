# Internal materialization and staged-overlay transfer for transitive promotion.

.wb_promotion_commit_id <- function() {
  paste0("commit_", format(Sys.time(), "%Y%m%d_%H%M%S"), "_",
         paste0(sample(c(0:9, letters), 8, TRUE), collapse = ""))
}

.wb_promotion_runtime_fingerprint <- function() {
  list(
    scworkbench_version = as.character(utils::packageVersion("scworkbench")),
    r_version = R.version.string,
    source_revision = Sys.getenv("SCWORKBENCH_SOURCE_REVISION", unset = NA_character_),
    container_digest = Sys.getenv("SCWORKBENCH_CONTAINER_DIGEST", unset = NA_character_),
    packages = vapply(c("BPCells", "Matrix", "irlba", "uwot", "igraph"), function(pkg) {
      if (!requireNamespace(pkg, quietly = TRUE)) return(NA_character_)
      as.character(utils::packageVersion(pkg))
    }, character(1))
  )
}

.wb_copy_db_rows <- function(from_con, to_con, table, where_sql, params = list()) {
  if (!.wb_table_exists(from_con, table) || !.wb_table_exists(to_con, table)) return(invisible(0L))
  rows <- DBI::dbGetQuery(from_con, paste0("SELECT * FROM ", table, " WHERE ", where_sql), params = params)
  if (!nrow(rows)) return(invisible(0L))
  fields <- intersect(DBI::dbListFields(from_con, table), DBI::dbListFields(to_con, table))
  rows <- rows[, fields, drop = FALSE]
  .wb_db_append_chunked(to_con, table, rows)
  invisible(nrow(rows))
}

.wb_prepare_staged_payload <- function(staging_bundle, workspace, rel_path) {
  rel_path <- as.character(rel_path %||% "")[1]
  .wb_assert(nzchar(rel_path) && !startsWith(rel_path, "/") && !grepl("(^|/)\\.\\.(/|$)", rel_path), "Unsafe staged payload path")
  src <- file.path(staging_bundle$dir, rel_path)
  existing <- workspace$mappings[[rel_path]]
  if (!is.null(existing)) {
    mapped_source <- normalizePath(as.character(existing$source %||% "")[1], winslash = "/", mustWork = FALSE)
    source <- normalizePath(src, winslash = "/", mustWork = TRUE)
    .wb_assert(identical(mapped_source, source), paste0(
      "Promotion payload path collision for '", rel_path, "'."
    ))
    return(invisible(rel_path))
  }
  pending_path <- .wb_promotion_workspace_path(workspace, rel_path)
  .wb_assert(file.exists(src) || dir.exists(src), paste0("Missing staged payload: ", src))
  workspace$mappings[[rel_path]]$source <- normalizePath(src, winslash = "/", mustWork = TRUE)
  ok <- file.copy(src, dirname(pending_path), recursive = TRUE, copy.date = TRUE)
  .wb_assert(isTRUE(ok), paste0("Failed to prepare staged payload: ", rel_path))
  invisible(rel_path)
}

.wb_stage_prepare_matrix_payloads <- function(staging_bundle, workspace, matrix_id) {
  row <- DBI::dbGetQuery(staging_bundle$con, "SELECT * FROM matrices WHERE matrix_id = ?;", params = list(matrix_id))
  .wb_assert(nrow(row) == 1L, paste0("Staged matrix is missing: ", matrix_id))
  frags <- DBI::dbGetQuery(staging_bundle$con, "SELECT * FROM matrix_fragments WHERE matrix_id = ?;", params = list(matrix_id))
  paths <- unique(c(as.character(row$path %||% character(0)), as.character(frags$path %||% character(0))))
  for (p in paths[nzchar(paths)]) .wb_prepare_staged_payload(staging_bundle, workspace, p)
  invisible(workspace)
}

.wb_path_relative_to_root <- function(path, root) {
  path <- normalizePath(as.character(path %||% "")[1], winslash = "/", mustWork = TRUE)
  root <- normalizePath(as.character(root %||% "")[1], winslash = "/", mustWork = TRUE)
  if (identical(path, root)) return("")
  prefix <- paste0(root, "/")
  if (!startsWith(path, prefix)) return(NULL)
  substring(path, nchar(prefix) + 1L)
}

.wb_stage_prepare_model_payload <- function(staging_bundle, bundle, workspace, prim) {
  if (!.wb_is_primitive(prim) || !identical(as.character(prim$kind), "model_ref") || !is.null(prim$model_obj)) {
    return(invisible(workspace))
  }
  model_path <- as.character(prim$model_path %||% "")[1]
  if (!nzchar(model_path)) return(invisible(workspace))

  candidate <- if (.wb_path_is_absolute(model_path)) model_path else file.path(staging_bundle$dir, model_path)
  .wb_assert(file.exists(candidate) || dir.exists(candidate), paste0(
    "Staged model_ref payload does not exist: ", model_path
  ))
  source_abs <- normalizePath(candidate, winslash = "/", mustWork = TRUE)
  base_rel <- .wb_path_relative_to_root(source_abs, bundle$dir)
  if (!is.null(base_rel)) return(invisible(workspace))

  stage_rel <- .wb_path_relative_to_root(source_abs, staging_bundle$dir)
  .wb_assert(!is.null(stage_rel) && nzchar(stage_rel), paste0(
    "model_ref promotion may only retain bundle-owned or session-staged payloads: ", model_path
  ))
  .wb_prepare_staged_payload(staging_bundle, workspace, stage_rel)
  invisible(workspace)
}

.wb_stage_prepare_space_payloads <- function(staging_bundle, workspace, space_id) {
  sm <- if (.wb_table_exists(staging_bundle$con, "space_models")) {
    DBI::dbGetQuery(staging_bundle$con, "SELECT * FROM space_models WHERE space_id = ?;", params = list(space_id))
  } else data.frame()
  if (nrow(sm) && "model_path" %in% names(sm)) {
    paths <- unique(as.character(sm$model_path))
    for (path in paths[nzchar(paths)]) .wb_prepare_staged_payload(staging_bundle, workspace, path)
  }
  invisible(workspace)
}

.wb_stage_commit_matrix <- function(staging_bundle, bundle, matrix_id) {
  src <- staging_bundle$con
  dst <- bundle$con
  exists <- DBI::dbGetQuery(dst, "SELECT matrix_id FROM matrices WHERE matrix_id = ?;", params = list(matrix_id))
  if (nrow(exists)) return(invisible(FALSE))
  row <- DBI::dbGetQuery(src, "SELECT * FROM matrices WHERE matrix_id = ?;", params = list(matrix_id))
  .wb_assert(nrow(row) == 1L, paste0("Staged matrix is missing: ", matrix_id))
  frags <- DBI::dbGetQuery(src, "SELECT * FROM matrix_fragments WHERE matrix_id = ? ORDER BY fragment_id;", params = list(matrix_id))
  .wb_copy_db_rows(src, dst, "matrices", "matrix_id = ?", list(matrix_id))
  .wb_copy_db_rows(src, dst, "features", "matrix_id = ?", list(matrix_id))
  .wb_copy_db_rows(src, dst, "matrix_fragments", "matrix_id = ?", list(matrix_id))
  if (nrow(frags)) {
    ids <- as.character(frags$fragment_id)
    q <- paste(rep("?", length(ids)), collapse = ",")
    .wb_copy_db_rows(src, dst, "matrix_fragment_cells", paste0("fragment_id IN (", q, ")"), as.list(ids))
    .wb_copy_db_rows(src, dst, "matrix_fragment_features", paste0("fragment_id IN (", q, ")"), as.list(ids))
  }
  invisible(TRUE)
}

.wb_run_is_committed <- function(bundle, run_id) {
  run_id <- as.character(run_id %||% "")[1]
  if (!nzchar(run_id) || !.wb_table_exists(bundle$con, "prov_runs")) return(FALSE)
  nrow(DBI::dbGetQuery(
    bundle$con,
    "SELECT 1 FROM prov_runs WHERE run_id = ? LIMIT 1;",
    params = list(run_id)
  )) > 0L
}

.wb_validate_materialization_producers <- function(bundle, runs, topo) {
  matrix_runs <- list()
  space_runs <- list()
  for (rid in topo) {
    if (.wb_run_is_committed(bundle, rid)) next
    for (prim in unname(runs[[rid]]$outputs %||% list())) {
      if (!.wb_is_primitive(prim)) next
      if (identical(as.character(prim$kind), "matrix")) {
        id <- as.character(prim$matrix_id %||% "")[1]
        if (nzchar(id)) matrix_runs[[id]] <- unique(c(matrix_runs[[id]] %||% character(0), rid))
      }
      if (prim$kind %in% c("space", "space_2d") &&
          !identical(as.character(prim$promotion_mode %||% "")[1], "merge_space_2d")) {
        id <- as.character(prim$space_id %||% "")[1]
        if (nzchar(id)) space_runs[[id]] <- unique(c(space_runs[[id]] %||% character(0), rid))
      }
    }
  }
  duplicate_matrices <- names(Filter(function(x) length(x) > 1L, matrix_runs))
  duplicate_spaces <- names(Filter(function(x) length(x) > 1L, space_runs))
  .wb_assert(!length(duplicate_matrices), paste0(
    "Promotion closure contains multiple uncommitted producers for matrix_id: ",
    paste(duplicate_matrices, collapse = ", "), ". Use unique output matrix IDs."
  ))
  .wb_assert(!length(duplicate_spaces), paste0(
    "Promotion closure contains multiple uncommitted producers for space_id: ",
    paste(duplicate_spaces, collapse = ", "), ". Use unique output space IDs."
  ))
  invisible(TRUE)
}

.wb_stage_prepare_materializations <- function(staging_bundle, bundle, workspace, runs, topo, commit_id) {
  .wb_assert(inherits(staging_bundle, "scworkbench_bundle"), "staging_bundle must be scworkbench_bundle")
  .wb_validate_materialization_producers(bundle, runs, topo)
  for (rid in topo) {
    # A session can continue after an intermediate snapshot is promoted. Those
    # durable ancestor runs remain in the session DAG, but their registry state
    # must not be materialized a second time or mistaken for an overwrite.
    if (.wb_run_is_committed(bundle, rid)) next
    for (prim in unname(runs[[rid]]$outputs %||% list())) {
      if (.wb_is_primitive(prim) && identical(prim$kind, "matrix")) {
        exists <- DBI::dbGetQuery(bundle$con, "SELECT matrix_id FROM matrices WHERE matrix_id = ?;", params = list(prim$matrix_id))
        .wb_assert(!nrow(exists), paste0(
          "Cannot promote staged matrix over committed matrix_id='", prim$matrix_id,
          "'. Use a new output matrix ID to preserve immutable lineage."
        ))
        .wb_stage_prepare_matrix_payloads(staging_bundle, workspace, prim$matrix_id)
      }
      if (.wb_is_primitive(prim) && prim$kind %in% c("space", "space_2d")) {
        exists <- DBI::dbGetQuery(bundle$con, "SELECT space_id FROM spaces WHERE space_id = ?;", params = list(prim$space_id))
        if (nrow(exists)) {
          .wb_assert(
            identical(as.character(prim$promotion_mode %||% "")[1], "merge_space_2d"),
            paste0(
              "Cannot promote staged space over committed space_id='", prim$space_id,
              "' without an explicit merge contract. Use a new output space ID."
            )
          )
        } else {
          .wb_stage_prepare_space_payloads(staging_bundle, workspace, prim$space_id)
        }
      }
      if (.wb_is_primitive(prim) && identical(prim$kind, "model_ref")) {
        .wb_stage_prepare_model_payload(staging_bundle, bundle, workspace, prim)
      }
    }
  }
  .wb_prepare_materialization_payloads(workspace, runs, topo, commit_id)
}

.wb_materialization_primitive <- function(workspace, prim) {
  if (!.wb_is_primitive(prim) || !identical(as.character(prim$kind), "model_ref")) return(prim)
  model_path <- as.character(prim$model_path %||% "")[1]
  if (!nzchar(model_path)) return(prim)

  mapped_rel <- .wb_promotion_workspace_final_rel_for_source(workspace, model_path)
  if (is.null(mapped_rel) && !.wb_path_is_absolute(model_path) && !is.null(workspace$mappings[[model_path]])) {
    mapped_rel <- model_path
  }
  if (is.null(mapped_rel)) {
    base_rel <- tryCatch(.wb_model_ref_bundle_relative_path(workspace$bundle, model_path), error = function(e) model_path)
    if (!.wb_path_is_absolute(base_rel)) mapped_rel <- base_rel
  }
  .wb_assert(!is.null(mapped_rel) && nzchar(mapped_rel), paste0(
    "Could not map model_ref payload into durable bundle storage: ", model_path
  ))
  prim$model_path <- as.character(mapped_rel)[1]
  prim
}

.wb_committed_materialization <- function(bundle, run_id, output_name) {
  if (!.wb_table_exists(bundle$con, "prov_materializations") ||
      !.wb_table_exists(bundle$con, "prov_commits")) return(data.frame())
  DBI::dbGetQuery(
    bundle$con,
    paste0("SELECT pm.path, pm.primitive_kind, pm.output_hash, pm.content_sha256, ",
     if (.wb_db_has_column(bundle$con, "prov_materializations", "content_identity_scheme")) "pm.content_identity_scheme" else "NULL AS content_identity_scheme", "\n",
     "FROM prov_materializations pm\n",
     "INNER JOIN prov_commits pc ON pc.commit_id = pm.commit_id\n",
     "WHERE pm.run_id = ? AND pm.output_name = ? AND pc.state = 'complete'\n",
     "ORDER BY pc.created_at DESC, pc.rowid DESC\n",
     "LIMIT 1;"),
    params = list(as.character(run_id)[1], as.character(output_name)[1])
  )
}

.wb_prepare_materialization_payloads <- function(workspace, runs, topo, commit_id) {
  root_rel <- file.path("provenance", "materializations", commit_id)
  rows <- list(); i <- 0L
  for (rid in topo) {
    run <- runs[[rid]]
    for (nm in names(run$outputs %||% list())) {
      prim <- run$outputs[[nm]]
      if (!.wb_is_primitive(prim)) next
      rel <- file.path(root_rel, rid, paste0(nm, ".rds"))
      prior <- if (.wb_run_is_committed(workspace$bundle, rid)) {
        .wb_committed_materialization(workspace$bundle, rid, nm)
      } else data.frame()
      if (nrow(prior)) {
        source <- file.path(workspace$bundle$dir, as.character(prior$path[1]))
        .wb_assert(file.exists(source), paste0(
          "Committed materialization payload is missing for run=", rid,
          ", output=", nm, ": ", as.character(prior$path[1])
        ))
        pending <- .wb_promotion_workspace_path(workspace, rel)
        .wb_assert(isTRUE(file.copy(source, pending, copy.date = TRUE)), paste0(
          "Failed to stage committed materialization for run=", rid, ", output=", nm
        ))
        primitive_kind <- as.character(prior$primitive_kind[1])
        output_hash <- as.character(prior$output_hash[1])
      } else {
        prim <- .wb_materialization_primitive(workspace, prim)
        saveRDS(prim, .wb_promotion_workspace_path(workspace, rel), version = 3)
        primitive_kind <- as.character(prim$kind)
        output_hash <- .wb_hash_text(serialize(prim, NULL, version = 3))
      }
      content_sha256 <- .wb_prov_sha256_file(.wb_promotion_workspace_path(workspace, rel))
      i <- i + 1L
      rows[[i]] <- data.frame(
        commit_id = commit_id, run_id = rid, output_name = nm,
        primitive_kind = primitive_kind, path = rel,
        output_hash = output_hash,
        content_sha256 = content_sha256,
        content_identity_scheme = unname(.wb_content_identity_schemes()[["raw_file"]]),
        stringsAsFactors = FALSE
      )
    }
  }
  if (length(rows)) do.call(rbind, rows) else data.frame()
}

.wb_stage_commit_space <- function(staging_bundle, bundle, space_id, prim = NULL) {
  src <- staging_bundle$con
  dst <- bundle$con
  exists <- DBI::dbGetQuery(dst, "SELECT space_id FROM spaces WHERE space_id = ?;", params = list(space_id))
  if (nrow(exists)) {
    .wb_assert(
      .wb_is_primitive(prim) && identical(as.character(prim$promotion_mode %||% "")[1], "merge_space_2d"),
      paste0("Cannot replace committed space during promotion: ", space_id)
    )
    .wb_entity_assert_replaceable(bundle, "space", space_id, action = "merge into")
    cell_ids <- unique(as.character(prim$cell_ids %||% character(0)))
    .wb_assert(length(cell_ids) > 0L, "merge_space_2d promotion requires explicit cell_ids")
    cl <- .wb_sql_in_clause(cell_ids)
    rows <- DBI::dbGetQuery(
      src,
      paste0("SELECT space_id, cell_id, x, y FROM space_2d WHERE space_id = ? AND cell_id ", cl$sql, ";"),
      params = c(list(space_id), cl$params)
    )
    .wb_assert(nrow(rows) == length(cell_ids), paste0(
      "Staged 2D-space merge is incomplete for ", space_id, ": expected ",
      length(cell_ids), " cells, found ", nrow(rows), "."
    ))
    if (isTRUE(prim$overwrite %||% FALSE)) {
      DBI::dbExecute(
        dst,
        paste0("DELETE FROM space_2d WHERE space_id = ? AND cell_id ", cl$sql, ";"),
        params = c(list(space_id), cl$params)
      )
    }
    .wb_db_append_chunked(dst, "space_2d", rows)
    return(invisible(TRUE))
  }
  row <- DBI::dbGetQuery(src, "SELECT * FROM spaces WHERE space_id = ?;", params = list(space_id))
  .wb_assert(nrow(row) == 1L, paste0("Staged space is missing: ", space_id))
  staged_model <- .wb_table_exists(src, "space_models") && nrow(DBI::dbGetQuery(src, "SELECT space_id FROM space_models WHERE space_id = ?;", params = list(space_id))) > 0L
  if (isTRUE(staged_model)) .wb_ensure_space_models_table(dst)
  .wb_copy_db_rows(src, dst, "spaces", "space_id = ?", list(space_id))
  .wb_copy_db_rows(src, dst, "space_2d", "space_id = ?", list(space_id))
  .wb_copy_db_rows(src, dst, "space_coords", "space_id = ?", list(space_id))
  .wb_copy_db_rows(src, dst, "space_models", "space_id = ?", list(space_id))
  invisible(TRUE)
}
