.scwb_docs_command <- function(command, arguments, wd = NULL) {
  run <- function() {
    output <- suppressWarnings(system2(
      command, arguments, stdout = TRUE, stderr = TRUE
    ))
    status <- attr(output, "status")
    if (is.null(status)) status <- 0L
    list(status = as.integer(status), output = output)
  }
  if (is.null(wd)) return(run())
  old <- setwd(wd)
  on.exit(setwd(old), add = TRUE)
  run()
}

.scwb_docs_require_success <- function(command, arguments, wd = NULL) {
  result <- .scwb_docs_command(command, arguments, wd = wd)
  if (!identical(result$status, 0L)) {
    stop(
      paste(
        c(
          paste("Command failed with status", result$status),
          result$output,
          paste(c(command, arguments), collapse = " ")
        ),
        collapse = "\n"
      ),
      call. = FALSE
    )
  }
  result$output
}

.scwb_docs_fixture <- function(root) {
  git <- Sys.which("git")
  rscript <- file.path(R.home("bin"), "Rscript")
  stopifnot(nzchar(git), file.exists(rscript))

  fixture_root <- tempfile("scwb_docs_revision_contract_")
  dir.create(fixture_root)
  common <- file.path(fixture_root, "common")
  linked <- file.path(fixture_root, "checked")
  dir.create(common)

  .scwb_docs_require_success(git, c("-C", common, "init", "--quiet"))
  .scwb_docs_require_success(git, c(
    "-C", common, "config", "user.name", "scworkbench-contract-test"
  ))
  .scwb_docs_require_success(git, c(
    "-C", common, "config", "user.email", "contract-test@invalid.example"
  ))
  revision <- trimws(.scwb_docs_require_success(git, c(
    "-C", root, "rev-parse", "--verify", "HEAD"
  )))
  .scwb_docs_require_success(git, c(
    "-C", common, "fetch", "--quiet", root, revision
  ))
  .scwb_docs_require_success(git, c(
    "-C", common, "checkout", "--quiet", "-b", "common-state", "FETCH_HEAD"
  ))
  .scwb_docs_require_success(git, c(
    "-C", common, "worktree", "add", "--detach", "--quiet", linked, revision
  ))

  list(
    root = fixture_root,
    common = common,
    linked = linked,
    revision = revision,
    git = git,
    rscript = rscript
  )
}

.scwb_docs_fixture_cleanup <- function(fixture) {
  suppressWarnings(system2(
    fixture$git,
    c("-C", fixture$common, "worktree", "remove", "--force", fixture$linked),
    stdout = TRUE, stderr = TRUE
  ))
  unlink(fixture$root, recursive = TRUE, force = TRUE)
  invisible(TRUE)
}

.scwb_docs_commit <- function(fixture, paths, message) {
  .scwb_docs_require_success(fixture$git, c("-C", fixture$linked, "add", paths))
  .scwb_docs_require_success(fixture$git, c(
    "-C", fixture$linked, "commit", "--quiet", "-m", message
  ))
  trimws(.scwb_docs_require_success(fixture$git, c(
    "-C", fixture$linked, "rev-parse", "--verify", "HEAD"
  )))
}

.scwb_docs_add_sentinel <- function(fixture) {
  path <- file.path(fixture$linked, "UNTRACKED_CHECK_MODE_SENTINEL")
  bytes <- charToRaw("must remain present and unconsumed\n")
  con <- file(path, open = "wb")
  on.exit(close(con), add = TRUE)
  writeBin(bytes, con)
  list(path = path, bytes = bytes)
}

.scwb_docs_observe <- function(fixture, sentinel) {
  list(
    linked_status = .scwb_docs_require_success(fixture$git, c(
      "-C", fixture$linked, "status", "--porcelain", "--untracked-files=all"
    )),
    linked_head = trimws(.scwb_docs_require_success(fixture$git, c(
      "-C", fixture$linked, "rev-parse", "--verify", "HEAD"
    ))),
    common_status = .scwb_docs_require_success(fixture$git, c(
      "-C", fixture$common, "status", "--porcelain", "--untracked-files=all"
    )),
    common_head = trimws(.scwb_docs_require_success(fixture$git, c(
      "-C", fixture$common, "rev-parse", "--verify", "HEAD"
    ))),
    worktrees = .scwb_docs_require_success(fixture$git, c(
      "-C", fixture$common, "worktree", "list", "--porcelain"
    )),
    sentinel = readBin(sentinel$path, what = "raw", n = length(sentinel$bytes))
  )
}

.scwb_docs_run_check <- function(fixture) {
  .scwb_docs_command(
    fixture$rscript,
    c("--vanilla", "inst/dev/regenerate_public_docs.R", "--check"),
    wd = fixture$linked
  )
}

test_generated_document_linked_worktree_revision_contract <- function() {
  root <- normalizePath(".", winslash = "/", mustWork = TRUE)
  fixture <- .scwb_docs_fixture(root)
  on.exit(.scwb_docs_fixture_cleanup(fixture), add = TRUE)

  common_catalog <- file.path(fixture$common, "docs", "getter_catalog_reference.md")
  lines <- readLines(common_catalog, warn = FALSE)
  generated_line <- grep("^Generated at:", lines)
  stopifnot(length(generated_line) == 1L)
  lines[[generated_line]] <- "Generated at: deliberately-divergent-common-checkout"
  writeLines(lines, common_catalog, useBytes = TRUE)
  .scwb_docs_require_success(fixture$git, c(
    "-C", fixture$common, "add", "docs/getter_catalog_reference.md"
  ))
  .scwb_docs_require_success(fixture$git, c(
    "-C", fixture$common, "commit", "--quiet", "-m", "diverge-common-checkout"
  ))

  sentinel <- .scwb_docs_add_sentinel(fixture)
  before <- .scwb_docs_observe(fixture, sentinel)
  result <- .scwb_docs_run_check(fixture)
  after <- .scwb_docs_observe(fixture, sentinel)
  stopifnot(
    identical(result$status, 0L),
    identical(after, before),
    identical(before$sentinel, sentinel$bytes),
    !any(grepl("GENERATED_REFERENCE_DRIFT", result$output, fixed = TRUE))
  )

  TRUE
}

test_generated_document_stale_linked_revision_rejected_contract <- function() {
  root <- normalizePath(".", winslash = "/", mustWork = TRUE)
  fixture <- .scwb_docs_fixture(root)
  on.exit(.scwb_docs_fixture_cleanup(fixture), add = TRUE)

  linked_catalog <- file.path(fixture$linked, "docs", "getter_catalog_reference.md")
  lines <- readLines(linked_catalog, warn = FALSE)
  generated_line <- grep("^Generated at:", lines)
  stopifnot(length(generated_line) == 1L)
  lines[[generated_line]] <- "Generated at: deliberately-stale-linked-revision"
  writeLines(lines, linked_catalog, useBytes = TRUE)
  stale_revision <- .scwb_docs_commit(
    fixture, "docs/getter_catalog_reference.md", "stale-linked-generated-catalog"
  )
  stopifnot(!identical(stale_revision, fixture$revision))

  sentinel <- .scwb_docs_add_sentinel(fixture)
  before <- .scwb_docs_observe(fixture, sentinel)
  stopifnot(!length(before$common_status))
  result <- .scwb_docs_run_check(fixture)
  after <- .scwb_docs_observe(fixture, sentinel)
  stopifnot(
    !identical(result$status, 0L),
    any(grepl("GENERATED_REFERENCE_DRIFT", result$output, fixed = TRUE)),
    identical(after, before),
    identical(before$sentinel, sentinel$bytes)
  )

  TRUE
}

test_generated_document_child_failure_cleanup_contract <- function() {
  root <- normalizePath(".", winslash = "/", mustWork = TRUE)
  fixture <- .scwb_docs_fixture(root)
  on.exit(.scwb_docs_fixture_cleanup(fixture), add = TRUE)

  generator <- file.path(fixture$linked, "inst", "dev", "regenerate_public_docs.R")
  lines <- readLines(generator, warn = FALSE)
  insertion <- grep("^Sys[.]setenv[(]", lines)
  stopifnot(length(insertion) == 1L)
  lines <- append(
    lines,
    'stop("FORCED_CHILD_GENERATOR_FAILURE", call. = FALSE)',
    after = insertion - 1L
  )
  writeLines(lines, generator, useBytes = TRUE)
  failure_revision <- .scwb_docs_commit(
    fixture, "inst/dev/regenerate_public_docs.R", "force-child-generator-failure"
  )
  stopifnot(!identical(failure_revision, fixture$revision))

  sentinel <- .scwb_docs_add_sentinel(fixture)
  before <- .scwb_docs_observe(fixture, sentinel)
  result <- .scwb_docs_run_check(fixture)
  after <- .scwb_docs_observe(fixture, sentinel)
  stopifnot(
    !identical(result$status, 0L),
    any(grepl("FORCED_CHILD_GENERATOR_FAILURE", result$output, fixed = TRUE)),
    identical(after, before),
    identical(before$sentinel, sentinel$bytes)
  )

  TRUE
}
