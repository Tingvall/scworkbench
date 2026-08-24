test_operation_pack_v1_contract <- function() {
  template_package <- "scworkbenchOperationPackTemplate"
  if (!requireNamespace(template_package, quietly = TRUE)) {
    return(contract_test_skip(paste0(
      "The independently distributed R reference pack is not installed; install ",
      template_package, " to run the cross-repository Phase 1 lifecycle proof."
    )))
  }
  root <- normalizePath(".", winslash = "/", mustWork = TRUE)
  helper <- file.path(root, "tests", "helpers", "operation_pack_v1_subprocess.R")
  log <- tempfile("operation_pack_v1_", fileext = ".log")
  status <- system2(file.path(R.home("bin"), "Rscript"), c(shQuote(helper), shQuote(root)),
                    stdout = log, stderr = log)
  output <- readLines(log, warn = FALSE)
  unlink(log)
  if (!identical(status, 0L)) stop(paste(output, collapse = "\n"), call. = FALSE)
  stopifnot(any(output == "OPERATION_PACK_V1_SUBPROCESS_OK"))
  TRUE
}
