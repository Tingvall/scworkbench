test_pybench_protocol_hello_bridge_contract <- function(bundle_dir,
                                                        pybench_python = .wb_pybench_default_python()) {
  if (!file.exists(pybench_python)) {
    return(contract_test_skip(paste("Pybench interpreter not found at", pybench_python)))
  }
  work_parent <- tempfile("scwb_pybench_hello_")
  dir.create(work_parent, recursive = TRUE, showWarnings = FALSE)
  source <- file.path(work_parent, "source.bundle")
  workspace <- file.path(work_parent, "sessions")
  fs::dir_copy(bundle_dir, source)
  b <- wb_open_bundle(source)
  on.exit({ try(wb_close_bundle(b), silent = TRUE); unlink(work_parent, recursive = TRUE, force = TRUE) }, add = TRUE)

  s <- wb_session_create(b, workspace, session_id = "protocol_hello_v2")
  rr <- wb_session_run_op(s, b, "py_protocol_hello", inputs = list(
    cell_set = "core", n_preview = 25L, min_cells = 1L
  ))
  stopifnot(identical(rr$run$params$protocol_version, "pybench-op-v2"),
            all(c("vector", "membership", "summary") %in% names(rr$run$outputs)))
  session_workspace <- rr$session$durable$workspace

  # Replace the R process-local handles, resume the published generation, and
  # promote only from the resumed durable graph.
  wb_close_bundle(b); b <- wb_open_bundle(source)
  resumed <- wb_session_resume(b, session_workspace)
  promoted <- wb_session_promote_current(
    b, resumed, outputs = c("vector", "membership", "summary"),
    created_by = "pybench-v2-hello-contract"
  )
  stopifnot(identical(promoted$session$durable$state, "promoted"),
            nrow(promoted$promoted) == 3L,
            all(promoted$promoted$status == "ok"))
  artifact_ids <- stats::setNames(as.character(promoted$promoted$artifact_id),
                                  as.character(promoted$promoted$output))

  wb_close_bundle(b); b <- wb_open_bundle(source)
  vec <- wb_art_load(b, artifact_ids[["vector"]], expected_kind = "cell_vector")
  mem <- wb_art_load(b, artifact_ids[["membership"]], expected_kind = "relation_family")
  sumt <- wb_art_load(b, artifact_ids[["summary"]], expected_kind = "obs_table")
  stopifnot(identical(as.character(vec$kind), "cell_vector"),
            identical(as.character(vec$value_type), "continuous"), length(vec$cell_id) == 25L,
            identical(as.character(mem$kind), "relation_family"), length(mem$key) == 25L,
            all(as.character(mem$key) == "root:HELLO::lineage:WORLD"),
            identical(as.character(sumt$kind), "obs_table"), nrow(sumt$table) == 1L,
            identical(as.character(sumt$table$metric[1]), "n_cells_written"),
            abs(as.numeric(sumt$table$value[1]) - 25) < 1e-8)
  TRUE
}
