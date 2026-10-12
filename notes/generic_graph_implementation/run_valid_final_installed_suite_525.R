args <- commandArgs(TRUE)
stopifnot(length(args) == 3L)
lib <- normalizePath(args[[1L]], mustWork = TRUE)
repo <- normalizePath(args[[2L]], mustWork = TRUE)
golden <- args[[3L]]
.libPaths(c(lib, .libPaths()))
library(scworkbench, lib.loc = lib)
stopifnot(identical(normalizePath(find.package("scworkbench")), normalizePath(file.path(lib,"scworkbench"))), !file.exists(golden))
setwd(repo)
# Reuse the repository's golden fixture generator with the pinned installed core.
# Only its development loader and CLI argument assignment are bypassed.
create_golden <- function() {
  env <- new.env(parent = globalenv()); env$args <- c(golden)
  on.exit(if (exists("b", env, inherits = FALSE) && DBI::dbIsValid(env$b$con)) wb_close_bundle(env$b), add = TRUE)
  for (expr in parse("inst/golden_bundle/create_golden_bundle.R")) {
    cli_args <- is.call(expr) && identical(expr[[1L]], as.name("<-")) && identical(expr[[2L]], as.name("args"))
    generator_cleanup <- is.call(expr) && identical(expr[[1L]], as.name("on.exit"))
    if (cli_args || generator_cleanup || identical(expr, quote(load_engine(repo)))) next
    eval(expr, env)
  }
}
create_golden()
test_env <- new.env(parent = asNamespace("scworkbench"))
sys.source("inst/tests/contract_test_runner.R", test_env)
inventory <- test_env$contract_test_discover(file.path(repo,"tests"), exclusions = character(), parent_env = test_env)
cat("VALID_FINAL_INSTALLED_CORE discovered=",length(inventory$tests)," files=",length(inventory$files),"\n",sep="")
run <- test_env$contract_test_execute(inventory, baseline_bundle_dir = normalizePath(golden), reporter = TRUE)
saveRDS(run, file.path(dirname(golden),"final_contract_suite_report.rds"))
test_env$contract_test_assert_success(run)
cat("VALID_FINAL_INSTALLED_CORE_SUITE PASS\n")
