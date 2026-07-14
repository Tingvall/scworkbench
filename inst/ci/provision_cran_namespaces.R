#!/usr/bin/env Rscript

cran_namespace_diagnostic <- function(package) {
  loaded <- tryCatch(
    {
      loadNamespace(package)
      list(ok = TRUE, error = "")
    },
    error = function(error) list(ok = FALSE, error = conditionMessage(error))
  )
  version <- tryCatch(
    as.character(utils::packageVersion(package)),
    error = function(error) NA_character_
  )
  list(
    ok = loaded$ok,
    error = loaded$error,
    version = version,
    libraries = paste(.libPaths(), collapse = " | ")
  )
}

provision_cran_namespaces <- function(packages,
                                      repo = getOption("repos")[["CRAN"]],
                                      check_only = FALSE) {
  packages <- unique(as.character(packages))
  if (!length(packages)) return(invisible(data.frame()))
  if (!is.character(repo) || length(repo) != 1L || !nzchar(repo)) {
    stop("A single CRAN repository URL is required")
  }

  results <- vector("list", length(packages))
  names(results) <- packages
  for (package in packages) {
    before <- cran_namespace_diagnostic(package)
    action <- if (before$ok) "already_loadable" else if (check_only) "check_only" else "install"

    if (!before$ok && !check_only) {
      if (!is.na(before$version)) {
        try(remove.packages(package), silent = TRUE)
      }
      install_error <- tryCatch(
        {
          utils::install.packages(package, repos = repo, dependencies = TRUE)
          NULL
        },
        error = function(error) conditionMessage(error)
      )
      after <- cran_namespace_diagnostic(package)
      if (!after$ok) {
        stop(
          "CRAN namespace provisioning failed for ", package,
          "; action=", action,
          "; repository=", repo,
          "; installed_version=", ifelse(is.na(after$version), "<none>", after$version),
          "; library_paths=", after$libraries,
          "; install_error=", ifelse(is.null(install_error), "<none>", install_error),
          "; namespace_error=", after$error
        )
      }
      results[[package]] <- data.frame(
        package = package,
        action = action,
        version = after$version,
        stringsAsFactors = FALSE
      )
    } else if (!before$ok) {
      stop(
        "CRAN namespace is unavailable for ", package,
        "; action=", action,
        "; installed_version=", ifelse(is.na(before$version), "<none>", before$version),
        "; library_paths=", before$libraries,
        "; namespace_error=", before$error
      )
    } else {
      results[[package]] <- data.frame(
        package = package,
        action = action,
        version = before$version,
        stringsAsFactors = FALSE
      )
    }

    cat(
      "CRAN namespace OK: ", package,
      " action=", results[[package]]$action,
      " version=", results[[package]]$version,
      "\n",
      sep = ""
    )
  }

  output <- do.call(rbind, results)
  missing <- packages[!vapply(packages, function(package) {
    cran_namespace_diagnostic(package)$ok
  }, logical(1))]
  if (length(missing)) {
    stop("CRAN namespace final verification failed: ", paste(missing, collapse = ", "))
  }
  invisible(output)
}

.wb_parse_cran_probe_args <- function(args) {
  values <- list(packages = NULL, repo = getOption("repos")[["CRAN"]], check_only = FALSE)
  while (length(args)) {
    key <- args[[1L]]
    args <- args[-1L]
    if (identical(key, "--check-only")) {
      values$check_only <- TRUE
      next
    }
    if (!key %in% c("--packages", "--repo") || !length(args)) {
      stop("Usage: provision_cran_namespaces.R --packages pkg1,pkg2 [--repo URL] [--check-only]")
    }
    values[[sub("^--", "", key)]] <- args[[1L]]
    args <- args[-1L]
  }
  values
}

if (identical(sys.nframe(), 0L)) {
  options <- .wb_parse_cran_probe_args(commandArgs(trailingOnly = TRUE))
  if (is.null(options$packages) || !nzchar(options$packages)) {
    stop("--packages is required when running this script directly")
  }
  provision_cran_namespaces(
    trimws(strsplit(options$packages, ",", fixed = TRUE)[[1L]]),
    repo = options$repo,
    check_only = options$check_only
  )
}
