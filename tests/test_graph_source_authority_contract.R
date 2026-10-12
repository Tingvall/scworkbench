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
    # Independent small-fixture preimage: the streaming cursor must preserve
    # the earlier ordered-row contract, not merely agree with its own header.
    reference_table <- if (value$kind == "cell_vector") "artifact_labels" else "artifact_pseudotime"
    reference_rows <- DBI::dbGetQuery(bundle$con, paste0("SELECT * FROM ", reference_table,
      " WHERE artifact_id=? ORDER BY payload_ordinal;"), params = list(artifact))
    stopifnot(nrow(reference_rows) <= 4L)
    numeric_field <- if (value$kind == "cell_vector") "value_num" else "pseudotime"
    cursor_plan <- DBI::dbGetQuery(bundle$con, paste0("EXPLAIN QUERY PLAN SELECT payload_ordinal,cell_id,",
      if (value$kind == "cell_vector") "label,value_type,value_num" else "lineage_id,pseudotime",
      " FROM ", reference_table, " WHERE artifact_id=? AND typeof(", numeric_field,
      ") IN ('null','integer','real') AND COALESCE(octet_length(cell_id),0)+",
      if (value$kind == "cell_vector") "COALESCE(octet_length(label),0)+COALESCE(octet_length(value_type),0)" else
        "COALESCE(octet_length(lineage_id),0)",
      "+512<=? ORDER BY payload_ordinal;"), params = list(artifact, 262144L))
    stopifnot(any(grepl(paste0(reference_table, "_payload_order"), cursor_plan$detail, fixed = TRUE)),
      !any(grepl("TEMP B-TREE", cursor_plan$detail, fixed = TRUE)))
    cat("GRAPH_SOURCE_CURSOR_PLAN", value$kind, paste(cursor_plan$detail, collapse = ";"), "\n")
    reference_payload <- lapply(seq_len(nrow(reference_rows)), function(i) {
      row <- reference_rows[i, , drop = FALSE]
      if (value$kind == "cell_vector") list(ordinal = as.character(row$payload_ordinal[[1L]]),
        cell_id = row$cell_id[[1L]], label = row$label[[1L]], value_type = row$value_type[[1L]],
        value_num = wb_graph_encode_finite_f64(row$value_num[[1L]])[[1L]]) else
        list(ordinal = as.character(row$payload_ordinal[[1L]]), cell_id = row$cell_id[[1L]],
          key = row$lineage_id[[1L]], value = wb_graph_encode_finite_f64(row$pseudotime[[1L]])[[1L]])
    })
    reference <- scworkbench:::.wb_graph_identity(
      "scworkbench.artifact.ordered-object-payload.canonical-json.v1",
      list(content_identity = list(scheme = "scworkbench.content.object.canonical-json.v1",
        sha256 = scworkbench:::.wb_prov_sha256_object(unclass(value))), kind = value$kind,
        metadata = list(present = TRUE, encoding = "R.serializeJSON.v1", sha256 =
          digest::digest(charToRaw(enc2utf8(jsonlite::serializeJSON(value$meta, digits = NA))),
            algo = "sha256", serialize = FALSE)), rows = reference_payload,
        schema = "scworkbench.artifact.ordered-object-payload.v1", value_type = value$value_type))
    stopifnot(identical(reference, expected))
    if (value$kind == "cell_vector") {
      last_row <- nrow(reference_rows)
      original_label <- reference_rows$label[[last_row]]
      original_ordinal <- reference_rows$payload_ordinal[[last_row]]
      DBI::dbExecute(bundle$con,
        "UPDATE artifact_labels SET label=? WHERE artifact_id=? AND payload_ordinal=?;",
        params = list(strrep("x", 262145L), artifact, original_ordinal))
      smaller <- scworkbench:::.wb_graph_budgets(list(memory_bytes = "8388608",
        partition_bytes = 262144L, partition_rows = 256L, collect_bytes = 4194304L,
        sqlite_cache_kib = 2048L))
      oversized <- tryCatch(scworkbench:::.wb_graph_object_verify(bundle$con, artifact, smaller),
        error = identity)
      stopifnot(inherits(oversized, "wb_graph_error"),
        grepl("Source record exceeds decoded byte admission", conditionMessage(oversized), fixed = TRUE))
      DBI::dbExecute(bundle$con,
        "UPDATE artifact_labels SET label=? WHERE artifact_id=? AND payload_ordinal=?;",
        params = list(original_label, artifact, original_ordinal))
      stopifnot(identical(scworkbench:::.wb_graph_object_verify(bundle$con, artifact, smaller), expected))
      # Raw bytes fit the SQL predicate, but escaped canonical bytes do not.
      # Fail after opening/fetching the cursor and prove it is retired before
      # retry, rather than leaving SQLite to close a pending result implicitly.
      spill_before <- sort(list.files(tempdir(),
        pattern = "^scwb_(graph_(identity_|tokens_)|object_meta_)", full.names = TRUE))
      DBI::dbExecute(bundle$con,
        "UPDATE artifact_labels SET label=? WHERE artifact_id=? AND payload_ordinal=?;",
        params = list(strrep("\001", 45000L), artifact, original_ordinal))
      escaped <- tryCatch(scworkbench:::.wb_graph_object_verify(bundle$con, artifact, smaller), error = identity)
      stopifnot(inherits(escaped, "wb_graph_error"),
        grepl("Whole-object materialization budget exceeded", conditionMessage(escaped), fixed = TRUE),
        identical(sort(list.files(tempdir(),
          pattern = "^scwb_(graph_(identity_|tokens_)|object_meta_)", full.names = TRUE)), spill_before))
      restoration_warnings <- character()
      withCallingHandlers(DBI::dbExecute(bundle$con,
        "UPDATE artifact_labels SET label=? WHERE artifact_id=? AND payload_ordinal=?;",
        params = list(original_label, artifact, original_ordinal)), warning = function(warning) {
          restoration_warnings <<- c(restoration_warnings, conditionMessage(warning))
          invokeRestart("muffleWarning")
        })
      stopifnot(!length(restoration_warnings),
        identical(scworkbench:::.wb_graph_object_verify(bundle$con, artifact, smaller), expected))
    }
    last_ordinal <- reference_rows$payload_ordinal[[nrow(reference_rows)]]
    DBI::dbExecute(bundle$con, paste0("UPDATE ", reference_table,
      " SET payload_ordinal=? WHERE artifact_id=? AND payload_ordinal=?;"),
      params = list(last_ordinal + 3L, artifact, last_ordinal))
    broken_order <- tryCatch(scworkbench:::.wb_graph_object_verify(bundle$con, artifact), error = identity)
    stopifnot(inherits(broken_order, "wb_graph_error"),
      grepl("Source payload order is not dense", conditionMessage(broken_order), fixed = TRUE))
    DBI::dbExecute(bundle$con, paste0("UPDATE ", reference_table,
      " SET payload_ordinal=? WHERE artifact_id=? AND payload_ordinal=?;"),
      params = list(last_ordinal, artifact, last_ordinal + 3L))
    stopifnot(identical(scworkbench:::.wb_graph_object_verify(bundle$con, artifact), expected))
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
    declaration <- list(name = "result", resource_budgets=list(
      max_spill_bytes="8589934592",max_published_bytes="8589934592",max_wal_bytes="8589934592",
      max_memory_bytes="8388608",max_collect_bytes="4194304",
      partition_limits=list(max_decoded_bytes="262144",max_rows="256")),
      axis_sources = list(list(input_name = "signal",
      axis_kind = "cell", selection_mode = "retained_input_axis", source_binding_selector = NULL)))
    authorities <- scworkbench:::.wb_operation_pack_v4_graph_axis_authorities(bundle,
      declaration, list(signal = loaded), list(), list(signal = wb_ref_artifact(artifact, "vector")),
      list(scheme = "scworkbench.operation_pack.transition.v2", scope = "transition excluding transition_identity",
        sha256 = strrep("a", 64L)))
    stopifnot(length(authorities) == 1L, authorities[[1L]]$axis_count == as.character(length(unique(value$cell_id))),
      identical(authorities[[1L]]$source_payload_closure_identity, expected))
    scworkbench:::.wb_operation_pack_v4_graph_authorities_assert(bundle,
      list(authorized_source_axes = authorities, resource_budgets=declaration$resource_budgets))
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
