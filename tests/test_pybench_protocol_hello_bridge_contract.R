test_pybench_protocol_hello_bridge_contract <- function(bundle_dir,
                                                        pybench_python = .wb_pybench_default_python()) {
  if (!file.exists(pybench_python)) {
    message("Skipping pybench hello bridge test: pybench interpreter not found at ", pybench_python)
    return(TRUE)
  }

  b <- wb_open_bundle(bundle_dir)
  on.exit(wb_close_bundle(b), add = TRUE)
  con <- b$con

  run <- wb_new_run(
    op_name = "py_protocol_hello",
    inputs = list(cell_set = "core"),
    params = list(n_preview = 25),
    outputs = list(),
    notes = "pybench hello bridge contract test"
  )

  outs_spec <- list(
    vector = list(type = "cell_vector", name = "py hello vector"),
    membership = list(type = "relation_family", name = "py hello membership"),
    summary = list(type = "obs_table", name = "py hello summary")
  )

  prereg <- .wb_pybench_preregister_outputs(
    bundle = b,
    run = run,
    outputs_spec = outs_spec,
    created_by = "test-pybench-bridge"
  )

  created_art_ids <- vapply(prereg, function(x) as.character(x$artifact_id), character(1))
  cleanup <- function() {
    ids <- as.list(unname(created_art_ids))
    if (!length(ids)) return(invisible(TRUE))
    try(DBI::dbExecute(con, paste0(
      "DELETE FROM artifact_labels WHERE artifact_id IN (", paste(rep("?", length(ids)), collapse = ","), ");"
    ), params = ids), silent = TRUE)
    try(DBI::dbExecute(con, paste0(
      "DELETE FROM artifact_relation_rows WHERE artifact_id IN (", paste(rep("?", length(ids)), collapse = ","), ");"
    ), params = ids), silent = TRUE)
    try(DBI::dbExecute(con, paste0(
      "DELETE FROM artifact_tables WHERE artifact_id IN (", paste(rep("?", length(ids)), collapse = ","), ");"
    ), params = ids), silent = TRUE)
    try(DBI::dbExecute(con, paste0(
      "DELETE FROM artifact_table_rows WHERE artifact_id IN (", paste(rep("?", length(ids)), collapse = ","), ");"
    ), params = ids), silent = TRUE)
    try(DBI::dbExecute(con, paste0(
      "DELETE FROM artifacts WHERE artifact_id IN (", paste(rep("?", length(ids)), collapse = ","), ");"
    ), params = ids), silent = TRUE)
    invisible(TRUE)
  }
  on.exit(cleanup(), add = TRUE)

  req <- .wb_pybench_build_request(
    bundle = b,
    op_name = "py_protocol_hello",
    run_id = as.character(run$run_id),
    inputs = list(
      cell_set = "core",
      space_id = "umap.peakvi_space"
    ),
    params = list(n_preview = 25),
    outputs = prereg
  )

  bridge <- .wb_pybench_run_module(
    module = "pybench.ops.py_protocol_hello",
    request = req,
    python_bin = pybench_python
  )

  rec <- bridge$receipt
  stopifnot(identical(as.character(rec$status), "ok"))
  stopifnot(identical(as.character(rec$op_name), "py_protocol_hello"))
  stopifnot(identical(as.character(rec$run_id), as.character(run$run_id)))
  stopifnot(is.list(rec$outputs))
  stopifnot(all(c("vector", "membership", "summary") %in% names(rec$outputs)))

  # R loader is the final compatibility check.
  vec <- wb_art_load(b, prereg$vector$artifact_id, expected_kind = "cell_vector")
  mem <- wb_art_load(b, prereg$membership$artifact_id, expected_kind = "relation_family")
  sumt <- wb_art_load(b, prereg$summary$artifact_id, expected_kind = "obs_table")

  stopifnot(identical(as.character(vec$kind), "cell_vector"))
  stopifnot(identical(as.character(vec$value_type), "continuous"))
  stopifnot(length(vec$cell_id) == 25L)

  stopifnot(identical(as.character(mem$kind), "relation_family"))
  stopifnot(length(mem$key) == 25L)
  stopifnot(all(as.character(mem$key) == "root:HELLO::lineage:WORLD"))
  stopifnot(all(as.numeric(mem$weight) == 1))

  stopifnot(identical(as.character(sumt$kind), "obs_table"))
  stopifnot(is.data.frame(sumt$table), nrow(sumt$table) == 1L)
  stopifnot(all(c("metric", "value", "cell_set") %in% names(sumt$table)))
  stopifnot(identical(as.character(sumt$table$metric[1]), "n_cells_written"))
  stopifnot(abs(as.numeric(sumt$table$value[1]) - 25) < 1e-8)
  stopifnot(identical(as.character(sumt$table$cell_set[1]), "core"))

  TRUE
}
