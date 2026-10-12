# Existing retained producer evidence only. Private transition receipts and
# unpromoted session references never become durable matrix source authority.
.wb_graph_matrix_producer_query <- function(snapshot = FALSE) {
  paste0("FROM prov_run_outputs o JOIN prov_run_entity_bindings b ",
    "ON b.snapshot_id=o.snapshot_id AND b.run_id=o.run_id AND b.binding_name=o.output_name ",
    "JOIN prov_runs r ON r.snapshot_id=o.snapshot_id AND r.run_id=o.run_id ",
    "WHERE b.entity_kind='matrix' AND b.entity_id=? AND b.direction='output' ",
    "AND b.relationship_type='MATERIALIZES' AND o.primitive_kind='matrix' ",
    if (snapshot) "AND o.snapshot_id=? " else "")
}

.wb_graph_matrix_producer <- function(bundle, matrix_id, snapshot_id, budgets) {
  con <- bundle$con
  budgets <- .wb_graph_effective_budgets(con, budgets)
  restore <- .wb_graph_aggregate_connection_budget(list(con), budgets)
  on.exit(restore(), add = TRUE)
  query <- .wb_graph_matrix_producer_query(TRUE)
  fields <- c("o.run_id", "o.output_name", "o.content_identity_scheme", "o.content_sha256",
    "o.verification_status", "b.content_hash", "b.content_identity_scheme",
    "r.run_hash", "r.run_hash_scheme", "r.op_name")
  bytes <- paste0("COALESCE(octet_length(", fields, "),0)", collapse = "+")
  stats <- DBI::dbGetQuery(con, paste0("SELECT COUNT(*) n,COALESCE(MAX(", bytes,
    "),0) bytes ", query), params = list(matrix_id, snapshot_id))
  .wb_graph_require(stats$n[[1L]] == 1L, "GRAPH_SOURCE_AUTHORITY_REQUIRED",
    "Matrix must have one independently retained producer output and MATERIALIZES binding in its exact snapshot; promote pending matrices first.")
  .wb_graph_require(stats$bytes[[1L]] <= budgets$partition_bytes,
    "GRAPH_RESOURCE_EXCEEDED", "Matrix producer selector exceeds admission before decoding.")
  row <- DBI::dbGetQuery(con, paste0("SELECT o.run_id,o.output_name,o.content_identity_scheme,",
    "o.content_sha256,o.verification_status,b.content_hash,b.content_identity_scheme binding_scheme,",
    "r.rowid producer_rowid,r.run_hash,r.run_hash_scheme,r.op_name ", query,
    "AND ", bytes, "<=?;"), params = list(matrix_id, snapshot_id, budgets$partition_bytes))
  .wb_graph_require(nrow(row) == 1L && row$verification_status[[1L]] == "content_verified" &&
    row$content_identity_scheme[[1L]] == "scworkbench.content.matrix.fragment-tree.v2" &&
    row$binding_scheme[[1L]] == row$content_identity_scheme[[1L]] &&
    row$content_hash[[1L]] == row$content_sha256[[1L]] &&
    row$run_hash_scheme[[1L]] == unname(.wb_identity_schemes()[["run"]]),
    "GRAPH_SOURCE_AUTHORITY_INVALID", "Matrix producer output, entity binding or run identity disagree.")
  identity <- list(scheme = row$content_identity_scheme[[1L]], sha256 = row$content_sha256[[1L]])
  .wb_graph_identity_assert(identity, "scworkbench.content.matrix.fragment-tree.v2")
  actual_run <- .wb_graph_matrix_producer_run_hash(con, row$producer_rowid[[1L]], budgets)
  .wb_graph_require(identical(actual_run, row$run_hash[[1L]]),
    "GRAPH_SOURCE_AUTHORITY_INVALID", "Matrix producer run differs from its independently retained hash.")
  c(identity, list(run_id = row$run_id[[1L]], output_name = row$output_name[[1L]]))
}

.wb_graph_matrix_producer_run_hash <- function(con, rowid, budgets) {
  budgets <- .wb_graph_effective_budgets(con, budgets)
  restore <- .wb_graph_aggregate_connection_budget(list(con), budgets)
  on.exit(restore(), add = TRUE)
  .wb_graph_storage_fault("producer_hash_budget", list(con = con, budgets = budgets))
  observer <- .wb_matrix_native_byte_observer(con)
  .wb_graph_require(!is.null(observer), "GRAPH_RESOURCE_ACCOUNTING_UNAVAILABLE",
    "Producer run verification requires durable incremental byte observation.")
  on.exit(observer$close(), add = TRUE)
  file_path <- tempfile("scwb_graph_identity_producer_")
  on.exit(unlink(file_path), add = TRUE)
  sink <- file(file_path, "wb")
  total <- 0
  emit <- function(bytes) {
    total <<- total + length(bytes)
    .wb_graph_require(total <= as.numeric(budgets$token_bytes),
      "GRAPH_RESOURCE_EXCEEDED", "Producer run hash exceeds token spill admission.")
    writeBin(bytes, sink)
  }
  tryCatch({
    emit(c(charToRaw("run-integrity-v2"), as.raw(0L)))
    for (column in c("op_name", "params_json", "inputs_json", "symbolic_inputs_json", "execution_inputs_json")) {
      size <- observer$column(rowid, column, "prov_runs")
      emit(c(charToRaw(sprintf("%016x", if (is.null(size)) 2L else as.integer(size))), as.raw(0L)))
      if (is.null(size)) emit(charToRaw("NA")) else {
        reader <- .wb_matrix_native_text_reader(con, rowid, column, budgets, observer, "prov_runs")
        repeat {chunk <- reader$next_chunk(); if (is.null(chunk)) break; emit(charToRaw(enc2utf8(chunk)))}
      }
      flush(sink)
      .wb_graph_spill_admit(budgets)
    }
  }, finally = close(sink))
  observer$finish()
  input <- file(file_path, "rb")
  tryCatch(unclass(as.character(openssl::sha256(input))), finally = close(input))
}
