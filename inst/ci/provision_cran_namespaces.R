#!/usr/bin/env Rscript

provision_cran_namespaces <- function(packages,
                                      repo = getOption("repos")[["CRAN"]], retries = 3L) {
  packages <- unique(as.character(packages))
  if (!length(packages)) return(invisible(data.frame()))
  if (!is.character(repo) || length(repo) != 1L || !nzchar(repo)) {
    stop("A single CRAN repository URL is required")
  }

  results <- vector("list", length(packages))
  names(results) <- packages
  for (package in packages) {
    installed <- package %in% rownames(installed.packages())
    action <- if (installed) "already_installed" else "install"

    if (!installed) {
      install_error <- NULL
      for (attempt in seq_len(as.integer(retries))) {
        install_error <- tryCatch({utils::install.packages(package, repos = repo, dependencies = NA); NULL}, error = function(error) conditionMessage(error))
        if (package %in% rownames(installed.packages())) break
        if (attempt < retries) Sys.sleep(min(2^(attempt-1L), 8L))
      }
      installed <- package %in% rownames(installed.packages())
      if (!installed) {
        stop(
          "CRAN package installation failed for ", package,
          "; action=", action,
          "; repository=", repo,
          "; installed_version=<none>",
          "; library_paths=", paste(.libPaths(), collapse = " | "),
          "; retries=", retries, "; install_error=", ifelse(is.null(install_error), "<none>", install_error)
        )
      }
    }

    version <- tryCatch(as.character(utils::packageVersion(package)), error = function(error) NA_character_)
    results[[package]] <- data.frame(
      package = package,
      action = action,
      version = version,
      stringsAsFactors = FALSE
    )

    cat(
      "CRAN package installed: ", package,
      " action=", results[[package]]$action,
      " version=", results[[package]]$version,
      "\n",
      sep = ""
    )
  }

  output <- do.call(rbind, results)
  missing <- packages[!packages %in% rownames(installed.packages())]
  if (length(missing)) {
    stop("CRAN package final installation verification failed: ", paste(missing, collapse = ", "))
  }
  invisible(output)
}

.wb_parse_cran_probe_args <- function(args) {
  values <- list(packages = NULL, repo = getOption("repos")[["CRAN"]])
  while (length(args)) {
    key <- args[[1L]]
    args <- args[-1L]
    if (!key %in% c("--packages", "--repo") || !length(args)) {
      stop("Usage: provision_cran_namespaces.R --packages pkg1,pkg2 [--repo URL]")
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
    repo = options$repo
  )
}
