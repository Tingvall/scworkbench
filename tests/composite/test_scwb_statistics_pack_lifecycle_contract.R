.statistics_fixture <- function(prefix = "scwb_statistics_") {
  root <- tempfile(prefix)
  bundle <- wb_init_bundle(root, overwrite = TRUE)
  cells <- paste0("cell_", sprintf("%02d", seq_len(12L)))
  features <- paste0("gene_", seq_len(5L))
  values <- matrix(c(
    0:11, 11:0, rep(c(0, 1), 6L), rep(c(2, 2, 3), 4L), rep(1, 12L)
  ), nrow = 5L, byrow = TRUE, dimnames = list(features, cells))
  wb_define_cells(bundle, cells, metadata = data.frame(
    cell_id = cells, forward = seq_along(cells),
    reverse = rev(seq_along(cells)), group = rep(c("A", "B"), each = 6L),
    stringsAsFactors = FALSE))
  wb_attach_matrix(bundle, "RNA_counts", values, feature_type = "gene")
  list(root = root, bundle = bundle, cells = cells, features = features,
    continuous = wb_prim_cell_vector(stats::setNames(seq_along(cells), cells),
      value_type = "continuous"),
    reverse = wb_prim_cell_vector(stats::setNames(rev(seq_along(cells)), cells),
      value_type = "continuous"),
    groups = wb_prim_cell_vector(stats::setNames(rep(c("A", "B"), each = 6L), cells),
      value_type = "categorical"),
    groups_b = wb_prim_cell_vector(stats::setNames(rep(c("X", "Y"), 6L), cells),
      value_type = "categorical"))
}

.statistics_run <- function(bundle, op_name, inputs) {
  wb_session_run_op(wb_session_new(), bundle, op_name,
    inputs = utils::modifyList(list(cell_set = "all", min_cells = 1L), inputs))
}

test_six_operation_qualified_name_and_receipt_smoke <- function() {
  contract_test_activate_statistics_pack()
  fixture <- .statistics_fixture("scwb_statistics_execution_")
  b <- fixture$bundle
  on.exit({
    try(wb_close_bundle(b), silent = TRUE)
    unlink(fixture$root, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  runs <- list(
    de = .statistics_run(b, "de_wilcox", list(matrix = "RNA_counts",
      group_a = fixture$cells[1:6], group_b = fixture$cells[7:12],
      min_pct = 0, p_adjust_method = "BH")),
    markers = .statistics_run(b, "markers_topn", list(matrix = "RNA_counts",
      clusters = fixture$groups, top_n = 2L, min_pct = 0,
      p_adjust_method = "BH")),
    assoc = .statistics_run(b, "cell_vector_assoc", list(
      vector_cont = fixture$continuous, vector_group = fixture$groups,
      min_n_per_group = 3L)),
    association = .statistics_run(b, "cell_vector_association", list(
      a = fixture$groups, b = fixture$groups_b, min_n_per_group = 3L,
      method = "auto")),
    compare = .statistics_run(b, "cell_vector_compare", list(
      a = fixture$continuous, b = fixture$reverse, compare_space = "rank",
      ties_method = "average", signal_a = "forward", signal_b = "reverse")),
    trend = .statistics_run(b, "feature_trend_spearman", list(
      matrix = "RNA_counts", pseudotime = fixture$continuous,
      min_pct_nonzero = 0, min_sd = 0, p_adjust_method = "BH",
      chunk_size = 2L))
  )
  qualified <- paste0("scwbstatistics::", c("de_wilcox", "markers_topn",
    "cell_vector_assoc", "cell_vector_association", "cell_vector_compare",
    "feature_trend_spearman"))
  stopifnot(identical(vapply(runs, function(x) x$run$op_name, character(1)),
    stats::setNames(qualified, names(runs))))
  stopifnot(all(vapply(runs, function(x) nzchar(as.character(
    x$result$operation_pack_transition$receipt_identity$sha256)), logical(1))))
  TRUE
}

test_promotion_replay_recipient <- function() {
  contract_test_activate_statistics_pack()
  fixture <- .statistics_fixture("scwb_statistics_recipient_")
  b <- fixture$bundle
  wb_close_bundle(b); b <- NULL
  clone_parent <- tempfile("scwb_statistics_source_clone_")
  dir.create(clone_parent)
  stopifnot(isTRUE(file.copy(fixture$root, clone_parent, recursive = TRUE)))
  source_clone <- file.path(clone_parent, basename(fixture$root))
  b <- wb_open_bundle(fixture$root)
  on.exit({
    try(wb_close_bundle(b), silent = TRUE)
    unlink(clone_parent, recursive = TRUE, force = TRUE)
    unlink(fixture$root, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  session <- wb_session_new()
  first <- wb_session_run_op(session, b, "metadata_cell_vector", inputs = list(
    source_column = "forward", vector_name = "forward",
    value_type = "continuous", missing_policy = "error", min_cells = 1L,
    overwrite = TRUE))
  session <- first$session
  second <- wb_session_run_op(session, b, "metadata_cell_vector", inputs = list(
    source_column = "reverse", vector_name = "reverse",
    value_type = "continuous", missing_policy = "error", min_cells = 1L,
    overwrite = TRUE))
  session <- second$session
  third <- wb_session_run_op(session, b, "metadata_cell_vector", inputs = list(
    source_column = "group", vector_name = "group",
    value_type = "categorical", missing_policy = "error", min_cells = 1L,
    overwrite = TRUE))
  session <- third$session
  de <- wb_session_run_op(session, b, "de_wilcox", inputs = list(
    matrix = "RNA_counts", group_a = fixture$cells[1:6],
    group_b = fixture$cells[7:12], min_pct = 0,
    p_adjust_method = "BH", min_cells = 1L))
  session <- de$session
  markers <- wb_session_run_op(session, b, "markers_topn", inputs = list(
    matrix = "RNA_counts", clusters = wb_ref_run(third$run$run_id, "vector"),
    top_n = 2L, min_pct = 0, p_adjust_method = "BH", min_cells = 1L))
  session <- markers$session
  predecessor <- wb_session_run_op(session, b, "cell_vector_assoc",
    inputs = list(vector_cont = wb_ref_run(first$run$run_id, "vector"),
      vector_group = wb_ref_run(third$run$run_id, "vector"),
      min_n_per_group = 3L, min_cells = 1L))
  session <- predecessor$session
  association <- wb_session_run_op(session, b, "cell_vector_association",
    inputs = list(a = wb_ref_run(first$run$run_id, "vector"),
      b = wb_ref_run(third$run$run_id, "vector"),
      min_n_per_group = 3L, method = "auto", min_cells = 1L))
  session <- association$session
  comparison <- wb_session_run_op(session, b, "cell_vector_compare",
    inputs = list(a = wb_ref_run(first$run$run_id, "vector"),
      b = wb_ref_run(second$run$run_id, "vector"),
      compare_space = "rank", ties_method = "average", min_cells = 1L))
  session <- comparison$session
  trend <- wb_session_run_op(session, b, "feature_trend_spearman",
    inputs = list(matrix = "RNA_counts",
      pseudotime = wb_ref_run(first$run$run_id, "vector"),
      min_pct_nonzero = 0, min_sd = 0, p_adjust_method = "BH",
      chunk_size = 2L, min_cells = 1L))
  session <- trend$session

  promoted <- wb_promote_analysis(
    bundle = b, runs = session$runs,
    head_run_id = c(first$run$run_id, second$run$run_id, third$run$run_id,
      de$run$run_id, markers$run$run_id, predecessor$run$run_id,
      association$run$run_id, comparison$run$run_id, trend$run$run_id),
    staging_bundle = wb_session_view(session), created_by = "contract")
  stopifnot(all(promoted$promoted$status == "ok"))
  snapshot_id <- as.character(promoted$provenance_snapshot_id)[1]
  sources <- as.character(wb_art_list(b)$source_op)
  stopifnot(all(paste0("scwbstatistics::", c(
    "de_wilcox", "markers_topn", "cell_vector_assoc",
    "cell_vector_association", "cell_vector_compare",
    "feature_trend_spearman")) %in% sources))

  replay <- wb_prov_validate_replay(b, snapshot_id = snapshot_id,
    mode = "symbolic", profile = "strict", strict = TRUE)
  stopifnot(isTRUE(replay$summary$valid), all(replay$per_run$status == "ok"))

  trend_artifact <- wb_art_list(b)
  trend_artifact <- as.character(trend_artifact$artifact_id[
    trend_artifact$source_op == "scwbstatistics::feature_trend_spearman"])[1]
  plan <- wb_target_reproduction_plan(b, paste0("artifact:", trend_artifact))
  stopifnot(identical(plan$status, "ok"), isTRUE(plan$reproducible))
  reproduced <- wb_target_execute_plan(plan, source_clone)
  stopifnot(identical(reproduced$status, "promoted_and_verified"),
    all(reproduced$verification$status == "passed"))
  reproduced_bundle <- wb_open_bundle(source_clone)
  stopifnot(isTRUE(wb_finalize_recipient_bundle(reproduced_bundle)$ready))
  wb_close_bundle(reproduced_bundle)

  stopifnot(isTRUE(wb_finalize_recipient_bundle(b)$ready))
  wb_close_bundle(b); b <- NULL

  writable <- wb_open_bundle(fixture$root)
  stopifnot(nrow(wb_art_list(writable)) == 12L)
  stopifnot(isTRUE(wb_finalize_recipient_bundle(writable)$ready))
  wb_close_bundle(writable)

  script <- tempfile("scwb_statistics_pack_free_", fileext = ".R")
  writeLines(c(
    paste0("devtools::load_all(", shQuote(normalizePath(".")), ", quiet=TRUE)"),
    "stopifnot(length(wb_list_ops()) == 43L)",
    paste0("root <- ", shQuote(fixture$root)),
    "stopifnot(isTRUE(wb_validate_bundle(root, read_only=TRUE)))",
    "bundle <- wb_open_bundle(root, validate=TRUE, read_only=TRUE)",
    "on.exit(wb_close_bundle(bundle), add=TRUE)",
    "artifacts <- wb_art_list(bundle)",
    "stopifnot(nrow(artifacts) == 12L)",
    "for (id in artifacts$artifact_id) stopifnot(inherits(wb_art_load(bundle, id), 'wb_primitive'))",
    "missing <- tryCatch(scworkbench:::.wb_op('cell_vector_compare'), error=identity)",
    "stopifnot(inherits(missing, 'wb_operation_pack_error'), identical(missing$code, 'OPERATION_PACK_REQUIRED'))",
    "cat('SCWBSTATISTICS_PACK_FREE_RECIPIENT_OK artifacts=12\\n')"
  ), script, useBytes = TRUE)
  output <- system2(file.path(R.home("bin"), "Rscript"), c("--vanilla", script),
    stdout = TRUE, stderr = TRUE)
  status <- attr(output, "status") %||% 0L
  stopifnot(identical(as.integer(status), 0L),
    any(grepl("SCWBSTATISTICS_PACK_FREE_RECIPIENT_OK", output, fixed = TRUE)))
  TRUE
}
