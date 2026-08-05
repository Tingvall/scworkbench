test_pybench_payload_parity_contract <- function(bundle_dir,
                                                 pybench_python = .wb_pybench_default_python()) {
  if (!file.exists(pybench_python)) {
    return(contract_test_skip(paste("PyBench interpreter not found at", pybench_python)))
  }

  b <- wb_open_bundle(bundle_dir)
  on.exit(try(wb_close_bundle(b), silent = TRUE), add = TRUE)
  before_db <- .wb_pybench_db_snapshot(b$con)
  before_payload <- .wb_pybench_payload_snapshot(bundle_dir, ignore_manifest = TRUE)

  script <- tempfile("pybench_direct_writer_rejected_", fileext = ".py")
  on.exit(unlink(script, force = TRUE), add = TRUE)
  writeLines(c(
    "import sys",
    "from pybench import open_bundle, close_bundle",
    "from pybench.artifacts_payload import write_artifact_cell_vector_payload",
    "bundle = open_bundle(sys.argv[1])",
    "try:",
    "    write_artifact_cell_vector_payload(bundle, 'not_authorized', ['c'], ['x'])",
    "finally:",
    "    close_bundle(bundle)"
  ), script)

  out <- suppressWarnings(system2(
    pybench_python, c(script, shQuote(normalizePath(bundle_dir, winslash = "/", mustWork = TRUE))),
    stdout = TRUE, stderr = TRUE
  ))
  status <- as.integer(attr(out, "status") %||% 0L)
  after_db <- .wb_pybench_db_snapshot(b$con)
  after_payload <- .wb_pybench_payload_snapshot(bundle_dir, ignore_manifest = TRUE)

  stopifnot(
    status != 0L,
    any(grepl("READ_ONLY|CAPABILITY|read-only|readonly", out, ignore.case = TRUE)),
    identical(before_db, after_db),
    identical(before_payload, after_payload)
  )
  TRUE
}
