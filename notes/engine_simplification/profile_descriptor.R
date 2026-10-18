args <- commandArgs(TRUE)
.libPaths(c(args[[1L]], .libPaths()))
suppressPackageStartupMessages(library(scworkbench))
root <- args[[2L]]; stopifnot(!dir.exists(root)); dir.create(root)
ns <- asNamespace("scworkbench")
# Final qualification uses the frozen repaired algorithm, never "old" from a
# candidate installation. Rebind its SHA/identity closures so descriptor work
# actually uses the repaired canonical encoder as well as repaired orchestration.
oracle_env <- new.env(parent = ns)
sys.source("tests/fixtures/engine_canonical_repaired_oracle.R", oracle_env)
oracle_env$.wb_operation_pack_canonical_json <- oracle_env$.engine_canonical_repaired_oracle
for (name in c(".wb_operation_pack_sha256", ".wb_operation_pack_v2_identity_plain",
    ".wb_operation_pack_v2_identity_scoped")) {
  helper <- get(name, ns); environment(helper) <- oracle_env
  assign(name, helper, oracle_env)
}
sys.source("tests/fixtures/engine_descriptor_repaired_oracle.R", oracle_env)
old <- oracle_env$.engine_descriptor_repaired_oracle
new <- ns$.wb_operation_pack_v2_input_descriptor
cat("BASELINE=frozen_repaired_descriptor_and_canonical_oracles CANDIDATE=installed_namespace\n")
cells <- paste0("cell_", seq_len(13199L)); set.seed(8L)
scores <- setNames(rnorm(length(cells)), cells)
objects <- list(cell_vector = wb_prim_cell_vector(scores, "continuous",
    meta = list(label = "score")),
  cell_vector_family = wb_prim_cell_vector_family(rep(c("A", "B"), each = length(cells)),
    rep(cells, 2L), rep(scores, 2L), value_type = "continuous"),
  relation_family = wb_prim_relation_family(rep(c("A", "B"), each = length(cells)),
    rep(cells, 2L), weight = rep(abs(scores), 2L)),
  model_ref = wb_prim_model_ref("fitted", "source", engine = "uwot"))
rows <- list()
for (name in names(objects)) {
  answers <- list()
  for (mode in c("baseline", "candidate")) {
    gc(); start <- proc.time()
    answer <- (if (mode == "baseline") old else new)(name, objects[[name]],
      list(kind = name, alignment = "exact"))
    elapsed <- proc.time() - start
    answers[[mode]] <- answer
    rows[[length(rows) + 1L]] <- data.frame(kind = name, mode = mode,
      elapsed = elapsed[["elapsed"]], user = elapsed[["user.self"]],
      descriptor_sha256 = digest::digest(jsonlite::serializeJSON(answer, digits = NA),
        algo = "sha256", serialize = FALSE))
  }
  stopifnot(identical(answers$baseline, answers$candidate))
}
write.csv(do.call(rbind, rows), file.path(root, "measurements.csv"), row.names = FALSE)
print(do.call(rbind, rows), row.names = FALSE)
# Same full old algorithms, not mocked decoders: all descriptors and negatives.
source("tests/test_engine_descriptor_preimage_contract.R")
.engine_descriptor_oracle <- function() old
stopifnot(test_engine_descriptor_preimage_exact_contract(),
  test_engine_descriptor_preimage_rejection_contract())
cat("DESCRIPTOR_EXACT_PREIMAGES_AND_REJECTIONS_OK\n")
