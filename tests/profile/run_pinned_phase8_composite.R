args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 4L) stop(paste(
  "usage: Rscript tests/profile/run_pinned_phase8_composite.R",
  "CORE_SOURCE CORE_COMMIT REPRESENTATION_SOURCE REPRESENTATION_COMMIT"),
  call. = FALSE)
core_source <- normalizePath(args[[1L]], winslash = "/", mustWork = TRUE)
representation_source <- normalizePath(args[[3L]], winslash = "/", mustWork = TRUE)
check_source <- function(path, expected, label) {
  head <- system2("git", c("-C", shQuote(path), "rev-parse", "HEAD"),
    stdout = TRUE, stderr = TRUE)
  if (!identical(head, expected)) stop(label, " source commit differs from pin")
  dirty <- system2("git", c("-C", shQuote(path), "status", "--porcelain"),
    stdout = TRUE, stderr = TRUE)
  if (length(dirty)) stop(label, " source worktree is dirty")
}
check_source(core_source, args[[2L]], "scworkbench")
check_source(representation_source, args[[4L]], "scwbRepresentation")
accepted_representation <- "e3bb38760bcdda426a83bfbd7350b6fb16890e94"
ancestor <- system2("git", c("-C", shQuote(representation_source),
  "merge-base", "--is-ancestor", accepted_representation, args[[4L]]),
  stdout = FALSE, stderr = FALSE)
if (!identical(as.integer(ancestor), 0L)) stop(
  "Representation source does not descend from the accepted runtime pin")
changed <- system2("git", c("-C", shQuote(representation_source),
  "diff", "--name-only", paste0(accepted_representation, "..", args[[4L]])),
  stdout = TRUE, stderr = TRUE)
if (length(changed) && any(!startsWith(changed, "tests/"))) stop(
  "Representation descendant changes package runtime outside tests")
setwd(core_source)
Sys.setenv(SCWBREPRESENTATION_SOURCE = representation_source)
devtools::load_all(core_source, quiet = TRUE)
sys.source(file.path(core_source, "inst", "tests", "contract_test_runner.R"),
  envir = globalenv())

golden <- tempfile("scworkbench-phase8-profile-golden-", tmpdir = "/tmp")
on.exit(unlink(golden, recursive = TRUE, force = TRUE), add = TRUE)
status <- system2(file.path(R.home("bin"), "Rscript"), c(
  shQuote(file.path(core_source, "inst", "golden_bundle",
    "create_golden_bundle.R")), shQuote(golden)))
if (!identical(as.integer(status), 0L)) stop("Golden bundle creation failed")

files <- c("test_durable_session_staged_space_registry_binding_contract.R",
           "test_immutable_history_state_machine_closure_contract.R")
inventory <- contract_test_discover(file.path(core_source, "tests", "composite",
  "phase8"), files = files)
if (!identical(length(inventory$tests), 2L)) stop(
  "Expected exactly two pinned Phase 8 Representation composite tests")
run <- contract_test_execute(inventory, baseline_bundle_dir = golden)
contract_test_assert_success(run)
if (!identical(as.integer(run$summary[["passed"]]), 2L) ||
    !identical(as.integer(run$summary[["skipped"]]), 0L)) stop(
  "Pinned Phase 8 composite must pass both tests without skips")
cat("PHASE8_PINNED_COMPOSITE_OK files=2 discovered=2 executed=2 passed=2 skipped=0 failed=0\n")
