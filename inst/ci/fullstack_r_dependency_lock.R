fullstack_lock_packages <- function(value) {
  packages <- trimws(strsplit(value, ",", fixed = TRUE)[[1L]])
  packages[nzchar(packages)]
}

fullstack_lock_github_packages <- function(value) {
  entries <- fullstack_lock_packages(value)
  if (!length(entries)) return(stats::setNames(character(), character()))
  match <- regexec("^([[:alnum:].]+)=([^@[:space:]]+)@([[:xdigit:]]{40})$", entries)
  parsed <- regmatches(entries, match)
  invalid <- lengths(parsed) != 4L
  if (any(invalid)) {
    stop("Invalid pinned GitHub prerequisite record(s): ", paste(entries[invalid], collapse = ", "))
  }
  values <- vapply(parsed, function(x) paste0(x[[3L]], "@", x[[4L]]), character(1))
  stats::setNames(values, vapply(parsed, `[[`, "", 2L))
}

read_fullstack_r_dependency_lock <- function(path) {
  fields <- read.dcf(path)
  required <- c(
    "SchemaVersion", "CRANRepository", "BioconductorRelease", "CRANPackages",
    "BioconductorPackages", "BioconductorGenomicFamily", "GitHubBPCellsRepo",
    "GitHubBPCellsRef", "GitHubBPCellsSubdir", "GitHubBPCellsPrerequisites", "GitHubMonocle3Repo",
    "GitHubMonocle3Ref", "GitHubMonocle3CRANPrerequisites", "GitHubMonocle3BioconductorPrerequisites",
    "GitHubMonocle3GitHubPrerequisites"
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
  lock$GitHubMonocle3GitHubPrerequisites <- fullstack_lock_github_packages(lock$GitHubMonocle3GitHubPrerequisites)
  github_prerequisites <- names(lock$GitHubMonocle3GitHubPrerequisites)
  release_owned <- unique(c(lock$CRANPackages, lock$BioconductorPackages,
                            lock$GitHubMonocle3CRANPrerequisites,
                            lock$GitHubMonocle3BioconductorPrerequisites))
  if (anyDuplicated(github_prerequisites) || length(intersect(github_prerequisites, release_owned))) {
    stop("Fullstack dependency lock assigns a GitHub prerequisite to more than one source")
  }
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

fullstack_monocle3_closure_packages <- function(lock) {
  unique(c(
    lock$GitHubMonocle3CRANPrerequisites,
    lock$GitHubMonocle3BioconductorPrerequisites,
    names(lock$GitHubMonocle3GitHubPrerequisites),
    "BPCells"
  ))
}

fullstack_validate_monocle3_closure <- function(lock, snapshot_path) {
  snapshot <- read.dcf(snapshot_path)
  required <- c("Package", "RemoteRef", "Depends", "Imports", "LinkingTo", "Remotes")
  if (!all(required %in% colnames(snapshot))) stop("Monocle3 dependency snapshot is incomplete")
  if (!identical(as.character(snapshot[1L, "Package"]), "monocle3") ||
      !identical(as.character(snapshot[1L, "RemoteRef"]), lock$GitHubMonocle3Ref)) {
    stop("Monocle3 dependency snapshot does not match the pinned source revision")
  }
  direct <- unique(unlist(lapply(c("Depends", "Imports", "LinkingTo"), function(field) {
    fullstack_description_packages(snapshot_path, field, exclude_r = TRUE)
  })))
  direct <- setdiff(direct, c("methods", "stats", "utils"))
  undeclared <- setdiff(direct, fullstack_monocle3_closure_packages(lock))
  if (length(undeclared)) {
    stop("Pinned monocle3 has undeclared direct dependency source(s): ", paste(undeclared, collapse = ", "))
  }
  required_remotes <- c(
    "github::bnprks/BPCells/r",
    "github::cole-trapnell-lab/speedglm"
  )
  remotes <- trimws(strsplit(snapshot[1L, "Remotes"], ",", fixed = TRUE)[[1L]])
  if (!all(required_remotes %in% remotes)) stop("Monocle3 snapshot has unowned GitHub remote(s)")
  if (!identical(lock$GitHubMonocle3GitHubPrerequisites[["speedglm"]],
                 "cole-trapnell-lab/speedglm@ca34b4e53319424b60c442bb550adf3574b4bfec")) {
    stop("Pinned monocle3 speedglm source is not locked to the declared remote")
  }
  invisible(direct)
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
