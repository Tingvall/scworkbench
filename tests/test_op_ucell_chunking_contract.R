test_op_ucell_chunking_contract <- function() {
  if (!requireNamespace("UCell", quietly = TRUE)) {
    return(contract_test_skip("UCell is not installed."))
  }

  tmp <- tempfile("scwb_ucell_chunk_")
  b <- wb_init_bundle(tmp, overwrite = TRUE)
  on.exit(wb_close_bundle(b), add = TRUE)

  cells <- paste0("c", seq_len(8))
  wb_define_cells(b, cells)

  mat <- Matrix::Matrix(
    matrix(
      c(
        8, 7, 0, 0, 1, 0, 0, 0,
        7, 6, 0, 0, 1, 0, 0, 0,
        0, 1, 8, 7, 0, 0, 0, 0,
        0, 1, 7, 6, 0, 0, 0, 0,
        0, 0, 0, 0, 8, 7, 1, 0,
        0, 0, 0, 0, 7, 6, 1, 0
      ),
      nrow = 6,
      byrow = TRUE,
      dimnames = list(c("g1", "g2", "g3", "g4", "g5", "g6"), cells)
    ),
    sparse = TRUE
  )
  wb_attach_matrix(b, matrix_id = "RNA_counts", mat = mat, feature_type = "gene")

  sigs <- list(
    sig_a = c("g1", "g2"),
    sig_b = c("g3", "g4"),
    sig_c = c("g5", "g6")
  )

  s0 <- wb_session_new()
  r1 <- wb_session_run_op(
    session = s0,
    bundle = b,
    op_name = "ucell",
    inputs = list(
      matrix = "RNA_counts",
      cell_set = "all",
      min_cells = 1L,
      features = sigs,
      max_rank = 100L,
      ncores = 1L,
      parallel_backend = "serial",
      missing_features_policy = "drop"
    )
  )
  run1 <- r1$run

  s1 <- wb_session_new()
  r2 <- wb_session_run_op(
    session = s1,
    bundle = b,
    op_name = "ucell",
    inputs = list(
      matrix = "RNA_counts",
      cell_set = "all",
      min_cells = 1L,
      features = sigs,
      max_rank = 100L,
      ncores = 1L,
      parallel_backend = "serial",
      chunk_size = 3L,
      missing_features_policy = "drop"
    )
  )
  run2 <- r2$run

  sc1 <- wb_primitive_to_table(run1$outputs$signature_scores, include_context = FALSE)
  sc2 <- wb_primitive_to_table(run2$outputs$signature_scores, include_context = FALSE)
  sc1 <- sc1[order(sc1$key, sc1$cell_id), , drop = FALSE]
  sc2 <- sc2[order(sc2$key, sc2$cell_id), , drop = FALSE]
  rownames(sc1) <- NULL
  rownames(sc2) <- NULL

  stopifnot(identical(as.character(sc1$key), as.character(sc2$key)))
  stopifnot(identical(as.character(sc1$cell_id), as.character(sc2$cell_id)))
  stopifnot(isTRUE(all.equal(as.numeric(sc1$value), as.numeric(sc2$value), tolerance = 1e-12)))

  sm1 <- run1$outputs$signature_summary$table
  sm2 <- run2$outputs$signature_summary$table
  sm1 <- sm1[order(sm1$entity_id), , drop = FALSE]
  sm2 <- sm2[order(sm2$entity_id), , drop = FALSE]
  rownames(sm1) <- NULL
  rownames(sm2) <- NULL
  stopifnot(identical(as.character(sm1$entity_id), as.character(sm2$entity_id)))
  stopifnot(isTRUE(all.equal(sm1, sm2, tolerance = 1e-12, check.attributes = FALSE)))

  stopifnot(is.list(run2$params$chunking))
  stopifnot(isTRUE(run2$params$chunking$enabled))
  stopifnot(identical(as.character(run2$params$chunking$axis), "cells"))
  stopifnot(identical(as.integer(run2$params$chunking$chunk_size), 3L))
  stopifnot(identical(as.integer(run2$params$chunking$n_chunks), 3L))
  stopifnot(identical(as.integer(run2$params$ncores), 1L))
  stopifnot(identical(as.character(run2$params$parallel_backend), "serial"))

  TRUE
}
