args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 5L) stop(paste(
  "usage: Rscript tests/profile/run_standard_profile_matrix.R",
  "CORE_SOURCE PYBENCH_SOURCE PACK_ROOT LATENT_PYTHON EVIDENCE_DIR"), call. = FALSE)
core_source <- normalizePath(args[[1L]], winslash = "/", mustWork = TRUE)
pybench_source <- normalizePath(args[[2L]], winslash = "/", mustWork = TRUE)
pack_root <- normalizePath(args[[3L]], winslash = "/", mustWork = TRUE)
if (!file.exists(args[[4L]]) || dir.exists(args[[4L]])) stop(
  "LATENT_PYTHON must name an existing interpreter", call. = FALSE)
latent_python <- file.path(normalizePath(dirname(args[[4L]]), winslash = "/",
  mustWork = TRUE), basename(args[[4L]]))
evidence <- normalizePath(args[[5L]], winslash = "/", mustWork = FALSE)
dir.create(evidence, recursive = TRUE, showWarnings = FALSE)
evidence <- normalizePath(evidence, winslash = "/", mustWork = TRUE)

expected <- c(
  scwbStatistics = "00d1ba6a63d853b146916243bb8035d32528d575",
  scwbGenePrograms = "1bc3ad43c920622ab1e45df4bd8bd968335e912b",
  scwbRNA = "5ceb7a3fd45ed56154131498a067eb1f5982c668",
  scwbRepresentation = "e3bb38760bcdda426a83bfbd7350b6fb16890e94",
  scwbTrajectory = "2bb8494bc89b02cc29418bb114ac70cb1b791eae",
  scwbLatent = "fe83554d4904861e76b7dd616e34c84fd23d3a16",
  scwbATAC = "0d0b2c0728e0db543442c1783fdc9398ee309eb5")
for (package in names(expected)) {
  path <- file.path(pack_root, package)
  head <- system2("git", c("-C", shQuote(path), "rev-parse", "HEAD"),
    stdout = TRUE, stderr = TRUE)
  if (!identical(head, unname(expected[[package]]))) stop(
    package, " is not at its locked source commit", call. = FALSE)
  dirty <- system2("git", c("-C", shQuote(path), "status", "--porcelain"),
    stdout = TRUE, stderr = TRUE)
  if (length(dirty)) stop(package, " source worktree is dirty", call. = FALSE)
}

libraries <- file.path(evidence, "libraries")
dir.create(libraries, recursive = TRUE, showWarnings = FALSE)
core_library <- file.path(libraries, "core")
full_library <- file.path(libraries, "standard")
receipt_path <- file.path(evidence, "standard_profile_installation_receipt.json")
dir.create(core_library, recursive = TRUE, showWarnings = FALSE)
dir.create(full_library, recursive = TRUE, showWarnings = FALSE)
r_binary <- file.path(R.home("bin"), "R")
rscript_binary <- file.path(R.home("bin"), "Rscript")
process_script <- file.path(core_source, "tests", "profile", "profile_process.R")
profile_source <- file.path(core_source, "inst", "standard_profile", "activate.R")

run_gate <- function(label, command, arguments, environment = character()) {
  log <- file.path(evidence, paste0(label, ".log"))
  exit <- file.path(evidence, paste0(label, ".exit"))
  status <- suppressWarnings(system2(command, arguments, stdout = log, stderr = log,
    env = environment))
  if (is.null(status)) status <- 0L
  temporary <- paste0(exit, ".tmp.", Sys.getpid())
  writeLines(as.character(as.integer(status)), temporary)
  if (!file.rename(temporary, exit)) stop("could not publish numeric exit sidecar: ", label)
  cat(label, " exit=", status, " log=", log, "\n", sep = "")
  if (!identical(as.integer(status), 0L)) {
    stop("profile matrix gate failed: ", label, "\n",
      paste(tail(readLines(log, warn = FALSE), 30L), collapse = "\n"), call. = FALSE)
  }
  invisible(log)
}

install <- function(label, source, library, r_libs = library) {
  run_gate(label, r_binary, c("CMD", "INSTALL",
    paste0("--library=", shQuote(library)), shQuote(source)),
    paste0("R_LIBS=", shQuote(r_libs)))
}
process <- function(label, mode, library) {
  installed_core <- if (mode %in% c("missing_pack", "profile", "active_collision"))
    library else core_library
  run_gate(label, rscript_binary, c("--vanilla", shQuote(process_script),
    shQuote(mode), shQuote(library), shQuote(installed_core), shQuote(profile_source),
    shQuote(receipt_path)),
    c(paste0("R_LIBS=", shQuote(paste(c(library, installed_core),
      collapse = .Platform$path.sep))),
      paste0("SCWB_LATENT_PYTHON=", shQuote(latent_python))))
}

install("install_core", core_source, core_library)
process("core_only", "core_only", core_library)
for (package in names(expected)) {
  library <- file.path(libraries, package)
  dir.create(library, recursive = TRUE, showWarnings = FALSE)
  install(paste0("install_", package), file.path(pack_root, package),
    library, core_library)
  process(paste0("activate_", package), paste0("pack:", package), library)
}
run_gate("standard_installer", rscript_binary, c("--vanilla",
  shQuote(file.path(core_source, "inst", "standard_profile", "install.R")),
  shQuote(core_source), shQuote(pybench_source), shQuote(pack_root),
  shQuote(latent_python), shQuote(full_library), shQuote(receipt_path)))
process("missing_pack", "missing_pack", full_library)
process("standard_profile", "profile", full_library)
install("install_collision_fixture", file.path(core_source, "tests", "fixtures",
  "operation-pack-v2-reference"), full_library, core_library)
process("active_collision", "active_collision", full_library)
cat("STANDARD_PROFILE_MATRIX_PASS packs=7 operations=61 individual_activations=7",
    " negatives=missing,wrong_pin,lock_collision,publication_rollback,active_collision\n")
