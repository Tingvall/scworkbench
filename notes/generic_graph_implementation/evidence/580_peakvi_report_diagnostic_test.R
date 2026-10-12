test_phase6_peakvi_no_pack_catalog_and_historical_inspection_contract <- function() {
  fingerprint <- function(root) {
    paths <- list.files(root, recursive = TRUE, full.names = TRUE,
      all.files = TRUE, no.. = TRUE)
    paths <- sort(paths[file.exists(paths) & !dir.exists(paths)],
      method = "radix")
    relative <- substring(paths, nchar(root) + 2L)
    stats::setNames(vapply(paths, .wb_prov_sha256_file, character(1)),
      relative)
  }
  names <- wb_list_ops()
  stopifnot(!any(c("peakvi_fit", "peakvi_project") %in% names),
    !exists("wb_op_peakvi_fit", envir = asNamespace("scworkbench"),
      inherits = FALSE),
    !exists("wb_op_peakvi_project", envir = asNamespace("scworkbench"),
      inherits = FALSE))
  for (name in c("peakvi_fit", "peakvi_project")) {
    rejected <- tryCatch(wb_op_interface(name), error = identity)
    stopifnot(inherits(rejected, "error"),
      grepl("Unknown op", conditionMessage(rejected), fixed = TRUE))
  }

  parent <- tempfile("scwb_peakvi_historical_")
  dir.create(parent)
  on.exit(unlink(parent, recursive = TRUE, force = TRUE), add = TRUE)
  archive <- file.path("tests", "fixtures",
    "phase6_peakvi_old_core_historical.bundle.tar.gz")
  stopifnot(identical(.wb_prov_sha256_file(archive),
    "4b7ab3996986cd69c3040c257332a9c19ba0e3245e772f5a1ed13508a6fa9c26"))
  utils::untar(archive, exdir = parent)
  root <- file.path(parent, "historical.bundle")
  before <- fingerprint(root)
  refused <- tryCatch(wb_open_bundle(root, read_only = TRUE),
    error = base::identity)
  stopifnot(inherits(refused, "error"),
    grepl("BUNDLE_SCHEMA_UPGRADE_REQUIRED", conditionMessage(refused),
      fixed = TRUE), identical(before, fingerprint(root)))
  # Migrate the disposable extracted copy, never the frozen source archive.
  writable <- wb_open_bundle(root)
  wb_migrate_bundle(writable)
  wb_close_bundle(writable)
  upgraded <- fingerprint(root)
  b <- wb_open_bundle(root, read_only = TRUE)
  graph <- wb_prov_bundle_dag(b, include_snapshots = TRUE)
  artifacts <- wb_art_list(b)
  stopifnot(nrow(artifacts) == 1L,
    identical(as.character(artifacts$source_op[[1L]]), "peakvi_fit"))
  loaded <- wb_art_load(b, as.character(artifacts$artifact_id[[1L]]),
    expected_kind = "model_ref")
  stopifnot(identical(loaded$engine, "peakvi"),
    "peakvi_fit" %in% as.character(graph$nodes$op_name),
    {report <- wb_bundle_validation_report(root, level = "recipient"); print(report); TRUE})
  wb_close_bundle(b)
  stopifnot(identical(upgraded, fingerprint(root)))
  TRUE
}

test_phase6_latent_union_no_pack_catalog_contract <- function() {
  stopifnot(!"model_bound_latent_union" %in% wb_list_ops(),
    !"scwblatent::model_bound_latent_union" %in% wb_list_ops(),
    !exists("wb_op_model_bound_latent_union",
      envir = asNamespace("scworkbench"), inherits = FALSE),
    inherits(tryCatch(wb_op_interface("model_bound_latent_union"),
      error = identity), "error"))
  TRUE
}
