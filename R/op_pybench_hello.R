# Lightweight end-to-end protocol operation used to qualify the R/Python
# boundary without invoking a scientific training runtime.

wb_op_py_protocol_hello <- function(bundle, cell_set = "all", n_preview = 25L,
                                    python_bin = .wb_pybench_default_python()) {
  .wb_assert_operation_execution(bundle, "py_protocol_hello")
  n_preview <- as.integer(n_preview)[1]
  .wb_assert(!is.na(n_preview) && n_preview >= 1L, "py_protocol_hello n_preview must be >= 1")
  run_tmp <- wb_new_run("py_protocol_hello", inputs = list(cell_set = cell_set), outputs = list())
  specs <- list(
    vector = list(type = "cell_vector", name = "PyBench hello vector"),
    membership = list(type = "relation_family", name = "PyBench hello membership"),
    summary = list(type = "obs_table", name = "PyBench hello summary")
  )
  prereg <- .wb_pybench_preregister_outputs(bundle, run_tmp, specs, created_by = "pybench-protocol-v2")
  ids <- vapply(prereg, function(x) as.character(x$artifact_id), character(1))
  ok <- FALSE
  on.exit(if (!ok) .wb_pybench_cleanup_staging_artifacts(bundle, ids, keep_model_files = FALSE), add = TRUE)
  request <- .wb_pybench_build_request(
    bundle, "py_protocol_hello", .wb_pybench_current_run_id(bundle),
    inputs = list(cell_set = as.character(cell_set)[1]),
    params = list(n_preview = n_preview), outputs = prereg
  )
  .wb_pybench_bridge_run_or_stop(bundle = bundle, module = "pybench.ops.py_protocol_hello",
                                  request = request, python_bin = python_bin)
  outputs <- list(
    vector = wb_art_load(bundle, prereg$vector$artifact_id, expected_kind = "cell_vector"),
    membership = wb_art_load(bundle, prereg$membership$artifact_id, expected_kind = "relation_family"),
    summary = wb_art_load(bundle, prereg$summary$artifact_id, expected_kind = "obs_table")
  )
  ok <- TRUE
  list(outputs = outputs, params = list(cell_set = as.character(cell_set)[1], n_preview = n_preview,
                                        protocol_version = .wb_pyproto_version()))
}
