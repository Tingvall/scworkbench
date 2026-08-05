test_pybench_staging_capability_v2_contract <- function() {
  valid_dir <- file.path("inst", "protocol", "fixtures", "valid")
  invalid_dir <- file.path("inst", "protocol", "fixtures", "invalid")
  for (path in list.files(valid_dir, full.names = TRUE)) {
    x <- jsonlite::read_json(path, simplifyVector = FALSE)
    if (identical(x$message_type, "request")) .wb_pyproto_validate_request(x) else .wb_pyproto_validate_receipt(x)
  }
  for (path in list.files(invalid_dir, full.names = TRUE)) {
    x <- jsonlite::read_json(path, simplifyVector = FALSE)
    stopifnot(inherits(try(.wb_pyproto_validate_request(x), silent = TRUE), "try-error"))
  }

  bundle_dir <- tempfile("scwb_pybench_v2_source_")
  workspace <- tempfile("scwb_pybench_v2_sessions_")
  b <- wb_init_bundle(bundle_dir, overwrite = TRUE)
  on.exit({
    try(wb_close_bundle(b), silent = TRUE)
    unlink(bundle_dir, recursive = TRUE, force = TRUE)
    unlink(workspace, recursive = TRUE, force = TRUE)
  }, add = TRUE)
  wb_define_cells(b, c("c1", "c2"))

  source_before <- .wb_pybench_db_snapshot(b$con)
  direct <- try(.wb_pybench_build_request(
    b, "py_protocol_hello", run_id = "run_direct",
    outputs = list(vector = list(artifact_id = "a_direct", type = "cell_vector"))
  ), silent = TRUE)
  stopifnot(inherits(direct, "try-error"), grepl("PYBENCH_SOURCE_WRITE_ATTEMPT", as.character(direct), fixed = TRUE),
            identical(source_before, .wb_pybench_db_snapshot(b$con)))

  s <- wb_session_create(b, workspace, session_id = "capability_contract")
  stage <- wb_session_view(s)
  stage$pybench_session_binding <- list(
    session_id = s$session_id,
    source_attestation = list(scheme = "scworkbench-scientific-state-v1",
                              content_sha256 = s$durable$source_identity$scientific_state_fingerprint),
    checkpoint_generation = s$durable$checkpoint_generation,
    root_sha256 = .wb_prov_sha256_object(list(session_id = s$session_id,
                                              stage_root = normalizePath(stage$dir, winslash = "/")))
  )

  .wb_with_mutation_context(bundle = stage, route = "session_execution", run_id = "run_planned", op_name = "py_protocol_hello", code = {
    run <- wb_new_run("py_protocol_hello", inputs = list(cell_set = "all"), outputs = list())
    outputs <- .wb_pybench_preregister_outputs(stage, run, list(
      vector = list(type = "cell_vector"), sibling = list(type = "cell_vector")
    ))
    req <- .wb_pybench_build_request(stage, "py_protocol_hello", "run_planned", outputs = outputs["vector"])
    stopifnot(req$protocol_version == "pybench-op-v2", req$run$run_id == "run_planned",
              req$run$session_id == s$session_id)

    mutate_bad <- function(edit, pattern) {
      x <- unserialize(serialize(req, NULL)); x <- edit(x)
      err <- try(.wb_pyproto_validate_request(x), silent = TRUE)
      stopifnot(inherits(err, "try-error"), grepl(pattern, as.character(err), fixed = TRUE))
    }
    mutate_bad(function(x) { x$run$session_id <- "other"; x }, "PYBENCH_CAPABILITY_MISMATCH")
    mutate_bad(function(x) { x$run$run_id <- "other"; x }, "PYBENCH_CAPABILITY_MISMATCH")
    mutate_bad(function(x) { x$execution_capability$source_attestation$content_sha256 <- "bad"; x }, "SHA-256")
    mutate_bad(function(x) { x$execution_capability$staging_identity$root_sha256 <- "bad"; x }, "SHA-256")
    mutate_bad(function(x) { x$execution_capability$write_allowlist[[1]]$output_id <- "sibling"; x }, "PYBENCH_CAPABILITY_MISMATCH")
    mutate_bad(function(x) { x$execution_capability$write_allowlist[[1]]$output_kind <- "obs_table"; x }, "PYBENCH_CAPABILITY_MISMATCH")
    mutate_bad(function(x) { x$execution_capability$write_allowlist[[1]]$key_scope$values <- list("sibling"); x }, "PYBENCH_CAPABILITY_MISMATCH")

    pre_db <- .wb_pybench_db_snapshot(stage$con)
    pre_payload <- .wb_pybench_payload_snapshot(stage$dir)
    clone <- .wb_pybench_clone_bundle(stage)
    on.exit({ try(wb_close_bundle(clone$bundle), silent = TRUE); unlink(clone$root, recursive = TRUE, force = TRUE) }, add = TRUE)
    DBI::dbExecute(clone$bundle$con,
      "INSERT INTO artifact_labels(artifact_id,cell_id,label,value_type,value_num) VALUES (?,?,?,?,?);",
      params = list(outputs$vector$artifact_id, "c1", "ok", "categorical", NA_real_))
    post_db <- .wb_pybench_db_snapshot(clone$bundle$con)
    observed <- .wb_pybench_audit_mutations(pre_db, post_db, pre_payload,
                                             .wb_pybench_payload_snapshot(clone$root), req)
    stopifnot(length(observed) == 1L, observed[[1]]$row_count == 1L,
              grepl("^[a-f0-9]{64}$", observed[[1]]$content_sha256))

    # An undeclared sibling row and schema mutation are rejected in the clone;
    # the visible stage remains byte/content equivalent and can be retried.
    bad_row <- .wb_pybench_clone_bundle(stage)
    DBI::dbExecute(bad_row$bundle$con,
      "INSERT INTO artifact_labels(artifact_id,cell_id,label,value_type,value_num) VALUES (?,?,?,?,?);",
      params = list(outputs$sibling$artifact_id, "c1", "bad", "categorical", NA_real_))
    rejected <- try(.wb_pybench_audit_mutations(pre_db, .wb_pybench_db_snapshot(bad_row$bundle$con), pre_payload,
                                                 .wb_pybench_payload_snapshot(bad_row$root), req), silent = TRUE)
    wb_close_bundle(bad_row$bundle); unlink(bad_row$root, recursive = TRUE, force = TRUE)
    stopifnot(inherits(rejected, "try-error"), grepl("PYBENCH_OUT_OF_SCOPE_MUTATION", as.character(rejected), fixed = TRUE),
              identical(pre_db, .wb_pybench_db_snapshot(stage$con)), identical(pre_payload, .wb_pybench_payload_snapshot(stage$dir)))

    bad_schema <- .wb_pybench_clone_bundle(stage)
    DBI::dbExecute(bad_schema$bundle$con, "CREATE TABLE pybench_escape(x TEXT);")
    rejected <- try(.wb_pybench_audit_mutations(pre_db, .wb_pybench_db_snapshot(bad_schema$bundle$con), pre_payload,
                                                 .wb_pybench_payload_snapshot(bad_schema$root), req), silent = TRUE)
    wb_close_bundle(bad_schema$bundle); unlink(bad_schema$root, recursive = TRUE, force = TRUE)
    stopifnot(inherits(rejected, "try-error"), grepl("SQLite schema changed", as.character(rejected), fixed = TRUE),
              identical(pre_db, .wb_pybench_db_snapshot(stage$con)))
  })
  wb_session_discard(s)
  TRUE
}
