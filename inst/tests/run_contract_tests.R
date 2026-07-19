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

if (identical(Sys.getenv("SCWORKBENCH_CONTRACT_TRACEBACK"), "1")) {
  options(error = function() {
    traceback(2)
    q(status = 1)
  })
}

test_dir <- file.path(repo, "tests")
test_files <- sort(list.files(test_dir, pattern = "^test_.*\\.R$", full.names = TRUE))
test_all_file <- file.path(test_dir, "test_all.R")
for (path in setdiff(test_files, test_all_file)) {
  sys.source(path, envir = globalenv())
}
sys.source(test_all_file, envir = globalenv())

# Isolation model: the generated/provided bundle is a read-only baseline. Each
# contract test that declares a bundle_dir argument receives its own recursive
# copy, so mutation-heavy ingestion and promotion tests cannot affect later
# validation tests. Tests without bundle_dir remain ordinary self-contained
# unit contracts.
baseline_bundle_dir <- bundle_dir
bundle_test_root <- tempfile("scworkbench_contract_bundles_", tmpdir = "/tmp")
dir.create(bundle_test_root, recursive = TRUE, showWarnings = FALSE)
on.exit(unlink(bundle_test_root, recursive = TRUE, force = TRUE), add = TRUE)

copy_bundle_for_test <- function(label) {
  target_parent <- file.path(bundle_test_root, paste0(gsub("[^A-Za-z0-9_.-]+", "_", label), "_", as.integer(Sys.time()), "_", sample.int(1e6, 1L)))
  dir.create(target_parent, recursive = TRUE, showWarnings = FALSE)
  ok <- file.copy(baseline_bundle_dir, target_parent, recursive = TRUE)
  if (!isTRUE(ok)) stop("Failed to copy baseline bundle for test: ", label, call. = FALSE)
  normalizePath(file.path(target_parent, basename(baseline_bundle_dir)), winslash = "/", mustWork = TRUE)
}

test_names <- setdiff(ls(globalenv(), pattern = "^test_"), "test_all")
for (test_name in test_names) {
  test_fn <- get(test_name, envir = globalenv())
  if (!is.function(test_fn) || !"bundle_dir" %in% names(formals(test_fn))) next
  assign(test_name, local({
    fn <- test_fn
    label <- test_name
    function(bundle_dir, ...) {
      isolated_bundle <- copy_bundle_for_test(label)
      on.exit(unlink(dirname(isolated_bundle), recursive = TRUE, force = TRUE), add = TRUE)
      do.call(fn, c(list(bundle_dir = isolated_bundle), list(...)))
    }
  }), envir = globalenv())
}

stopifnot(exists("test_all", mode = "function"))
stopifnot(isTRUE(test_all(baseline_bundle_dir)))
cat("scworkbench contract suite passed for ", baseline_bundle_dir, "\n", sep = "")
