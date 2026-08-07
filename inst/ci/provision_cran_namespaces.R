#!/usr/bin/env Rscript

provision_cran_namespaces <- function(packages,
                                      repo = getOption("repos")[["CRAN"]], retries = 3L,
                                      target_versions = NULL,
                                      install_one = NULL,
                                      installed_names = NULL,
                                      installed_version = NULL,
                                      remove_one = NULL,
                                      sleep_fun = Sys.sleep) {
  packages <- unique(as.character(packages))
  if (!length(packages)) return(invisible(data.frame()))
  if (!is.character(repo) || length(repo) != 1L || !nzchar(repo)) {
    stop("A single CRAN repository URL is required")
  }

  if (is.null(installed_names)) installed_names <- function() rownames(installed.packages())
  if (is.null(installed_version)) installed_version <- function(package) as.character(utils::packageVersion(package))
  if (is.null(remove_one)) remove_one <- function(package) remove.packages(package)
  if (is.null(install_one)) install_one <- function(package, expected, repo) {
    if (is.null(expected)) {
      utils::install.packages(package, repos = repo, dependencies = NA)
    } else {
      remotes::install_version(
        package, version = expected, repos = repo,
        upgrade = "never", dependencies = FALSE
      )
    }
  }

  is_installed <- function(package) package %in% installed_names()
  version_of <- function(package) {
    tryCatch(installed_version(package), error = function(error) NA_character_)
  }
  expected_for <- function(package) {
    if (is.null(target_versions) || !package %in% names(target_versions)) NULL else as.character(target_versions[[package]])
  }

  results <- vector("list", length(packages))
  names(results) <- packages
  pending <- character()
  for (package in packages) {
    installed <- is_installed(package)
    expected <- expected_for(package)
    observed <- if (installed) version_of(package) else NA_character_
    if (installed && !is.null(expected) && !identical(observed, expected)) {
      remove_one(package)
      installed <- FALSE
    }
    if (installed) {
      results[[package]] <- data.frame(
        package = package,
        action = "already_installed",
        version = observed,
        stringsAsFactors = FALSE
      )
    } else {
      pending <- c(pending, package)
    }
  }

  last_errors <- stats::setNames(rep(NA_character_, length(pending)), pending)
  while (length(pending)) {
    deferred <- character()
    progress <- FALSE
    for (package in pending) {
      expected <- expected_for(package)
      action <- if (is.null(expected)) "install" else "install_locked_version"
      install_error <- NULL
      for (attempt in seq_len(as.integer(retries))) {
        install_error <- tryCatch({
          install_one(package, expected, repo)
          NULL
        }, error = function(error) conditionMessage(error))
        if (is_installed(package)) break
        if (attempt < retries) sleep_fun(min(2^(attempt - 1L), 8L))
      }
      if (!is_installed(package)) {
        deferred <- c(deferred, package)
        last_errors[[package]] <- ifelse(is.null(install_error), "<none>", install_error)
        next
      }
      version <- version_of(package)
      if (!is.null(expected) && !identical(version, expected)) {
        stop("CRAN version lock mismatch after installation: package=", package,
             "; expected=", expected, "; observed=", version)
      }
      results[[package]] <- data.frame(
        package = package,
        action = action,
        version = version,
        stringsAsFactors = FALSE
      )
      cat("CRAN package installed: ", package, " action=", action,
          " version=", version, "\n", sep = "")
      progress <- TRUE
    }
    if (!length(deferred)) break
    if (!progress) {
      details <- vapply(deferred, function(package) {
        paste0(package, "=", last_errors[[package]])
      }, character(1))
      stop(
        "CRAN package installation made no dependency-order progress; repository=", repo,
        "; pending=", paste(details, collapse = "; "),
        "; library_paths=", paste(.libPaths(), collapse = " | "),
        "; retries=", retries
      )
    }
    pending <- deferred
  }

  output <- do.call(rbind, results)
  missing <- packages[!packages %in% installed_names()]
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
