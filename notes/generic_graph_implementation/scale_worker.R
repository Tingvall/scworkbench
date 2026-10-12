# Installed-candidate lifecycle driver. Pack author code is in the fixture
# package; this recipient/operator orchestrates through public engine surfaces.
args <- commandArgs(TRUE)
stopifnot(length(args) == 4L)
main <- function(args) {
fixture <- readRDS(args[[1L]])
.libPaths(c(fixture$core_library, .libPaths()))
library(scworkbench)
expected_library <- Sys.getenv("SCWB_SCALE_EXPECTED_CORE_LIBRARY", "")
if (nzchar(expected_library)) stopifnot(
  identical(normalizePath(fixture$core_library), normalizePath(expected_library)),
  identical(normalizePath(find.package("scworkbench")),
    normalizePath(file.path(expected_library, "scworkbench"))))
expected_runtime_hash <- Sys.getenv("SCWB_SCALE_EXPECTED_SOURCE_CLOSURE_SHA256", "")
if (nzchar(expected_runtime_hash)) {
  actual_runtime_hash <- digest::digest(paste(deparse(body(getFromNamespace(
    ".wb_graph_object_closure", "scworkbench"))), collapse = "\n"),
    algo = "sha256", serialize = FALSE)
  stopifnot(identical(actual_runtime_hash, expected_runtime_hash))
  cat("GRAPH_SCALE_EXACT_RUNTIME source_closure_function_sha256=", actual_runtime_hash,
    " installed_package=", find.package("scworkbench"), "\n", sep = "")
}
output <- args[[2L]]; count <- as.integer(args[[3L]]); mode <- args[[4L]]
stopifnot(mode %in% c("baseline", "run", "fault", "inspect"))
cells <- function(i) if (i == 1L) "cell_2" else if (i == 2L) "cell_10" else
  if (i == 3L) "cell_1" else paste0("cell_", i + 100L, "_", strrep("a", 192L))
if (mode == "inspect") {
  record <- readRDS(file.path(output, "promoted.rds"))
  stopifnot(!"graphscalefixt::stream_graph" %in% wb_list_ops())
  fingerprint <- function() {
    paths <- sort(list.files(record$relocated, recursive = TRUE, all.files = TRUE,
      full.names = TRUE, no.. = TRUE), method = "radix")
    paths <- paths[!file.info(paths)$isdir]
    stats::setNames(vapply(paths, function(path) digest::digest(file = path,
      algo = "sha256", serialize = FALSE), character(1)),
      substring(paths, nchar(record$relocated) + 2L))
  }
  filesystem_before <- fingerprint()
  bundle <- wb_open_bundle(record$relocated, read_only = TRUE)
  on.exit(wb_close_bundle(bundle), add = TRUE)
  before <- wb_manifest(bundle)
  budgets <- list(memory_bytes = "8388608", sqlite_cache_kib = 2048L,
    partition_bytes = 262144, partition_rows = 256L, collect_bytes = 4194304)
  info <- wb_art_graph_info(bundle, record$artifact_id, budgets = budgets)
  stopifnot(info$source_authority$status == "verified",
    identical(info$descriptor_identity, record$descriptor_identity),
    identical(info$component_counts$nodes, as.character(count)),
    identical(info$component_counts$binding_mappings, as.character(count)))
  for (component in names(info$component_counts)) {
    offset <- 0L
    repeat {
      part <- wb_art_graph_slice(bundle, record$artifact_id, component,
        as.character(offset), 512L, 262144)
      if (!length(part)) break
      if (component == "nodes") for (i in seq_along(part))
        stopifnot(part[[i]]$node_id == cells(offset + i))
      if (component == "binding_mappings") for (i in seq_along(part))
        stopifnot(part[[i]]$node_id == cells(offset + i), part[[i]]$axis_id == cells(offset + i))
      offset <- offset + length(part)
    }
    stopifnot(as.character(offset) == info$component_counts[[component]])
  }
  stopifnot(identical(wb_manifest(bundle), before))
  wb_close_bundle(bundle); bundle <- NULL
  stopifnot(identical(filesystem_before, fingerprint()))
  cat("GRAPH_SCALE_REOPEN process_replaced=TRUE pack_free=TRUE source_verified=TRUE descriptor_unchanged=TRUE bounded_components=PASS filesystem_fingerprint_unchanged=TRUE\n")
  quit(status = 0L)
}

stopifnot(!file.exists(output)); dir.create(output)
destination <- file.path(output, "destination.bundle")
stopifnot(file.copy(fixture$source_bundle, output, recursive = TRUE))
stopifnot(file.rename(file.path(output, basename(fixture$source_bundle)), destination))
.libPaths(c(fixture$pack_library, .libPaths()))
wb_operation_pack_load("scwbGraphScaleFixture")
bundle <- wb_open_bundle(destination)
on.exit(try(wb_close_bundle(bundle), silent = TRUE), add = TRUE)
# Repeated baseline processes run this same source authentication and engine
# lifecycle. Source arrays are never loaded by the graph input reference.
gc(FALSE)
before <- wb_art_list(bundle)
manifest_before <- wb_manifest(bundle)
private_before <- sort(list.files(tempdir(), pattern = "^scwb_graph_(stage_|identity_|tokens_)", full.names = TRUE))
sessions_before <- sort(list.dirs(file.path(tempdir(), "scworkbench_sessions"), recursive = FALSE))
started <- proc.time()
if (identical(Sys.getenv("SCWB_SCALE_MANIFEST_TRACE"), "1"))
  options(scworkbench.manifest_test_hook = function(event, final = NULL, ...) {
    if (event == "published" && !is.null(final) && startsWith(final, destination))
      print(sys.calls())
  })
result <- tryCatch(wb_session_run_op(wb_session_new(), bundle,
  "graphscalefixt::stream_graph", inputs = list(source = wb_ref_artifact(fixture$seed_graph_artifact_id, "result"),
    nodes = count, fault = if (mode == "fault") "binding_mappings" else "none")),
  error = identity)
if (mode == "fault") {
  manifest_after <- wb_manifest(bundle)
  if (!identical(manifest_after, manifest_before)) {
    print(all.equal(manifest_before, manifest_after))
    saveRDS(list(before = manifest_before, after = manifest_after),
      file.path(output, "fault_manifest_diagnostic.rds"))
  }
  stopifnot(inherits(result, "error"),
    grepl("GRAPH_SCALE injected late application failure", conditionMessage(result), fixed = TRUE),
    identical(wb_art_list(bundle), before), identical(wb_manifest(bundle), manifest_before),
    identical(sort(list.files(tempdir(), pattern = "^scwb_graph_(stage_|identity_|tokens_)", full.names = TRUE)), private_before),
    identical(sort(list.dirs(file.path(tempdir(), "scworkbench_sessions"), recursive = FALSE)), sessions_before))
  cat("GRAPH_SCALE_LATE_FAULT expected_failure=TRUE committed_inventory_unchanged=TRUE private_stage_spill_session_residue=0\n")
  quit(status = 0L)
}
if (inherits(result, "error")) stop(result)
identity <- result$run$outputs$result$descriptor_identity
promotion <- wb_session_promote_current(bundle, result$session, outputs = "result")
stopifnot(nrow(promotion$promoted) == 2L)
artifact <- as.character(promotion$promoted$artifact_id[promotion$promoted$output == "result"][[1L]])
info <- wb_art_graph_info(bundle, artifact, budgets = list(memory_bytes = "8388608",
  sqlite_cache_kib = 2048L, partition_bytes = 262144, partition_rows = 256L, collect_bytes = 4194304))
stopifnot(identical(info$descriptor_identity, identity), info$source_authority$status == "verified")
wb_session_discard(result$session)
stopifnot(wb_finalize_recipient_bundle(bundle)$ready)
wb_close_bundle(bundle); bundle <- NULL
relocated <- file.path(output, "relocated.bundle")
stopifnot(file.rename(destination, relocated))
saveRDS(list(artifact_id = artifact, descriptor_identity = identity, relocated = relocated,
  canonical_bytes = info$canonical_bytes, component_counts = info$component_counts,
  elapsed = unname((proc.time() - started)[["elapsed"]])), file.path(output, "promoted.rds"))
cat("GRAPH_SCALE_LIFECYCLE canonical_bytes=", info$canonical_bytes,
  " nodes=", count, " mixed_closure=2 promote_finalize_relocate=PASS reopen=pending_separate_process\n", sep = "")
}
main(args)
