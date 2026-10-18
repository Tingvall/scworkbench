args <- commandArgs(TRUE)
.libPaths(c(args[[1L]], .libPaths()))
suppressPackageStartupMessages(library(scworkbench))
root <- args[[2L]]; mode <- args[[3L]]
stopifnot(!dir.exists(root), mode %in% c("baseline", "candidate")); dir.create(root)
ns <- asNamespace("scworkbench")
oracle_env <- new.env(parent = ns)
sys.source("tests/fixtures/engine_canonical_repaired_oracle.R", oracle_env)
old <- oracle_env$.engine_canonical_repaired_oracle
new <- ns$.wb_operation_pack_canonical_json
cat("BASELINE=frozen_repaired_canonical_oracle CANDIDATE=installed_namespace\n")
encoder <- if (mode == "baseline") old else new
values <- list(axis31535 = paste0("feature_", seq_len(31535L)),
  list_axis31535 = as.list(paste0("feature_", seq_len(31535L))))
for (n in c(1000L, 5000L)) values[[paste0("table", n)]] <- data.frame(
  feature_id = paste0("gene_", seq_len(n)), component = rep(1:50, length.out = n),
  loading = sin(seq_len(n)), PC = rep(paste0("PC", 1:50), length.out = n))
rows <- list()
for (name in names(values)) {
  gc(); start <- proc.time()
  text <- encoder(values[[name]])
  elapsed <- (proc.time() - start)[["elapsed"]]
  rows[[length(rows) + 1L]] <- data.frame(mode = mode, case = name,
    elapsed = elapsed, bytes = nchar(text, type = "bytes"),
    sha256 = digest::digest(text, algo = "sha256", serialize = FALSE))
}
write.csv(do.call(rbind, rows), file.path(root, "measurements.csv"), row.names = FALSE)
print(do.call(rbind, rows), row.names = FALSE)
if (mode == "candidate") {
  source("tests/test_engine_canonical_preimage_contract.R")
  .engine_canonical_oracle <- function() old
  stopifnot(test_engine_canonical_array_and_key_plan_contract(),
    test_engine_canonical_preimage_rejection_contract(),
    test_engine_canonical_table_batches_contract())
}
cat("CANONICAL_CHARACTER_AND_KEY_PREIMAGES_OK\n")
