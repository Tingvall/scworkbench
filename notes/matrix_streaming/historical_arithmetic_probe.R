# Explain, not waive, the failed historical-vs-R 1e-14 comparison.
args <- commandArgs(TRUE)
suppressPackageStartupMessages(library(BPCells))
paths <- list.dirs(file.path(args[1], "historical_counts.bundle", "mat"),
  recursive = FALSE, full.names = TRUE)
stopifnot(length(paths) == 1L)
matrix <- open_matrix_dir(paths[[1]])[, 1:128, drop = FALSE]
raw <- as.matrix(matrix)
library <- as.numeric(Matrix::colSums(matrix))
stopifnot(identical(library, as.numeric(colSums(raw))))
library[library <= 0] <- Inf
multiplied <- multiply_cols(matrix, 10000 / library)
scaled <- t(t(raw) * (10000 / library))
stopifnot(identical(as.matrix(multiplied), scaled))
actual <- as.matrix(log1p(multiplied))
expected <- log1p(scaled)
cat("LIBRARY_SUMS_AND_SCALED_VALUES_EXACT\n")
cat("LAZY_LOG1P_MAX_ABS_DIFFERENCE", max(abs(actual - expected)), "\n")
cat("PREDECLARED_1E_MINUS14_EQUIVALENCE", max(abs(actual - expected)) < 1e-14, "\n")
cat("No tolerance or scientific parameter changed; no BPCells/runtime source repair performed.\n")
