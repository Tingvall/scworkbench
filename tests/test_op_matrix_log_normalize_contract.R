test_op_matrix_log_normalize_contract <- function() {
  if (!requireNamespace("BPCells", quietly = TRUE)) {
    message("Skipping matrix_log_normalize contract test: BPCells not installed.")
    return(TRUE)
  }

  tmp <- tempfile("scwb_matrix_log_normalize_")
  b <- wb_init_bundle(tmp, overwrite = TRUE)
  on.exit({
    wb_close_bundle(b)
    unlink(tmp, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  cells <- paste0("c", seq_len(3))
  wb_define_cells(b, cells)

  mat <- Matrix::Matrix(
    matrix(
      c(
        1, 0, 3,
        0, 2, 4
      ),
      nrow = 2,
      byrow = TRUE,
      dimnames = list(c("g1", "g2"), cells)
    ),
    sparse = TRUE
  )
  wb_attach_matrix(b, matrix_id = "RNA_counts", mat = mat, feature_type = "gene")

  rr <- wb_session_run_op(
    session = wb_session_new(),
    bundle = b,
    op_name = "matrix_log_normalize",
    inputs = list(
      matrix = "RNA_counts",
      cell_set = "all",
      min_cells = 1L,
      output_matrix_id = "RNA_log1p_cp10k",
      scale_factor = 10000,
      overwrite = TRUE
    )
  )

  stopifnot(identical(as.character(rr$run$outputs$matrix$kind), "matrix"))
  stopifnot(identical(as.character(rr$run$outputs$matrix$matrix_id), "RNA_log1p_cp10k"))
  stopifnot(identical(as.character(rr$run$outputs$summary$table_type), "matrix_log_normalize_summary"))

  mats <- wb_matrices(b)
  stopifnot("RNA_log1p_cp10k" %in% as.character(mats$matrix_id))

  got <- as.matrix(wb_slice(b, matrix_id = "RNA_log1p_cp10k", features = c("g1", "g2"), cells = cells))
  lib_size <- as.numeric(Matrix::colSums(mat))
  expected <- log1p(t(t(as.matrix(mat)) / lib_size * 10000))
  dimnames(expected) <- dimnames(mat)
  stopifnot(isTRUE(all.equal(got, expected, tolerance = 1e-8, check.attributes = FALSE)))

  summary <- rr$run$outputs$summary$table
  stopifnot(identical(as.character(summary$output_matrix_id[1]), "RNA_log1p_cp10k"))
  stopifnot(identical(as.character(summary$source_matrix_id[1]), "RNA_counts"))
  stopifnot(identical(as.integer(summary$n_features[1]), 2L))
  stopifnot(identical(as.integer(summary$n_cells[1]), 3L))
  stopifnot(identical(as.integer(summary$n_zero_library_cells[1]), 0L))

  err <- try(
    wb_session_run_op(
      session = wb_session_new(),
      bundle = b,
      op_name = "matrix_log_normalize",
      inputs = list(
        matrix = "RNA_counts",
        cell_set = "all",
        min_cells = 1L,
        output_matrix_id = "RNA_log1p_cp10k",
        scale_factor = 10000,
        overwrite = FALSE
      )
    ),
    silent = TRUE
  )
  stopifnot(inherits(err, "try-error"))

  TRUE
}
