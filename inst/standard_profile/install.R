args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 6L) stop(paste(
  "usage: Rscript inst/standard_profile/install.R",
  "CORE_SOURCE PYBENCH_SOURCE PACK_ROOT LATENT_PYTHON R_LIBRARY RECEIPT_PATH"),
  call. = FALSE)
core_source <- normalizePath(args[[1L]], winslash = "/", mustWork = TRUE)
pybench_source <- normalizePath(args[[2L]], winslash = "/", mustWork = TRUE)
pack_root <- normalizePath(args[[3L]], winslash = "/", mustWork = TRUE)
if (!file.exists(args[[4L]]) || dir.exists(args[[4L]])) stop(
  "LATENT_PYTHON must name an existing interpreter", call. = FALSE)
# Keep the venv entry itself: resolving the python symlink escapes its package set.
latent_python <- file.path(normalizePath(dirname(args[[4L]]), winslash = "/",
  mustWork = TRUE), basename(args[[4L]]))
library_path <- normalizePath(args[[5L]], winslash = "/", mustWork = FALSE)
receipt_path <- path.expand(args[[6L]])
dir.create(library_path, recursive = TRUE, showWarnings = FALSE)
library_path <- normalizePath(library_path, winslash = "/", mustWork = TRUE)
dir.create(dirname(receipt_path), recursive = TRUE, showWarnings = FALSE)
receipt_path <- file.path(normalizePath(dirname(receipt_path), winslash = "/",
  mustWork = TRUE), basename(receipt_path))
if (startsWith(receipt_path, paste0(library_path, "/"))) stop(
  "The installation receipt must be outside the installed package library.",
  call. = FALSE)
Sys.setenv(SCWB_LATENT_PYTHON = latent_python)

profile_root <- file.path(core_source, "inst", "standard_profile")
profile_path <- file.path(profile_root, "profile.json")
profile_script <- file.path(profile_root, "activate.R")
stopifnot(file.exists(profile_path), file.exists(profile_script))
lock <- jsonlite::fromJSON(profile_path, simplifyVector = FALSE)

git_output <- function(path, arguments) {
  output <- suppressWarnings(system2("git", c("-C", shQuote(path), arguments),
    stdout = TRUE, stderr = TRUE))
  if (!is.null(attr(output, "status")) && attr(output, "status") != 0L)
    stop("Git preflight failed at ", path, ": ", paste(output, collapse = "\n"),
      call. = FALSE)
  output
}
verify_source <- function(path, expected = NULL) {
  head <- git_output(path, c("rev-parse", "HEAD"))
  if (length(head) != 1L || (!is.null(expected) && !identical(head, expected)))
    stop("Wrong source commit at ", path, call. = FALSE)
  if (length(git_output(path, c("status", "--porcelain"))))
    stop("Dirty source worktree at ", path, call. = FALSE)
  head
}
core_commit <- verify_source(core_source)
ancestor <- suppressWarnings(system2("git", c("-C", shQuote(core_source),
  "merge-base", "--is-ancestor", lock$core_start_commit, core_commit),
  stdout = FALSE, stderr = FALSE))
if (!identical(as.integer(ancestor), 0L)) stop(
  "The core source is not descended from the accepted Phase 7 starting commit.",
  call. = FALSE)
verify_source(pybench_source, lock$pybench_source_commit)
for (entry in lock$packs) {
  path <- file.path(pack_root, entry$package)
  verify_source(path, entry$source_commit)
  manifest <- file.path(path, "inst", "scworkbench", "operation-pack.json")
  if (!identical(digest::digest(manifest, algo = "sha256", file = TRUE),
      entry$manifest_source_sha256)) stop(
    "The source manifest bytes differ from the locked pin: ", entry$package,
    call. = FALSE)
}

r_binary <- file.path(R.home("bin"), "R")
install_one <- function(source, name) {
  log <- file.path(dirname(receipt_path), paste0(name, ".install.log"))
  exit <- file.path(dirname(receipt_path), paste0(name, ".install.exit"))
  status <- suppressWarnings(system2(r_binary, c("CMD", "INSTALL",
    paste0("--library=", shQuote(library_path)), shQuote(source)),
    stdout = log, stderr = log,
    env = paste0("R_LIBS=", shQuote(library_path))))
  temporary <- paste0(exit, ".tmp.", Sys.getpid())
  writeLines(as.character(as.integer(status)), temporary)
  if (!file.rename(temporary, exit)) stop("Could not publish install exit: ", name)
  if (!identical(as.integer(status), 0L)) stop("Install failed for ", name,
    "; see ", log, call. = FALSE)
  cat("INSTALL_OK ", name, "\n", sep = "")
}
install_one(core_source, "scworkbench")
for (entry in lock$packs) install_one(file.path(pack_root, entry$package),
  entry$package)

.libPaths(c(library_path, .libPaths()))
base::library(scworkbench, lib.loc = library_path)
sys.source(system.file("standard_profile", "activate.R", package = "scworkbench",
  lib.loc = library_path, mustWork = TRUE), envir = .GlobalEnv)
installed_lock <- system.file("standard_profile", "profile.json",
  package = "scworkbench", lib.loc = library_path, mustWork = TRUE)
if (!identical(digest::digest(profile_path, algo = "sha256", file = TRUE),
    digest::digest(installed_lock, algo = "sha256", file = TRUE))) stop(
  "Installed profile lock differs from the verified core source.", call. = FALSE)

installed <- lapply(lock$packs, function(entry) {
  identity <- scworkbench::wb_operation_pack_validate(entry$package,
    lib.loc = library_path)$identity
  .scwb_profile_check_identity(identity, entry)
  c(entry, list(pack_sha256 = identity$pack_sha256))
})
receipt <- list(
  schema_version = "scworkbench.standard_profile.installation_receipt.v1",
  profile_sha256 = digest::digest(installed_lock, algo = "sha256", file = TRUE),
  core_source_commit = core_commit,
  core_version = as.character(utils::packageVersion("scworkbench")),
  core_installed_tree_sha256 = .scwb_profile_tree_sha256(
    find.package("scworkbench", lib.loc = library_path)),
  pybench_source_commit = lock$pybench_source_commit,
  packs = installed)
.scwb_profile_preflight(lock, receipt, lib.loc = library_path)
if (nrow(scworkbench::wb_operation_packs())) stop(
  "Installation unexpectedly activated a pack.", call. = FALSE)
temporary <- paste0(receipt_path, ".tmp.", Sys.getpid())
jsonlite::write_json(receipt, temporary, pretty = TRUE, auto_unbox = TRUE)
if (!file.rename(temporary, receipt_path)) stop(
  "Could not atomically publish installation receipt.", call. = FALSE)
cat("STANDARD_PROFILE_INSTALL_OK core=", core_commit,
  " packs=7 activated=0 receipt=", receipt_path, "\n", sep = "")
