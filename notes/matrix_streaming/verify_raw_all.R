args <- commandArgs(TRUE)
.libPaths(c(args[2], .libPaths()))
suppressPackageStartupMessages({library(scworkbench); library(SingleCellExperiment)})
sce <- readRDS("/home/dirk/Projects/.scworkbench-experiments/rc38_axolotl_definitive/source/aztekin_tail_2019_sce.rds")
counts <- assay(sce, "counts")
b <- wb_open_bundle(file.path(args[1], "xenopus.bundle"), read_only = TRUE, validate = FALSE)
cells <- wb_cells_with_matrix(b, "counts")
features <- wb_features(b, "counts")$feature_id
stopifnot(setequal(cells, colnames(counts)), setequal(features, rownames(counts)))
parts <- wb_partition_axis(cells, 128L)
for (part in parts) {
  actual <- wb_slice(b, "counts", features, part)
  expected <- counts[match(features, rownames(counts)), match(part, colnames(counts)), drop = FALSE]
  stopifnot(identical(dimnames(actual), dimnames(expected)),
    identical(as.matrix(actual), as.matrix(expected)),
    identical(Matrix::colSums(actual), Matrix::colSums(expected)),
    identical(typeof(actual@x), typeof(expected@x)))
}
wb_close_bundle(b)
cat("RAW_ALL_VALUES_AND_NAMED_SUMS_EXACT cells=", length(cells),
  " features=", length(features), " parts=", length(parts),
  " storage=dgCMatrix/double; original source membership and explicit ordered reads verified\n", sep = "")
