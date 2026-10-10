.wb_sdk_asset <- function(...) {
  path <- system.file("sdk", "operation-packs", ..., package = "scworkbench")
  if (!nzchar(path) || !file.exists(path)) stop("Installed SDK asset is missing.", call. = FALSE)
  path
}

.wb_sdk_text <- function(value, label) {
  if (!is.character(value) || length(value) != 1L || is.na(value) ||
      !nzchar(trimws(value)) || grepl("[\r\n]", value))
    stop(label, " must be one nonempty line.", call. = FALSE)
  value
}

#' Scaffold an Explicit Operation Pack
#'
#' Generate an installed ABI-v3 matrix or ABI-v4 graph reference project without installation,
#' activation, network access or Git mutation. The destination must not exist
#' and its parent must exist. Generation is published by one directory rename.
#' Publication uses Linux `renameat2(RENAME_NOREPLACE)` and atomically refuses
#' any competing destination. Unsupported platforms, kernels or filesystems
#' fail closed without a replacing-rename fallback.
#' See the installed SDK tutorial for the complete author workflow.
#' @param path New project directory; spaces are supported, traversal is not.
#' @param package Valid R package name.
#' @param namespace Non-reserved lowercase pack namespace.
#' @param author Real maintainer name.
#' @param email Maintainer email address.
#' @param license Supported template license, currently `"MIT"`.
#' @param backend Supported installed template backend, currently `"R"`.
#' @param template `"matrix_cell_sum"` (ABI3) or `"graph"` (ABI4).
#' @return Descriptor with SDK version, project, package, namespace and manifest.
#' @export
wb_operation_pack_scaffold <- function(path, package, namespace, author, email,
                                       license = "MIT", backend = "R",
                                       template = c("matrix_cell_sum", "graph")) {
  template <- match.arg(template)
  path <- .wb_sdk_text(path, "path")
  package <- .wb_sdk_text(package, "package")
  namespace <- .wb_sdk_text(namespace, "namespace")
  author <- .wb_sdk_text(author, "author"); email <- .wb_sdk_text(email, "email")
  if (!grepl("^[A-Za-z][A-Za-z0-9.]*$", package) || nchar(package) < 2L ||
      grepl("[.]$", package)) stop("Invalid R package name.", call. = FALSE)
  if (!grepl("^[a-z][a-z0-9_]*$", namespace)) stop("Invalid namespace.", call. = FALSE)
  if (namespace %in% .wb_operation_pack_reserved_namespaces())
    stop("Operation-pack namespace is reserved.", call. = FALSE)
  if (!grepl("^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$", email))
    stop("A maintainer email is required.", call. = FALSE)
  if (!identical(license, "MIT") || !identical(backend, "R"))
    stop("The installed R SDK supports the MIT/R template; Python has its PyBench companion.", call. = FALSE)
  parts <- strsplit(gsub("\\\\", "/", path), "/", fixed = TRUE)[[1L]]
  if (any(parts %in% c(".", "..")) || !nzchar(basename(path)))
    stop("Destination traversal is forbidden.", call. = FALSE)
  link <- Sys.readlink(path)
  if (file.exists(path) || dir.exists(path) || (!is.na(link) && nzchar(link)))
    stop("Destination already exists; overwrite is forbidden.", call. = FALSE)
  parent <- normalizePath(dirname(path), winslash = "/", mustWork = TRUE)
  destination <- file.path(parent, basename(path))
  stage <- tempfile(".scwb-sdk-", tmpdir = parent)
  if (!dir.create(stage)) stop("Cannot create scaffold staging directory.", call. = FALSE)
  on.exit(if (dir.exists(stage)) unlink(stage, recursive = TRUE, force = TRUE), add = TRUE)
  template_root <- .wb_sdk_asset("templates", if (template == "graph") "graph-R" else "R")
  paths <- sort(list.files(template_root, recursive = TRUE, all.files = TRUE,
    no.. = TRUE, include.dirs = FALSE))
  replacements <- c("@PACKAGE@" = package, "@NAMESPACE@" = namespace,
    "@AUTHOR@" = author, "@EMAIL@" = email, "@YEAR@" = format(Sys.Date(), "%Y"))
  # Encode metadata through DCF/R/JSON syntax, rather than interpolating code.
  if (grepl('["\\\\]', author) || grepl('["\\\\]', email))
    stop("Author metadata cannot contain quote or backslash characters.", call. = FALSE)
  for (relative in paths) {
    output <- file.path(stage, relative)
    dir.create(dirname(output), recursive = TRUE, showWarnings = FALSE)
    value <- readLines(file.path(template_root, relative), warn = FALSE)
    for (key in names(replacements)) value <- gsub(key, replacements[[key]],
      value, fixed = TRUE)
    writeLines(value, output, useBytes = TRUE)
    hook <- getOption("scworkbench.sdk_scaffold_test_hook", NULL)
    if (is.function(hook)) hook(relative)
  }
  manifest <- file.path(stage, "inst", "scworkbench", "operation-pack.json")
  wb_operation_pack_manifest_validate(manifest)
  read.dcf(file.path(stage, "DESCRIPTION"))
  publish_hook <- getOption("scworkbench.sdk_scaffold_publication_test_hook", NULL)
  if (is.function(publish_hook)) publish_hook(stage, destination)
  .Call(C_scwb_sdk_publish_noreplace, stage, destination)
  list(sdk_version = if (template == "graph") "1.1.0" else "1.0.0",
    pack_abi_version = if (template == "graph") "4" else "3",
    path = destination, package = package,
    namespace = namespace, manifest = file.path(destination, "inst",
      "scworkbench", "operation-pack.json"))
}

#' Inspect Installed Operation Pack SDK Capabilities
#' @param backend Optional `"R"` or `"Python"` backend filter.
#' @param kind Optional primitive kind filter.
#' @param pack_abi_version Inventory version, `"3"` (default) or `"4"`.
#' @return Versioned catalog with distinct manifest, request and runtime support.
#'   Inspection supplies no grants. Unsupported policy combinations are explicit.
#' @export
wb_operation_pack_capabilities <- function(backend = NULL, kind = NULL,
                                           pack_abi_version = c("3", "4")) {
  pack_abi_version <- match.arg(pack_abi_version)
  catalog <- jsonlite::read_json(.wb_sdk_asset(if (pack_abi_version == "4")
    "capabilities-v4.json" else "capabilities.json"), simplifyVector = FALSE)
  if (!is.null(backend)) {
    if (length(backend) != 1L || is.na(backend) || !backend %in% c("R", "Python"))
      stop("backend must be R or Python.", call. = FALSE)
    catalog$capabilities <- Filter(function(x) backend %in% unlist(x$backends), catalog$capabilities)
  }
  if (!is.null(kind)) catalog$capabilities <- Filter(function(x)
    kind %in% unlist(x$kinds), catalog$capabilities)
  catalog
}

#' Map an Already Granted Ordered Partition Reader
#' @param reader Invocation-scoped reader supplied by core.
#' @param grant Entry from `context$typed_slice_reads`.
#' @param FUN Function of the returned primitive and one-based partition index.
#' @return Ordered list of callback results. This wraps [wb_partition_axis()]
#'   and the granted reader; it never accepts a bundle or slices storage itself.
#'   Bounded reads do not imply bounded total algorithm memory.
#' @export
wb_operation_pack_map_partitions <- function(reader, grant, FUN) {
  if (!is.function(reader) || !is.function(FUN) || !is.list(grant) ||
      !identical(grant$call_discipline, "ordered_partition_exactly_once") ||
      !grant$chunk_axis %in% c("cells", "features"))
    stop("An issued ordered typed-slice reader and its context grant are required.", call. = FALSE)
  cells <- as.character(grant$cells); features <- as.character(grant$features)
  plans <- wb_partition_axis(if (grant$chunk_axis == "cells") cells else features,
    grant$requested_chunk_size)
  lapply(seq_along(plans), function(index) {
    value <- if (grant$chunk_axis == "cells")
      reader(features = features, cells = plans[[index]]) else
      reader(features = plans[[index]], cells = cells)
    FUN(value, index)
  })
}

#' Check an Operation Pack Project
#'
#' Static checks do not import the target. Installed and contract checks require
#' `trusted = TRUE` because installation/entry points/tests execute author code.
#' Local installation occurs in an isolated library with no dependency downloads.
#' Contract mode invokes the author's `tests/run_contract_tests.R` in a fresh
#' process through the existing public session dispatcher.
#' @param path Project directory.
#' @param level Static metadata/manifest, trusted installed validation, or contract.
#' @param trusted Explicit permission to execute target code.
#' @param lib.loc Optional core dependency library paths used by child processes.
#' @return Report with checks, test counts, exits, logs, identities, and qualified.
#'   A zero helper exit does not mean `R CMD check` Status OK or scientific validity.
#' @export
wb_operation_pack_check <- function(path, level = c("static", "installed", "contract"),
                                   trusted = FALSE, lib.loc = NULL) {
  level <- match.arg(level)
  path <- normalizePath(path, winslash = "/", mustWork = TRUE)
  if (level != "static" && !isTRUE(trusted))
    stop("trusted = TRUE is required to install or execute pack code.", call. = FALSE)
  report <- list(sdk_version = "1.0.0", level = level, qualified = FALSE,
    checks = list(), tests = list(discovered = 0L, executed = 0L, passed = 0L,
      skipped = 0L, failed = 0L), command_exits = list(), logs = list(), diagnostics = list(),
    runtime = list(R = as.character(getRversion()), scworkbench =
      as.character(utils::packageVersion("scworkbench"))))
  validate <- tryCatch({
    dcf <- read.dcf(file.path(path, "DESCRIPTION"))
    for (field in c("Package", "Version", "Title", "Description", "License", "Authors@R", "Imports"))
      if (!field %in% colnames(dcf) || !nzchar(dcf[[1L, field]])) stop("Missing package metadata: ", field)
    if (!grepl("scworkbench", dcf[[1L, "Imports"]], fixed = TRUE))
      stop("scworkbench must be a declared dependency.")
    expression <- parse(text = dcf[[1L, "Authors@R"]])
    literal_author <- function(x) {
      if (is.atomic(x)) return(TRUE)
      if (!is.call(x) || !as.character(x[[1L]]) %in% c("person", "c")) return(FALSE)
      all(vapply(as.list(x)[-1L], literal_author, logical(1)))
    }
    if (length(expression) != 1L || !literal_author(expression[[1L]]))
      stop("Authors@R must contain literal person/c calls; static validation never executes author code.")
    author_environment <- new.env(parent = emptyenv())
    author_environment$person <- utils::person; author_environment$c <- base::c
    authors <- eval(expression, envir = author_environment)
    if (!inherits(authors, "person") || !any(vapply(unclass(authors),
      function(x) "cre" %in% x$role && length(x$email) && nzchar(x$email), logical(1))))
      stop("A real creator with email is required.")
    validated <- wb_operation_pack_manifest_validate(file.path(path, "inst",
      "scworkbench", "operation-pack.json"))
    if (!identical(validated$manifest$package$name, dcf[[1L, "Package"]]) ||
        !identical(validated$manifest$package$version, dcf[[1L, "Version"]]))
      stop("DESCRIPTION and manifest package/version differ.")
    validated
  }, error = identity)
  if (inherits(validate, "error")) {
    report$checks$static <- list(passed = FALSE, reason = conditionMessage(validate))
    return(report)
  }
  report$checks$static <- list(passed = TRUE)
  report$identity <- validate$identity
  if (level == "static") { report$qualified <- TRUE; return(report) }
  library <- tempfile("scwb-sdk-check-library-"); dir.create(library)
  logs <- tempfile("scwb-sdk-check-logs-"); dir.create(logs)
  paths <- unique(c(library, lib.loc, .libPaths()))
  env <- paste0("R_LIBS=", shQuote(paste(paths, collapse = .Platform$path.sep)))
  install_log <- file.path(logs, "install.log")
  status <- system2(file.path(R.home("bin"), "R"), c("CMD", "INSTALL",
    paste0("--library=", shQuote(library)), shQuote(path)), env = env,
    stdout = install_log, stderr = install_log)
  report$library <- library; report$logs$install <- install_log
  report$command_exits$install <- as.integer(status)
  report$diagnostics$install <- readLines(install_log, warn = FALSE)
  if (status != 0L) return(report)
  installed_log <- file.path(logs, "installed.log")
  status <- system2(file.path(R.home("bin"), "Rscript"), c("--vanilla",
    shQuote(.wb_sdk_asset("scripts", "installed_check.R")),
    shQuote(validate$manifest$package$name), shQuote(library)), env = env,
    stdout = installed_log, stderr = installed_log)
  report$command_exits$installed <- as.integer(status)
  report$logs$installed <- installed_log
  report$diagnostics$installed <- readLines(installed_log, warn = FALSE)
  if (status != 0L) return(report)
  report$checks$installed <- list(passed = TRUE)
  if (level == "installed") { report$qualified <- TRUE; return(report) }
  script <- file.path(path, "tests", "run_contract_tests.R")
  if (!file.exists(script)) {
    report$checks$contract <- list(passed = FALSE, reason = "Author contract runner is missing.")
    return(report)
  }
  result_path <- file.path(logs, "contract_report.rds")
  log <- file.path(logs, "contract.log")
  old <- setwd(path); on.exit(setwd(old), add = TRUE)
  status <- system2(file.path(R.home("bin"), "Rscript"), c("--vanilla",
    shQuote(script), shQuote(library), shQuote(result_path)), env = env,
    stdout = log, stderr = log)
  report$command_exits$contract <- as.integer(status); report$logs$contract <- log
  report$diagnostics$contract <- readLines(log, warn = FALSE)
  if (file.exists(result_path)) {
    result <- tryCatch(readRDS(result_path), error = function(e) NULL)
    if (!is.list(result)) result <- list()
    counts <- result$counts
    valid_counts <- is.list(counts) && identical(names(counts),
      c("discovered", "executed", "passed", "skipped", "failed")) &&
      all(vapply(counts, function(x) is.numeric(x) && length(x) == 1L &&
        is.finite(x) && x >= 0 && x == floor(x), logical(1)))
    valid_report <- tryCatch(identical(result$sdk_version, "1.0.0") && valid_counts &&
        counts$executed == length(result$cases) && counts$executed ==
          counts$passed + counts$skipped + counts$failed &&
        counts$executed <= counts$discovered &&
        identical(as.integer(table(factor(vapply(result$cases, `[[`, character(1), "status"),
          levels = c("passed", "skipped", "failed")))),
          as.integer(unlist(counts[c("passed", "skipped", "failed")]))),
      error = function(e) FALSE)
    if (isTRUE(valid_report)) {
      report$tests <- result$counts; report$cases <- result$cases
      report$execution_identities <- result$identities
    }
  }
  report$qualified <- identical(as.integer(status), 0L) &&
    report$tests$executed > 0L && report$tests$failed == 0L &&
    report$tests$skipped == 0L && report$tests$executed == report$tests$discovered
  report
}
