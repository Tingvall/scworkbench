test_release_metadata_profile_contract <- function() {
  root <- normalizePath(".", winslash = "/", mustWork = TRUE)
  profile <- jsonlite::read_json(file.path(root, "inst/standard_profile/profile.json"))
  activation <- paste(readLines(file.path(root, "inst/standard_profile/activate.R")),
    collapse = "\n")
  stopifnot(grepl(profile$pybench_source_commit, activation, fixed = TRUE))
  matrix_script <- parse(file.path(root, "tests/profile/run_standard_profile_matrix.R"))
  expected_expr <- Filter(function(expr) is.call(expr) &&
    identical(expr[[1L]], as.name("<-")) &&
    identical(expr[[2L]], as.name("expected")), as.list(matrix_script))
  stopifnot(length(expected_expr) == 1L)
  expected <- eval(expected_expr[[1L]][[3L]], envir = baseenv())
  pinned <- setNames(vapply(profile$packs, `[[`, character(1), "source_commit"),
    vapply(profile$packs, `[[`, character(1), "package"))
  stopifnot(identical(expected, pinned))
  scratch <- tempfile("scwb-release-profile-")
  dir.create(scratch)
  on.exit(unlink(scratch, recursive = TRUE, force = TRUE), add = TRUE)
  files <- c("DESCRIPTION", "inst/release/composite_release.dcf",
    "inst/release/gate_policy.json", "inst/standard_profile/profile.json",
    "inst/protocol/pybench-op-v2.schema.json",
    "containers/apptainer/fullstack_r_versions.lock.csv",
    "containers/apptainer/fullstack_python_requirements.lock",
    "containers/apptainer/scworkbench_fullstack.def")
  for (file in files) {
    target <- file.path(scratch, file)
    dir.create(dirname(target), recursive = TRUE, showWarnings = FALSE)
    stopifnot(file.copy(file.path(root, file), target))
  }
  metadata <- file.path(scratch, "inst/release/composite_release.dcf")
  original <- readLines(metadata, warn = FALSE)
  validator <- file.path(root, "inst/ci/validate_release_metadata.R")
  validate <- function() suppressWarnings(system2("Rscript",
    c("--vanilla", shQuote(validator), shQuote(scratch)),
    stdout = FALSE, stderr = FALSE))
  stopifnot(identical(validate(), 0L))
  replace_field <- function(field, value) {
    lines <- original
    index <- grep(paste0("^", field, ": "), lines)
    stopifnot(length(index) == 1L)
    lines[[index]] <- paste0(field, ": ", value)
    writeLines(lines, metadata)
    stopifnot(validate() != 0L)
  }
  replace_field("StandardProfileSHA256", strrep("0", 64L))
  replace_field("StandardProfilePackedOperationCount", "55")
  replace_field("PyBenchCommit", strrep("0", 40L))
  TRUE
}

stopifnot(test_release_metadata_profile_contract())
cat("release profile metadata contract: PASS\n")
