args <- commandArgs(TRUE)
suppressPackageStartupMessages(library(SingleCellExperiment))
sce <- readRDS("/home/dirk/Projects/.scworkbench-experiments/rc38_axolotl_definitive/source/aztekin_tail_2019_sce.rds")
counts <- assay(sce, "counts")
conversion <- arithmetic <- c(user.self = 0, sys.self = 0, elapsed = 0)
for (start in seq.int(1L, ncol(counts), by = 2000L)) {
  t <- proc.time()
  raw <- as.matrix(counts[, seq.int(start, min(ncol(counts), start + 1999L)), drop = FALSE])
  conversion <- conversion + (proc.time() - t)[names(conversion)]
  t <- proc.time()
  library <- colSums(raw); library[library <= 0] <- Inf
  normalized <- log1p(t(t(raw) * (10000 / library)))
  arithmetic <- arithmetic + (proc.time() - t)[names(arithmetic)]
  stopifnot(all(is.finite(normalized)))
  rm(raw, normalized)
}
cat("INDEPENDENT_MATCHED_SOURCE_KERNEL_ONLY chunk_size=2000 scale_factor=10000\n")
print(list(source_sparse_to_dense_conversion = conversion,
  normalization_arithmetic = arithmetic))
if (length(args)) jsonlite::write_json(list(conversion = as.list(conversion),
  arithmetic = as.list(arithmetic), scope = "isolated reference kernel; excludes core and pack publication"),
  args[1], pretty = TRUE, auto_unbox = TRUE)
