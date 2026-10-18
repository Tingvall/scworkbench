# Matched-input/hardware normalization comparison, NOT a historical full
# baseline or frozen-image reproduction. A fresh minimal counts-only bundle
# deliberately excludes source annotations and imported spaces from timing.
args <- commandArgs(TRUE)
.libPaths(c(args[2], .libPaths()))
suppressPackageStartupMessages({library(scworkbench); library(SingleCellExperiment)})
source_path <- "/home/dirk/Projects/.scworkbench-experiments/rc38_axolotl_definitive/source/aztekin_tail_2019_sce.rds"
sce <- readRDS(source_path); counts <- assay(sce, "counts")
cat("HISTORICAL_CORE d95d8df9955f08f0732feb653cbe9be9a6869d26\n")
cat("SOURCE_SHA", digest::digest(file = source_path, algo = "sha256"), "DIM", dim(counts), "\n")
b <- wb_init_bundle(file.path(args[1], "historical_counts.bundle"))
wb_define_cells(b, colnames(counts))
wb_attach_matrix(b, "counts", counts, layer = "counts", feature_type = "gene")
start <- proc.time()
result <- wb_session_run_op(wb_session_new(), b, "matrix_log_normalize",
  inputs = list(matrix = "counts", cell_set = "all", output_matrix_id = "RNA_log_norm",
    scale_factor = 10000, overwrite = FALSE))
elapsed <- proc.time() - start
cat("HISTORICAL_PUBLIC_NORMALIZATION_ELAPSED", elapsed[["elapsed"]],
  "USER", elapsed[["user.self"]], "SYSTEM", elapsed[["sys.self"]], "\n")
view <- wb_session_view(result$session)
features <- rownames(counts); cells <- colnames(counts)
maximum_error <- 0
for (start in seq.int(1L, length(cells), by = 128L)) {
  part <- cells[seq.int(start, min(length(cells), start + 127L))]
  raw <- as.matrix(counts[, part, drop = FALSE])
  library <- colSums(raw); library[library <= 0] <- Inf
  expected <- log1p(t(t(raw) * (10000 / library)))
  actual <- as.matrix(wb_slice(view, "RNA_log_norm", features, part))
  maximum_error <- max(maximum_error, abs(actual - expected))
  stopifnot(identical(dimnames(actual), dimnames(expected)), maximum_error < 1e-14)
}
cat("HISTORICAL_REFERENCE_MAX_ABS_ERROR", maximum_error, "\n")
wb_close_bundle(b)
cat("MATCHED_NORMALIZATION_ONLY_OK; full historical baseline unavailable in this comparison\n")
