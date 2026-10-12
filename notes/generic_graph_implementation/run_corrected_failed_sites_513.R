args <- commandArgs(TRUE); stopifnot(length(args)==2L)
.libPaths(c(args[[1L]],.libPaths())); library(scworkbench,lib.loc=args[[1L]])
setwd(args[[2L]])
env <- new.env(parent=asNamespace("scworkbench"))
sys.source("inst/tests/contract_test_runner.R",env)
files <- c("tests/test_central_schema_foreign_key_closure_contract.R",
 "tests/test_central_schema_migration_foreign_keys_contract.R",
 "tests/test_durable_session_generation_recovery_contract.R",
 "tests/test_durable_session_source_payload_corruption_contract.R")
for(file in files)sys.source(file,env)
selected <- c("test_central_schema_foreign_key_closure_contract","test_central_schema_migration_foreign_keys_contract",
 "test_durable_session_generation_recovery_contract","test_durable_session_source_payload_corruption_contract")
results <- list()
for(name in selected) {
 cat("CORRECTED_SITE START",name,"\n");flush.console()
 value <- tryCatch(env[[name]](),error=identity)
 results[[name]] <- list(pass=isTRUE(value),error=if(inherits(value,"error"))conditionMessage(value)else NULL)
 cat("CORRECTED_SITE",if(isTRUE(value))"PASS"else"FAIL",name,
 if(inherits(value,"error"))conditionMessage(value)else"","\n");flush.console()
}
saveRDS(results,"/tmp/scwb-graph-final-508.3ude86tr/corrected_failed_sites_513.rds")
stopifnot(all(vapply(results,function(value)value$pass,logical(1))))
