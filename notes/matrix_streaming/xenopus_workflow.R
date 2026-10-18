args <- commandArgs(TRUE)
stopifnot(length(args) == 3L)
mode <- args[1]; chamber <- normalizePath(args[2], mustWork = TRUE)
.libPaths(c(args[3], .libPaths()))
suppressPackageStartupMessages({library(scworkbench); library(SingleCellExperiment)})
source_path <- "/home/dirk/Projects/.scworkbench-experiments/rc38_axolotl_definitive/source/aztekin_tail_2019_sce.rds"
source_sha <- "7dfefc974d9b38ea3513c1e181f119f2c4cbde5fcf603298f71953bff7b85280"
stopifnot(identical(digest::digest(file = source_path, algo = "sha256"), source_sha))
bundle_dir <- file.path(chamber, "xenopus.bundle")
metrics <- new.env(parent = emptyenv()); metrics$rows <- list()
record <- function(phase, seconds) {
  row <- data.frame(phase = phase, elapsed = seconds[["elapsed"]],
    user = seconds[["user.self"]], system = seconds[["sys.self"]])
  metrics$rows[[length(metrics$rows) + 1L]] <- row
  print(row); flush.console()
  write.csv(do.call(rbind, metrics$rows), file.path(chamber, paste0(mode, "_timings.csv")), row.names = FALSE)
}
measure <- function(phase, code) {
  start <- proc.time(); value <- force(code); record(phase, proc.time() - start); value
}
cat("MODE", mode, "UTC", format(Sys.time(), tz = "UTC"), "\n")
print(system("df -T . /tmp", intern = TRUE)); print(system("nproc", intern = TRUE))
cat("DENSE_GUARD_UNCHANGED", getOption("scworkbench.max_dense_materialize_mb", 256), "\n")
sce <- measure("read_source_rds", readRDS(source_path))
counts <- assay(sce, "counts")
cat("SOURCE_DIM", dim(counts), "CLASS", class(counts), "TYPE", typeof(counts@x),
  "NNZ", length(counts@x), "\n")
if (mode %in% c("prepare", "alignment")) {
  b <- if (mode == "prepare") {
    stopifnot(!dir.exists(bundle_dir))
    measure("source_ingestion", wb_bundle_from_sce(source_path, bundle_dir,
      created_by = "forge_matrix_streaming_acceptance"))
  } else wb_open_bundle(bundle_dir)
  cells <- wb_cells_with_matrix(b, "counts")
  features <- wb_features(b, "counts")$feature_id
  stopifnot(setequal(cells, colnames(counts)), setequal(features, rownames(counts)))
  selected_cells <- cells[seq_len(min(2000L, length(cells)))]
  selected_features <- features
  observed <- measure("aligned_source_read_2000", wb_slice(b, "counts",
    selected_features, selected_cells))
  reference <- counts[match(selected_features, rownames(counts)),
    match(selected_cells, colnames(counts)), drop = FALSE]
  stopifnot(identical(dimnames(observed), dimnames(reference)),
    identical(as.matrix(observed), as.matrix(reference)))
  observed_sums <- as.numeric(Matrix::colSums(observed))
  reference_sums <- as.numeric(Matrix::colSums(reference))
  stopifnot(identical(observed_sums, reference_sums))
  jsonlite::write_json(list(source_sha256 = source_sha, dimensions = dim(counts),
    source_class = class(counts), source_value_type = typeof(counts@x),
    getter_class = class(observed), getter_value_type = typeof(observed@x),
    complete_cell_membership = TRUE, complete_feature_membership = TRUE,
    ordered_cells_equal_source = identical(cells, colnames(counts)),
    ordered_features_equal_source = identical(features, rownames(counts)),
    matched_2000_cell_axes_and_all_values_exact = TRUE,
    matched_column_sums_exact = TRUE,
    named_column_sums_identical = identical(Matrix::colSums(observed), Matrix::colSums(reference)),
    column_sum_type_observed = typeof(Matrix::colSums(observed)),
    column_sum_type_reference = typeof(Matrix::colSums(reference)), total = sum(observed),
    unnamed_positional_sums_exact = identical(as.numeric(Matrix::colSums(counts[, seq_len(length(selected_cells)), drop = FALSE])), observed_sums)),
    file.path(chamber, "alignment.json"), auto_unbox = TRUE, pretty = TRUE)
  wb_finalize_recipient_bundle(b); wb_close_bundle(b)
  cat("PREPARATION_AND_ALIGNMENT_OK\n")
} else {
  stopifnot(mode == "baseline")
  wb_operation_pack_load("scwbRNA", lib.loc = args[3])
  wb_operation_pack_load("scwbRepresentation", lib.loc = args[3])
  # Phase totals may nest (request includes source preparation). They must not
  # be summed as disjoint wall time. Arithmetic is also sampled with Rprof.
  options(scwb.matrix.profile = function(name, elapsed) record(name, elapsed))
  ns <- asNamespace("scworkbench")
  trace_names <- c(".wb_operation_pack_v3_request", "wb_slice",
    ".wb_operation_pack_v3_matrix_consumed_identity",
    ".wb_operation_pack_matrix_stream_identity", ".wb_matrix_write_continuous",
    ".wb_operation_pack_v3_publish_materializations", ".wb_session_sqlite_backup",
    ".wb_matrix_stream_reader")
  for (name in trace_names) trace(name, where = ns, print = FALSE,
    tracer = quote(.scwb_profile_start <- proc.time()),
    exit = substitute(getOption("scwb.matrix.profile")(NAME,
      proc.time() - .scwb_profile_start), list(NAME = name)))
  b <- wb_open_bundle(bundle_dir, validate = FALSE)
  s <- wb_session_create(b, workspace_root = file.path(chamber, "sessions"),
    session_id = "baseline_rna")
  Rprof(file.path(chamber, "baseline.Rprof"), interval = .02)
  norm <- measure("normalization_total", wb_session_run_op(s, b,
    "scwbrna::matrix_log_normalize", inputs = list(matrix = "counts",
      cell_set = "all", output_matrix_id = "RNA_log_norm", scale_factor = 10000,
      chunk_size = 2000L, overwrite = FALSE)))
  s <- norm$session
  cat("NORMALIZATION_RUN", norm$run$run_id, "\n")
  hvg <- measure("hvg_total", wb_session_run_op(s, b, "scwbrna::hvg_select",
    inputs = list(matrix = "RNA_log_norm", cell_set = "all", n_features = 2000L,
      method = "vst", chunk_size = 256L, seed = 1L)))
  s <- hvg$session
  pca <- measure("pca_total", wb_session_run_op(s, b, "scwbrepresentation::pca_fit",
    inputs = list(matrix = "RNA_log_norm", features = wb_ref_run(hvg$run$run_id,
      "selected_features"), cell_set = "all", n_components = 50L, center = TRUE,
      scale = TRUE, backend = "irlba", seed = 1L, space_id_out = "rna.pca",
      overwrite = FALSE, max_dense_gb = 8, chunk_size = 256L)))
  s <- pca$session
  umap <- measure("umap_total", wb_session_run_op(s, b, "scwbrepresentation::umap_fit",
    inputs = list(space = wb_ref_run(pca$run$run_id, "space"), cell_set = "all",
      dims = 1:30, space_id_out = "rna.umap", n_neighbors = 30L, min_dist = .3,
      spread = 1, metric = "euclidean", nn_method = "nndescent", seed = 1L)))
  s <- umap$session
  Rprof(NULL)
  view <- wb_session_view(s)
  cells <- wb_cells_with_matrix(view, "RNA_log_norm")
  features <- wb_features(view, "RNA_log_norm")$feature_id
  measure("independent_normalization_reference", {
    for (part in wb_partition_axis(cells, 128L)) {
      raw <- as.matrix(counts[match(features, rownames(counts)),
        match(part, colnames(counts)), drop = FALSE])
      library <- colSums(raw); library[library <= 0] <- Inf
      expected <- log1p(t(t(raw) * (10000 / library)))
      actual <- as.matrix(wb_slice(view, "RNA_log_norm", features, part))
      stopifnot(identical(dimnames(actual), dimnames(expected)),
        max(abs(actual - expected)) < 1e-14)
    }
    TRUE
  })
  outputs <- list(wb_ref_run(norm$run$run_id, "summary"),
    wb_ref_run(hvg$run$run_id, "selected_features"), wb_ref_run(hvg$run$run_id, "fit_summary"),
    wb_ref_run(pca$run$run_id, "loadings"), wb_ref_run(pca$run$run_id, "variance"),
    wb_ref_run(pca$run$run_id, "fit_summary"), wb_ref_run(umap$run$run_id, "model"))
  promo <- measure("promotion_total", wb_session_promote_current(b, s,
    outputs = outputs, name_prefix = "baseline_rna", created_by = "forge_acceptance",
    fail_fast = TRUE))
  print(promo)
  measure("finalization", wb_finalize_recipient_bundle(b))
  wb_close_bundle(b)
  b <- measure("read_only_reopen", wb_open_bundle(bundle_dir, read_only = TRUE))
  stopifnot("RNA_log_norm" %in% wb_matrices(b)$matrix_id,
    all(c("rna.pca", "rna.umap") %in% wb_spaces(b)$space_id))
  print(wb_matrices(b)); print(wb_spaces(b))
  wb_close_bundle(b)
  cat("BASELINE_PROMOTED_FINALIZED_READONLY_OK\n")
}
