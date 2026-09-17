#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
option <- function(name) {
  prefix <- paste0("--", name, "=")
  hit <- args[startsWith(args, prefix)]
  if (length(hit) != 1L) stop("exactly one ", prefix, " argument is required")
  sub(prefix, "", hit, fixed = TRUE)
}
git_value <- function(source, command) {
  value <- system2("git", c("-C", shQuote(source), command), stdout = TRUE,
    stderr = TRUE)
  if (!is.null(attr(value, "status"))) stop("git inspection failed for ", source)
  trimws(value)
}
source_identity <- function(path, commit, label) {
  path <- normalizePath(path, winslash = "/", mustWork = TRUE)
  if (!identical(git_value(path, c("rev-parse", "HEAD")), commit))
    stop(label, " commit mismatch")
  dirty <- git_value(path, c("status", "--porcelain", "--untracked-files=all"))
  if (length(dirty) && any(nzchar(dirty))) stop(label, " source tree is dirty")
  path
}
core_source <- source_identity(option("core-source"), option("core-commit"),
  "scworkbench")
statistics_source <- source_identity(option("statistics-source"),
  option("statistics-commit"), "scwbStatistics")
geneprograms_source <- source_identity(option("geneprograms-source"),
  option("geneprograms-commit"), "scwbGenePrograms")
devtools::load_all(core_source, quiet = TRUE)
source(file.path(core_source, "inst", "tests", "contract_test_runner.R"),
  local = globalenv())
Sys.setenv(SCWBSTATISTICS_SOURCE = statistics_source,
  SCWBGENEPROGRAMS_SOURCE = geneprograms_source)
inventory <- contract_test_discover(file.path(core_source, "tests", "composite"),
  files = c("test_scwb_geneprograms_pack_catalog_contract.R",
    "test_scwb_geneprograms_pack_lifecycle_contract.R"))
run <- contract_test_execute(inventory)
contract_test_assert_success(run)
cat("GENEPROGRAMS COMPOSITE OK files=", run$summary[["files"]],
  " discovered=", run$summary[["discovered"]],
  " executed=", run$summary[["executed"]],
  " passed=", run$summary[["passed"]],
  " skipped=", run$summary[["skipped"]],
  " failed=", run$summary[["failed"]], "\n", sep = "")
