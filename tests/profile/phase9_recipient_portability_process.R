args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 6L) stop(paste(
  "usage: phase9_recipient_portability_process.R",
  "MODE LIB RECEIPT FINAL_BUNDLE SOURCE_ONLY_BUNDLE WORK_ROOT"),
  call. = FALSE)
mode <- args[[1L]]
library_path <- normalizePath(args[[2L]], winslash = "/", mustWork = TRUE)
receipt_path <- args[[3L]]
final_path <- normalizePath(args[[4L]], winslash = "/", mustWork = TRUE)
source_path <- if (identical(args[[5L]], "-")) NULL else
  normalizePath(args[[5L]], winslash = "/", mustWork = TRUE)
work_root <- normalizePath(args[[6L]], winslash = "/", mustWork = FALSE)
if (dir.exists(work_root)) stop("Portability work root already exists")
dir.create(work_root, recursive = TRUE)
.libPaths(c(library_path, .libPaths()))
base::library(scworkbench, lib.loc = library_path)

copy_bundle <- function(source, parent) {
  dir.create(parent, recursive = TRUE)
  if (!isTRUE(file.copy(source, parent, recursive = TRUE)))
    stop("Could not copy bundle ", source)
  file.path(parent, basename(source))
}
fingerprint <- function(path) {
  entries <- list.files(path, recursive = TRUE, full.names = TRUE,
    all.files = TRUE, no.. = TRUE)
  files <- sort(entries[!dir.exists(entries)], method = "radix")
  stats::setNames(vapply(files, function(file) digest::digest(file = file,
    algo = "sha256"), character(1)), substring(files, nchar(path) + 2L))
}

if (identical(mode, "pack_free")) {
  stopifnot(nrow(wb_operation_packs()) == 0L, length(wb_list_ops()) == 5L)
  before <- fingerprint(final_path)
  relocated <- copy_bundle(final_path, file.path(work_root, "relocated"))
  stopifnot(identical(before, fingerprint(relocated)),
    isTRUE(wb_validate_bundle(relocated, read_only = TRUE)))
  bundle <- wb_open_bundle(relocated, read_only = TRUE)
  artifacts <- wb_art_list(bundle)
  stopifnot(nrow(artifacts) >= 3L,
    all(vapply(artifacts$artifact_id, function(id)
      inherits(wb_art_load(bundle, id), "wb_primitive"), logical(1))),
    all(c("pca") %in% wb_spaces(bundle)$space_id),
    any(grepl("scwbtrajectory::space_path_define",
      wb_prov_bundle_dag(bundle)$nodes$op_name, fixed = TRUE)))
  wb_close_bundle(bundle)
  stopifnot(identical(before, fingerprint(relocated)),
    identical(before, fingerprint(final_path)))
  cat("PHASE9_PACK_FREE_RECIPIENT_OK artifacts=", nrow(artifacts),
    " relocated_bytes_identical=TRUE\n", sep = "")
} else if (mode %in% c("same_install", "second_install", "transferred_install")) {
  if (!identical(Sys.getenv("PYTHONDONTWRITEBYTECODE"), "1")) stop(
    "The frozen CPU interpreter must disable installed-pack bytecode writes")
  if (is.null(source_path)) stop("Replay requires a source-only bundle")
  sys.source(system.file("standard_profile", "activate.R",
    package = "scworkbench", lib.loc = library_path, mustWork = TRUE),
    envir = globalenv())
  activation <- tryCatch(scwb_standard_profile_activate(receipt_path,
    lib.loc = library_path), error = identity)
  if (inherits(activation, "error")) {
    if (!identical(mode, "transferred_install")) stop(activation)
    cat("PHASE9_TRANSFER_UNSUPPORTED activation=",
      conditionMessage(activation), "\n", sep = "")
  } else {
    stopifnot(nrow(activation$packs) == 7L, length(wb_list_ops()) == 61L)
    target <- copy_bundle(source_path, file.path(work_root, "replay_source"))
    original <- wb_open_bundle(final_path, read_only = TRUE)
    destination <- wb_open_bundle(target)
    dag <- wb_prov_bundle_dag(original)
    run_rows <- which(as.character(dag$nodes$op_name) ==
      "scwbrna::cell_suffix_label" & !is.na(dag$nodes$run_id))
    stopifnot(length(run_rows) >= 1L)
    run_id <- as.character(dag$nodes$run_id[run_rows])[[1L]]
    contract <- wb_prov_run_replay_inputs(original, run_id)
    compatible <- isTRUE(contract$diagnostics$compatible)
    replay <- tryCatch(wb_prov_validate_replay(original, mode = "symbolic",
      profile = "strict", strict = TRUE, destination_bundle = destination),
      error = identity)
    wb_close_bundle(destination)
    wb_close_bundle(original)
    if (identical(mode, "second_install")) {
      issue_codes <- vapply(contract$diagnostics$issues, `[[`, character(1),
        "code")
      stopifnot(!compatible,
        "OPERATION_CONTRACT_INCOMPATIBLE" %in% issue_codes)
      cat("PHASE9_SECOND_INSTALL_CONTRACT_REJECTED",
        " numerical_strict_replay_valid=",
        !inherits(replay, "error") && isTRUE(replay$summary$valid),
        " pack_instance_differs=TRUE\n", sep = "")
    } else {
      if (inherits(replay, "error")) stop(replay)
      stopifnot(compatible, isTRUE(replay$summary$valid),
        replay$summary$n_runs >= 1L,
        all(replay$per_run$status == "ok"),
        all(replay$per_output$output_match))
      cat(if (identical(mode, "same_install"))
        "PHASE9_SAME_INSTALL_STRICT_REPLAY_OK" else
        "PHASE9_TRANSFER_STRICT_REPLAY_OK", " runs=",
        replay$summary$n_runs, "\n", sep = "")
    }
  }
} else stop("Unknown portability mode: ", mode)
