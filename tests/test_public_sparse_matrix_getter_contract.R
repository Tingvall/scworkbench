test_public_sparse_matrix_complete_and_overlap_contract <- function() {
  root <- tempfile("public_sparse_overlap_")
  b <- wb_init_bundle(root)
  on.exit({wb_close_bundle(b); unlink(root, recursive = TRUE)}, add = TRUE)
  cells <- c("c2", "c1", "c3"); features <- c("g2", "g1", "g3")
  wb_define_cells(b, cells)
  first <- matrix(c(0, 2, 3, 4, 0, 6, 7, 8, 9), 3,
    dimnames = list(features, cells))
  wb_attach_matrix(b, "m", Matrix::Matrix(first, sparse = TRUE))
  DBI::dbExecute(b$con, "UPDATE matrix_fragments SET created_at='2000-01-01' WHERE matrix_id='m';")
  template <- wb_matrix_fragments(b, "m")
  # Explicit legacy-overlap fixture; current public registration rightly refuses
  # creating overlaps, but retained bundles still have the getter contract.
  append_fragment <- function(value, id, date) {
    row <- template; row$fragment_id <- id
    row$path <- paste0("matrices/", id); row$created_at <- date
    row$n_features <- nrow(value); row$n_cells <- ncol(value)
    row$feature_ids_json <- jsonlite::toJSON(rownames(value))
    row$cell_ids_json <- jsonlite::toJSON(colnames(value))
    BPCells::write_matrix_dir(methods::as(methods::as(
      Matrix::Matrix(value, sparse = TRUE), "generalMatrix"), "CsparseMatrix"),
      dir = file.path(root, row$path[[1]]))
    DBI::dbAppendTable(b$con, "matrix_fragments", row)
  }
  partial <- matrix(c(0, 21), 2, dimnames = list(c("g1", "g2"), "c1"))
  append_fragment(partial, "partial", "2000-01-02")
  newest <- first[c(3, 1, 2), c(2, 3, 1)] + 30
  newest["g2", "c2"] <- 0
  append_fragment(newest, "full", "2000-01-03")
  read <- function(f, c, na = "zero", newest_wins = TRUE)
    wb_matrix_read_features(b, "m", f, c, missing = na, prefer_newest = newest_wins)
  for (f in list(features, rev(features))) for (c in list(cells, rev(cells))) {
    stopifnot(identical(as.matrix(read(f, c)), newest[f, c, drop = FALSE]),
      identical(as.matrix(read(f, c, newest_wins = FALSE)), first[f, c, drop = FALSE]),
      identical(read(f, c, na = "NA"), newest[f, c, drop = FALSE]))
  }
  # Remove the last complete overlap: a later partial block must overwrite zero.
  DBI::dbExecute(b$con, "DELETE FROM matrix_fragments WHERE fragment_id='full';")
  expected <- first; expected[rownames(partial), colnames(partial)] <- partial
  stopifnot(identical(as.matrix(read(features, cells)), expected))
  for (f in list(features[1], features)) for (c in list(cells[1], cells)) {
    result <- read(f, c)
    stopifnot(inherits(result, "sparseMatrix"),
      identical(as.matrix(result), expected[f, c, drop = FALSE]))
  }
  # Duplicate selections deliberately preserve historical named-map behavior,
  # rather than silently replacing it with conventional matrix subsetting.
  dup_f <- c("g1", "g1", "g2"); dup_c <- c("c1", "c1")
  legacy <- Matrix::Matrix(0, nrow = 3, ncol = 2, sparse = TRUE)
  dimnames(legacy) <- list(dup_f, dup_c)
  for (value in list(first, partial)) {
    ff <- intersect(dup_f, rownames(value)); cc <- intersect(dup_c, colnames(value))
    legacy[unname(setNames(seq_along(dup_f), dup_f)[ff]),
      unname(setNames(seq_along(dup_c), dup_c)[cc])] <- value[ff, cc, drop = FALSE]
  }
  stopifnot(identical(as.matrix(read(dup_f, dup_c)), as.matrix(legacy)))
  absent <- read(c("absent", "g1"), c("absent", "c1"))
  stopifnot(identical(as.numeric(absent[1, ]), c(0, 0)),
    identical(as.numeric(absent[, 1]), c(0, 0)))
  absent_na <- read(c("absent", "g1"), c("absent", "c1"), "NA")
  stopifnot(all(is.na(absent_na[1, ])), all(is.na(absent_na[, 1])))
  zeros <- first * 0
  append_fragment(zeros, "zeros", "2000-01-04")
  stopifnot(inherits(read(features, cells), "sparseMatrix"),
    identical(as.matrix(read(features, cells)), zeros))
  # Stable tie ordering retains the existing order rule. SQL forbids NULL dates.
  for (stamp in list("2000-01-01")) {
    DBI::dbExecute(b$con, "UPDATE matrix_fragments SET created_at=? WHERE fragment_id='zeros';",
      params = list(stamp))
    fragments <- wb_matrix_fragments(b, "m")
    ordered <- order(fragments$created_at, na.last = TRUE)
    values <- setNames(list(first, partial, zeros), c(template$fragment_id, "partial", "zeros"))
    for (newest_wins in c(TRUE, FALSE)) {
      oracle <- first * 0
      for (i in if (newest_wins) ordered else rev(ordered)) {
        value <- values[[fragments$fragment_id[[i]]]]
        oracle[rownames(value), colnames(value)] <- value
      }
      stopifnot(identical(as.matrix(read(features, cells, newest_wins = newest_wins)), oracle))
    }
  }
  before <- scworkbench:::.wb_prov_file_tree_sha256(root)
  invisible(read(features, cells))
  stopifnot(identical(before, scworkbench:::.wb_prov_file_tree_sha256(root)))
  # Feature JSON remains validated first even for a nonintersecting cell axis.
  DBI::dbExecute(b$con, "UPDATE matrix_fragments SET feature_ids_json='invalid', cell_ids_json='[\"elsewhere\"]' WHERE fragment_id='zeros';")
  error <- tryCatch(read(features, cells), error = identity)
  stopifnot(inherits(error, "error"), grepl("invalid", conditionMessage(error), fixed = TRUE))
  TRUE
}

test_private_sparse_matrix_disjoint_assembly_contract <- function() {
  root <- tempfile("private_sparse_fragments_")
  b <- wb_init_bundle(root)
  on.exit({wb_close_bundle(b); unlink(root, recursive = TRUE)}, add = TRUE)
  features <- c("g2", "g1", "g3"); cells <- c("c2", "c1", "zero", "c3")
  values <- matrix(as.double(seq_len(12)), 3, dimnames = list(features, cells))
  values[, "zero"] <- 0
  wb_define_cells(b, cells)
  wb_attach_matrix(b, "m", Matrix::Matrix(values, sparse = TRUE))
  template <- wb_matrix_fragments(b, "m")
  for (table in c("matrix_fragment_cells", "matrix_fragment_features"))
    DBI::dbExecute(b$con, paste0("DELETE FROM ", table, " WHERE fragment_id=?;"),
      params = list(template$fragment_id[[1]]))
  DBI::dbExecute(b$con, "DELETE FROM matrix_fragments WHERE matrix_id='m';")
  add_fragment <- function(value, id, f = rownames(value), c = colnames(value)) {
    row <- template; row$fragment_id <- id; row$path <- paste0("matrices/", id)
    row$n_features <- nrow(value); row$n_cells <- ncol(value)
    row$feature_ids_json <- jsonlite::toJSON(f); row$cell_ids_json <- jsonlite::toJSON(c)
    # Incidental physical labels are not the logical multi-fragment namespace.
    rownames(value) <- paste0("physical_", seq_len(nrow(value)))
    BPCells::write_matrix_dir(methods::as(methods::as(
      Matrix::Matrix(value, sparse = TRUE), "generalMatrix"), "CsparseMatrix"),
      dir = file.path(root, row$path[[1]]))
    DBI::dbAppendTable(b$con, "matrix_fragments", row)
  }
  add_fragment(values[, c(4, 2), drop = FALSE], "one")
  add_fragment(values[, 3, drop = FALSE], "two")
  add_fragment(values[, 1, drop = FALSE], "three")
  for (axis in c("cells", "features")) {
    plan <- scworkbench:::.wb_matrix_stream_reader(b, "m", axis)
    tryCatch({
      for (f in list(features, rev(features), features[1]))
        for (c in list(cells, rev(cells), cells[c(2, 1, 3)], cells[1])) {
          actual <- plan$read(f, c)
          stopifnot(inherits(actual, "sparseMatrix"), typeof(actual@x) == "double",
            identical(as.matrix(actual), values[f, c, drop = FALSE]))
        }
      # Incomplete coverage and duplicates deliberately exercise legacy fallback.
      absent <- plan$read(features, c(cells, "missing"))
      stopifnot(identical(as.matrix(absent[, cells]), values),
        all(absent[, "missing"] == 0))
      duplicate_error <- tryCatch(plan$read(features[c(1, 1, 2)], cells), error = identity)
      stopifnot(inherits(duplicate_error, "error"),
        grepl("duplicated values", conditionMessage(duplicate_error), fixed = TRUE))
    }, finally = plan$close())
    stopifnot(!dir.exists(plan$root))
  }
  # Overlapping and partial-row fragments must use the original overwrite loop.
  changed <- matrix(0, 1, dimnames = list("g1", "c2"))
  add_fragment(changed, "partial")
  plan <- scworkbench:::.wb_matrix_stream_reader(b, "m", "cells")
  expected <- values; expected["g1", "c2"] <- 0
  tryCatch(stopifnot(identical(as.matrix(plan$read(features, cells)), expected)),
    finally = plan$close())
  TRUE
}
