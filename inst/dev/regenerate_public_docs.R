#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
check <- "--check" %in% args
root <- normalizePath(".", winslash = "/", mustWork = TRUE)
run <- function(command, arguments) {
  output <- system2(command, arguments, stdout = TRUE, stderr = TRUE)
  status <- attr(output, "status")
  if (is.null(status)) status <- 0L
  if (!identical(as.integer(status), 0L)) stop(paste(c(output, paste(c(command, arguments), collapse = " ")), collapse = "\n"), call. = FALSE)
}
if (check) {
  scratch <- tempfile("scwb_docs_check_")
  dir.create(scratch)
  on.exit(unlink(scratch, recursive = TRUE, force = TRUE), add = TRUE)
  run("git", c("clone", "--quiet", root, scratch))
  output <- system2("Rscript", file.path(scratch, "inst/dev/regenerate_public_docs.R"), stdout = TRUE, stderr = TRUE)
  status <- attr(output, "status")
  if (is.null(status)) status <- 0L
  if (!identical(as.integer(status), 0L)) stop(paste(output, collapse = "\n"), call. = FALSE)
  changed <- system2("git", c("-C", scratch, "status", "--porcelain"), stdout = TRUE)
  if (length(changed)) stop(paste0("GENERATED_REFERENCE_DRIFT:\n", paste(changed, collapse = "\n")), call. = FALSE)
  quit(status = 0L)
}
Sys.setenv(TZ = "UTC", SOURCE_DATE_EPOCH = "1")
run("Rscript", c("-e", shQuote("devtools::document('.', quiet=TRUE)")))
run("Rscript", "inst/dev/generate_operation_docs.R")
run("Rscript", "inst/dev/generate_schema_catalog.R")
run("Rscript", c("-e", shQuote("devtools::load_all('.', quiet=TRUE); wb_refresh_semantic_catalogs(docs_dir='docs')")))
source("inst/dev/documentation_policy.R")
scwb_write_documentation_manifest(root)
