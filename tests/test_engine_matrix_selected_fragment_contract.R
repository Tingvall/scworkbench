.selected_fragment_fixture <- function() {
  f <- new.env(parent = emptyenv())
  f$root <- tempfile("selected_fragment_"); f$b <- wb_init_bundle(f$root)
  f$close <- function() {wb_close_bundle(f$b); unlink(f$root, recursive = TRUE)}
  f$features <- c("f_2", "f_10", "f_1"); f$cells <- c("c_2", "c_10", "c_1")
  f$values <- matrix(as.double(c(1, 0, 3, 4, 5, 0, 0, 8, 9)), 3L,
    dimnames = list(f$features, f$cells))
  wb_define_cells(f$b, f$cells)
  wb_attach_matrix(f$b, "m", Matrix::Matrix(f$values, sparse = TRUE))
  template <- wb_matrix_fragments(f$b, "m")
  for (table in c("matrix_fragment_cells", "matrix_fragment_features"))
    DBI::dbExecute(f$b$con, paste0("DELETE FROM ", table, " WHERE fragment_id=?"),
      params = list(template$fragment_id[[1L]]))
  DBI::dbExecute(f$b$con, "DELETE FROM matrix_fragments WHERE matrix_id='m'")
  # Owned storage-layout fixture: retain the logical matrix, split its physical
  # columns and populate both normalized membership tables in exact row order.
  for (i in seq_along(f$cells)) {
    row <- template; row$fragment_id <- paste0("selected_", i)
    row$path <- paste0("matrices/selected_", i)
    row$n_features <- 3L; row$n_cells <- 1L
    row$feature_ids_json <- as.character(jsonlite::toJSON(f$features))
    row$cell_ids_json <- as.character(jsonlite::toJSON(f$cells[i]))
    row$created_at <- paste0("2000-01-0", i)
    BPCells::write_matrix_dir(methods::as(methods::as(
      Matrix::Matrix(f$values[, i, drop = FALSE], sparse = TRUE),
      "generalMatrix"), "CsparseMatrix"), dir = file.path(f$root, row$path[[1L]]))
    DBI::dbAppendTable(f$b$con, "matrix_fragments", row)
    DBI::dbAppendTable(f$b$con, "matrix_fragment_features", data.frame(
      fragment_id = rep(row$fragment_id, 3L), feature_id = f$features))
    DBI::dbAppendTable(f$b$con, "matrix_fragment_cells", data.frame(
      fragment_id = row$fragment_id, cell_id = f$cells[i]))
  }
  f$readonly <- function() {
    stopifnot(wb_finalize_recipient_bundle(f$b)$ready)
    wb_close_bundle(f$b)
    f$b <- wb_open_bundle(f$root, read_only = TRUE, validate = FALSE)
  }
  f
}

test_engine_matrix_selected_fragment_alignment_purity_freshness_contract <- function() {
  f <- .selected_fragment_fixture(); on.exit(f$close(), add = TRUE)
  f$readonly()
  before <- scworkbench:::.wb_prov_file_tree_sha256(f$root)
  for (features in list(f$features, rev(f$features)))
    for (cells in list(f$cells, rev(f$cells), f$cells[c(3L, 1L)], f$cells[1L])) {
      actual <- wb_matrix_read_features(f$b, "m", features, cells)
      stopifnot(inherits(actual, "sparseMatrix"), typeof(actual@x) == "double",
        identical(as.matrix(actual), f$values[features, cells, drop = FALSE]))
      for (feature in features) stopifnot(identical(
        wb_matrix_read_feature(f$b, "m", feature, cells),
        setNames(as.double(f$values[feature, cells]), cells)))
    }
  stopifnot(identical(before, scworkbench:::.wb_prov_file_tree_sha256(f$root)))
  wb_close_bundle(f$b); f$b <- wb_open_bundle(f$root, read_only = FALSE, validate = FALSE)
  DBI::dbExecute(f$b$con, "UPDATE matrix_fragments SET feature_ids_json=? WHERE fragment_id='selected_1'",
    params = list(as.character(jsonlite::toJSON(rev(f$features)))))
  expected <- f$values; expected[, 1L] <- rev(expected[, 1L])
  stopifnot(identical(as.matrix(wb_matrix_read_features(f$b, "m", f$features, f$cells)), expected))
  TRUE
}

test_engine_matrix_selected_fragment_deep_validation_contract <- function() {
  f <- .selected_fragment_fixture(); on.exit(f$close(), add = TRUE)
  f$readonly()
  # Target-specific before/after assertion, not just an unrelated failing report.
  code <- "MATRIX_FRAGMENT_FEATURE_ORDER_MISMATCH"
  baseline <- wb_bundle_validation_report(f$root, level = "content")
  stopifnot(!any(baseline$diagnostics$code == code & baseline$diagnostics$entity_id == "selected_3"))
  wb_close_bundle(f$b); f$b <- wb_open_bundle(f$root, read_only = FALSE, validate = FALSE)
  DBI::dbExecute(f$b$con, "UPDATE matrix_fragments SET feature_ids_json='invalid_feature_axis' WHERE fragment_id='selected_3'")
  f$readonly()
  before <- scworkbench:::.wb_prov_file_tree_sha256(f$root)
  cell <- f$cells[1L]
  stopifnot(identical(as.matrix(wb_matrix_read_features(f$b, "m", f$features, cell)),
    f$values[, 1L, drop = FALSE]), identical(wb_matrix_read_feature(f$b, "m", f$features[1L], cell),
    setNames(as.double(f$values[1L, 1L]), cell)))
  for (level in c("content", "recipient")) {
    report <- wb_bundle_validation_report(f$root, level = level)
    stopifnot(!isTRUE(report$ok), any(report$diagnostics$code == code &
      report$diagnostics$entity_id == "selected_3"))
  }
  stopifnot(identical(before, scworkbench:::.wb_prov_file_tree_sha256(f$root)))
  TRUE
}

test_engine_matrix_selected_fragment_selected_and_cell_corruption_contract <- function() {
  f <- .selected_fragment_fixture(); on.exit(f$close(), add = TRUE)
  readers <- list(function(cell) wb_matrix_read_features(f$b, "m", f$features, cell),
    function(cell) wb_matrix_read_feature(f$b, "m", f$features[1L], cell))
  DBI::dbExecute(f$b$con, "UPDATE matrix_fragments SET feature_ids_json='invalid_feature_axis' WHERE fragment_id='selected_3'")
  for (read in readers) {
    error <- tryCatch(read(f$cells[3L]), error = identity)
    stopifnot(inherits(error, "error"), grepl("invalid_feature_axis", conditionMessage(error), fixed = TRUE))
  }
  # An undecodable cell axis cannot prove disjointness, so still fails closed.
  DBI::dbExecute(f$b$con, "UPDATE matrix_fragments SET cell_ids_json='invalid_cell_axis' WHERE fragment_id='selected_2'")
  for (read in readers) {
    error <- tryCatch(read(f$cells[1L]), error = identity)
    stopifnot(inherits(error, "error"), grepl("invalid_cell_axis", conditionMessage(error), fixed = TRUE))
  }
  TRUE
}
