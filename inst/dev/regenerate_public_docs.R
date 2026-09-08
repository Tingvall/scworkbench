#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
check <- "--check" %in% args
root <- normalizePath(".", winslash = "/", mustWork = TRUE)
run <- function(command, arguments) {
  output <- system2(command, arguments, stdout = TRUE, stderr = TRUE)
  status <- attr(output, "status")
  if (is.null(status)) status <- 0L
  if (!identical(as.integer(status), 0L)) stop(paste(c(output, paste(c(command, arguments), collapse = " ")), collapse = "\n"), call. = FALSE)
  invisible(output)
}
check_committed_revision <- function() {
  revision <- trimws(run("git", c("-C", root, "rev-parse", "--verify", "HEAD")))
  if (length(revision) != 1L || !grepl("^[0-9a-f]{40}$", revision)) {
    stop("Unable to resolve the exact committed revision for documentation checking.", call. = FALSE)
  }

  scratch <- tempfile("scwb_docs_check_")
  cleanup <- function() {
    suppressWarnings(system2(
      "git", c("-C", root, "worktree", "remove", "--force", scratch),
      stdout = TRUE, stderr = TRUE
    ))
    if (dir.exists(scratch)) unlink(scratch, recursive = TRUE, force = TRUE)
  }
  on.exit(cleanup(), add = TRUE)
  run("git", c(
    "-C", root, "worktree", "add", "--detach", "--quiet", scratch, revision
  ))
  checked_revision <- trimws(run("git", c(
    "-C", scratch, "rev-parse", "--verify", "HEAD"
  )))
  if (!identical(checked_revision, revision)) {
    stop(
      "Generated-document check staged a revision other than the invoking checkout HEAD.",
      call. = FALSE
    )
  }

  output <- system2(
    "Rscript", c("--vanilla", file.path(scratch, "inst/dev/regenerate_public_docs.R")),
    stdout = TRUE, stderr = TRUE
  )
  status <- attr(output, "status")
  if (is.null(status)) status <- 0L
  if (!identical(as.integer(status), 0L)) stop(paste(output, collapse = "\n"), call. = FALSE)
  changed <- run("git", c("-C", scratch, "status", "--porcelain"))
  if (length(changed)) stop(paste0("GENERATED_REFERENCE_DRIFT:\n", paste(changed, collapse = "\n")), call. = FALSE)
  invisible(TRUE)
}
if (check) {
  check_committed_revision()
  quit(status = 0L)
}
Sys.setenv(TZ = "UTC", SOURCE_DATE_EPOCH = "1")
run("Rscript", c("-e", shQuote("devtools::document('.', quiet=TRUE)")))
run("Rscript", "inst/dev/generate_operation_docs.R")
run("Rscript", "inst/dev/generate_schema_catalog.R")
run("Rscript", c("-e", shQuote("devtools::load_all('.', quiet=TRUE); wb_refresh_semantic_catalogs(docs_dir='docs')")))
source("inst/dev/documentation_policy.R")
scwb_write_documentation_manifest(root)
