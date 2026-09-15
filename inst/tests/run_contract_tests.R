#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
bundle_arg <- grep("^--bundle=", args, value = TRUE)
test_file_arg <- grep("^--test-file=", args, value = TRUE)
if (length(bundle_arg) > 1L) {
  stop("Specify at most one --bundle=/path argument.", call. = FALSE)
}
unknown <- setdiff(args, c(bundle_arg, test_file_arg))
if (length(unknown)) {
  stop("Unknown argument(s): ", paste(unknown, collapse = ", "), call. = FALSE)
}

cmd <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", cmd, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1L]]) else "inst/tests/run_contract_tests.R"
repo <- normalizePath(file.path(dirname(script_path), "..", ".."), winslash = "/", mustWork = FALSE)
if (!file.exists(file.path(repo, "DESCRIPTION"))) {
  repo <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
}

load_engine <- function(repo_dir) {
  if (requireNamespace("devtools", quietly = TRUE)) {
    devtools::load_all(repo_dir, quiet = TRUE)
    return(invisible(TRUE))
  }
  if (requireNamespace("pkgload", quietly = TRUE)) {
    pkgload::load_all(repo_dir, quiet = TRUE)
    return(invisible(TRUE))
  }
  stop("Install devtools or pkgload to run package contract tests.", call. = FALSE)
}

bundle_dir <- if (length(bundle_arg)) {
  normalizePath(sub("^--bundle=", "", bundle_arg[[1L]]), winslash = "/", mustWork = TRUE)
} else {
  path <- tempfile("scworkbench_golden_", tmpdir = "/tmp")
  status <- system2(
    file.path(R.home("bin"), "Rscript"),
    c(file.path(repo, "inst", "golden_bundle", "create_golden_bundle.R"), path)
  )
  if (!identical(as.integer(status), 0L)) {
    stop("Golden bundle generation failed.", call. = FALSE)
  }
  on.exit(unlink(path, recursive = TRUE, force = TRUE), add = TRUE)
  normalizePath(path, winslash = "/", mustWork = TRUE)
}

load_engine(repo)
sys.source(file.path(repo, "inst", "tests", "contract_test_runner.R"), envir = globalenv())

if (identical(Sys.getenv("SCWORKBENCH_CONTRACT_TRACEBACK"), "1")) {
  options(error = function() {
    traceback(2)
    q(status = 1)
  })
}

# Intentionally empty. Any future exclusion must name a discovered test and
# provide a non-empty reason; stale entries make discovery fail.
intentional_exclusions <- character()
inventory <- contract_test_discover(
  file.path(repo, "tests"),
  exclusions = intentional_exclusions,
  parent_env = globalenv(),
  files = if (length(test_file_arg)) sub("^--test-file=", "", test_file_arg) else NULL
)
cat("Discovered ", length(inventory$tests), " contract tests in ",
    length(inventory$files), " files.\n", sep = "")
run <- contract_test_execute(inventory, baseline_bundle_dir = bundle_dir, reporter = TRUE)
contract_test_assert_success(run)
cat("scworkbench contract suite passed for ", bundle_dir, "\n", sep = "")
