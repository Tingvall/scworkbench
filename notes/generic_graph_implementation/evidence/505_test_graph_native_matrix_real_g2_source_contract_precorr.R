test_graph_native_matrix_real_promoted_g2_source_contract <- function() {
  library_dir <- tempfile("native_real_g2_library_"); dir.create(library_dir)
  old <- .libPaths(); root <- tempfile("native_real_g2_bundle_"); bundle <- result <- NULL
  on.exit({
    try(wb_operation_pack_unload("scwbrna"), silent = TRUE)
    if (!is.null(result)) try(wb_session_discard(result$session), silent = TRUE)
    if (!is.null(bundle)) try(wb_close_bundle(bundle), silent = TRUE)
    .libPaths(old); unlink(c(root, library_dir), recursive = TRUE)
  }, add = TRUE)
  pack <- "/home/dirk/Projects/operation_packs/scwbRNA"
  stopifnot(identical(system2("git", c("-C", pack, "rev-parse", "HEAD"), stdout = TRUE)[[1L]],
    "151dd29211b219343dce6247c5e48fc932b4c83d"))
  log <- tempfile("native_real_g2_install_")
  status <- system2(file.path(R.home("bin"), "R"), c("CMD", "INSTALL",
    paste0("--library=", shQuote(library_dir)), shQuote(pack)), stdout = log, stderr = log)
  if (status != 0L) stop(paste(readLines(log), collapse = "\n"))
  .libPaths(c(library_dir, old))
  wb_operation_pack_load("scwbRNA", lib.loc = library_dir)
  bundle <- wb_init_bundle(root)
  cells <- c("c2", "c1", "c3"); features <- c("g2", "g1")
  wb_define_cells(bundle, cells)
  wb_attach_matrix(bundle, "RNA", Matrix::Matrix(matrix(1:6, 2L,
    dimnames = list(features, cells)), sparse = TRUE))
  result <- wb_session_run_op(wb_session_new(), bundle, "scwbrna::matrix_log_normalize",
    inputs = list(matrix = "RNA", output_matrix_id = "RNA_log", min_cells = 1L, chunk_size = 2L))
  ref <- wb_ref_run(result$run$run_id, "matrix")
  policy <- scworkbench:::.wb_graph_budgets(list(memory_bytes = "8388608",
    partition_bytes = 262144L, partition_rows = 256L, collect_bytes = 4194304L,
    sqlite_cache_kib = 2048L))
  error <- tryCatch(scworkbench:::.wb_graph_matrix_retained_selector(bundle, "RNA_log", policy, ref),
    error = identity)
  stopifnot(inherits(error, "wb_graph_error"), error$code == "GRAPH_SOURCE_AUTHORITY_REQUIRED",
    "RNA_log" %in% wb_matrices(result$session$staging_bundle)$matrix_id,
    !"RNA_log" %in% wb_matrices(bundle)$matrix_id)
  wb_session_promote_current(bundle, result$session, outputs = "summary")
  stopifnot(DBI::dbGetQuery(bundle$con, "SELECT COUNT(*) n FROM matrix_cells WHERE matrix_id='RNA_log';")$n[[1L]] == 0L,
    identical(wb_cells_with_matrix(bundle, "RNA_log"), cells))
  selected <- scworkbench:::.wb_graph_matrix_retained_selector(bundle, "RNA_log", policy, ref)
  snapshot <- scworkbench:::.wb_graph_matrix_retained_snapshot(bundle, selected, policy)
  for (axis in c("cell", "feature")) {
    source <- list(kind = "matrix", source_id = "RNA_log")
    axes <- scworkbench:::.wb_graph_source_axis_hash(bundle, source, axis, policy)
    binding <- c(list(binding_id = paste0(axis, "_source"), axis_kind = axis, source_ref = source,
      source_snapshot_identity = snapshot$source_snapshot_identity),
      axes[c("axis_content_identity", "axis_order_identity")])
    actual <- scworkbench:::.wb_graph_native_matrix_source_authorize(bundle, binding, policy)
    stopifnot(identical(actual$source_payload_closure_identity, snapshot$source_payload_closure_identity),
      actual$axis_count == if (axis == "cell") "3" else "2",
      selected$run_id == result$run$run_id, selected$output_name == "matrix")
  }
  cat("GRAPH_NATIVE_REAL_G2 public_normalize=PASS public_matrix_promotion=PASS",
    " exact_run_output=PASS unused_source_authority_cells=3 features=2 native_dispatch=DISABLED\n")
  TRUE
}
