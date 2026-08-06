#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
output <- if (length(args)) args[[1L]] else "containers/apptainer/fullstack_r_versions.lock.csv"
packages <- sort(unique(installed.packages()[, "Package"]))
installed <- data.frame(
  Package = packages,
  Version = vapply(packages, function(package) as.character(utils::packageVersion(package)), character(1)),
  Priority = vapply(packages, function(package) {
    value <- utils::packageDescription(package)$Priority
    if (is.null(value)) "" else as.character(value)
  }, character(1)),
  stringsAsFactors = FALSE
)

classify <- function(package, priority) {
  description <- utils::packageDescription(package)
  repository <- if (is.null(description$Repository)) "" else as.character(description$Repository)
  remote_type <- if (is.null(description$RemoteType)) "" else as.character(description$RemoteType)
  if (package %in% c("BPCells", "monocle3") || identical(remote_type, "github")) return("Pinned GitHub")
  if (priority %in% c("base", "recommended")) return("R distribution")
  if (grepl("^Bioconductor", repository)) return("Bioconductor release")
  if (identical(repository, "CRAN")) return("CRAN")
  "qualified base image"
}

source_ref <- function(package, source_class) {
  description <- utils::packageDescription(package)
  if (identical(source_class, "CRAN")) return("https://cloud.r-project.org")
  if (identical(source_class, "Bioconductor release")) return("Bioconductor 3.21")
  if (identical(source_class, "R distribution")) return(paste0("R ", getRversion()))
  if (identical(source_class, "Pinned GitHub")) {
    user <- if (is.null(description$RemoteUsername)) "" else description$RemoteUsername
    repo <- if (is.null(description$RemoteRepo)) package else description$RemoteRepo
    sha <- if (is.null(description$RemoteSha)) "" else description$RemoteSha
    return(paste0("github:", user, "/", repo, "@", sha))
  }
  "pinned OCI base image"
}

classes <- mapply(classify, installed$Package, installed$Priority, USE.NAMES = FALSE)
lock <- data.frame(
  package = installed$Package,
  source_class = classes,
  source_ref = mapply(source_ref, installed$Package, classes, USE.NAMES = FALSE),
  version = installed$Version,
  stringsAsFactors = FALSE
)
lock <- lock[order(tolower(lock$package), lock$package), , drop = FALSE]
utils::write.csv(lock, output, row.names = FALSE, quote = TRUE)
cat("fullstack R version snapshot: ", nrow(lock), " packages\n", sep = "")
