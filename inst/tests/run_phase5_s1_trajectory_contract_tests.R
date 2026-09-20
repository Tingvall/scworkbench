#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
option <- function(name) {
  prefix <- paste0("--", name, "=")
  hit <- args[startsWith(args, prefix)]
  if (length(hit) != 1L) stop("exactly one ", prefix,
    " argument is required")
  sub(prefix, "", hit, fixed = TRUE)
}
git_value <- function(source, command) {
  value <- system2("git", c("-C", shQuote(source), command), stdout = TRUE,
    stderr = TRUE)
  if (!is.null(attr(value, "status"))) stop("git inspection failed for ",
    source)
  trimws(value)
}
source_identity <- function(path, commit, label) {
  path <- normalizePath(path, winslash = "/", mustWork = TRUE)
  if (!identical(git_value(path, c("rev-parse", "HEAD")), commit))
    stop(label, " commit mismatch")
  dirty <- git_value(path, c("status", "--porcelain",
    "--untracked-files=all"))
  if (length(dirty) && any(nzchar(dirty))) stop(label,
    " source tree is dirty")
  path
}
core_source <- source_identity(option("core-source"), option("core-commit"),
  "scworkbench")
trajectory_source <- source_identity(option("trajectory-source"),
  option("trajectory-commit"), "scwbTrajectory")
rna_source <- source_identity(option("rna-source"), option("rna-commit"),
  "scwbRNA")
representation_source <- source_identity(option("representation-source"),
  option("representation-commit"), "scwbRepresentation")
devtools::load_all(core_source, quiet = TRUE)
source(file.path(core_source, "inst", "tests", "contract_test_runner.R"),
  local = globalenv())
Sys.setenv(SCWBTRAJECTORY_SOURCE = trajectory_source,
  SCWBRNA_SOURCE = rna_source,
  SCWBREPRESENTATION_SOURCE = representation_source)
core <- contract_test_discover(file.path(core_source, "tests"), files = c(
  "test_operation_pack_v3_trajectory_family_contract.R"))
core_run <- contract_test_execute(core)
contract_test_assert_success(core_run)
composite <- contract_test_discover(file.path(core_source, "tests",
  "composite"), files = c(
    "test_scwb_trajectory_pack_catalog_contract.R",
    "test_phase5_s1_trajectory_composite_contract.R"))
composite_run <- contract_test_execute(composite)
contract_test_assert_success(composite_run)
summary <- core_run$summary + composite_run$summary
summary[["files"]] <- core_run$summary[["files"]] +
  composite_run$summary[["files"]]
cat("PHASE5 S1 TRAJECTORY CORE/COMPOSITE OK ",
  paste(names(summary), summary, sep = "=", collapse = " "), "\n", sep = "")
