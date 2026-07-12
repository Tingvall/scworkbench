#!/usr/bin/env Rscript

# Canonical package-level contract runner. It deliberately sources every
# top-level contract test before invoking test_all(), which keeps newly added
# test files from being silently omitted by a one-file test command.

args <- commandArgs(trailingOnly = TRUE)
bundle_arg <- grep("^--bundle=", args, value = TRUE)
if (length(bundle_arg) > 1L) {
  stop("Specify at most one --bundle=/path argument.", call. = FALSE)
}
unknown <- setdiff(args, bundle_arg)
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
  # The golden generator runs in a child R process. Keep its output outside an
  # R-session-specific tempdir so child cleanup cannot remove the fixture.
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

test_dir <- file.path(repo, "tests")
test_files <- sort(list.files(test_dir, pattern = "^test_.*\\.R$", full.names = TRUE))
test_all_file <- file.path(test_dir, "test_all.R")
for (path in setdiff(test_files, test_all_file)) {
  sys.source(path, envir = globalenv())
}
sys.source(test_all_file, envir = globalenv())

stopifnot(exists("test_all", mode = "function"))
stopifnot(isTRUE(test_all(bundle_dir)))
cat("scworkbench contract suite passed for ", bundle_dir, "\n", sep = "")
