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
  DBI::dbAppendTable(to_con, table, rows)
  invisible(nrow(rows))
}

.wb_copy_staged_payload <- function(staging_bundle, bundle, rel_path) {
  rel_path <- as.character(rel_path %||% "")[1]
  .wb_assert(nzchar(rel_path) && !startsWith(rel_path, "/") && !grepl("(^|/)\\.\\.(/|$)", rel_path),
             paste0("Unsafe staged payload path: ", rel_path))
  src <- file.path(staging_bundle$dir, rel_path)
  dst <- file.path(bundle$dir, rel_path)
  .wb_assert(file.exists(src) || dir.exists(src), paste0("Missing staged payload: ", src))
  .wb_assert(!file.exists(dst) && !dir.exists(dst), paste0("Promotion destination already exists: ", dst))
  dir.create(dirname(dst), recursive = TRUE, showWarnings = FALSE)
  ok <- file.copy(src, dirname(dst), recursive = TRUE, copy.date = TRUE)
  .wb_assert(isTRUE(ok) && (file.exists(dst) || dir.exists(dst)), paste0("Failed to copy staged payload: ", rel_path))
  dst
}

.wb_prepare_staged_payload <- function(staging_bundle, workspace, rel_path) {
  rel_path <- as.character(rel_path %||% "")[1]
  .wb_assert(nzchar(rel_path) && !startsWith(rel_path, "/") && !grepl("(^|/)\\.\\.(/|$)", rel_path), "Unsafe staged payload path")
  src <- file.path(staging_bundle$dir, rel_path)
  pending_path <- .wb_promotion_workspace_path(workspace, rel_path)
  .wb_assert(file.exists(src) || dir.exists(src), paste0("Missing staged payload: ", src))
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

.wb_stage_prepare_materializations <- function(staging_bundle, bundle, workspace, runs, topo, commit_id) {
  .wb_assert(inherits(staging_bundle, "scworkbench_bundle"), "staging_bundle must be scworkbench_bundle")
  for (rid in topo) {
    for (prim in unname(runs[[rid]]$outputs %||% list())) {
      if (.wb_is_primitive(prim) && identical(prim$kind, "matrix")) {
        exists <- DBI::dbGetQuery(bundle$con, "SELECT matrix_id FROM matrices WHERE matrix_id = ?;", params = list(prim$matrix_id))
        if (!nrow(exists)) .wb_stage_prepare_matrix_payloads(staging_bundle, workspace, prim$matrix_id)
      }
    }
  }
  .wb_prepare_materialization_payloads(workspace, runs, topo, commit_id)
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
      saveRDS(prim, .wb_promotion_workspace_path(workspace, rel), version = 3)
      i <- i + 1L
      rows[[i]] <- data.frame(
        commit_id = commit_id, run_id = rid, output_name = nm,
        primitive_kind = as.character(prim$kind), path = rel,
        output_hash = .wb_hash_text(serialize(prim, NULL, version = 3)),
        stringsAsFactors = FALSE
      )
    }
  }
  if (length(rows)) do.call(rbind, rows) else data.frame()
}

.wb_stage_commit_space <- function(staging_bundle, bundle, space_id) {
  src <- staging_bundle$con
  dst <- bundle$con
  exists <- DBI::dbGetQuery(dst, "SELECT space_id FROM spaces WHERE space_id = ?;", params = list(space_id))
  if (nrow(exists)) return(invisible(FALSE))
  row <- DBI::dbGetQuery(src, "SELECT * FROM spaces WHERE space_id = ?;", params = list(space_id))
  .wb_assert(nrow(row) == 1L, paste0("Staged space is missing: ", space_id))
  sm <- if (.wb_table_exists(src, "space_models")) DBI::dbGetQuery(src, "SELECT * FROM space_models WHERE space_id = ?;", params = list(space_id)) else data.frame()
  copied <- character(0)
  tryCatch({
    if (nrow(sm) && "model_path" %in% names(sm) && nzchar(as.character(sm$model_path[1]))) {
      copied <- c(copied, .wb_copy_staged_payload(staging_bundle, bundle, as.character(sm$model_path[1])))
    }
    .wb_copy_db_rows(src, dst, "spaces", "space_id = ?", list(space_id))
    .wb_copy_db_rows(src, dst, "space_2d", "space_id = ?", list(space_id))
    .wb_copy_db_rows(src, dst, "space_coords", "space_id = ?", list(space_id))
    .wb_copy_db_rows(src, dst, "space_models", "space_id = ?", list(space_id))
  }, error = function(e) {
    for (p in copied) if (file.exists(p) || dir.exists(p)) unlink(p, recursive = TRUE, force = TRUE)
    stop(e)
  })
  invisible(TRUE)
}

.wb_stage_commit_materializations <- function(staging_bundle, bundle, runs, topo, commit_id) {
  .wb_assert(inherits(staging_bundle, "scworkbench_bundle"), "staging_bundle must be scworkbench_bundle")
  for (rid in topo) {
    run <- runs[[rid]]
    for (prim in unname(run$outputs %||% list())) {
      if (!.wb_is_primitive(prim)) next
      if (identical(prim$kind, "matrix")) .wb_stage_commit_matrix(staging_bundle, bundle, prim$matrix_id)
      if (prim$kind %in% c("space", "space_2d")) .wb_stage_commit_space(staging_bundle, bundle, prim$space_id)
    }
  }
  if (exists("wb_refresh_manifest", mode = "function")) wb_refresh_manifest(bundle)

  root_rel <- file.path("provenance", "materializations", commit_id)
  root_abs <- file.path(bundle$dir, root_rel)
  dir.create(root_abs, recursive = TRUE, showWarnings = FALSE)
  rows <- list()
  i <- 0L
  for (rid in topo) {
    run <- runs[[rid]]
    for (nm in names(run$outputs %||% list())) {
      prim <- run$outputs[[nm]]
      if (!.wb_is_primitive(prim)) next
      rel <- file.path(root_rel, rid, paste0(nm, ".rds"))
      abs <- file.path(bundle$dir, rel)
      dir.create(dirname(abs), recursive = TRUE, showWarnings = FALSE)
      saveRDS(prim, abs, version = 3)
      i <- i + 1L
      rows[[i]] <- data.frame(
        commit_id = commit_id, run_id = rid, output_name = nm,
        primitive_kind = as.character(prim$kind), path = rel,
        output_hash = .wb_hash_text(serialize(prim, NULL, version = 3)),
        stringsAsFactors = FALSE
      )
    }
  }
  if (!length(rows)) return(data.frame())
  do.call(rbind, rows)
}
