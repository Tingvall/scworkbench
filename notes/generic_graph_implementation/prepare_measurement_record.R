# Attribute an existing, immutable source fixture to an exact installed runtime.
# This generates qualification evidence; it does not alter a bundle or its
# original source-setup record. Runtime body hashing is operator instrumentation,
# not a pack-supplied scientific identity or an authority grant.
args <- commandArgs(TRUE)
stopifnot(length(args) == 4L, grepl("^[0-9a-f]{40}$", args[[4L]]),
  file.exists(args[[1L]]), !file.exists(args[[3L]]))
library_path <- normalizePath(args[[2L]], mustWork = TRUE)
.libPaths(c(library_path, .libPaths()))
library(scworkbench)
stopifnot(identical(normalizePath(find.package("scworkbench")),
  normalizePath(file.path(library_path, "scworkbench"))))
original_sha <- digest::digest(file = args[[1L]], algo = "sha256", serialize = FALSE)
record <- readRDS(args[[1L]])
stopifnot(record$schema == "scworkbench.graph.scale-fixture.v1")
runtime_sha <- digest::digest(paste(deparse(body(getFromNamespace(
  ".wb_graph_object_closure", "scworkbench"))), collapse = "\n"),
  algo = "sha256", serialize = FALSE)
record$core_library <- library_path
record$measurement <- list(core_commit = args[[4L]],
  original_fixture_record_sha256 = original_sha,
  source_closure_runtime_sha256 = runtime_sha)
saveRDS(record, args[[3L]])
stopifnot(identical(original_sha,
  digest::digest(file = args[[1L]], algo = "sha256", serialize = FALSE)))
cat("MEASUREMENT_RECORD core_commit=", args[[4L]], " installed_package=",
  find.package("scworkbench"), " source_closure_runtime_sha256=", runtime_sha,
  " original_fixture_record_sha256=", original_sha,
  " output_sha256=", digest::digest(file = args[[3L]], algo = "sha256", serialize = FALSE),
  " original_record_unchanged=TRUE\n", sep = "")
