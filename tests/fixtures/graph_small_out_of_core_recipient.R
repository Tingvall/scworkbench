args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 4L)
.libPaths(c(dirname(args[[1L]]), .libPaths()))
library(scworkbench)
source(args[[4L]])
record <- readRDS(args[[3L]]); root <- args[[2L]]
before <- graph_small_fingerprint(root)
bundle <- wb_open_bundle(root, read_only = TRUE)
stopifnot(!any(grepl("^graphsmallfixture::", wb_list_ops())),
  !any(c("scwbGraphSmallFixture", "scwbRNA") %in% loadedNamespaces()),
  !"scwbrna::matrix_log_normalize" %in% wb_list_ops())
for (artifact in record$artifacts) graph_small_assert(bundle, artifact, record$expected, record$policy)
wb_close_bundle(bundle)
report <- wb_bundle_validation_report(root, level = "recipient")
if (!report$ok) print(report$diagnostics)
stopifnot(report$ok, identical(report$pre_validation_fingerprint, report$post_validation_fingerprint),
  identical(before, graph_small_fingerprint(root)))
cat("GRAPH_SMALL_RECIPIENT pack_free=TRUE read_only=TRUE exact_rows_roots_bindings=TRUE purity=TRUE PASS\n")
