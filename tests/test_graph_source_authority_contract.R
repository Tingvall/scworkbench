test_graph_retained_cell_source_payload_contract <- function() {
  root <- tempfile("graph_source_authority_")
  bundle <- wb_init_bundle(root)
  on.exit({try(wb_close_bundle(bundle), silent = TRUE); unlink(root, recursive = TRUE)}, add = TRUE)
  cells <- c("cell_2", "cell_10", "cell_1")
  wb_define_cells(bundle, cells)
  values <- list(
    categorical = wb_prim_cell_vector(stats::setNames(c("z", "a", "z"), cells),
      meta = list(label = "東京", ordered = c(2L, 1L))),
    continuous = wb_prim_cell_vector(stats::setNames(c(2.5, 1.7, 1), cells),
      value_type = "continuous", meta = list(label = "measure")),
    family = wb_prim_cell_vector_family(c("b", "a", "b", "a"),
      c("cell_2", "cell_1", "cell_10", "cell_2"), c(.2, NA_real_, .4, .8),
      value_type = "probability", meta = list(label = "family", order = c(2L, 1L))))
  for (value in values) {
    run <- wb_new_run("metadata_cell_vector", inputs = list(cell_set = "all"),
      params = list(), outputs = list(vector = value))
    result <- wb_promote_analysis(bundle, stats::setNames(list(run), run$run_id),
      head_run_id = run$run_id, outputs = "vector")
    artifact <- result$promoted$artifact_id[[1]]
    loaded <- wb_art_load(bundle, artifact)
    stopifnot(identical(unclass(value), unclass(loaded)))
    expected <- scworkbench:::.wb_graph_object_verify(bundle$con, artifact)
    snapshot <- DBI::dbGetQuery(bundle$con,
      "SELECT h.* FROM prov_heads h JOIN artifacts a ON a.provenance_snapshot_id=h.snapshot_id WHERE a.artifact_id=?;",
      params = list(artifact))
    snapshot_identity <- scworkbench:::.wb_operation_pack_v3_head_snapshot(snapshot)$source_snapshot_identity
    snapshot_identity$scope <- NULL
    source_ref <- list(kind = "retained_cell_axis", source_id = artifact)
    axis <- scworkbench:::.wb_graph_source_axis_hash(bundle, source_ref, "cell",
      scworkbench:::.wb_graph_budgets())
    binding <- list(binding_id = "view", axis_kind = "cell", source_ref = source_ref,
      source_snapshot_identity = snapshot_identity,
      axis_content_identity = axis$axis_content_identity, axis_order_identity = axis$axis_order_identity)
    admitted <- scworkbench:::.wb_graph_source_authorize(bundle, binding,
      scworkbench:::.wb_graph_budgets())
    stopifnot(identical(admitted$source_payload_closure_identity, expected))
    # Explicit CV/CVF source declarations grant the full independently
    # certified retained axis, not an incidental in-memory cell-id array.
    declaration <- list(name = "result", axis_sources = list(list(input_name = "signal",
      axis_kind = "cell", selection_mode = "retained_input_axis", source_binding_selector = NULL)))
    authorities <- scworkbench:::.wb_operation_pack_v4_graph_axis_authorities(bundle,
      declaration, list(signal = loaded), list(), list(signal = wb_ref_artifact(artifact, "vector")),
      list(scheme = "scworkbench.operation_pack.transition.v2", scope = "transition excluding transition_identity",
        sha256 = strrep("a", 64L)))
    stopifnot(length(authorities) == 1L, authorities[[1L]]$axis_count == as.character(length(unique(value$cell_id))),
      identical(authorities[[1L]]$source_payload_closure_identity, expected))
    scworkbench:::.wb_operation_pack_v4_graph_authorities_assert(bundle,
      list(authorized_source_axes = authorities))
    reordered <- loaded; reordered$cell_id <- rev(reordered$cell_id)
    stopifnot(inherits(tryCatch(scworkbench:::.wb_operation_pack_v4_graph_axis_authorities(bundle,
      declaration, list(signal = reordered), list(), list(signal = wb_ref_artifact(artifact, "vector")),
      authorities[[1L]]$transition_identity), error = identity), "wb_graph_error"))
    original_heads <- snapshot$head_run_ids_json[[1L]]
    for (heads in list(list("foreign_run"), list(run$run_id, run$run_id))) {
      DBI::dbExecute(bundle$con, "UPDATE prov_heads SET head_run_ids_json=? WHERE snapshot_id=?;",
        params = list(scworkbench:::.wb_operation_pack_canonical_json(heads), snapshot$snapshot_id[[1L]]))
      mutated <- snapshot; mutated$head_run_ids_json <- scworkbench:::.wb_operation_pack_canonical_json(heads)
      forged_snapshot <- scworkbench:::.wb_operation_pack_v3_head_snapshot(mutated)$source_snapshot_identity
      forged_snapshot$scope <- NULL
      stopifnot(inherits(tryCatch(scworkbench:::.wb_graph_source_snapshot(bundle, forged_snapshot,
        scworkbench:::.wb_graph_budgets()), error = identity), "wb_graph_error"))
    }
    DBI::dbExecute(bundle$con, "UPDATE prov_heads SET head_run_ids_json=? WHERE snapshot_id=?;",
      params = list(original_heads, snapshot$snapshot_id[[1L]]))
    numeric_column <- if (value$kind == "cell_vector") "value_num" else "pseudotime"
    payload_table <- if (value$kind == "cell_vector") "artifact_labels" else "artifact_pseudotime"
    numeric_before <- DBI::dbGetQuery(bundle$con, paste0("SELECT ", numeric_column,
      " FROM ", payload_table, " WHERE artifact_id=? AND payload_ordinal=0;"), params = list(artifact))[[1L]][[1L]]
    DBI::dbExecute(bundle$con, paste0("UPDATE ", payload_table, " SET ", numeric_column,
      "=? WHERE artifact_id=? AND payload_ordinal=0;"), params = list(strrep("x", 1048577), artifact))
    stopifnot(inherits(tryCatch(scworkbench:::.wb_graph_object_verify(bundle$con, artifact), error = identity),
      "wb_graph_error"))
    DBI::dbExecute(bundle$con, paste0("UPDATE ", payload_table, " SET ", numeric_column,
      "=? WHERE artifact_id=? AND payload_ordinal=0;"), params = list(numeric_before, artifact))
    original_certificate <- DBI::dbGetQuery(bundle$con,
      "SELECT content_identity_scheme,content_sha256 FROM prov_run_outputs WHERE artifact_id=?;",
      params = list(artifact))
    for (field in c("content_identity_scheme", "content_sha256")) {
      DBI::dbExecute(bundle$con, paste0("UPDATE prov_run_outputs SET ", field,
        "=? WHERE artifact_id=?;"), params = list(if (field == "content_sha256")
          paste(rep("0", 64L), collapse = "") else "unknown.identity.v1", artifact))
      stopifnot(inherits(tryCatch(scworkbench:::.wb_graph_source_authorize(bundle, binding,
        scworkbench:::.wb_graph_budgets()), error = identity), "wb_graph_error"))
      DBI::dbExecute(bundle$con, paste0("UPDATE prov_run_outputs SET ", field,
        "=? WHERE artifact_id=?;"), params = list(original_certificate[[field]][[1]], artifact))
    }
    other_kind <- if (value$kind == "cell_vector") "cell_vector_family" else "cell_vector"
    for (table in c("artifacts", "prov_run_outputs")) {
      field <- if (table == "artifacts") "type" else "primitive_kind"
      DBI::dbExecute(bundle$con, paste0("UPDATE ", table, " SET ", field,
        "=? WHERE artifact_id=?;"), params = list(other_kind, artifact))
      stopifnot(inherits(tryCatch(scworkbench:::.wb_graph_source_authorize(bundle, binding,
        scworkbench:::.wb_graph_budgets()), error = identity), "wb_graph_error"))
      DBI::dbExecute(bundle$con, paste0("UPDATE ", table, " SET ", field,
        "=? WHERE artifact_id=?;"), params = list(value$kind, artifact))
    }
    actual_cells <- unique(value$cell_id)
    stopifnot(identical(axis$axis_order_identity$sha256,
      scworkbench:::.wb_graph_identity("scworkbench.cell_order.v1", as.list(actual_cells))$sha256))
    graph <- wb_prim_graph(lapply(actual_cells, function(cell) list(node_id = cell)),
      list(), list(), associations = list(c(binding,
        list(mapping = lapply(actual_cells, function(cell) list(node_id = cell, axis_id = cell))))))
    stage <- scworkbench:::.wb_graph_stage_small(graph)
    tryCatch(scworkbench:::.wb_graph_sources_assert(bundle, stage$con, "staged", stage$budgets),
      finally = scworkbench:::.wb_graph_stage_discard(stage))
    table <- if (value$kind == "cell_vector") "artifact_labels" else "artifact_pseudotime"
    column <- if (value$kind == "cell_vector") "label" else "pseudotime"
    original <- DBI::dbGetQuery(bundle$con, paste0("SELECT ", column, " FROM ", table,
      " WHERE artifact_id=? AND payload_ordinal=0;"), params = list(artifact))[[1]][[1]]
    DBI::dbExecute(bundle$con, paste0("UPDATE ", table, " SET ", column,
      "=? WHERE artifact_id=? AND payload_ordinal=0;"),
      params = list(if (value$kind == "cell_vector") "altered" else .99, artifact))
    forged <- scworkbench:::.wb_graph_object_closure(bundle$con, artifact)
    DBI::dbExecute(bundle$con,
      "UPDATE artifact_object_payload_meta SET closure_identity_json=? WHERE artifact_id=?;",
      params = list(scworkbench:::.wb_operation_pack_canonical_json(forged), artifact))
    stopifnot(inherits(tryCatch(scworkbench:::.wb_graph_object_verify(bundle$con, artifact),
      error = identity), "wb_graph_error"),
      inherits(tryCatch(scworkbench:::.wb_graph_source_authorize(bundle, binding,
        scworkbench:::.wb_graph_budgets()), error = identity), "wb_graph_error"))
    DBI::dbExecute(bundle$con, paste0("UPDATE ", table, " SET ", column,
      "=? WHERE artifact_id=? AND payload_ordinal=0;"), params = list(original, artifact))
    DBI::dbExecute(bundle$con,
      "UPDATE artifact_object_payload_meta SET closure_identity_json=? WHERE artifact_id=?;",
      params = list(scworkbench:::.wb_operation_pack_canonical_json(expected), artifact))
    stopifnot(identical(scworkbench:::.wb_graph_object_verify(bundle$con, artifact), expected))
    rowid <- DBI::dbGetQuery(bundle$con,
      "SELECT rowid FROM prov_run_outputs WHERE artifact_id=?;", params = list(artifact))$rowid[[1]]
    DBI::dbExecute(bundle$con, "UPDATE prov_run_outputs SET rowid=-7 WHERE rowid=?;", params = list(rowid))
    stopifnot(inherits(tryCatch(scworkbench:::.wb_graph_object_verify(bundle$con, artifact),
      error = identity), "wb_graph_error"))
    DBI::dbExecute(bundle$con, "UPDATE prov_run_outputs SET rowid=? WHERE rowid=-7;", params = list(rowid))
    chunk <- DBI::dbGetQuery(bundle$con,
      "SELECT chunk FROM artifact_object_metadata_chunks WHERE artifact_id=? AND chunk_ordinal=0;",
      params = list(artifact))$chunk[[1]]
    DBI::dbExecute(bundle$con, "PRAGMA ignore_check_constraints=ON;")
    DBI::dbExecute(bundle$con, "UPDATE artifact_object_metadata_chunks SET chunk=? WHERE artifact_id=?;",
      params = list(list(raw(65537)), artifact))
    stopifnot(inherits(tryCatch(scworkbench:::.wb_graph_object_verify(bundle$con, artifact),
      error = identity), "wb_graph_error"))
    DBI::dbExecute(bundle$con, "UPDATE artifact_object_metadata_chunks SET chunk=? WHERE artifact_id=?;",
      params = list(list(chunk), artifact))
    DBI::dbExecute(bundle$con, "PRAGMA ignore_check_constraints=OFF;")
    stopifnot(identical(scworkbench:::.wb_graph_object_verify(bundle$con, artifact), expected))
    changed <- chunk; changed[[length(changed)]] <- as.raw(0)
    DBI::dbExecute(bundle$con, "UPDATE artifact_object_metadata_chunks SET chunk=? WHERE artifact_id=?;",
      params = list(list(changed), artifact))
    stopifnot(inherits(tryCatch(scworkbench:::.wb_graph_object_verify(bundle$con, artifact),
      error = identity), "wb_graph_error"),
      inherits(tryCatch(wb_art_load(bundle, artifact), error = identity), "error"))
    DBI::dbExecute(bundle$con, "UPDATE artifact_object_metadata_chunks SET chunk=? WHERE artifact_id=?;",
      params = list(list(chunk), artifact))
    stopifnot(identical(scworkbench:::.wb_graph_object_verify(bundle$con, artifact), expected))
  }
  TRUE
}
