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
representation_source <- source_identity(option("representation-source"),
  option("representation-commit"), "scwbRepresentation")
devtools::load_all(core_source, quiet = TRUE)
source(file.path(core_source, "inst", "tests", "contract_test_runner.R"),
  local = globalenv())
Sys.setenv(SCWBREPRESENTATION_SOURCE = representation_source)

golden <- tempfile("scworkbench-ownership-golden-", tmpdir = "/tmp")
on.exit(unlink(golden, recursive = TRUE, force = TRUE), add = TRUE)
status <- system2(file.path(R.home("bin"), "Rscript"),
  c(file.path(core_source, "inst", "golden_bundle", "create_golden_bundle.R"), golden))
if (!identical(status, 0L)) stop("Golden bundle generation failed.", call. = FALSE)

core_files <- c(
  "test_cell_vector_durable_identity_roundtrip_contract.R",
  "test_foundation_hardening_1to5.R",
  "test_op_slingshot_fit_project_contract.R",
  "test_op_slingshot_promoted_model_project_contract.R",
  "test_plot_wranglers_contract.R",
  "test_promotion_artifact_payload_atomicity_contract.R",
  "test_report_draft_contract.R",
  "test_representation_extraction_contract.R",
  "test_session_dag_contract.R",
  "test_trajectory_family_helpers_contract.R"
)
core <- contract_test_discover(file.path(core_source, "tests"), files = core_files)
core_run <- contract_test_execute(core, baseline_bundle_dir = golden)
contract_test_assert_success(core_run)

composite_files <- c(
  "test_scwb_representation_cell_vector_identity_contract.R",
  "test_scwb_representation_transitive_promotion_contract.R"
)
composite <- contract_test_discover(file.path(core_source, "tests", "composite"),
  files = composite_files)
composite_run <- contract_test_execute(composite)
contract_test_assert_success(composite_run)

total <- core_run$summary + composite_run$summary
cat("REPRESENTATION TEST OWNERSHIP OK files=", total[["files"]],
  " discovered=", total[["discovered"]],
  " executed=", total[["executed"]],
  " passed=", total[["passed"]],
  " skipped=", total[["skipped"]],
  " failed=", total[["failed"]], "\n", sep = "")
