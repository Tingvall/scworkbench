args <- commandArgs(TRUE)
stopifnot(length(args) == 2L)
fixture <- readRDS("/tmp/scwb-graph-native-long-axis-90000-development/measurement-9a11d1f.rds")
original <- fixture
fixture$core_library <- file.path(args[[1L]], "library")
.libPaths(c(fixture$core_library, .libPaths()))
library(scworkbench)
stopifnot(identical(normalizePath(find.package("scworkbench")),
  normalizePath(file.path(fixture$core_library, "scworkbench"))),
  identical(fixture$source_bundle, original$source_bundle), fixture$source_axis_count == 90000L,
  fixture$source_axis_utf8_bytes == 18258618L, !file.exists(args[[2L]]))
fixture$development_checkpoint <- list(name = "246_manifest_small_batch_diagnostic",
  native_matrix_dispatch = "disabled", qualification = FALSE,
  source_ledger = "notes/generic_graph_implementation/evidence/246_review_checkpoint.sha256",
  source_closure_function_sha256 = digest::digest(paste(deparse(body(getFromNamespace(
    ".wb_graph_object_closure", "scworkbench"))), collapse = "\n"), algo = "sha256", serialize = FALSE))
fixture$development_checkpoint$manifest_function_sha256 <- digest::digest(paste(deparse(body(
  getFromNamespace(".wb_manifest_table_identity", "scworkbench"))), collapse = "\n"),
  algo = "sha256", serialize = FALSE)
fixture$development_checkpoint$source_ledger_sha256 <- digest::digest(file =
  fixture$development_checkpoint$source_ledger, algo = "sha256", serialize = FALSE)
fixture$development_checkpoint$original_db_sha256 <- digest::digest(file =
  file.path(fixture$source_bundle, "db/app.sqlite"), algo = "sha256", serialize = FALSE)
saveRDS(fixture, args[[2L]])
cat("MANIFEST_BATCH_LIFECYCLE_RECORD installed=", find.package("scworkbench"),
  " source=", fixture$source_bundle, " original_axes=90000 source_utf8_bytes=18258618",
  " source_closure_function_sha256=", fixture$development_checkpoint$source_closure_function_sha256,
  " qualification=FALSE native_matrix_dispatch=disabled\n", sep = "")
