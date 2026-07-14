#!/usr/bin/env Rscript

.parse_args <- function(args) {
  values <- list(lock = NULL, description = "DESCRIPTION", manifest = NULL)
  while (length(args)) {
    key <- args[[1L]]
    args <- args[-1L]
    if (!key %in% c("--lock", "--description", "--manifest") || !length(args)) {
      stop("Usage: validate_fullstack_r_dependencies.R --lock PATH [--description PATH] [--manifest PATH]")
    }
    values[[sub("^--", "", key)]] <- args[[1L]]
    args <- args[-1L]
  }
  if (is.null(values$lock)) stop("--lock is required")
  values
}

arguments <- .parse_args(commandArgs(trailingOnly = TRUE))
script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
if (!length(script_arg)) stop("Cannot locate validator script path")
source(file.path(dirname(normalizePath(sub("^--file=", "", script_arg[[1L]]))), "fullstack_r_dependency_lock.R"))

lock <- read_fullstack_r_dependency_lock(arguments$lock)
classes <- fullstack_source_classes(lock, arguments$description)
refs <- fullstack_source_refs(lock, classes)
packages <- names(classes)

diagnose_namespace <- function(package) {
  loaded <- tryCatch(
    {
      loadNamespace(package)
      list(ok = TRUE, error = "")
    },
    error = function(error) list(ok = FALSE, error = conditionMessage(error))
  )
  list(
    ok = loaded$ok,
    error = loaded$error,
    version = tryCatch(as.character(utils::packageVersion(package)), error = function(error) NA_character_)
  )
}

diagnostics <- lapply(packages, diagnose_namespace)
manifest <- data.frame(
  package = packages,
  source_class = unname(classes),
  source_ref = unname(refs),
  version = vapply(diagnostics, `[[`, "", "version"),
  namespace_loadable = vapply(diagnostics, `[[`, logical(1), "ok"),
  namespace_error = vapply(diagnostics, `[[`, "", "error"),
  library_paths = paste(.libPaths(), collapse = " | "),
  stringsAsFactors = FALSE
)

if (!is.null(arguments$manifest)) {
  write.csv(manifest, arguments$manifest, row.names = FALSE, quote = TRUE)
}

failed <- manifest[!manifest$namespace_loadable, , drop = FALSE]
if (nrow(failed)) {
  details <- vapply(seq_len(nrow(failed)), function(index) {
    paste0(
      failed$package[[index]],
      " version=", ifelse(is.na(failed$version[[index]]), "<none>", failed$version[[index]]),
      " error=", failed$namespace_error[[index]]
    )
  }, character(1))
  stop(
    "Fresh-process fullstack namespace validation failed: ",
    paste(details, collapse = "; "),
    "; library_paths=", paste(.libPaths(), collapse = " | ")
  )
}

cat(
  "Fresh-process fullstack namespace validation OK: ", nrow(manifest), " package(s)\n",
  paste(sprintf("%s=%s", manifest$package, manifest$version), collapse = "\n"),
  "\n",
  sep = ""
)
