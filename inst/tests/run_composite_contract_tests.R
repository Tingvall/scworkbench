args <- commandArgs(trailingOnly = TRUE)
option <- function(name) {
  prefix <- paste0("--", name, "=")
  value <- args[startsWith(args, prefix)]
  if (length(value) != 1L) stop("exactly one ", prefix, " argument is required", call. = FALSE)
  sub(prefix, "", value, fixed = TRUE)
}
git_value <- function(source, command) {
  value <- system2("git", c("-C", shQuote(source), command), stdout = TRUE, stderr = TRUE)
  if (!is.null(attr(value, "status"))) stop("git inspection failed for ", source, call. = FALSE)
  trimws(value)
}
source_identity <- function(source, expected_commit, label) {
  if (!dir.exists(source)) stop(label, " source tree is missing", call. = FALSE)
  source <- normalizePath(source, winslash = "/", mustWork = TRUE)
  actual <- git_value(source, c("rev-parse", "HEAD"))
  if (!identical(actual, expected_commit)) stop(label, " source commit mismatch", call. = FALSE)
  dirty <- git_value(source, c("status", "--porcelain", "--untracked-files=all"))
  if (length(dirty) && any(nzchar(dirty))) stop(label, " source tree is dirty", call. = FALSE)
  source
}
core_commit <- option("core-commit")
pack_commit <- option("pack-commit")
expected_manifest <- option("pack-manifest-sha256")
core_source <- source_identity(option("core-source"), core_commit, "scworkbench")
pack_source <- source_identity(option("pack-source"), pack_commit, "scwbStatistics")
manifest <- file.path(pack_source, "inst", "scworkbench", "operation-pack.json")
actual_manifest <- digest::digest(manifest, file = TRUE, algo = "sha256", serialize = FALSE)
if (!identical(actual_manifest, expected_manifest)) stop("scwbStatistics manifest identity mismatch",
  call. = FALSE)
cat("COMPOSITE PREFLIGHT OK core=", core_commit, " pack=", pack_commit,
  " manifest=", actual_manifest, "\n", sep = "")
if ("--preflight-only" %in% args) quit(status = 0L)
devtools::load_all(core_source, quiet = TRUE)
source(file.path(core_source, "inst", "tests", "contract_test_runner.R"), local = globalenv())
Sys.setenv(SCWBSTATISTICS_SOURCE = pack_source)
inventory <- contract_test_discover(file.path(core_source, "tests", "composite"))
run <- contract_test_execute(inventory)
contract_test_assert_success(run)
cat("COMPOSITE CONTRACTS OK files=", run$summary[["files"]],
  " discovered=", run$summary[["discovered"]], " executed=", run$summary[["executed"]],
  " passed=", run$summary[["passed"]], " skipped=", run$summary[["skipped"]],
  " failed=", run$summary[["failed"]], "\n", sep = "")
