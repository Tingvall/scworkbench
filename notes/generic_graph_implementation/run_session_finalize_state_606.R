lib <- "/tmp/scwb-final-585.ki8nvr4e/library"
.libPaths(c(lib,.libPaths()));library(scworkbench,lib.loc=lib)
e <- new.env(parent=asNamespace("scworkbench"))
sys.source("inst/tests/contract_test_runner.R",e)
sys.source("notes/generic_graph_implementation/evidence/605_session_finalize_diagnostic_test.R",e)
e$wb_finalize_recipient_bundle <- function(bundle) {
  snapshot <- function() list(readiness=wb_recipient_readiness(bundle$dir),journal_mode=DBI::dbGetQuery(bundle$con,"PRAGMA journal_mode;")[[1]],file_hashes=e$.session_inspection_regular_file_inventory(bundle$dir),scientific_state=scworkbench:::.wb_manifest_registry_snapshot(bundle$con)$fingerprint)
  before <- snapshot()
  value <- scworkbench::wb_finalize_recipient_bundle(bundle)
  after <- snapshot()
  stopifnot(isTRUE(after$readiness$ready),identical(before$scientific_state,after$scientific_state))
  saveRDS(list(before=before,after=after,result=value),"notes/generic_graph_implementation/evidence/606_session_finalize_state.rds")
  cat("SESSION_FINALIZE before_journal=",before$journal_mode," after_journal=",after$journal_mode," logical_state_unchanged=TRUE\n",sep="")
  value
}
stopifnot(isTRUE(e$test_session_inspection_and_ingest_integrity_contract()))
cat("SESSION_PUBLIC_FINALIZE_ORIGINAL_ASSERTIONS PASS\n")
