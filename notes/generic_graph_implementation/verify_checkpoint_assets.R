# Focused protocol/fixture byte parity and syntax; not a package suite.
args <- commandArgs(TRUE)
stopifnot(length(args) == 1L)
peer <- normalizePath(args[[1L]], mustWork = TRUE)
schemas <- c("graph-v1.schema.json", "operation-pack-v4.schema.json",
  "operation-pack-transition-request-v4.schema.json",
  "operation-pack-transition-receipt-v4.schema.json",
  "pybench-op-v5-python-runtime.schema.json")
core <- file.path("inst", "protocol", schemas)
python <- file.path(peer, "protocol", schemas)
fixtures <- c("content-identities.json", "binding-descriptor-identities.json",
  "scenario-roundtrip-vectors.json", "negative-rehash-identities.csv")
core <- c(core, file.path("inst", "protocol", "fixtures", "graph-v1", fixtures),
  "tests/fixtures/graph-abi4-draft-interop.json")
python <- c(python, file.path(peer, "protocol", "fixtures", "graph-v1", fixtures),
  file.path(peer, "protocol", "fixtures", "graph-v1", "draft-abi4-mixed-interop.json"))
sha <- function(path) digest::digest(file = path, algo = "sha256", serialize = FALSE)
for (i in seq_along(core)) {
  stopifnot(file.exists(core[[i]]), file.exists(python[[i]]), sha(core[[i]]) == sha(python[[i]]))
  if (endsWith(core[[i]], ".json")) jsonlite::read_json(core[[i]], simplifyVector = FALSE)
  cat("SHARED_ASSET ", core[[i]], " sha256=", sha(core[[i]]), " PASS\n", sep = "")
}
files <- c(list.files("R", "[.]R$", full.names = TRUE),
  list.files("tests", "[.]R$", full.names = TRUE),
  list.files("notes/generic_graph_implementation", "[.]R$", full.names = TRUE))
for (path in files) parse(path)
cat("GRAPH_CHECKPOINT_STATIC schemas=5 authoritative_fixture_assets=4 synthetic_test_fixture=1 byte_parity=PASS R_syntax=PASS\n")
status <- system2("git", c("diff", "--check"))
stopifnot(status == 0L)
cat("GIT_DIFF_CHECK PASS\n")
