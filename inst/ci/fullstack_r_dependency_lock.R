fullstack_lock_packages <- function(value) {
  packages <- trimws(strsplit(value, ",", fixed = TRUE)[[1L]])
  packages[nzchar(packages)]
}

read_fullstack_r_dependency_lock <- function(path) {
  fields <- read.dcf(path)
  required <- c(
    "SchemaVersion", "CRANRepository", "BioconductorRelease", "CRANPackages",
    "BioconductorPackages", "BioconductorGenomicFamily", "GitHubBPCellsRepo",
    "GitHubBPCellsRef", "GitHubBPCellsSubdir", "GitHubBPCellsPrerequisites", "GitHubMonocle3Repo",
    "GitHubMonocle3Ref", "GitHubMonocle3CRANPrerequisites", "GitHubMonocle3BioconductorPrerequisites"
  )
  missing <- setdiff(required, colnames(fields))
  if (length(missing)) {
    stop("Fullstack dependency lock is missing fields: ", paste(missing, collapse = ", "))
  }
  lock <- as.list(fields[1L, required])
  lock$CRANPackages <- fullstack_lock_packages(lock$CRANPackages)
  lock$BioconductorPackages <- fullstack_lock_packages(lock$BioconductorPackages)
  lock$BioconductorGenomicFamily <- fullstack_lock_packages(lock$BioconductorGenomicFamily)
  lock$GitHubBPCellsPrerequisites <- fullstack_lock_packages(lock$GitHubBPCellsPrerequisites)
  lock$GitHubMonocle3CRANPrerequisites <- fullstack_lock_packages(lock$GitHubMonocle3CRANPrerequisites)
  lock$GitHubMonocle3BioconductorPrerequisites <- fullstack_lock_packages(lock$GitHubMonocle3BioconductorPrerequisites)
  lock
}

configure_fullstack_repositories <- function(lock) {
  repositories <- BiocManager::repositories(version = lock$BioconductorRelease)
  repositories[["CRAN"]] <- lock$CRANRepository
  options(repos = repositories)
  invisible(repositories)
}

fullstack_declared_suggests <- function(description_path) {
  fullstack_description_packages(description_path, "Suggests", exclude_r = TRUE)
}

fullstack_description_packages <- function(description_path, field, exclude_r = FALSE) {
  fields <- read.dcf(description_path)
  if (!field %in% colnames(fields) || !nzchar(fields[1L, field])) return(character())
  entries <- trimws(strsplit(fields[1L, field], ",", fixed = TRUE)[[1L]])
  packages <- trimws(sub("\\s*\\(.*$", "", entries))
  packages <- packages[nzchar(packages)]
  if (exclude_r) packages <- setdiff(packages, "R")
  unique(packages)
}

fullstack_source_classes <- function(lock, description_path) {
  classes <- c(
    setNames(rep("CRAN", length(lock$CRANPackages)), lock$CRANPackages),
    setNames(rep("Bioconductor release", length(lock$BioconductorPackages)), lock$BioconductorPackages),
    BPCells = "Pinned GitHub",
    monocle3 = "Pinned GitHub",
    methods = "R base"
  )
  product_dependencies <- unique(c(
    fullstack_description_packages(description_path, "Imports"),
    fullstack_declared_suggests(description_path)
  ))
  unknown <- setdiff(product_dependencies, names(classes))
  if (length(unknown)) {
    stop("DESCRIPTION Imports/Suggests have no fullstack source class: ", paste(unknown, collapse = ", "))
  }
  if (anyDuplicated(names(classes))) stop("Fullstack dependency lock has duplicate package ownership")
  classes
}

fullstack_source_refs <- function(lock, classes) {
  refs <- classes
  refs[classes == "CRAN"] <- lock$CRANRepository
  refs[classes == "Bioconductor release"] <- paste0("Bioconductor ", lock$BioconductorRelease)
  refs["BPCells"] <- paste0("github:", lock$GitHubBPCellsRepo, "@", lock$GitHubBPCellsRef)
  refs["monocle3"] <- paste0("github:", lock$GitHubMonocle3Repo, "@", lock$GitHubMonocle3Ref)
  refs["methods"] <- paste0("R ", getRversion())
  refs
}
