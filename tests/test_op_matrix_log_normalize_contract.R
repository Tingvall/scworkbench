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
  out_info <- wb_matrix_info(b, "RNA_log1p_cp10k")
  out_path <- file.path(b$dir, as.character(out_info$path[1]))
  stopifnot(identical(BPCells::matrix_type(.wb_bp_open_matrix_dir(out_path)), "double"))
  stopifnot(any(got != 0))

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

  # A persistence failure must not leave an all-zero transform registered when
  # its declared source has nonzero library sizes.
  bad_id <- "RNA_log_bad_zero"
  zero_expr <- BPCells::multiply_cols(wb_matrix(b, "RNA_counts"), rep(0, length(cells)))
  zero_err <- try(
    .wb_matrix_register_transformed(
      bundle = b,
      matrix_id = bad_id,
      source_matrix_id = "RNA_counts",
      mat = zero_expr,
      feature_ids = c("g1", "g2"),
      cell_ids = cells,
      layer = "log1p_cp10000",
      feature_type = "gene",
      description = "intentional zero-write regression fixture",
      source_library_size = lib_size
    ),
    silent = TRUE
  )
  stopifnot(inherits(zero_err, "try-error"))
  stopifnot(nrow(wb_matrix_info(b, bad_id)) == 0L)

  TRUE
}

test_op_matrix_log_normalize_multifragment_contract <- function() {
  if (!requireNamespace("BPCells", quietly = TRUE)) {
    message("Skipping matrix_log_normalize multi-fragment contract test: BPCells not installed.")
    return(TRUE)
  }

  tmp <- tempfile("scwb_matrix_log_normalize_multifrag_")
  b <- wb_init_bundle(tmp, overwrite = TRUE)
  on.exit({
    wb_close_bundle(b)
    unlink(tmp, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  cells <- paste0("c", seq_len(4))
  features <- c("g1", "g2")
  wb_define_cells(b, cells)

  frag1 <- Matrix::Matrix(
    matrix(c(1, 0, 0, 2), nrow = 2, byrow = TRUE, dimnames = list(features, cells[1:2])),
    sparse = TRUE
  )
  frag1 <- methods::as(methods::as(frag1, "generalMatrix"), "CsparseMatrix")
  frag2 <- Matrix::Matrix(
    matrix(c(3, 1, 4, 0), nrow = 2, byrow = TRUE, dimnames = list(features, cells[3:4])),
    sparse = TRUE
  )
  frag2 <- methods::as(methods::as(frag2, "generalMatrix"), "CsparseMatrix")
  rel1 <- file.path("mat", "source_frag_1")
  rel2 <- file.path("mat", "source_frag_2")
  dir.create(file.path(tmp, "mat"), recursive = TRUE, showWarnings = FALSE)
  BPCells::write_matrix_dir(frag1, file.path(tmp, rel1))
  BPCells::write_matrix_dir(frag2, file.path(tmp, rel2))

  DBI::dbWriteTable(
    b$con,
    "matrices",
    data.frame(
      matrix_id = "RNA_counts",
      layer = "counts",
      feature_type = "gene",
      n_features = 2L,
      n_cells = 4L,
      storage = "bpcells",
      path = rel1,
      description = "synthetic multi-fragment source",
      stringsAsFactors = FALSE
    ),
    append = TRUE
  )
  DBI::dbWriteTable(
    b$con,
    "features",
    data.frame(
      matrix_id = "RNA_counts",
      feature_id = features,
      feature_type = "gene",
      chr = NA_character_,
      start = NA_integer_,
      end = NA_integer_,
      stringsAsFactors = FALSE
    ),
    append = TRUE
  )
  wb_register_matrix_fragment(b$con, "RNA_counts", rel1, features, cells[1:2], source = "test")
  wb_register_matrix_fragment(b$con, "RNA_counts", rel2, features, cells[3:4], source = "test")

  err_matrix <- try(wb_matrix(b, "RNA_counts"), silent = TRUE)
  stopifnot(inherits(err_matrix, "try-error"))

  rr <- wb_session_run_op(
    session = wb_session_new(),
    bundle = b,
    op_name = "matrix_log_normalize",
    inputs = list(
      matrix = "RNA_counts",
      cell_set = "all",
      min_cells = 1L,
      output_matrix_id = "RNA_log_norm",
      scale_factor = 10000,
      overwrite = TRUE
    )
  )

  stopifnot(identical(as.character(rr$run$outputs$matrix$matrix_id), "RNA_log_norm"))
  out_frags <- wb_matrix_fragments(b, "RNA_log_norm")
  stopifnot(nrow(out_frags) == 2L)
  stopifnot(sum(as.integer(out_frags$n_cells)) == 4L)
  stopifnot(isTRUE(wb_validate_bundle(tmp)))

  got <- as.matrix(wb_slice(b, matrix_id = "RNA_log_norm", features = features, cells = cells))
  src <- cbind(as.matrix(frag1), as.matrix(frag2))
  lib_size <- as.numeric(Matrix::colSums(src))
  expected <- log1p(t(t(src) / lib_size * 10000))
  dimnames(expected) <- dimnames(src)
  stopifnot(isTRUE(all.equal(got, expected, tolerance = 1e-8, check.attributes = FALSE)))
  for (path in file.path(b$dir, as.character(out_frags$path))) {
    stopifnot(identical(BPCells::matrix_type(.wb_bp_open_matrix_dir(path)), "double"))
  }
  stopifnot(any(got != 0))

  summary <- rr$run$outputs$summary$table
  stopifnot(identical(as.integer(summary$n_cells[1]), 4L))
  stopifnot(identical(as.integer(summary$n_fragments[1]), 2L))

  TRUE
}
