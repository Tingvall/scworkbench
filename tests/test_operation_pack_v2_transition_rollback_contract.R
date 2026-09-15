test_operation_pack_v2_transition_rollback_contract <- function() {
  contract_test_activate_core_conformance_pack()
  bundle <- wb_init_bundle(tempfile("scwb-conformance-rollback-"))
  on.exit(wb_close_bundle(bundle), add = TRUE)
  cells <- paste0("c", 1:6)
  a <- wb_prim_cell_vector(stats::setNames(1:6, cells), "continuous")
  b <- wb_prim_cell_vector(stats::setNames(6:1, cells), "continuous")
  execute <- getFromNamespace(".wb_operation_pack_v2_execute", "scworkbench")
  fingerprint <- function() .wb_manifest_registry_snapshot(bundle$con)$fingerprint
  before <- fingerprint()
  events <- list(resolved = c("OPERATION_PACK_PREFLIGHT_FAILED", "preflight"),
    staged = c("PYBENCH_PROCESS_FAILED", "execution"),
    receipt_received = c("PYBENCH_RECEIPT_MISMATCH", "receipt"),
    audited = c("PYBENCH_OUTPUT_INVALID", "audit"),
    before_publication = c("PYBENCH_PUBLICATION_FAILED", "publication"),
    published = c("PYBENCH_PUBLICATION_FAILED", "publication"))
  for (event_name in names(events)) {
    options(scworkbench.operation_pack_v2_test_hook = local({
      target <- event_name
      function(event, ...) if (identical(event, target)) stop("injected")
    }))
    error <- tryCatch(execute(bundle, "scwbv2reference::two_table_terminal",
      list(a = a, b = b), list()), error = identity)
    options(scworkbench.operation_pack_v2_test_hook = NULL)
    stopifnot(inherits(error, "wb_operation_pack_error"),
      identical(error$code, events[[event_name]][[1]]),
      identical(error$phase, events[[event_name]][[2]]),
      identical(before, fingerprint()),
      !dir.exists(file.path(bundle$dir, "operation_pack_v2")))
  }
  success <- execute(bundle, "scwbv2reference::two_table_terminal",
    list(a = a, b = b), list())
  stopifnot(success$state == "reopened",
    setequal(names(success$outputs), c("summary", "detail")))
  TRUE
}
