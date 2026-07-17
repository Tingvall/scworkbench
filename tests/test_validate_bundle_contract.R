test_validate_bundle_contract <- function() {
  tmp <- tempfile("scwb_validate_bundle_")
  b <- wb_init_bundle(tmp, overwrite = TRUE)
  on.exit({
    try(wb_close_bundle(b), silent = TRUE)
    unlink(tmp, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  cells <- paste0("cell", 1:4)
  wb_define_cells(
    b,
    cell_ids = cells,
    metadata = data.frame(
      cell_id = cells,
      dataset_id = "dataset1",
      stringsAsFactors = FALSE
    ),
    dataset_id = "dataset1"
  )

  mat <- Matrix::Matrix(
    matrix(c(
      1, 0, 2, 0,
      0, 3, 0, 4,
      5, 0, 0, 6
    ), nrow = 3, byrow = TRUE, dimnames = list(paste0("gene", 1:3), cells)),
    sparse = TRUE
  )
  wb_attach_matrix(b, matrix_id = "RNA_counts", mat = mat, feature_type = "gene")

  stopifnot(isTRUE(wb_validate_bundle(tmp)))
  wrong_type <- try(wb_validate_bundle(b), silent = TRUE)
  stopifnot(inherits(wrong_type, "try-error"))
  stopifnot(grepl("one non-empty path string", as.character(wrong_type), fixed = TRUE))
  TRUE
}
