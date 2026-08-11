test_unambiguous_manifest_feature_counts_contract <- function() {
  if (!requireNamespace("BPCells", quietly = TRUE)) {
    return(contract_test_skip("BPCells is not installed."))
  }

  roots <- character()
  open_bundles <- list()
  old_hook <- getOption("scworkbench.manifest_test_hook")
  on.exit({
    options(scworkbench.manifest_test_hook = old_hook)
    for (bundle in open_bundles) try(wb_close_bundle(bundle), silent = TRUE)
    for (root in roots) unlink(root, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  sparse_fixture <- function(feature_ids, cell_ids = c("cell_1", "cell_2")) {
    Matrix::sparseMatrix(
      i = 1L, j = 1L, x = 1,
      dims = c(length(feature_ids), length(cell_ids)),
      dimnames = list(feature_ids, cell_ids)
    )
  }
  new_bundle <- function(prefix) {
    root <- tempfile(prefix)
    roots <<- c(roots, root)
    bundle <- wb_init_bundle(root, overwrite = TRUE)
    wb_define_cells(bundle, c("cell_1", "cell_2"), dataset_id = "dataset_1")
    open_bundles[[length(open_bundles) + 1L]] <<- bundle
    bundle
  }
  assert_feature_contract <- function(bundle, expected) {
    manifest <- wb_manifest(bundle)
    reconstructed <- wb_manifest(bundle, view = "reconstructed")
    expected <- stats::setNames(as.list(as.integer(expected)), names(expected))
    stopifnot(
      identical(as.character(manifest$scworkbench_manifest_version), "2.3.0"),
      is.null(manifest$counts$n_features),
      identical(as.integer(manifest$counts$feature_registry_records),
                as.integer(sum(unlist(expected, use.names = FALSE)))),
      identical(manifest$counts$feature_counts_by_matrix, expected),
      identical(reconstructed$counts$feature_counts_by_matrix, expected),
      identical(as.character(manifest$counts$bundle_unique_feature_count$status),
                "not_applicable"),
      nzchar(as.character(manifest$counts$bundle_unique_feature_count$reason)),
      isTRUE(reconstructed$publication$durable_registry_agreement)
    )
    invisible(manifest)
  }

  # One biological feature universe has one matrix-scoped registry record per
  # feature, without a generic n_features alias.
  genes <- sprintf("gene_%05d", seq_len(12292L))
  one <- new_bundle("scwb_manifest_one_matrix_")
  wb_attach_matrix(one, "RNA_counts", sparse_fixture(genes), feature_type = "gene")
  assert_feature_contract(one, c(RNA_counts = 12292L))

  # Identical identifiers in two matrices remain two explicit matrix-scoped
  # registries. The 24,584 records are never presented as biological features.
  shared <- new_bundle("scwb_manifest_shared_universe_")
  wb_attach_matrix(shared, "RNA_counts", sparse_fixture(genes), feature_type = "gene")
  wb_attach_matrix(shared, "RNA_log", sparse_fixture(genes), layer = "data", feature_type = "gene")
  shared_manifest <- assert_feature_contract(
    shared, c(RNA_counts = 12292L, RNA_log = 12292L)
  )
  overview <- wb_bundle_overview(shared, validate = FALSE)
  stopifnot(
    is.null(overview$counts$n_features),
    is.null(overview$manifest$counts$n_features),
    identical(as.integer(overview$counts$feature_registry_records), 24584L),
    identical(overview$counts$feature_counts_by_matrix,
              shared_manifest$counts$feature_counts_by_matrix),
    identical(as.character(overview$counts$bundle_unique_feature_count$status),
              "not_applicable")
  )

  # A failed publication cannot expose partial JSON, and publication remains
  # inside the active assembly bundle's exclusive writer scope.
  manifest_path <- file.path(shared$dir, "manifest.json")
  before_bytes <- readBin(manifest_path, "raw", n = file.info(manifest_path)$size)
  stopifnot(isTRUE(scworkbench:::.wb_writer_lock_held(shared$dir)))
  options(scworkbench.manifest_test_hook = function(event, ...) {
    if (identical(event, "before_publish")) stop("forced 2.3 publication interruption", call. = FALSE)
  })
  interrupted <- try(wb_attach_metadata(
    shared,
    data.frame(cell_id = c("cell_1", "cell_2"), manifest_probe = c(1L, 2L)),
    source = "manifest_feature_count_contract"
  ), silent = TRUE)
  stopifnot(
    inherits(interrupted, "try-error"),
    grepl("forced 2.3 publication interruption", as.character(interrupted), fixed = TRUE),
    identical(readBin(manifest_path, "raw", n = file.info(manifest_path)$size), before_bytes),
    !isTRUE(wb_manifest(shared, "reconstructed")$publication$durable_registry_agreement)
  )
  options(scworkbench.manifest_test_hook = NULL)
  scworkbench:::.wb_with_mutation_context(
    shared, route = "ingestion", code = wb_refresh_manifest(shared)
  )
  assert_feature_contract(shared, c(RNA_counts = 12292L, RNA_log = 12292L))

  # Partial overlap cannot be silently deduplicated across matrix scopes.
  partial <- new_bundle("scwb_manifest_partial_overlap_")
  wb_attach_matrix(partial, "matrix_a", sparse_fixture(sprintf("gene_%05d", 1:8)), feature_type = "gene")
  wb_attach_matrix(partial, "matrix_b", sparse_fixture(sprintf("gene_%05d", 5:12)), feature_type = "gene")
  assert_feature_contract(partial, c(matrix_a = 8L, matrix_b = 8L))

  # Equal spelling across modality namespaces is not evidence of identity.
  modalities <- new_bundle("scwb_manifest_modalities_")
  shared_spellings <- paste0("feature_", seq_len(6L))
  wb_attach_matrix(modalities, "ADT_counts", sparse_fixture(shared_spellings), feature_type = "protein")
  wb_attach_matrix(modalities, "RNA_counts", sparse_fixture(shared_spellings), feature_type = "gene")
  modality_manifest <- assert_feature_contract(
    modalities, c(ADT_counts = 6L, RNA_counts = 6L)
  )
  stopifnot(identical(as.integer(modality_manifest$counts$feature_registry_records), 12L))

  # Schema-aware validation reports both removal of the ambiguous alias and
  # corruption of the per-matrix registry binding.
  correct_manifest <- wb_manifest(modalities)
  modality_root <- modalities$dir
  wb_close_bundle(modalities)
  open_bundles[[4L]] <- NULL
  corrupt_manifest <- correct_manifest
  corrupt_manifest$counts$n_features <- 12L
  corrupt_manifest$counts$feature_counts_by_matrix$RNA_counts <- 7L
  jsonlite::write_json(corrupt_manifest, file.path(modality_root, "manifest.json"),
                       pretty = TRUE, auto_unbox = TRUE, null = "null", na = "null")
  corrupt_report <- wb_bundle_validation_report(modality_root, "structural")
  expected_corruption_codes <- c(
    "MANIFEST_FEATURE_COUNT_SCHEMA_INVALID",
    "MANIFEST_FEATURE_COUNTS_BY_MATRIX_MISMATCH"
  )
  observed_corruption_codes <- as.character(corrupt_report$diagnostics$code)
  if (!all(expected_corruption_codes %in% observed_corruption_codes)) {
    stop("Missing feature-count corruption diagnostics; observed: ",
         paste(observed_corruption_codes, collapse = ", "), call. = FALSE)
  }
  jsonlite::write_json(correct_manifest, file.path(modality_root, "manifest.json"),
                       pretty = TRUE, auto_unbox = TRUE, null = "null", na = "null")
  stopifnot(isTRUE(wb_bundle_validation_report(modality_root, "structural")$ok))

  # Finalization, relocation, immutable reopen, reconstruction, and recipient
  # validation preserve the same explicit counts.
  stopifnot(isTRUE(wb_finalize_recipient_bundle(shared)$ready))
  wb_close_bundle(shared)
  open_bundles[[2L]] <- NULL
  relocated <- tempfile("scwb_manifest_relocated_")
  roots <- c(roots, relocated)
  fs::dir_copy(dirname(manifest_path), relocated)
  recipient <- wb_open_bundle(relocated, read_only = TRUE)
  open_bundles[[length(open_bundles) + 1L]] <- recipient
  assert_feature_contract(recipient, c(RNA_counts = 12292L, RNA_log = 12292L))
  recipient_report <- wb_bundle_validation_report(relocated, "recipient")
  stopifnot(
    isTRUE(recipient_report$ok),
    !any(grepl("MANIFEST_.*FEATURE", as.character(recipient_report$diagnostics$code)))
  )

  TRUE
}
