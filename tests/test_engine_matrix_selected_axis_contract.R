.wb_selected_axis_test_reader <- function() {
  reader <- get0(".wb_matrix_stream_reader",
    environment(.wb_selected_axis_test_reader), inherits = TRUE)
  if (is.null(reader)) reader <- scworkbench:::.wb_matrix_stream_reader
  reader
}

test_engine_matrix_selected_axis_values_contract <- function() {
  root <- tempfile("selected_axis_bundle_")
  b <- wb_init_bundle(root)
  on.exit({ try(wb_close_bundle(b), silent = TRUE)
    unlink(root, recursive = TRUE) }, add = TRUE)
  features <- c("f_10", "f_2", "f_1", "f_4", "f_7", "f_3")
  cells <- c("c_3", "c_10", "zero", "c_1", "c_2")
  values <- matrix(as.double(seq_len(30L)), 6L,
    dimnames = list(features, cells))
  values[, "zero"] <- 0
  wb_define_cells(b, rev(cells))
  wb_attach_matrix(b, "RNA", values, feature_type = "gene")
  selected_features <- c("f_7", "f_10", "f_1")
  selected_cells <- c("zero", "c_2", "c_10")
  reader <- .wb_selected_axis_test_reader()
  for (axis in c("features", "cells")) {
    plan <- reader(b, "RNA", axis, selected_features, selected_cells)
    tryCatch({
      for (chunk in wb_partition_axis(if (axis == "features")
          selected_features else selected_cells, 2L)) {
        f <- if (axis == "features") chunk else selected_features
        c <- if (axis == "cells") chunk else selected_cells
        block <- plan$read(f, c)
        stopifnot(identical(as.matrix(block), values[f, c, drop = FALSE]),
          inherits(block, "Matrix"), typeof(block@x) == "double")
      }
      # Invocation-private projection permits in-projection access in explicit
      # order; the public adapter separately enforces granted read discipline.
      stopifnot(identical(as.matrix(plan$read(rev(selected_features),
        rev(selected_cells))), values[rev(selected_features),
          rev(selected_cells), drop = FALSE]))
      for (request in list(list("f_2", selected_cells),
          list(selected_features, "c_3"), list("foreign", selected_cells))) {
        error <- tryCatch(plan$read(request[[1L]], request[[2L]]),
          error = identity)
        stopifnot(inherits(error, "error"))
      }
    }, finally = plan$close())
    stopifnot(!dir.exists(plan$root))
  }
  # NULL defaults retain complete logical axes, not the last projection.
  plan <- reader(b, "RNA", "features")
  tryCatch(stopifnot(identical(as.matrix(plan$read(features, cells)), values)),
    finally = plan$close())
  TRUE
}

test_engine_matrix_selected_axis_failure_cleanup_contract <- function() {
  root <- tempfile("selected_axis_failure_")
  b <- wb_init_bundle(root)
  on.exit({ try(wb_close_bundle(b), silent = TRUE)
    unlink(root, recursive = TRUE) }, add = TRUE)
  values <- matrix(as.double(1:12), 3L, dimnames = list(
    c("f3", "f1", "f2"), c("c4", "c1", "c3", "c2")))
  wb_define_cells(b, colnames(values))
  wb_attach_matrix(b, "RNA", values, feature_type = "gene")
  reader <- .wb_selected_axis_test_reader()
  roots <- function() sort(list.files(tempdir(), pattern = "^scwb_matrix_reader_",
    full.names = TRUE))
  before <- roots()
  for (selection in list(character(), c("f1", "f1"), NA_character_,
      "", "foreign")) {
    error <- tryCatch(reader(b, "RNA", "features", features = selection),
      error = identity)
    stopifnot(inherits(error, "error"), identical(roots(), before))
  }
  # Force constructor failure after its temporary root was allocated. Physical
  # dimensions must not become trusted just because a projection was requested.
  DBI::dbExecute(b$con, "UPDATE matrix_fragments SET feature_ids_json='[\"f3\",\"f1\"]' WHERE matrix_id='RNA';")
  error <- tryCatch(reader(b, "RNA", "features", features = "f1"),
    error = identity)
  stopifnot(inherits(error, "error"), identical(roots(), before))
  TRUE
}
