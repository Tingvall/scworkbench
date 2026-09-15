test_contract_runner_discovery_contract <- function() {
  if (!exists("contract_test_discover", mode = "function")) {
    sys.source(file.path("inst", "tests", "contract_test_runner.R"), envir = globalenv())
  }

  test_dir <- tempfile("contract_discovery_")
  dir.create(test_dir, recursive = TRUE)
  on.exit(unlink(test_dir, recursive = TRUE, force = TRUE), add = TRUE)
  marker <- tempfile("contract_discovery_marker_")
  on.exit(unlink(marker, force = TRUE), add = TRUE)

  writeLines(c(
    "test_new_unregistered_contract <- function() {",
    sprintf("  writeLines('executed', %s)", deparse(marker)),
    "  TRUE",
    "}"
  ), file.path(test_dir, "test_new_unregistered_contract.R"))
  writeLines(c(
    "test_explicit_skip_contract <- function() {",
    "  contract_test_skip('dependency unavailable in fixture')",
    "}"
  ), file.path(test_dir, "test_explicit_skip_contract.R"))
  inventory <- contract_test_discover(test_dir)
  selected <- contract_test_discover(test_dir,
    files = "test_new_unregistered_contract.R")
  stopifnot(length(selected$tests) == 1L,
    identical(selected$tests[[1]]$name, "test_new_unregistered_contract"))
  missing_selection <- tryCatch(contract_test_discover(test_dir,
    files = "test_absent_contract.R"), error = identity)
  stopifnot(inherits(missing_selection, "error"),
    grepl("Unknown selected contract test file", conditionMessage(missing_selection), fixed = TRUE))
  run <- contract_test_execute(inventory, reporter = FALSE)
  stopifnot(
    identical(as.integer(run$summary[c("discovered", "executed", "passed", "skipped", "accounted")]), c(2L, 2L, 1L, 1L, 2L)),
    identical(sort(run$results$name), c("test_explicit_skip_contract", "test_new_unregistered_contract")),
    identical(run$results$status[run$results$name == "test_new_unregistered_contract"], "passed"),
    identical(run$results$status[run$results$name == "test_explicit_skip_contract"], "skipped"),
    identical(run$results$reason[run$results$name == "test_explicit_skip_contract"], "dependency unavailable in fixture"),
    file.exists(marker),
    identical(readLines(marker, warn = FALSE), "executed")
  )

  excluded_inventory <- contract_test_discover(
    test_dir,
    exclusions = c(test_explicit_skip_contract = "covered by a platform-specific gate")
  )
  excluded_run <- contract_test_execute(excluded_inventory, reporter = FALSE)
  stopifnot(
    identical(as.integer(excluded_run$summary[c("discovered", "executed", "passed", "excluded", "accounted")]), c(2L, 1L, 1L, 1L, 2L)),
    identical(excluded_run$results$status[excluded_run$results$name == "test_explicit_skip_contract"], "excluded")
  )

  writeLines("test_unknown_contract <- function(required_input) TRUE",
             file.path(test_dir, "test_unknown_contract.R"))
  unknown_error <- tryCatch({ contract_test_discover(test_dir); NULL }, error = identity)
  stopifnot(inherits(unknown_error, "error"), grepl("unsupported required argument", conditionMessage(unknown_error), fixed = TRUE))
  unlink(file.path(test_dir, "test_unknown_contract.R"))

  writeLines("test_new_unregistered_contract <- function() TRUE",
             file.path(test_dir, "test_duplicate_contract.R"))
  duplicate_error <- tryCatch({ contract_test_discover(test_dir); NULL }, error = identity)
  stopifnot(inherits(duplicate_error, "error"), grepl("Duplicate contract test name", conditionMessage(duplicate_error), fixed = TRUE))
  unlink(file.path(test_dir, "test_duplicate_contract.R"))

  stale_error <- tryCatch({
    contract_test_discover(test_dir, exclusions = c(test_removed_contract = "retired by design"))
    NULL
  }, error = identity)
  stopifnot(inherits(stale_error, "error"), grepl("Stale intentional exclusion", conditionMessage(stale_error), fixed = TRUE))

  repository_inventory <- contract_test_discover(file.path("tests"))
  stopifnot(
    identical(sort(basename(repository_inventory$files)), sort(list.files("tests", pattern = "^test_.*\\.R$"))),
    !any(grepl("/tests/composite/", vapply(repository_inventory$tests, `[[`,
      character(1), "file"), fixed = TRUE)),
    sum(vapply(repository_inventory$tests, function(record) identical(record$name, "test_contract_runner_discovery_contract"), logical(1))) == 1L
  )

  TRUE
}
