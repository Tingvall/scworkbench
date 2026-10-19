.engine_graph_recovery_process_fixture <- function(modes) {
  package <- normalizePath(find.package("scworkbench"), winslash = "/", mustWork = TRUE)
  if (!file.exists(file.path(package, "Meta", "package.rds")))
    return(contract_test_skip("This process-replacement proof requires an actual installed core library."))
  root <- tempfile("graph_durable_recovery_"); dir.create(root)
  on.exit(unlink(root, recursive = TRUE, force = TRUE), add = TRUE)
  dir.create(file.path(root, "packs"))
  source <- file.path(normalizePath(".", winslash = "/"), "tests/fixtures/operation-pack-v4-graph")
  install <- system2(file.path(R.home("bin"), "R"), c("CMD", "INSTALL",
    paste0("--library=", shQuote(file.path(root, "packs"))), shQuote(source)),
    stdout = file.path(root, "install.log"), stderr = file.path(root, "install.log"))
  if (install != 0L) stop(paste(readLines(file.path(root, "install.log")), collapse = "\n"))
  script <- normalizePath("tests/fixtures/graph_durable_replacement_process.R", mustWork = TRUE)
  dll <- digest::digest(file = getLoadedDLLs()[["scworkbench"]][["path"]], algo = "sha256")
  old_libs <- Sys.getenv("R_LIBS", unset = NA_character_)
  on.exit(if (is.na(old_libs)) Sys.unsetenv("R_LIBS") else Sys.setenv(R_LIBS = old_libs), add = TRUE)
  Sys.setenv(R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep))
  for (mode in modes) {
    log <- file.path(root, paste0(mode, ".log"))
    status <- system2(file.path(R.home("bin"), "Rscript"),
      c("--vanilla", shQuote(script), mode, shQuote(root), shQuote(dirname(package)), dll), stdout = log, stderr = log)
    output <- readLines(log, warn = FALSE)
    if (status != 0L) stop(paste(mode, status, paste(output, collapse = "\n")))
    stopifnot(any(output == paste("GRAPH_DURABLE_PROCESS_OK", mode)))
  }
  TRUE
}

test_engine_graph_durable_three_process_recovery_contract <- function() {
  .engine_graph_recovery_process_fixture(c("writer", "loader", "resume"))
}

test_engine_graph_durable_tamper_cleanup_restored_retry_contract <- function() {
  .engine_graph_recovery_process_fixture(c("writer", "attacks"))
}

test_engine_graph_durable_partial_multi_run_cleanup_contract <- function() {
  .engine_graph_recovery_process_fixture(c("writer_two", "multi_failure"))
}

test_engine_graph_durable_source_rejection_before_import_contract <- function() {
  .engine_graph_recovery_process_fixture(c("writer", "source_failure"))
}
