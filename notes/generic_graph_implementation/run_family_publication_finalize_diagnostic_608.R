lib <- "/tmp/scwb-final-585.ki8nvr4e/library"
.libPaths(c(lib,.libPaths()));library(scworkbench,lib.loc=lib)
e <- new.env(parent=asNamespace("scworkbench"))
sys.source("inst/tests/contract_test_runner.R",e)
sys.source("notes/generic_graph_implementation/evidence/608_family_publication_finalize_diagnostic_test.R",e)
e$wb_finalize_recipient_bundle <- function(bundle) {
  snapshot <- function() list(readiness=wb_recipient_readiness(bundle$dir),journal_mode=DBI::dbGetQuery(bundle$con,"PRAGMA journal_mode;")[[1]],file_hashes=scworkbench:::.wb_prov_path_identity(bundle$dir)$content_sha256,scientific_state=scworkbench:::.wb_manifest_registry_snapshot(bundle$con)$fingerprint)
  before <- snapshot()
  value <- scworkbench::wb_finalize_recipient_bundle(bundle)
  after <- snapshot()
  stopifnot(isTRUE(after$readiness$ready),identical(before$scientific_state,after$scientific_state))
  saveRDS(list(before=before,after=after,result=value),"notes/generic_graph_implementation/evidence/608_family_publication_finalize_state.rds")
  cat("SESSION_FINALIZE before_journal=",before$journal_mode," after_journal=",after$journal_mode," logical_state_unchanged=TRUE\n",sep="")
  value
}
stopifnot(isTRUE(e$test_operation_pack_v2_cell_set_family_publication_contract()))
cat("FAMILY_PUBLICATION_PUBLIC_FINALIZE_ORIGINAL_ASSERTIONS PASS\n")
