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

test_operation_pack_v1_backend_admission_contract <- function() {
  template_package <- "scworkbenchOperationPackTemplate"
  if (!requireNamespace(template_package, quietly = TRUE)) {
    return(contract_test_skip(paste0(
      "The independently distributed R reference pack is not installed; install ",
      template_package, " to run the cross-language backend-admission proof."
    )))
  }
  root <- normalizePath(".", winslash = "/", mustWork = TRUE)
  helper <- file.path(root, "tests", "helpers", "operation_pack_v1_backend_subprocess.R")
  log <- tempfile("operation_pack_v1_backend_", fileext = ".log")
  status <- system2(file.path(R.home("bin"), "Rscript"), c(shQuote(helper), shQuote(root)),
                    stdout = log, stderr = log)
  output <- readLines(log, warn = FALSE)
  unlink(log)
  if (!identical(status, 0L)) stop(paste(output, collapse = "\n"), call. = FALSE)
  stopifnot(any(output == "OPERATION_PACK_V1_BACKEND_ADMISSION_OK"))
  TRUE
}

test_operation_pack_v1_cross_language_lifecycle_contract <- function() {
  template_package <- "scworkbenchOperationPackTemplate"
  if (!requireNamespace(template_package, quietly = TRUE)) {
    return(contract_test_skip("The R operation-pack reference package is not installed."))
  }
  python <- Sys.getenv("SCWORKBENCH_PYBENCH_PYTHON", unset = "")
  manifest <- Sys.getenv("SCWORKBENCH_PYTHON_PACK_MANIFEST", unset = "")
  if (!nzchar(python) || !file.exists(python) || !nzchar(manifest) || !file.exists(manifest)) {
    return(contract_test_skip(paste0(
      "Set SCWORKBENCH_PYBENCH_PYTHON and SCWORKBENCH_PYTHON_PACK_MANIFEST ",
      "to execute the installed cross-language lifecycle proof.")))
  }
  root <- normalizePath(".", winslash = "/", mustWork = TRUE)
  helper <- file.path(root, "tests", "helpers",
                      "operation_pack_v1_cross_language_subprocess.R")
  log <- tempfile("operation_pack_v1_cross_language_", fileext = ".log")
  status <- system2(file.path(R.home("bin"), "Rscript"), c(
    shQuote(helper), shQuote(root), shQuote(python), shQuote(manifest)
  ), stdout = log, stderr = log)
  output <- readLines(log, warn = FALSE)
  unlink(log)
  if (!identical(status, 0L)) stop(paste(output, collapse = "\n"), call. = FALSE)
  stopifnot(any(output == "OPERATION_PACK_V1_CROSS_LANGUAGE_OK"))
  TRUE
}

test_operation_pack_v1_python_fault_confinement_contract <- function() {
  python <- Sys.getenv("SCWORKBENCH_PYBENCH_PYTHON", unset = "")
  manifest <- Sys.getenv("SCWORKBENCH_PYTHON_PACK_MANIFEST", unset = "")
  if (!nzchar(python) || !file.exists(python) || !nzchar(manifest) || !file.exists(manifest)) {
    return(contract_test_skip("Installed Python operation-pack fixtures are not configured."))
  }
  root <- normalizePath(".", winslash = "/", mustWork = TRUE)
  helper <- file.path(root, "tests", "helpers",
                      "operation_pack_v1_python_fault_subprocess.R")
  log <- tempfile("operation_pack_v1_python_faults_", fileext = ".log")
  status <- system2(file.path(R.home("bin"), "Rscript"), c(
    shQuote(helper), shQuote(root), shQuote(python), shQuote(manifest)
  ), stdout = log, stderr = log)
  output <- readLines(log, warn = FALSE)
  unlink(log)
  if (!identical(status, 0L)) stop(paste(output, collapse = "\n"), call. = FALSE)
  stopifnot(any(output == "OPERATION_PACK_V1_PYTHON_FAULTS_OK"))
  TRUE
}
