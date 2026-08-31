args <- commandArgs(trailingOnly = TRUE)
library(scworkbench, lib.loc = args[[1]])

fixture_path <- system.file("protocol", "fixtures", "operation-pack-canonical-json-v1",
                            "cases.json", package = "scworkbench")
identity_path <- system.file("protocol", "fixtures", "operation-pack-v1",
                             "canonical-identities.json", package = "scworkbench")
schema_path <- system.file("protocol", "operation-pack-v1.schema.json", package = "scworkbench")
spec_path <- system.file("protocol", "operation-pack-canonical-json-v1.md", package = "scworkbench")
stopifnot(all(file.exists(c(fixture_path, identity_path, schema_path, spec_path))))
fixture <- jsonlite::read_json(fixture_path, simplifyVector = FALSE)
identities <- jsonlite::read_json(identity_path, simplifyVector = FALSE)
parse <- getFromNamespace(".wb_operation_pack_parse_canonical_json", "scworkbench")
canonical <- getFromNamespace(".wb_operation_pack_canonical_json", "scworkbench")
for (case in fixture$valid) stopifnot(identical(canonical(parse(case$input_json)), case$canonical_json))
for (case in fixture$invalid) {
  error <- tryCatch({ canonical(parse(case$input_json)); NULL }, error = identity)
  stopifnot(inherits(error, "wb_operation_pack_error"), identical(error$code, case$code))
}
sha <- function(path) digest::digest(file = path, algo = "sha256", serialize = FALSE)
stopifnot(
  identical(sha(schema_path), identities$authoritative_schema_sha256),
  identical(sha(spec_path), identities$identity_scheme_spec_sha256),
  identical(sha(fixture_path), identities$canonical_fixture_corpus_sha256)
)
cat("OPERATION_PACK_CANONICAL_INSTALLED_OK\n")
