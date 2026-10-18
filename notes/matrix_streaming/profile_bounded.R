args <- commandArgs(TRUE)
stopifnot(length(args) == 1L)
.libPaths(c(args[[1L]], .libPaths()))
library(scworkbench)
source("tests/test_operation_pack_matrix_streaming_contract.R")
cat("RUNTIME", R.version.string, "\n")
cat("CPU", paste(system("nproc", intern = TRUE), collapse = " "), "\n")
print(system("df -T . /tmp", intern = TRUE))
stopifnot(test_operation_pack_matrix_streaming_identity_contract(),
  test_operation_pack_matrix_streaming_numeric_contract())
cat("PASS identity and numeric contracts (2/2); skips=0\n")
set.seed(21)
values <- matrix(rpois(800L * 160L, .1), nrow = 800L,
  dimnames = list(paste0("g", seq_len(800L)), paste0("c", seq_len(160L))))
for (label in c("legacy", "stream")) {
  gc()
  time <- system.time(identity <- if (label == "legacy")
    .wb_matrix_slice_legacy_oracle(values, rownames(values), colnames(values)) else
      scworkbench:::.wb_operation_pack_v3_matrix_slice_content(values,
        rownames(values), colnames(values)))
  cat(label, "800x160 nnz", sum(values != 0), "identity", identity$sha256, "\n")
  print(time)
}
