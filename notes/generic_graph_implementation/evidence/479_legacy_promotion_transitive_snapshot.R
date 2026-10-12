# Internal materialization and staged-overlay transfer for transitive promotion.

.wb_promotion_commit_id <- function(con = NULL) {
  .wb_allocate_db_identifier(
    con, "prov_commits", "commit_id",
    paste0("commit_", format(Sys.time(), "%Y%m%d_%H%M%S"), "_"),
    n = 8L, purpose = "promotion commit"
  )
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

.wb_stage_copy_fragment_memberships <- function(from_con, to_con, fragments) {
  if (!nrow(fragments)) return(invisible(0L))
  copied <- 0L
  for (i in seq_len(nrow(fragments))) {
    fragment_id <- as.character(fragments$fragment_id[[i]])
    declared_features <- as.character(jsonlite::fromJSON(fragments$feature_ids_json[[i]]))
    declared_cells <- as.character(jsonlite::fromJSON(fragments$cell_ids_json[[i]]))
    source_features <- as.character(DBI::dbGetQuery(
      from_con,
      "SELECT feature_id FROM matrix_fragment_features WHERE fragment_id = ?;",
      params = list(fragment_id)
    )$feature_id)
    source_cells <- as.character(DBI::dbGetQuery(
      from_con,
      "SELECT cell_id FROM matrix_fragment_cells WHERE fragment_id = ?;",
      params = list(fragment_id)
    )$cell_id)
    .wb_assert(length(source_features) == length(declared_features) &&
                 setequal(source_features, declared_features), paste0(
      "Staged matrix fragment feature registry contradicts its declared identities: ", fragment_id
    ))
    .wb_assert(length(source_cells) == length(declared_cells) &&
                 setequal(source_cells, declared_cells), paste0(
      "Staged matrix fragment cell registry contradicts its declared identities: ", fragment_id
    ))
    .wb_db_append_chunked(to_con, "matrix_fragment_features", data.frame(
      fragment_id = rep(fragment_id, length(declared_features)),
      feature_id = declared_features,
      stringsAsFactors = FALSE
    ))
    .wb_db_append_chunked(to_con, "matrix_fragment_cells", data.frame(
      fragment_id = rep(fragment_id, length(declared_cells)),
      cell_id = declared_cells,
      stringsAsFactors = FALSE
    ))
    copied <- copied + length(declared_features) + length(declared_cells)
  }
  invisible(copied)
}

.wb_prepare_staged_payload <- function(staging_bundle, workspace, rel_path) {
  rel_path <- as.character(rel_path %||% "")[1]
  status <- .wb_path_status(staging_bundle$dir, rel_path, expected_type="either",
                            must_exist=TRUE, purpose="staged promotion payload")
  .wb_assert(isTRUE(status$ok), paste0(status$code, ": unsafe staged payload path"))
  rel_path <- status$relative
  src <- status$absolute
  parents <- names(workspace$mappings)[vapply(names(workspace$mappings),
    function(path) startsWith(rel_path, paste0(path, "/")), logical(1))]
  if (length(parents)) {
    parent <- parents[[which.max(nchar(parents))]]
    mapped_root <- as.character(workspace$mappings[[parent]]$source %||% "")[1]
    suffix <- substring(rel_path, nchar(parent) + 2L)
    expected <- normalizePath(file.path(mapped_root, suffix), winslash = "/",
      mustWork = TRUE)
    observed <- normalizePath(src, winslash = "/", mustWork = TRUE)
    .wb_assert(identical(expected, observed), paste0(
      "Promotion payload ancestry collision for '", rel_path, "'."))
    return(invisible(rel_path))
  }
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
  model_path <- as.character(prim$model_tree_root %||%
    prim$model_path %||% "")[1]
  if (!nzchar(model_path)) return(invisible(workspace))

  candidate <- if (.wb_path_is_absolute(model_path)) model_path else .wb_bundle_path_require(staging_bundle, model_path, expected_type="either", purpose="staged model_ref")
  .wb_assert(file.exists(candidate) || dir.exists(candidate), paste0(
    "Staged model_ref payload does not exist: ", model_path
  ))
  source_abs <- normalizePath(candidate, winslash = "/", mustWork = TRUE)
  tree <- prim$model_tree_manifest %||% NULL
  if (!is.null(tree)) {
    .wb_operation_pack_v3_assert_model_tree_manifest(tree,
      as.character(prim$engine %||% "")[1],
      as.character(prim$model_type %||% prim$engine %||% "")[1],
      code = "PYBENCH_OUTPUT_INVALID", phase = "promotion")
    observed <- .wb_operation_pack_v3_model_tree_manifest(source_abs,
      tree$engine, tree$model_type, tree$primary_path,
      code = "PYBENCH_OUTPUT_INVALID", phase = "promotion")
    .wb_assert(identical(observed, tree),
      "Contained model tree changed before promotion staging.")
    payload <- .wb_operation_pack_v3_model_payload_identity(observed)
    .wb_assert(is.null(prim$model_payload_manifest_identity) || identical(
      payload, prim$model_payload_manifest_identity),
      "Contained model payload identity changed before promotion staging.")
    already <- names(workspace$mappings)[vapply(workspace$mappings,
      function(mapping) identical(as.character(mapping$source %||% "")[1],
        source_abs), logical(1))]
    if (length(already)) return(invisible(workspace))
    final_rel <- file.path("artifact_models", workspace$commit_id,
      paste0("model_tree_", tree$manifest_identity$sha256))
    pending <- .wb_promotion_workspace_path(workspace, final_rel)
    workspace$mappings[[final_rel]]$source <- source_abs
    .wb_operation_pack_v3_copy_model_tree(source_abs, tree, pending)
    return(invisible(workspace))
  }
  stage_rel <- .wb_path_relative_to_root(source_abs, staging_bundle$dir)
  if (!is.null(stage_rel) && nzchar(stage_rel)) {
    .wb_prepare_staged_payload(staging_bundle, workspace, stage_rel)
    return(invisible(workspace))
  }
  base_rel <- .wb_path_relative_to_root(source_abs, bundle$dir)
  if (!is.null(base_rel)) return(invisible(workspace))
  .wb_assert(!is.null(stage_rel) && nzchar(stage_rel), paste0(
    "model_ref promotion may only retain bundle-owned or session-staged payloads: ", model_path
  ))
  invisible(workspace)
}

.wb_stage_prepare_space_payloads <- function(staging_bundle, bundle, workspace,
                                              space_id) {
  payload <- if (.wb_table_exists(staging_bundle$con, "space_payloads")) {
    DBI::dbGetQuery(staging_bundle$con, "SELECT path FROM space_payloads WHERE space_id = ?;",
                    params = list(space_id))
  } else data.frame()
  if (nrow(payload)) for (path in unique(as.character(payload$path))) {
    if (nzchar(path)) .wb_prepare_staged_payload(staging_bundle, workspace, path)
  }
  sm <- if (.wb_table_exists(staging_bundle$con, "space_models")) {
    DBI::dbGetQuery(staging_bundle$con, "SELECT * FROM space_models WHERE space_id = ?;", params = list(space_id))
  } else data.frame()
  if (nrow(sm) && "model_path" %in% names(sm)) {
    paths <- unique(as.character(sm$model_path))
    for (path in paths[nzchar(paths)]) {
      staged <- tryCatch(.wb_bundle_path_require(staging_bundle, path,
        expected_type = "either", must_exist = TRUE,
        purpose = "staged space model"), error = function(e) NULL)
      if (!is.null(staged) && !is.null(
          .wb_promotion_workspace_final_rel_for_source(workspace, staged)))
        next
      durable <- tryCatch(.wb_bundle_path_require(bundle, path,
        expected_type = "either", must_exist = TRUE,
        purpose = "durable space model"), error = function(e) NULL)
      if (is.null(durable))
        .wb_prepare_staged_payload(staging_bundle, workspace, path)
    }
  }
  invisible(workspace)
}

.wb_stage_assert_publication_replace <- function(bundle, prim, kind, id) {
  grant <- prim$publication_grant %||% NULL
  schema <- as.character(grant$schema %||% "")[1]
  ordinary <- identical(schema,
    "scworkbench.operation_pack.materialization_publication_grant.v1")
  space2d <- identical(schema,
    "scworkbench.operation_pack.space_2d_publication_grant.v1")
  valid_mode <- if (ordinary) identical(as.character(grant$mode)[1],
    "replace") else space2d && as.character(grant$mode)[1] %in%
      c("selected_cell_merge", "full_replace")
  valid_kind <- identical(as.character(grant$target_kind)[1], kind) ||
    (space2d && identical(kind, "space") &&
      identical(as.character(grant$target_kind)[1], "space_2d"))
  .wb_assert(is.list(grant) && valid_mode && valid_kind &&
      identical(as.character(grant$target_id)[1], id), paste0(
        "Cannot replace committed ", kind, " without its exact authenticated publication grant: ", id))
  preimage_kind <- if (space2d) "space_2d" else kind
  current <- .wb_operation_pack_v3_materialization_preimage(bundle,
    preimage_kind,
    id, grant$preimage$transition_source_state_identity)
  if (space2d && identical(current$state, "present")) {
    value <- wb_space(bundle, id)
    if (is.data.frame(value)) value <- .wb_as_coord_matrix(value)
    current$cell_order_identity <- .wb_operation_pack_v2_identity_plain(
      "scworkbench.cell_order.v1", unname(as.list(rownames(value))))
    current$coordinate_dimensions <- 2L
  }
  .wb_assert(identical(.wb_operation_pack_canonical_json(current),
      .wb_operation_pack_canonical_json(grant$preimage)), paste0(
        "Committed ", kind, " changed after the replacement grant was issued: ", id))
  invisible(grant)
}

.wb_stage_commit_matrix <- function(staging_bundle, bundle, matrix_id,
                                    prim = NULL, workspace = NULL) {
  src <- staging_bundle$con
  dst <- bundle$con
  exists <- DBI::dbGetQuery(dst, "SELECT matrix_id FROM matrices WHERE matrix_id = ?;", params = list(matrix_id))
  old_paths <- character()
  if (nrow(exists)) {
    .wb_stage_assert_publication_replace(bundle, prim, "matrix", matrix_id)
    old_paths <- unique(c(as.character(DBI::dbGetQuery(dst,
      "SELECT path FROM matrices WHERE matrix_id=?;", params = list(matrix_id))$path),
      as.character(DBI::dbGetQuery(dst,
        "SELECT path FROM matrix_fragments WHERE matrix_id=?;",
        params = list(matrix_id))$path)))
    .wb_operation_pack_v3_retire_materialization_binding(dst, "matrix",
      matrix_id)
    .wb_operation_pack_v3_delete_matrix_registry(dst, matrix_id)
  }
  row <- DBI::dbGetQuery(src, "SELECT * FROM matrices WHERE matrix_id = ?;", params = list(matrix_id))
  .wb_assert(nrow(row) == 1L, paste0("Staged matrix is missing: ", matrix_id))
  frags <- DBI::dbGetQuery(src, "SELECT * FROM matrix_fragments WHERE matrix_id = ? ORDER BY fragment_id;", params = list(matrix_id))
  .wb_copy_db_rows(src, dst, "matrices", "matrix_id = ?", list(matrix_id))
  .wb_copy_db_rows(src, dst, "features", "matrix_id = ?", list(matrix_id))
  .wb_copy_db_rows(src, dst, "matrix_fragments", "matrix_id = ?", list(matrix_id))
  if (nrow(frags)) {
    .wb_stage_copy_fragment_memberships(src, dst, frags)
  }
  if (!is.null(workspace) && length(old_paths)) {
    new_paths <- unique(c(as.character(row$path), as.character(frags$path)))
    for (path in setdiff(old_paths[nzchar(old_paths)], new_paths))
      .wb_promotion_workspace_retire_after_commit(workspace, path)
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
        if (nrow(exists)) .wb_stage_assert_publication_replace(bundle, prim,
          "matrix", as.character(prim$matrix_id)[1])
        .wb_stage_prepare_matrix_payloads(staging_bundle, workspace, prim$matrix_id)
      }
      if (.wb_is_primitive(prim) && prim$kind %in% c("space", "space_2d")) {
        exists <- DBI::dbGetQuery(bundle$con, "SELECT space_id FROM spaces WHERE space_id = ?;", params = list(prim$space_id))
        if (nrow(exists) && !is.null(prim$publication_grant))
          .wb_stage_assert_publication_replace(bundle, prim, "space",
            as.character(prim$space_id)[1])
        else if (nrow(exists) && !identical(as.character(
            prim$promotion_mode %||% "")[1], "merge_space_2d"))
          .wb_stage_assert_publication_replace(bundle, prim, "space",
            as.character(prim$space_id)[1])
        .wb_stage_prepare_space_payloads(staging_bundle, bundle, workspace,
          prim$space_id)
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
  model_path <- as.character(prim$model_tree_root %||%
    prim$model_path %||% "")[1]
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
  if (!is.null(prim$model_tree_manifest))
    prim$model_tree_root <- as.character(mapped_rel)[1]
  prim
}

.wb_committed_materialization <- function(bundle, run_id, output_name) {
  if (!.wb_table_exists(bundle$con, "prov_materializations") ||
      !.wb_table_exists(bundle$con, "prov_commits")) return(data.frame())
  DBI::dbGetQuery(
    bundle$con,
    paste0("SELECT pm.path, pm.primitive_kind, pm.output_hash, pm.content_sha256, ",
     if (.wb_db_has_column(bundle$con, "prov_materializations", "output_hash_scheme")) "pm.output_hash_scheme" else "NULL AS output_hash_scheme", ", ",
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
        source <- .wb_bundle_path_require(
          workspace$bundle, as.character(prior$path[1]), expected_type="file",
          purpose=paste0("committed materialization ",rid,"::",nm)
        )
        pending <- .wb_promotion_workspace_path(workspace, rel)
        .wb_assert(isTRUE(file.copy(source, pending, copy.date = TRUE)), paste0(
          "Failed to stage committed materialization for run=", rid, ", output=", nm
        ))
        primitive_kind <- as.character(prior$primitive_kind[1])
        output_hash <- as.character(prior$output_hash[1])
        output_hash_scheme <- as.character(prior$output_hash_scheme[1] %||% unname(.wb_identity_schemes()[["legacy"]]))
      } else {
        prim <- .wb_materialization_primitive(workspace, prim)
        saveRDS(prim, .wb_promotion_workspace_path(workspace, rel), version = 3)
        primitive_kind <- as.character(prim$kind)
        output_hash <- .wb_prov_materialization_hash(prim)
        output_hash_scheme <- unname(.wb_identity_schemes()[["materialization"]])
      }
      content_sha256 <- .wb_prov_sha256_file(.wb_promotion_workspace_path(workspace, rel))
      i <- i + 1L
      rows[[i]] <- data.frame(
        commit_id = commit_id, run_id = rid, output_name = nm,
        primitive_kind = primitive_kind, path = rel,
        output_hash = output_hash,
        output_hash_scheme = output_hash_scheme,
        content_sha256 = content_sha256,
        content_identity_scheme = unname(.wb_content_identity_schemes()[["raw_file"]]),
        stringsAsFactors = FALSE
      )
    }
  }
  if (length(rows)) do.call(rbind, rows) else data.frame()
}

.wb_stage_commit_space <- function(staging_bundle, bundle, space_id, prim = NULL,
                                   workspace = NULL) {
  src <- staging_bundle$con
  dst <- bundle$con
  exists <- DBI::dbGetQuery(dst, "SELECT space_id FROM spaces WHERE space_id = ?;", params = list(space_id))
  if (nrow(exists)) {
    replacement <- .wb_is_primitive(prim) && !is.null(
      prim$publication_grant) && as.character(
        prim$publication_grant$mode)[1] %in% c("replace",
          "selected_cell_merge", "full_replace")
    if (replacement) .wb_stage_assert_publication_replace(bundle, prim,
      "space", space_id) else .wb_assert(.wb_is_primitive(prim) &&
        identical(as.character(prim$promotion_mode %||% "")[1],
          "merge_space_2d"), paste0(
            "Cannot replace committed space during promotion: ", space_id))
    if (!replacement) .wb_entity_assert_replaceable(bundle, "space", space_id,
      action = "merge into")
    if (replacement) .wb_operation_pack_v3_retire_materialization_binding(
      dst, "space", space_id)
    staged_space <- DBI::dbGetQuery(src, "SELECT * FROM spaces WHERE space_id = ?;", params = list(space_id))
    staged_payload <- DBI::dbGetQuery(src, "SELECT * FROM space_payloads WHERE space_id = ?;", params = list(space_id))
    .wb_assert(nrow(staged_space) == 1L && nrow(staged_payload) == 1L,
               paste0("Staged dense-space merge is incomplete for ", space_id, "."))
    old_payload <- DBI::dbGetQuery(dst, "SELECT path FROM space_payloads WHERE space_id = ?;",
                                  params = list(space_id))
    DBI::dbExecute(dst, "DELETE FROM space_payloads WHERE space_id = ?;", params = list(space_id))
    DBI::dbExecute(dst,
      "UPDATE spaces SET source=?, dims=?, storage=?, description=? WHERE space_id=?;",
      params = list(staged_space$source[[1L]], staged_space$dims[[1L]], staged_space$storage[[1L]],
                    staged_space$description[[1L]], space_id))
    .wb_db_append_chunked(dst, "space_payloads", staged_payload)
    if (!is.null(workspace) && nrow(old_payload)) {
      old_paths <- setdiff(as.character(old_payload$path), as.character(staged_payload$path))
      for (path in old_paths[nzchar(old_paths)]) {
        .wb_promotion_workspace_retire_after_commit(workspace, path)
      }
    }
    return(invisible(TRUE))
  }
  row <- DBI::dbGetQuery(src, "SELECT * FROM spaces WHERE space_id = ?;", params = list(space_id))
  .wb_assert(nrow(row) == 1L, paste0("Staged space is missing: ", space_id))
  staged_model <- .wb_table_exists(src, "space_models") && nrow(DBI::dbGetQuery(src, "SELECT space_id FROM space_models WHERE space_id = ?;", params = list(space_id))) > 0L
  if (isTRUE(staged_model)) .wb_ensure_space_models_table(dst)
  .wb_copy_db_rows(src, dst, "spaces", "space_id = ?", list(space_id))
  .wb_copy_db_rows(src, dst, "space_payloads", "space_id = ?", list(space_id))
  if (isTRUE(staged_model)) {
    model <- DBI::dbGetQuery(src,
      "SELECT * FROM space_models WHERE space_id = ?;", params = list(space_id))
    if (!is.null(workspace)) {
      staged_path <- .wb_bundle_path_require(staging_bundle,
        as.character(model$model_path[[1L]]), expected_type = "either",
        must_exist = TRUE, purpose = "staged space model")
      mapped <- .wb_promotion_workspace_final_rel_for_source(workspace,
        staged_path)
      if (!is.null(mapped)) model$model_path[[1L]] <- mapped
    }
    .wb_db_append_chunked(dst, "space_models", model)
  }
  invisible(TRUE)
}
