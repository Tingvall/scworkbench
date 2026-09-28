args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 5L) stop(paste(
  "usage: profile_lifecycle_process.R MODE LIB RECEIPT FIXTURE_ROOT PROFILE_SOURCE"),
  call. = FALSE)
mode <- args[[1L]]
library_path <- normalizePath(args[[2L]], winslash = "/", mustWork = TRUE)
receipt_path <- normalizePath(args[[3L]], winslash = "/", mustWork = TRUE)
fixture_root <- normalizePath(args[[4L]], winslash = "/", mustWork = FALSE)
.libPaths(c(library_path, .libPaths()))
base::library(scworkbench, lib.loc = library_path)
sys.source(args[[5L]], envir = globalenv())
bundle_root <- file.path(fixture_root, "final.bundle")
exact_root <- file.path(fixture_root, "exact_source", "final.bundle")
missing_root <- file.path(fixture_root, "missing_source", "final.bundle")

if (identical(mode, "create_exact_replay")) {
  if (dir.exists(fixture_root)) stop("Lifecycle fixture root already exists")
  dir.create(fixture_root, recursive = TRUE)
  bundle <- wb_init_bundle(bundle_root, overwrite = TRUE)
  wb_define_cells(bundle, c("cell_1-A", "cell_2-B", "cell_3-A"))
  wb_close_bundle(bundle)
  for (parent in c(dirname(exact_root), dirname(missing_root))) {
    dir.create(parent, recursive = TRUE)
    if (!isTRUE(file.copy(bundle_root, parent, recursive = TRUE))) stop(
      "Could not copy the source-only replay bundle")
  }

  stopifnot(nrow(wb_operation_packs()) == 0L)
  profile <- scwb_standard_profile_activate(receipt_path, lib.loc = library_path)
  stopifnot(nrow(profile$packs) == 7L, length(wb_list_ops()) == 61L)
  bundle <- wb_open_bundle(bundle_root)
  executed <- wb_session_run_op(wb_session_new(), bundle,
    "scwbrna::cell_suffix_label", inputs = list(cell_set = "all",
      min_cells = 1L, sep = "-", default_label = "other"))
  rna <- wb_operation_pack_inspect("scwbrna")$identity
  stopifnot(identical(executed$run$operation_pack$pack_sha256,
    rna$pack_sha256))
  promoted <- wb_session_promote_current(bundle, executed$session,
    outputs = c("labels", "label_table"), name_prefix = "profile",
    created_by = "phase8-standard-profile")
  stopifnot(nrow(promoted$promoted) == 2L,
    isTRUE(wb_finalize_recipient_bundle(bundle)$ready))
  wb_close_bundle(bundle)

  final <- wb_open_bundle(bundle_root, read_only = TRUE)
  exact <- wb_open_bundle(exact_root)
  replay <- wb_prov_validate_replay(final, mode = "symbolic",
    profile = "strict", strict = TRUE, destination_bundle = exact)
  stopifnot(isTRUE(replay$summary$valid), replay$summary$n_runs == 1L,
    all(replay$per_run$status == "ok"), all(replay$per_output$output_match))
  wb_close_bundle(exact)
  wb_close_bundle(final)
  cat("PROFILE_EXACT_REPLAY_OK promoted=2 runs=1 pack_sha256=",
    rna$pack_sha256, "\n", sep = "")
} else if (identical(mode, "pack_free_inspect_missing_replay")) {
  stopifnot(nrow(wb_operation_packs()) == 0L,
    identical(length(wb_list_ops()), 5L))
  stopifnot(isTRUE(wb_validate_bundle(bundle_root, read_only = TRUE)))
  final <- wb_open_bundle(bundle_root, read_only = TRUE)
  artifacts <- wb_art_list(final)
  stopifnot(nrow(artifacts) == 2L,
    all(vapply(artifacts$artifact_id, function(id)
      inherits(wb_art_load(final, id), "wb_primitive"), logical(1))))
  dag <- wb_prov_bundle_dag(final)
  stopifnot(any(as.character(dag$nodes$op_name) ==
    "scwbrna::cell_suffix_label", na.rm = TRUE))
  missing <- wb_open_bundle(missing_root)
  error <- tryCatch(wb_prov_validate_replay(final, mode = "symbolic",
    profile = "strict", strict = TRUE, destination_bundle = missing),
    error = identity)
  stopifnot(inherits(error, "error"),
    grepl("requires its exact compatible operation pack",
      conditionMessage(error), fixed = TRUE),
    nrow(wb_operation_packs()) == 0L)
  wb_close_bundle(missing)
  wb_close_bundle(final)
  cat("PROFILE_PACK_FREE_INSPECTION_OK artifacts=2; MISSING_PACK_REPLAY_REJECTED\n")
} else stop("Unknown lifecycle mode: ", mode)
