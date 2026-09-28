#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
root <- if (length(args)) normalizePath(args[[1L]], mustWork = TRUE) else normalizePath(".", mustWork = TRUE)
pybench_root <- if (length(args) >= 2L) normalizePath(args[[2L]], mustWork = TRUE) else NULL

metadata_path <- file.path(root, "inst", "release", "composite_release.dcf")
metadata <- read.dcf(metadata_path)
required <- c(
  "SchemaVersion", "ReleaseVersion", "ScworkbenchVersion", "PyBenchVersion",
  "PyBenchCommit", "PyBenchRepository", "ProtocolVersion", "ProtocolSHA256",
  "StandardProfileSchemaVersion", "StandardProfileSHA256",
  "StandardProfilePackCount", "StandardProfilePackedOperationCount",
  "StandardProfileTotalOperationCount",
  "BaseImage", "BaseImageDigestAMD64", "RVersion", "RVersionLockSHA256",
  "PythonVersion", "PythonVersionLockSHA256", "GPUValidation", "LargeDataValidation"
)
missing <- setdiff(required, colnames(metadata))
if (length(missing)) stop("Composite release metadata missing: ", paste(missing, collapse = ", "))
value <- function(field) as.character(metadata[1L, field])

description <- read.dcf(file.path(root, "DESCRIPTION"))
profile <- jsonlite::read_json(file.path(root, "inst", "standard_profile",
  "profile.json"), simplifyVector = FALSE)
profile_packs <- profile$packs
profile_pack_counts <- vapply(profile_packs, function(pack) {
  stopifnot(is.list(pack), is.character(pack$source_commit),
    grepl("^[0-9a-f]{40}$", pack$source_commit),
    is.character(pack$manifest_source_sha256),
    grepl("^[0-9a-f]{64}$", pack$manifest_source_sha256),
    is.character(pack$manifest_sha256),
    grepl("^[0-9a-f]{64}$", pack$manifest_sha256))
  as.integer(pack$operation_count)
}, integer(1))
stopifnot(
  identical(value("SchemaVersion"), "scworkbench.composite-release.v2"),
  identical(value("ReleaseVersion"), value("ScworkbenchVersion")),
  identical(value("ScworkbenchVersion"), as.character(description[1L, "Version"])),
  identical(value("PyBenchVersion"), as.character(description[1L, "Config/scworkbench/PyBench-Version"])),
  identical(value("ProtocolVersion"), as.character(description[1L, "Config/scworkbench/PyBench-Protocol"])),
  identical(value("ProtocolSHA256"), as.character(description[1L, "Config/scworkbench/PyBench-Protocol-SHA256"])),
  identical(value("StandardProfileSchemaVersion"), profile$schema_version),
  identical(profile$schema_version, "scworkbench.standard_profile.v1"),
  identical(value("PyBenchCommit"), profile$pybench_source_commit),
  identical(as.integer(value("StandardProfilePackCount")), length(profile_packs)),
  identical(as.integer(value("StandardProfilePackedOperationCount")),
    as.integer(profile$packed_operation_count)),
  identical(as.integer(value("StandardProfilePackedOperationCount")),
    as.integer(sum(profile_pack_counts))),
  identical(as.integer(value("StandardProfileTotalOperationCount")),
    as.integer(length(profile$core_operations) + sum(profile_pack_counts))),
  !anyDuplicated(vapply(profile_packs, function(pack) pack$namespace,
    character(1))),
  grepl("^sha256:[0-9a-f]{64}$", value("BaseImageDigestAMD64")),
  grepl("^[0-9a-f]{40}$", value("PyBenchCommit"))
)

sha256 <- function(path) unname(tools::md5sum(path))
sha256_external <- function(path) {
  output <- system2("sha256sum", path, stdout = TRUE)
  if (!length(output)) stop("sha256sum produced no output for ", path)
  sub("[[:space:]].*$", "", output[[1L]])
}
checks <- c(
  ProtocolSHA256 = sha256_external(file.path(root, "inst", "protocol", "pybench-op-v2.schema.json")),
  StandardProfileSHA256 = sha256_external(file.path(root, "inst",
    "standard_profile", "profile.json")),
  RVersionLockSHA256 = sha256_external(file.path(root, "containers", "apptainer", "fullstack_r_versions.lock.csv")),
  PythonVersionLockSHA256 = sha256_external(file.path(root, "containers", "apptainer", "fullstack_python_requirements.lock"))
)
for (field in names(checks)) {
  if (!identical(value(field), checks[[field]])) stop(field, " does not match its locked file")
}

definition <- readLines(file.path(root, "containers", "apptainer", "scworkbench_fullstack.def"), warn = FALSE)
expected_from <- paste0("From: bioconductor/bioconductor_docker@", value("BaseImageDigestAMD64"))
if (!expected_from %in% definition) stop("Apptainer base image is not pinned to composite metadata")

gate_policy <- jsonlite::read_json(file.path(root, "inst", "release", "gate_policy.json"), simplifyVector = TRUE)
stopifnot(identical(gate_policy$schema, "scworkbench.release-gates.v1"),
          length(gate_policy$required) >= 8L,
          all(vapply(gate_policy$scheduled_or_manual, function(x) {
            identical(x$default_status, "not_run") && isTRUE(x$required_for_final_release)
          }, logical(1))))

if (!is.null(pybench_root)) {
  pyproject <- readLines(file.path(pybench_root, "pyproject.toml"), warn = FALSE)
  version_line <- grep('^version = "', pyproject, value = TRUE)
  build_line <- grep('requires = ["hatchling==', pyproject, value = TRUE, fixed = TRUE)
  stopifnot(length(version_line) == 1L, length(build_line) == 1L)
  pybench_version <- sub('^version = "([^"]+)".*$', "\\1", version_line)
  stopifnot(identical(pybench_version, value("PyBenchVersion")))
  schema <- file.path(pybench_root, "protocol", "pybench-op-v2.schema.json")
  stopifnot(file.exists(schema), identical(sha256_external(schema), value("ProtocolSHA256")))
  head <- system2("git", c("-C", pybench_root, "rev-parse", "HEAD"), stdout = TRUE)
  stopifnot(length(head) == 1L, identical(head[[1L]], value("PyBenchCommit")))
}

cat("composite release metadata: OK\n")
