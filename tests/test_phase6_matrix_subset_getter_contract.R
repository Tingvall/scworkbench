test_phase6_matrix_subset_getter_and_recipient_contract <- function() {
  root <- tempfile("phase6-subset-matrix-")
  bundle <- wb_init_bundle(root)
  on.exit({
    try(wb_close_bundle(bundle), silent = TRUE)
    unlink(root, recursive = TRUE, force = TRUE)
  }, add = TRUE)
  cells <- c("cell_2", "cell_10", "cell_1", "query_1")
  wb_define_cells(bundle, cells)
  features <- c("peak_2", "peak_1")
  values <- matrix(as.integer(seq_len(6L)), nrow = 2L,
    dimnames = list(features, cells[1:3]))
  wb_attach_matrix(bundle, "subset", Matrix::Matrix(values, sparse = TRUE),
    feature_type = "peak", cell_ids = cells[1:3])
  observed <- wb_slice(bundle, "subset", features = features,
    cells = c("cell_1", "cell_2"))
  stopifnot(isTRUE(all.equal(as.matrix(observed),
    values[, c("cell_1", "cell_2"), drop = FALSE],
    check.attributes = FALSE)),
    identical(colnames(observed), c("cell_1", "cell_2")),
    identical(wb_cells_with_matrix(bundle, "subset"), cells[1:3]))
  missing <- tryCatch(wb_slice(bundle, "subset", features = features,
    cells = "query_1"), error = identity)
  stopifnot(inherits(missing, "error"))
  stopifnot(isTRUE(wb_finalize_recipient_bundle(bundle)$ready))
  wb_close_bundle(bundle)
  bundle <- wb_open_bundle(root, read_only = TRUE)
  report <- wb_bundle_validation_report(root, level = "recipient")
  stopifnot(isTRUE(report$ok), identical(report$pre_validation_fingerprint,
    report$post_validation_fingerprint))
  TRUE
}
