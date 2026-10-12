.libPaths(c("/tmp/scwb-graph-final-valid-522.hxhra5_g/library",.libPaths()))
library(scworkbench,lib.loc="/tmp/scwb-graph-final-valid-522.hxhra5_g/library")
env <- new.env(parent=asNamespace("scworkbench"))
sys.source("inst/tests/contract_test_runner.R",env)
# Canonical runner helpers are also visible to nested default-global fixtures.
for (binding in ls(env,all.names=TRUE)) assign(binding,get(binding,env,inherits=FALSE),globalenv())
sys.source("tests/test_contract_runner_discovery_contract.R",env)
stopifnot(isTRUE(env$test_contract_runner_discovery_contract()))
cat("DISCOVERY_HARNESS_FOCUS unchanged_test=PASS shared_helper_bindings=TRUE product_source_unchanged=TRUE\n")
