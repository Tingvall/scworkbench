test_op_feature_trend_spearman_chunking_contract <- function() {
  tmp <- tempfile("scwb_feature_trend_chunk_")
  b <- wb_init_bundle(tmp, overwrite = TRUE)
  on.exit(wb_close_bundle(b), add = TRUE)

  cells <- paste0("c", seq_len(12))
  wb_define_cells(b, cells)

  pt <- stats::setNames(seq_len(length(cells)), cells)
  mat <- Matrix::Matrix(
    rbind(
      seq_len(12),               # strong up
      rev(seq_len(12)),          # strong down
      rep(c(0, 1), 6),           # patterned
      rep(c(1, 0), 6),           # patterned inverse
      c(rep(0, 6), rep(5, 6)),   # step up
      c(rep(5, 6), rep(0, 6))    # step down
    ),
    sparse = TRUE,
    dimnames = list(paste0("g", seq_len(6)), cells)
  )
  wb_attach_matrix(b, matrix_id = "RNA_counts", mat = mat, feature_type = "gene")

  s0 <- wb_session_new()
  r1 <- wb_session_run_op(
    session = s0,
    bundle = b,
    op_name = "feature_trend_spearman",
    inputs = list(
      matrix = "RNA_counts",
      pseudotime = wb_prim_cell_vector(pt, value_type = "continuous"),
      cell_set = "all",
      min_cells = 1L,
      features = paste0("g", seq_len(6)),
      min_pct_nonzero = 0,
      min_sd = 0,
      p_adjust_method = "BH",
      chunk_size = 128L
    )
  )

  s1 <- wb_session_new()
  r2 <- wb_session_run_op(
    session = s1,
    bundle = b,
    op_name = "feature_trend_spearman",
    inputs = list(
      matrix = "RNA_counts",
      pseudotime = wb_prim_cell_vector(pt, value_type = "continuous"),
      cell_set = "all",
      min_cells = 1L,
      features = paste0("g", seq_len(6)),
      min_pct_nonzero = 0,
      min_sd = 0,
      p_adjust_method = "BH",
      chunk_size = 2L
    )
  )

  t1 <- r1$run$outputs$trend_table$table
  t2 <- r2$run$outputs$trend_table$table
  t1 <- t1[order(t1$feature_id), , drop = FALSE]
  t2 <- t2[order(t2$feature_id), , drop = FALSE]
  rownames(t1) <- NULL
  rownames(t2) <- NULL

  stopifnot(identical(as.character(t1$feature_id), as.character(t2$feature_id)))
  stopifnot(isTRUE(all.equal(t1, t2, tolerance = 1e-12, check.attributes = FALSE)))

  stopifnot(is.list(r2$run$params$chunking))
  stopifnot(isTRUE(r2$run$params$chunking$enabled))
  stopifnot(identical(as.character(r2$run$params$chunking$axis), "features"))
  stopifnot(identical(as.integer(r2$run$params$chunking$chunk_size), 2L))
  stopifnot(identical(as.integer(r2$run$params$chunking$n_chunks), 3L))

  iface <- wb_op_interface("feature_trend_spearman")
  stopifnot(is.list(iface$chunking))
  stopifnot(identical(as.character(iface$chunking$status), "implemented_generic"))

  TRUE
}
