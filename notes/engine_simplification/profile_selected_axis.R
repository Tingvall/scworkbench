args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 3L, args[[1L]] %in% c("baseline", "candidate"))
.libPaths(c(args[[2L]], .libPaths()))
suppressPackageStartupMessages(library(scworkbench))
root <- args[[3L]]
dir.create(root, recursive = TRUE, showWarnings = FALSE)
reference <- readRDS(paste0("/tmp/scwb-engine-simplification-forge-20261018/",
  "direct-xenopus-v3/scientific_reference.rds"))
features <- reference$pca$selected
cells <- rownames(reference$pca$coords)
stopifnot(length(features) == 2000L, length(cells) == 13199L)
b <- wb_open_bundle(paste0("/tmp/scwb-matrix-streaming-forge-20261018/",
  "verified-xenopus/xenopus.bundle"), read_only = TRUE, validate = FALSE)
reader <- scworkbench:::.wb_matrix_stream_reader
if (args[[1L]] == "candidate") {
  e <- new.env(parent = asNamespace("scworkbench"))
  sys.source("R/getters_matrices.R", e)
  reader <- e$.wb_matrix_stream_reader
}
rchar <- function() as.double(sub("rchar: ", "", grep("^rchar: ",
  readLines("/proc/self/io", warn = FALSE), value = TRUE)))
timing <- list()
measure <- function(name, fun) {
  start_bytes <- rchar(); start <- proc.time()[["elapsed"]]
  value <- fun()
  elapsed <- proc.time()[["elapsed"]] - start
  bytes <- rchar() - start_bytes
  timing[[length(timing) + 1L]] <<- data.frame(mode = args[[1L]],
    phase = name, elapsed_seconds = elapsed, rchar = bytes)
  cat(sprintf("READER mode=%s phase=%s elapsed_seconds=%.6f rchar=%.0f\n",
    args[[1L]], name, elapsed, bytes))
  value
}
tryCatch({
  plan <- measure("prepare", function() if (args[[1L]] == "baseline")
    reader(b, "RNA_log_norm", "features") else
      reader(b, "RNA_log_norm", "features", features = features, cells = cells))
  tryCatch({
    partitions <- wb_partition_axis(features, 256L)
    for (i in seq_along(partitions)) {
      selected <- partitions[[i]]
      block <- measure(sprintf("read_%02d", i), function()
        as.matrix(plan$read(selected, cells)))
      expected_path <- file.path(root, sprintf("block_%02d.rds", i))
      if (args[[1L]] == "baseline") {
        stopifnot(!file.exists(expected_path))
        saveRDS(block, expected_path, compress = FALSE)
      } else stopifnot(identical(block, readRDS(expected_path)))
      stopifnot(identical(rownames(block), selected),
        identical(colnames(block), cells), nrow(block) <= 256L)
      rm(block); gc(FALSE)
    }
  }, finally = { plan$close(); stopifnot(!dir.exists(plan$root)) })
  totals <- do.call(rbind, timing)
  write.csv(totals, file.path(root, paste0(args[[1L]], ".csv")), row.names = FALSE)
  cat(sprintf("READER_TOTAL mode=%s elapsed_seconds=%.6f rchar=%.0f parts=%d exact_blocks=TRUE cleanup=TRUE\n",
    args[[1L]], sum(totals$elapsed_seconds), sum(totals$rchar), nrow(totals) - 1L))
}, finally = wb_close_bundle(b))
