#!/usr/bin/env Rscript

.wb_declared_suggests <- function(description_path) {
  fields <- read.dcf(description_path)
  if (!"Suggests" %in% colnames(fields) || !nzchar(fields[1L, "Suggests"])) {
    return(character())
  }

  entries <- trimws(strsplit(fields[1L, "Suggests"], ",", fixed = TRUE)[[1L]])
  packages <- trimws(sub("\\s*\\(.*$", "", entries))
  unique(packages[nzchar(packages) & packages != "R"])
}

.wb_parse_args <- function(args) {
  values <- list(description = "DESCRIPTION", manifest = NULL)
  while (length(args)) {
    key <- args[[1L]]
    args <- args[-1L]
    if (!key %in% c("--description", "--manifest") || !length(args)) {
      stop("Usage: check_declared_suggests.R [--description PATH] [--manifest PATH]")
    }
    values[[sub("^--", "", key)]] <- args[[1L]]
    args <- args[-1L]
  }
  values
}

options <- .wb_parse_args(commandArgs(trailingOnly = TRUE))
if (!file.exists(options$description)) {
  stop("DESCRIPTION file does not exist: ", options$description)
}

packages <- .wb_declared_suggests(options$description)
available <- vapply(packages, requireNamespace, logical(1), quietly = TRUE)
versions <- vapply(
  packages,
  function(package) if (requireNamespace(package, quietly = TRUE)) {
    as.character(utils::packageVersion(package))
  } else {
    NA_character_
  },
  character(1)
)
manifest <- data.frame(
  package = packages,
  available = available,
  version = versions,
  stringsAsFactors = FALSE
)

if (!is.null(options$manifest)) {
  write.csv(manifest, options$manifest, row.names = FALSE, quote = TRUE)
}

missing <- manifest$package[!manifest$available]
if (length(missing)) {
  stop(
    "Missing declared Suggests (", length(missing), "): ",
    paste(missing, collapse = ", ")
  )
}

cat(
  "Declared Suggests preflight OK: ", nrow(manifest), " package(s)\n",
  paste(sprintf("%s=%s", manifest$package, manifest$version), collapse = "\n"),
  "\n",
  sep = ""
)
