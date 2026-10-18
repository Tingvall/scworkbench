args <- commandArgs(TRUE)
.libPaths(c(args[1L], .libPaths()))
suppressPackageStartupMessages(library(scworkbench))
wb_operation_pack_load("scwbRNA", lib.loc = args[1])
wb_operation_pack_load("scwbRepresentation", lib.loc = args[1])
root <- tempfile("scwb_small_stream_workflow_")
set.seed(29)
cells <- paste0("c", c(2, 10, 1, 3:9, 11:32))
features <- paste0("f", 24:1)
counts <- matrix(rpois(24L * 32L, 2), 24L, dimnames = list(features, cells))
counts[, "c1"] <- 0
b <- wb_init_bundle(root)
wb_define_cells(b, cells)
wb_attach_matrix(b, "counts", counts, layer = "counts", feature_type = "gene")
authentication <- new.env(parent = emptyenv()); authentication$calls <- 0L
options(scwb.matrix.authentication.counter = authentication)
trace(".wb_operation_pack_v3_matrix_consumed_identity", where = asNamespace("scworkbench"),
  print = FALSE, tracer = quote({
    counter <- getOption("scwb.matrix.authentication.counter")
    counter$calls <- counter$calls + 1L
  }))
norm <- wb_session_run_op(wb_session_new(), b, "matrix_log_normalize",
  inputs = list(matrix = "counts", output_matrix_id = "RNA_log", scale_factor = 10000,
    chunk_size = 7L, min_cells = 1L))
untrace(".wb_operation_pack_v3_matrix_consumed_identity", where = asNamespace("scworkbench"))
stopifnot(authentication$calls == 3L)
cat("SOURCE_AUTHENTICATION_PASSES=3 NORMALIZATION_CHUNKS=5 (not two full hashes per chunk)\n")
cat("PASS normalization execution\n")
view <- wb_session_view(norm$session)
actual <- as.matrix(wb_slice(view, "RNA_log", features, cells))
library <- colSums(counts); library[library <= 0] <- Inf
expected <- log1p(t(t(counts) * (10000 / library)))
stopifnot(identical(dimnames(actual), dimnames(expected)),
  max(abs(actual - expected)) < 1e-14, all(actual[, "c1"] == 0),
  identical(as.integer(norm$run$outputs$summary$table$n_zero_library_cells), 1L))
plan <- scworkbench:::.wb_matrix_stream_reader(view, "RNA_log", "features")
stopifnot(max(abs(as.matrix(plan$read(features, cells)) - expected)) < 1e-14)
plan$close()
hvg <- wb_session_run_op(norm$session, b, "hvg_select", inputs = list(
  matrix = "RNA_log", n_features = 8L, method = "vst", chunk_size = 5L, seed = 1L,
  min_cells = 1L))
cat("PASS HVG execution\n")
pca <- wb_session_run_op(hvg$session, b, "pca_fit", inputs = list(matrix = "RNA_log",
  features = wb_ref_run(hvg$run$run_id, "selected_features"), n_components = 3L,
  center = TRUE, scale = TRUE, backend = "irlba", seed = 1L, space_id_out = "pca",
  max_dense_gb = 8, chunk_size = 3L, min_cells = 1L))
cat("PASS PCA execution\n")
umap <- wb_session_run_op(pca$session, b, "umap_fit", inputs = list(
  space = wb_ref_run(pca$run$run_id, "space"), dims = 1:3, space_id_out = "umap",
  n_neighbors = 5L, min_dist = .3, spread = 1, metric = "euclidean",
  nn_method = "nndescent", seed = 1L, min_cells = 1L))
cat("PASS UMAP execution\n")
promotion <- wb_session_promote_current(b, umap$session, outputs = list(
  wb_ref_run(norm$run$run_id, "summary"), wb_ref_run(hvg$run$run_id, "fit_summary"),
  wb_ref_run(pca$run$run_id, "fit_summary"), wb_ref_run(umap$run$run_id, "model")),
  fail_fast = TRUE)
print(promotion)
wb_finalize_recipient_bundle(b); wb_close_bundle(b)
b <- wb_open_bundle(root, read_only = TRUE)
stopifnot(all(c("pca", "umap") %in% wb_spaces(b)$space_id),
  max(abs(as.matrix(wb_slice(b, "RNA_log", features, cells)) - expected)) < 1e-14)
wb_close_bundle(b)
cat("PASS small normalize/HVG/PCA/UMAP promote/finalize/read-only; zero library preserved\n")
