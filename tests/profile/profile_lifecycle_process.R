args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 6L) stop(paste(
  "usage: profile_lifecycle_process.R MODE LIB RECEIPT FIXTURE_ROOT PROFILE_SOURCE CORE_SOURCE"),
  call. = FALSE)
mode <- args[[1L]]
library_path <- normalizePath(args[[2L]], winslash = "/", mustWork = TRUE)
receipt_path <- normalizePath(args[[3L]], winslash = "/", mustWork = TRUE)
fixture_root <- normalizePath(args[[4L]], winslash = "/", mustWork = FALSE)
.libPaths(c(library_path, .libPaths()))
base::library(scworkbench, lib.loc = library_path)
sys.source(args[[5L]], envir = globalenv())
core_source <- normalizePath(args[[6L]], winslash = "/", mustWork = TRUE)
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
} else if (identical(mode, "archived_v9_disposable_upgrade")) {
  stopifnot(nrow(wb_operation_packs()) == 0L)
  archive <- file.path(core_source, "tests", "fixtures",
    "phase5_s2_retained_old_core_bundle.tar.gz")
  expected_archive <- "e6b2a277b2ff614d44f04ab8bbb80fbd3339f82886df8b0168d437733d67051b"
  archive_before <- digest::digest(archive, algo = "sha256", file = TRUE)
  stopifnot(identical(archive_before, expected_archive))
  copy_parent <- file.path(fixture_root, "archived_v9_copy")
  dir.create(copy_parent, recursive = TRUE)
  utils::untar(archive, exdir = copy_parent)
  copy_root <- file.path(copy_parent, "forge1-s2-retained-bundle")
  db_path <- file.path(copy_root, "db", "app.sqlite")
  before <- digest::digest(db_path, algo = "sha256", file = TRUE)
  refused <- tryCatch(wb_open_bundle(copy_root, read_only = TRUE),
    error = identity)
  stopifnot(inherits(refused, "error"),
    grepl("BUNDLE_SCHEMA_UPGRADE_REQUIRED", conditionMessage(refused),
      fixed = TRUE),
    identical(before, digest::digest(db_path, algo = "sha256", file = TRUE)))
  writable <- wb_open_bundle(copy_root)
  wb_migrate_bundle(writable)
  wb_close_bundle(writable)
  migrated <- digest::digest(db_path, algo = "sha256", file = TRUE)
  historical <- wb_open_bundle(copy_root, read_only = TRUE)
  artifacts <- wb_art_list(historical)
  stopifnot(nrow(artifacts) > 0L,
    any(as.character(artifacts$source_op) == "trajectory_de"))
  de_id <- as.character(artifacts$artifact_id[
    as.character(artifacts$source_op) == "trajectory_de"])[[1L]]
  stopifnot(inherits(wb_art_load(historical, de_id), "wb_primitive"))
  wb_close_bundle(historical)
  validated <- wb_validate_bundle(copy_root, read_only = TRUE)
  stopifnot(isTRUE(validated),
    identical(migrated, digest::digest(db_path, algo = "sha256", file = TRUE)),
    identical(archive_before, digest::digest(archive, algo = "sha256", file = TRUE)),
    nrow(wb_operation_packs()) == 0L)
  cat("PROFILE_ARCHIVED_V9_COPY_OK migrated_readonly_valid=TRUE archive_unchanged=TRUE artifacts=",
    nrow(artifacts), "\n", sep = "")
} else stop("Unknown lifecycle mode: ", mode)
