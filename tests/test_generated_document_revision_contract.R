test_generated_document_linked_worktree_revision_contract <- function() {
  root <- normalizePath(".", winslash = "/", mustWork = TRUE)
  git <- Sys.which("git")
  rscript <- file.path(R.home("bin"), "Rscript")
  stopifnot(nzchar(git), file.exists(rscript))

  run <- function(command, arguments, wd = NULL, expect = 0L) {
    old <- NULL
    if (!is.null(wd)) {
      old <- setwd(wd)
      on.exit(setwd(old), add = TRUE)
    }
    output <- system2(command, arguments, stdout = TRUE, stderr = TRUE)
    status <- attr(output, "status")
    if (is.null(status)) status <- 0L
    if (!identical(as.integer(status), as.integer(expect))) {
      stop(
        paste(
          c(
            paste("Command failed with status", status, "(expected", expect, ")"),
            output,
            paste(c(command, arguments), collapse = " ")
          ),
          collapse = "\n"
        ),
        call. = FALSE
      )
    }
    output
  }

  fixture_root <- tempfile("scwb_docs_revision_contract_")
  dir.create(fixture_root)
  on.exit(unlink(fixture_root, recursive = TRUE, force = TRUE), add = TRUE)
  common <- file.path(fixture_root, "common")
  linked <- file.path(fixture_root, "checked")
  dir.create(common)

  run(git, c("-C", common, "init", "--quiet"))
  run(git, c("-C", common, "config", "user.name", "scworkbench-contract-test"))
  run(git, c("-C", common, "config", "user.email", "contract-test@invalid.example"))
  checked_revision <- trimws(run(git, c("-C", root, "rev-parse", "--verify", "HEAD")))
  run(git, c("-C", common, "fetch", "--quiet", root, checked_revision))
  run(git, c("-C", common, "checkout", "--quiet", "-b", "common-state", "FETCH_HEAD"))
  run(git, c(
    "-C", common, "worktree", "add", "--detach", "--quiet", linked,
    checked_revision
  ))
  on.exit(
    suppressWarnings(system2(
      git, c("-C", common, "worktree", "remove", "--force", linked),
      stdout = TRUE, stderr = TRUE
    )),
    add = TRUE
  )

  common_catalog <- file.path(common, "docs", "getter_catalog_reference.md")
  common_lines <- readLines(common_catalog, warn = FALSE)
  generated_line <- grep("^Generated at:", common_lines)
  stopifnot(length(generated_line) == 1L)
  common_lines[[generated_line]] <- "Generated at: deliberately-divergent-common-checkout"
  writeLines(common_lines, common_catalog, useBytes = TRUE)
  run(git, c("-C", common, "add", "docs/getter_catalog_reference.md"))
  run(git, c("-C", common, "commit", "--quiet", "-m", "diverge-common-checkout"))
  common_revision <- trimws(run(git, c("-C", common, "rev-parse", "--verify", "HEAD")))
  stopifnot(!identical(common_revision, checked_revision))

  sentinel <- file.path(linked, "UNTRACKED_CHECK_MODE_SENTINEL")
  sentinel_text <- "must remain present and unconsumed"
  writeLines(sentinel_text, sentinel, useBytes = TRUE)
  status_before <- run(git, c(
    "-C", linked, "status", "--porcelain", "--untracked-files=all"
  ))
  worktrees_before <- run(git, c("-C", common, "worktree", "list", "--porcelain"))
  stopifnot(any(grepl("UNTRACKED_CHECK_MODE_SENTINEL", status_before, fixed = TRUE)))

  output <- run(
    rscript,
    c("--vanilla", "inst/dev/regenerate_public_docs.R", "--check"),
    wd = linked
  )
  status_after <- run(git, c(
    "-C", linked, "status", "--porcelain", "--untracked-files=all"
  ))
  worktrees_after <- run(git, c("-C", common, "worktree", "list", "--porcelain"))
  stopifnot(
    identical(status_after, status_before),
    identical(worktrees_after, worktrees_before),
    identical(readLines(sentinel, warn = FALSE), sentinel_text),
    identical(
      trimws(run(git, c("-C", linked, "rev-parse", "--verify", "HEAD"))),
      checked_revision
    ),
    !any(grepl("GENERATED_REFERENCE_DRIFT", output, fixed = TRUE))
  )

  TRUE
}
