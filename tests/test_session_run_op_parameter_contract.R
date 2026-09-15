test_session_run_op_parameter_contract <- function() {
  contract_test_activate_core_conformance_pack()
  tmp <- tempfile("scwb_session_params_")
  b <- wb_init_bundle(tmp, overwrite = TRUE)
  on.exit({
    try(wb_close_bundle(b), silent = TRUE)
    unlink(tmp, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  cells <- paste0("c", seq_len(12))
  features <- paste0("g", seq_len(4))
  wb_define_cells(b, cells)
  counts <- Matrix::Matrix(
    matrix(c(
      rep(c(4, 0), each = 6),
      rep(c(0, 3), each = 6),
      rep(1, 12),
      rep(c(0, 2), each = 6)
    ), nrow = 4, byrow = TRUE,
    dimnames = list(features, cells)),
    sparse = TRUE
  )
  wb_attach_matrix(b, "RNA_counts", counts, feature_type = "gene")
  cluster_values <- stats::setNames(rep(c("A", "B"), each = 6), cells)

  rejected <- try(
    wb_session_run_op(
      wb_session_new(), b, "scwbv2reference::feature_table_from_matrix",
      inputs = list(matrix = "RNA_counts", labels = wb_prim_cell_vector(cluster_values), cell_set = "all"),
      selected_features = features[1:2], result_limit = 1
    ),
    silent = TRUE
  )
  stopifnot(inherits(rejected, "try-error"))
  stopifnot(grepl("supplied in inputs", as.character(rejected), fixed = TRUE))

  started <- Sys.time()
  rr <- wb_session_run_op(
    wb_session_new(), b, "scwbv2reference::feature_table_from_matrix",
    inputs = list(
      matrix = "RNA_counts",
      labels = wb_prim_cell_vector(cluster_values),
      cell_set = "all",
      min_cells = 1L,
      selected_features = features[1:2],
      result_limit = 1
    )
  )
  elapsed <- as.numeric(difftime(Sys.time(), started, units = "secs"))
  result <- rr$run$outputs$result$table
  stopifnot(identical(rr$run$params$result_limit, 1L))
  stopifnot(identical(rr$run$inputs$user_inputs$result_limit, 1L))
  stopifnot(identical(rr$run$inputs$user_inputs$min_cells, 1L))
  stopifnot(identical(as.integer(rr$run$params$selected_feature_count), 2L))
  stopifnot(identical(as.integer(rr$run$params$n_results), nrow(result)))
  stopifnot(is.finite(elapsed) && elapsed < 30)
  TRUE
}
