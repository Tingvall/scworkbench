.statistics_error_code <- function(expr) {
  error <- tryCatch(force(expr), error = identity)
  stopifnot(inherits(error, "wb_operation_pack_error"))
  as.character(error$code)[1]
}

test_catalog_activation <- function() {
  stopifnot(length(wb_list_ops()) == 43L, nrow(wb_operation_packs()) == 0L)
  before <- wb_operation_catalog_identity()
  stopifnot(identical(.statistics_error_code(.wb_op("de_wilcox")),
    "OPERATION_PACK_REQUIRED"))
  stopifnot(identical(before, wb_operation_catalog_identity()))
  contract_test_activate_statistics_pack()
  migrated <- .wb_operation_pack_migrated_map()
  short_names <- names(migrated)[startsWith(unname(migrated), "scwbstatistics::")]
  namespaced <- unname(migrated[short_names])
  stopifnot(length(wb_list_ops()) == 49L, all(namespaced %in% wb_list_ops()))
  for (short in short_names) {
    interface <- wb_op_interface(short)
    stopifnot(identical(interface$op_name, paste0("scwbstatistics::", short)))
  }
  first <- wb_operation_pack_inspect("scwbstatistics")
  second <- wb_operation_pack_load("scwbStatistics",
    lib.loc = .contract_test_statistics_state$library)
  stopifnot(identical(first$identity$pack_sha256, second$identity$pack_sha256),
    length(wb_list_ops()) == 49L)
  TRUE
}

test_scwb_statistics_pack_installation_inert_and_source_confinement_contract <- function() {
  source <- normalizePath(Sys.getenv("SCWBSTATISTICS_SOURCE"), mustWork = TRUE)
  library <- tempfile("scwbStatistics-inert-library-")
  dir.create(library)
  on.exit({
    if ("scwbStatistics" %in% loadedNamespaces()) {
      try(unloadNamespace("scwbStatistics"), silent = TRUE)
    }
    unlink(library, recursive = TRUE, force = TRUE)
  }, add = TRUE)
  before <- list(ops = wb_list_ops(), packs = wb_operation_packs(),
    identity = wb_operation_catalog_identity())
  log <- tempfile(fileext = ".log")
  status <- system2(file.path(R.home("bin"), "R"), c("CMD", "INSTALL",
    paste0("--library=", shQuote(library)), shQuote(source)),
    stdout = log, stderr = log)
  if (!identical(status, 0L)) {
    stop(paste(readLines(log, warn = FALSE), collapse = "\n"), call. = FALSE)
  }
  stopifnot(
    identical(before$ops, wb_list_ops()),
    identical(before$packs, wb_operation_packs()),
    identical(before$identity, wb_operation_catalog_identity())
  )

  method_source <- paste(readLines(file.path(source, "R", "statistics.R"),
    warn = FALSE), collapse = "\n")
  forbidden <- c(
    "DBI::", "dbConnect", "dbGetQuery", "dbExecute", "SQLite",
    "bundle\\$dir", "bundle_path", "staging_path", "final_path",
    "prov_runs", "prov_run_outputs", "operation_pack_registry"
  )
  stopifnot(
    !any(vapply(forbidden, grepl, logical(1), x = method_source,
      fixed = TRUE)),
    grepl("readers\\$", method_source),
    grepl("writers\\$write_terminal_primitive", method_source)
  )
  TRUE
}

test_scwb_statistics_pack_late_admission_zero_residue_contract <- function() {
  if ("scwbStatistics" %in% loadedNamespaces()) unloadNamespace("scwbStatistics")
  source <- Sys.getenv("SCWBSTATISTICS_SOURCE")
  library <- tempfile("scwbStatistics-invalid-library-"); dir.create(library)
  log <- tempfile(fileext = ".log")
  status <- system2(file.path(R.home("bin"), "R"), c("CMD", "INSTALL",
    paste0("--library=", shQuote(library)), shQuote(source)), stdout=log, stderr=log)
  if (!identical(status, 0L)) stop(paste(readLines(log), collapse="\n"), call.=FALSE)
  on.exit({
    if ("scwbStatistics" %in% loadedNamespaces()) unloadNamespace("scwbStatistics")
    unlink(library, recursive=TRUE, force=TRUE)
  }, add=TRUE)
  manifest <- system.file("scworkbench", "operation-pack.json",
    package="scwbStatistics", lib.loc=library)
  text <- readLines(manifest, warn=FALSE)
  text <- sub('"output": "trend_table", "merge": "row_bind_then_global_p_adjust_v1"',
    '"output": "missing", "merge": "row_bind_then_global_p_adjust_v1"', text, fixed=TRUE)
  writeLines(text, manifest, useBytes=TRUE)
  before_ops <- wb_list_ops(); before_packs <- wb_operation_packs()
  before_identity <- wb_operation_catalog_identity()
  code <- .statistics_error_code(wb_operation_pack_load("scwbStatistics", lib.loc=library))
  stopifnot(identical(code, "OPERATION_PACK_MANIFEST_SEMANTICS_INVALID"),
    identical(before_ops, wb_list_ops()), identical(before_packs, wb_operation_packs()),
    identical(before_identity, wb_operation_catalog_identity()))
  TRUE
}
