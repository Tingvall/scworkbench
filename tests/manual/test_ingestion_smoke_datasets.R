# Manual smoke tests for canonical downloaded ingestion examples.
#
# Run from the package root after loading scworkbench, for example:
# Rscript -e 'devtools::load_all(".", quiet=TRUE); source("tests/manual/test_ingestion_smoke_datasets.R"); test_ingestion_smoke_datasets()'

test_ingestion_smoke_datasets <- function(root = Sys.getenv("SCWORKBENCH_INGESTION_SMOKE_ROOT", unset = ""),
                                          out_root = tempfile("scworkbench_ingestion_smoke_")) {
  if (!nzchar(root)) {
    stop("Set SCWORKBENCH_INGESTION_SMOKE_ROOT or pass root= to run manual ingestion smoke tests.", call. = FALSE)
  }
  dir.create(out_root, recursive = TRUE, showWarnings = FALSE)

  results <- list()

  sce_path <- file.path(root, "reprocessed_allen_tophat_counts_sce.rds")
  if (file.exists(sce_path) &&
      requireNamespace("SingleCellExperiment", quietly = TRUE) &&
      requireNamespace("SummarizedExperiment", quietly = TRUE) &&
      requireNamespace("BPCells", quietly = TRUE)) {
    sce_bundle <- file.path(out_root, "allen_sce_bundle")
    b <- wb_bundle_from_sce(sce_path, bundle_dir = sce_bundle, overwrite = TRUE, created_by = "manual_smoke")
    on.exit(try(wb_close_bundle(b), silent = TRUE), add = TRUE)
    mats <- wb_matrices(b)
    meta <- wb_meta(b)
    stopifnot("tophat_counts" %in% mats$matrix_id)
    mi <- mats[mats$matrix_id == "tophat_counts", , drop = FALSE]
    stopifnot(mi$n_cells[[1]] == 379L)
    stopifnot(mi$n_features[[1]] == 20816L)
    stopifnot(nrow(meta) == 379L)
    results$sce <- list(bundle = sce_bundle, matrices = mats, n_meta_rows = nrow(meta), cell_sets = wb_cell_sets(b))
  } else {
    results$sce <- "skipped: dataset or required packages missing"
  }

  h5ad_path <- file.path(root, "pbmc3k_processed_scanpy.h5ad")
  if (file.exists(h5ad_path) &&
      requireNamespace("zellkonverter", quietly = TRUE) &&
      requireNamespace("SingleCellExperiment", quietly = TRUE) &&
      requireNamespace("SummarizedExperiment", quietly = TRUE) &&
      requireNamespace("BPCells", quietly = TRUE)) {
    h5ad_bundle <- file.path(out_root, "pbmc3k_h5ad_bundle")
    b <- wb_bundle_from_h5ad(h5ad_path, bundle_dir = h5ad_bundle, overwrite = TRUE, created_by = "manual_smoke")
    on.exit(try(wb_close_bundle(b), silent = TRUE), add = TRUE)
    mats <- wb_matrices(b)
    meta <- wb_meta(b)
    stopifnot(nrow(mats) >= 1L)
    stopifnot(any(mats$n_cells == 2638L))
    stopifnot(any(mats$n_features == 1838L))
    stopifnot(nrow(meta) == 2638L)
    results$h5ad <- list(bundle = h5ad_bundle, matrices = mats, spaces = wb_spaces(b), cell_sets = wb_cell_sets(b))
  } else {
    results$h5ad <- "skipped: dataset or required packages missing"
  }

  results
}
