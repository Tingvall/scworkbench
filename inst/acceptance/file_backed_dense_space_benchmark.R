#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
arg <- function(name, default = "") {
  hit <- grep(paste0("^--", name, "="), args, value = TRUE)
  if (length(hit)) sub(paste0("^--", name, "="), "", hit[[1L]]) else default
}
historical <- arg("historical", "/home/dirk/Projects/lymphocyte_trajectory/operator_tests/rc25_honeybee_operator_a/GSE270605_honeybee_brain_10x_bundle")
output <- arg("output", "")
source_root <- Sys.getenv("SCWORKBENCH_SOURCE_ROOT", unset = "")
if (nzchar(source_root)) devtools::load_all(source_root, quiet = TRUE) else library(scworkbench)
stopifnot(dir.exists(historical), requireNamespace("rhdf5", quietly = TRUE), requireNamespace("jsonlite", quietly = TRUE))

tree_bytes <- function(path) {
  files <- list.files(path, recursive = TRUE, all.files = TRUE, full.names = TRUE, no.. = TRUE)
  files <- files[file.exists(files) & !dir.exists(files)]
  sum(file.info(files)$size, na.rm = TRUE)
}
peak_mb <- function() scworkbench:::.wb_validation_process_memory()$peak_rss_mb
measure <- function(expr) {
  gc(); before <- peak_mb(); elapsed <- system.time(value <- force(expr))[["elapsed"]]
  list(value = value, elapsed_seconds = unname(elapsed), process_peak_rss_mb = peak_mb(),
       incremental_peak_rss_mb = max(0, peak_mb() - before))
}
table_rows <- function(con, table) {
  if (!table %in% DBI::dbListTables(con)) return(0)
  as.numeric(DBI::dbGetQuery(con, paste0("SELECT COUNT(*) AS n FROM ", DBI::dbQuoteIdentifier(con, table)))$n[[1L]])
}

# The historical fixture is measured through a read-only SQLite connection and
# is never opened as a mutable scworkbench bundle.
manifest <- jsonlite::read_json(file.path(historical, "manifest.json"), simplifyVector = TRUE)
old_db <- file.path(historical, as.character(manifest$storage$sqlite$path))
old_con <- DBI::dbConnect(RSQLite::SQLite(), paste0("file:", normalizePath(old_db, winslash = "/", mustWork = TRUE), "?immutable=1"), flags = RSQLite::SQLITE_RO)
on.exit(try(DBI::dbDisconnect(old_con), silent = TRUE), add = TRUE)
old_rows <- setNames(vapply(c("space_coords", "space_2d", "artifact_space_2d"), function(x) table_rows(old_con, x), numeric(1)),
                     c("space_coords", "space_2d", "artifact_space_2d"))
old_cells <- DBI::dbGetQuery(old_con, "SELECT cell_id FROM cells ORDER BY rowid")$cell_id
stopifnot(length(old_cells) == 120895L, !anyDuplicated(old_cells))
historical_measurements <- list(
  path = normalizePath(historical, winslash = "/", mustWork = TRUE),
  sqlite_bytes = unname(file.info(old_db)$size), total_bundle_bytes = tree_bytes(historical),
  coordinate_value_rows = as.list(old_rows)
)
DBI::dbDisconnect(old_con); old_con <- NULL

benchmark_parent <- tempfile("scwb_dense_benchmark_"); dir.create(benchmark_parent)
on.exit(unlink(benchmark_parent, recursive = TRUE, force = TRUE), add = TRUE)
bundle_dir <- file.path(benchmark_parent, "honeybee_dense_space_bundle")
b <- wb_init_bundle(bundle_dir, overwrite = TRUE)
on.exit(try(wb_close_bundle(b), silent = TRUE), add = TRUE)
wb_define_cells(b, old_cells)

make_coords <- function(n_dims, phase) {
  x <- matrix(sin((seq_len(length(old_cells) * n_dims) + phase) / 997), nrow = length(old_cells), ncol = n_dims)
  rownames(x) <- old_cells; colnames(x) <- paste0("dim_", seq_len(n_dims)); x
}
writes <- list()
for (spec in list(c("benchmark.pca50", 50L, 11L), c("benchmark.latent30", 30L, 23L), c("benchmark.umap2", 2L, 37L))) {
  id <- spec[[1L]]; dims <- as.integer(spec[[2L]]); coords <- make_coords(dims, as.integer(spec[[3L]]))
  writes[[id]] <- measure(wb_add_space(b, id, coords, source = "honeybee-scale-benchmark"))[c("elapsed_seconds", "process_peak_rss_mb", "incremental_peak_rss_mb")]
  rm(coords); gc()
}

subset_ids <- old_cells[seq.int(1L, length(old_cells), length.out = 100L)]
subset_read <- measure(wb_space(b, "benchmark.pca50", cells = subset_ids, dims = c(1L, 7L, 19L, 33L, 50L)))
subset_evidence <- attr(subset_read$value, "scworkbench_payload_read")
stopifnot(subset_evidence$values_read == 500L, subset_evidence$total_values == length(old_cells) * 50L)
subset_read$value <- NULL
full_read <- measure(wb_space(b, "benchmark.pca50")); stopifnot(nrow(full_read$value) == length(old_cells), ncol(full_read$value) == 50L)
full_read$value <- NULL; gc()

# Exercise actual session-overlay payload publication and closure-aware
# promotion without paying for another model fit.
staged <- scworkbench:::.wb_session_stage_bundle(b, wb_session_new())
s <- staged$session; sb <- staged$bundle; promotion_space <- "benchmark.promoted2"
promotion_coords <- make_coords(2L, 71L)
run <- wb_new_run("umap_fit", inputs = list(cell_set = "all", parents = character(), user_inputs = list()),
                  outputs = list(space_2d = wb_prim_space_2d(promotion_space)))
scworkbench:::.wb_with_mutation_context(sb, route = "session_execution", run_id = run$run_id, op_name = "umap_fit", code = {
  wb_add_space(sb, promotion_space, promotion_coords, source = "honeybee-scale-benchmark-promotion")
})
rm(promotion_coords); s <- wb_session_add_run(s, run); s <- wb_session_set_active(s, "space_2d", wb_ref_run(run$run_id, "space_2d"))
promotion <- measure(wb_session_promote_current(b, s, outputs = "space_2d", created_by = "forge-dense-space-benchmark"))
stopifnot(any(promotion$value$promoted$status == "ok"), promotion_space %in% wb_spaces(b)$space_id)
promotion$value <- NULL

validation <- list()
for (level in c("structural", "content")) {
  report <- wb_bundle_validation_report(bundle_dir, level = level)
  stopifnot(isTRUE(report$ok))
  validation[[level]] <- list(elapsed_seconds = report$elapsed_seconds, process_peak_rss_mb = report$process_peak_rss_mb, status = report$status)
}

# PyBench v2 lightweight writable audit. Its session staging and complete-tree
# pre/post audit are intentionally measured separately from HDF5 getter cost.
python <- Sys.getenv("SCWORKBENCH_PYBENCH_PYTHON", unset = scworkbench:::.wb_pybench_default_python())
stopifnot(file.exists(python))
Sys.setenv(SCWORKBENCH_PYBENCH_PYTHON = python)
py_workspace <- file.path(benchmark_parent, "pybench_sessions")
bytes_before_pybench <- tree_bytes(benchmark_parent)
pybench <- measure({
  ps <- wb_session_create(b, py_workspace, "dense_benchmark_hello")
  wb_session_run_op(ps, b, "py_protocol_hello", inputs = list(cell_set = "all", n_preview = 25L, min_cells = 1L))
})
bytes_after_pybench <- tree_bytes(benchmark_parent)
py_stage_bytes <- tree_bytes(pybench$value$session$durable$workspace)
wb_session_discard(pybench$value$session); pybench$value <- NULL

wb_finalize_recipient_bundle(b); wb_close_bundle(b); b <- NULL
recipient <- wb_bundle_validation_report(bundle_dir, level = "recipient")
stopifnot(isTRUE(recipient$ok), identical(recipient$pre_validation_fingerprint, recipient$post_validation_fingerprint))

db_path <- file.path(bundle_dir, "db", "app.sqlite")
payload_files <- list.files(file.path(bundle_dir, "space_payloads"), pattern = "[.]h5$", full.names = TRUE)
payload_bytes <- sum(file.info(payload_files)$size)
raw_numeric_bytes <- length(old_cells) * (50L + 30L) * 8
duplicated_id_bytes <- 2 * sum(nchar(old_cells, type = "bytes"))
con <- DBI::dbConnect(RSQLite::SQLite(), paste0("file:", normalizePath(db_path, winslash = "/", mustWork = TRUE), "?immutable=1"), flags = RSQLite::SQLITE_RO)
new_rows <- setNames(vapply(c("space_coords", "space_2d", "artifact_space_2d"), function(x) table_rows(con, x), numeric(1)),
                     c("space_coords", "space_2d", "artifact_space_2d"))
registry_rows <- table_rows(con, "space_payloads"); DBI::dbDisconnect(con)
stopifnot(sum(new_rows) == 0, registry_rows == 4L)

result <- list(
  schema_version = "scworkbench.file_backed_dense_space_benchmark.v1",
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%OS6%z"),
  fixture = list(n_cells = length(old_cells), dimensions = c(pca = 50L, latent = 30L, umap = 2L), historical = historical_measurements),
  new_bundle = list(
    sqlite_bytes = unname(file.info(db_path)$size), total_bundle_bytes = tree_bytes(bundle_dir),
    coordinate_payload_bytes = payload_bytes, coordinate_value_rows = as.list(new_rows), space_payload_registry_rows = registry_rows,
    pca50_plus_latent30_raw_numeric_bytes = raw_numeric_bytes,
    duplicated_ordered_cell_identity_bytes = duplicated_id_bytes,
    payload_to_raw_numeric_plus_identity_multiplier = payload_bytes / (raw_numeric_bytes + duplicated_id_bytes),
    multiplier_scope = "Conservative upper bound: numerator includes the two additional 2D payloads; denominator is 50D+30D numeric bytes plus their two ordered cell-ID vectors."
  ),
  write = writes,
  getter = list(
    full_50d = full_read[c("elapsed_seconds", "process_peak_rss_mb", "incremental_peak_rss_mb")],
    subset_100_cells_5_dims = c(subset_read[c("elapsed_seconds", "process_peak_rss_mb", "incremental_peak_rss_mb")],
                                 list(values_read = subset_evidence$values_read, total_values = subset_evidence$total_values,
                                      estimated_coordinate_bytes_read = subset_evidence$values_read * 8,
                                      bounded_fraction = subset_evidence$values_read / subset_evidence$total_values))
  ),
  promotion = promotion[c("elapsed_seconds", "process_peak_rss_mb", "incremental_peak_rss_mb")],
  validation = c(validation, list(recipient = list(elapsed_seconds = recipient$elapsed_seconds, process_peak_rss_mb = recipient$process_peak_rss_mb, status = recipient$status))),
  pybench_lightweight_writable_audit = list(
    operation = "py_protocol_hello", elapsed_seconds = pybench$elapsed_seconds,
    process_peak_rss_mb = pybench$process_peak_rss_mb, incremental_peak_rss_mb = pybench$incremental_peak_rss_mb,
    source_tree_bytes_read_lower_bound = bytes_before_pybench,
    temporary_workspace_apparent_bytes_high_water = py_stage_bytes,
    tree_bytes_written_delta = bytes_after_pybench - bytes_before_pybench,
    clone_behavior = "session source snapshot plus mutable-tree link/reflink/copy strategy; complete payload tree hashing remains",
    reflink_unavailable_boundary = "No reflink availability is assumed; apparent workspace bytes and elapsed time are reported without claiming physical block sharing."
  ),
  portability = list(
    hdf5_boundary = "HDF5 dimension metadata and coordinate arrays are written in reversed C-order by PyBench so rhdf5 exposes the canonical R n_cells-by-n_dims order; R writes its canonical order directly through rhdf5.",
    dtype = "IEEE-754 float64 little-endian", ordered_cell_identity = "UTF-8 variable-length strings in canonical payload row order"
  ),
  conclusion = list(
    sqlite_coordinate_rows_zero = sum(new_rows) == 0,
    bounded_subset_read = subset_evidence$values_read < subset_evidence$total_values,
    remaining_pybench_boundary = "Complete-payload hashing and full mutable-tree clone/audit overhead remain outside the dense-space relational-row removal."
  )
)
json <- jsonlite::toJSON(result, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = 16)
if (nzchar(output)) writeLines(json, output, useBytes = TRUE) else cat(json, "\n")
cat("FILE_BACKED_DENSE_SPACE_BENCHMARK_OK\n")
