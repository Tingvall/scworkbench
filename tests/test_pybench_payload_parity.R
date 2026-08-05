test_pybench_payload_parity <- function(pybench_python = .wb_pybench_default_python()) {
  if (!file.exists(pybench_python)) {
    return(contract_test_skip(paste("Pybench interpreter not found at", pybench_python)))
  }

  bundle_dir <- tempfile("scwb_pybench_payload_parity_")
  b <- wb_init_bundle(
    out_dir = bundle_dir,
    bundle_id = "pybench_payload_parity",
    bundle_name = "pybench payload parity fixture",
    overwrite = TRUE
  )
  on.exit(try(wb_close_bundle(b), silent = TRUE), add = TRUE)
  on.exit(unlink(bundle_dir, recursive = TRUE, force = TRUE), add = TRUE)

  cells <- sprintf("cell_%02d", seq_len(12))
  wb_define_cells(
    b,
    cell_ids = cells,
    metadata = data.frame(
      cell_id = cells,
      sample = rep(c("A", "B"), each = 6),
      stringsAsFactors = FALSE
    ),
    dataset_id = rep(c("sample_A", "sample_B"), each = 6),
    set_name = "core",
    source = "pybench_payload_parity",
    created_by = "test"
  )

  run <- wb_new_run(
    op_name = "pybench_payload_parity",
    inputs = list(
      cell_set = "core",
      effective_n = length(cells),
      parents = character(0),
      provenance_refs = list(),
      user_inputs = list()
    ),
    params = list(writer = "pybench.write_artifact_cell_vector_payload"),
    outputs = list(),
    notes = "pybench payload -> R wb_art_load parity test"
  )

  # scworkbench owns artifact registration/provenance. pybench writes payload rows only.
  # There is no exported public API for a writable artifact shell without payload,
  # so this test uses the same internal preregistration helper as the pybench bridges.
  prereg <- .wb_pybench_preregister_outputs(
    bundle = b,
    run = run,
    outputs_spec = list(vector = list(type = "cell_vector", name = "pybench parity cell vector")),
    created_by = "test-pybench-parity"
  )
  artifact_id <- as.character(prereg$vector$artifact_id)
  stopifnot(nzchar(artifact_id))

  cfg <- list(
    bundle_dir = normalizePath(bundle_dir, winslash = "/", mustWork = TRUE),
    artifact_id = artifact_id,
    cell_id = cells,
    value = rep(c("alpha", "beta", "gamma"), each = 4),
    value_type = "categorical"
  )
  cfg_path <- tempfile("pybench_cell_vector_cfg_", fileext = ".json")
  py_path <- tempfile("pybench_cell_vector_write_", fileext = ".py")
  on.exit(unlink(c(cfg_path, py_path), force = TRUE), add = TRUE)

  jsonlite::write_json(cfg, cfg_path, auto_unbox = TRUE, pretty = TRUE)
  writeLines(c(
    "import json, sys",
    "from pybench import open_bundle, close_bundle",
    "from pybench.artifacts_payload import write_artifact_cell_vector_payload",
    "",
    "cfg = json.load(open(sys.argv[1]))",
    "b = open_bundle(cfg['bundle_dir'])",
    "try:",
    "    write_artifact_cell_vector_payload(",
    "        b,",
    "        artifact_id=cfg['artifact_id'],",
    "        cell_id=cfg['cell_id'],",
    "        value=cfg['value'],",
    "        value_type=cfg.get('value_type', 'categorical'),",
    "    )",
    "finally:",
    "    close_bundle(b)"
  ), py_path)

  out <- system2(pybench_python, c(py_path, cfg_path), stdout = TRUE, stderr = TRUE)
  status <- attr(out, "status") %||% 0L
  stopifnot(as.integer(status) != 0L,
            DBI::dbGetQuery(b$con, "SELECT count(*) n FROM artifact_labels WHERE artifact_id=?;",
                            params = list(artifact_id))$n[1] == 0L,
            !length(list.files(file.path(bundle_dir, "artifact_models"), all.files = TRUE, no.. = TRUE)))

  TRUE
}
