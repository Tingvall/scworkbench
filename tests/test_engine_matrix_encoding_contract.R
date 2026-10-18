.wb_matrix_encoding_test_context <- function() {
  e <- environment(.wb_matrix_encoding_test_context)
  ns <- asNamespace("scworkbench")
  get_helper <- function(name) {
    value <- get0(name, e, inherits = TRUE)
    if (is.null(value)) value <- get(name, ns)
    value
  }
  list(axis = get_helper(".wb_operation_pack_matrix_axis_json"),
    stream = get_helper(".wb_operation_pack_matrix_stream_identity"),
    append = get_helper("C_scwb_matrix_slice_append"))
}

.wb_matrix_encoding_old_oracle <- function(values, features, cells) {
  dense <- as.matrix(values)
  indices <- which(dense != 0, arr.ind = TRUE)
  if (length(indices)) indices <- indices[order(indices[, 2L],
    indices[, 1L]), , drop = FALSE]
  entries <- lapply(seq_len(nrow(indices)), function(i) list(
    row = as.integer(indices[i, 1L]), column = as.integer(indices[i, 2L]),
    value = unname(dense[indices[i, 1L], indices[i, 2L]])))
  scworkbench:::.wb_operation_pack_v2_identity_plain(
    "scworkbench.operation_pack.matrix_slice.content.v1", list(
      schema = "scworkbench.operation_pack.matrix_slice.content.v1",
      kind = "matrix", dimensions = list(as.integer(length(features)),
        as.integer(length(cells))), feature_id = unname(as.list(features)),
      cell_id = unname(as.list(cells)), entries = entries))
}

test_engine_matrix_axis_encoding_contract <- function() {
  axis <- .wb_matrix_encoding_test_context()$axis
  old <- function(ids) scworkbench:::.wb_operation_pack_canonical_json(
    unname(as.list(ids)))
  controls <- vapply(seq_len(31L), intToUtf8, character(1))
  cases <- list(character(), "", NA_character_,
    c("cell_2", "cell_10", "cell_1", "é", "雪", "😀", NA_character_),
    c('quote"', "slash\\", "a\nb", "tab\t", controls),
    setNames(c("a", "b"), c("ignored1", "ignored2")),
    factor(c("b", "a", NA)), c(1, NA_real_, 1.5))
  for (ids in cases) stopifnot(identical(axis(ids), old(ids)))
  invalid <- rawToChar(as.raw(255L)); Encoding(invalid) <- "UTF-8"
  for (ids in list(invalid, c("valid", invalid))) {
    expected <- tryCatch(old(ids), error = identity)
    observed <- tryCatch(axis(ids), error = identity)
    stopifnot(inherits(expected, "error"), inherits(observed, "error"),
      identical(class(expected), class(observed)),
      identical(conditionMessage(expected), conditionMessage(observed)))
  }
  TRUE
}

test_engine_matrix_coordinate_encoding_contract <- function() {
  append <- .wb_matrix_encoding_test_context()$append
  rows <- as.integer(c(1, 2, 9, 10, 11, 99, 100, 101, 999, 1000,
    1001, 1000000, .Machine$integer.max))
  columns <- rev(rows)
  path <- tempfile("matrix_token_parity_")
  on.exit(unlink(path), add = TRUE)
  read_tokens <- function(values) {
    if (file.exists(path)) unlink(path)
    .Call(append, path, rows, columns, values, TRUE)
    paste0("[", readChar(path, file.info(path)$size, useBytes = TRUE), "]")
  }
  for (values in list(as.double(rows), -as.double(rows),
      seq_along(rows) / 7, rep(c(TRUE, FALSE), length.out = length(rows)))) {
    actual <- read_tokens(values)
    expected <- scworkbench:::.wb_operation_pack_canonical_json(lapply(
      seq_along(rows), function(i) list(column = columns[[i]],
        row = rows[[i]], value = values[[i]])))
    stopifnot(identical(actual, expected))
  }
  # Preserve native vector admission and finite-value rejection.
  for (values in list(as.raw(seq_along(rows)), as.integer(rows),
      replace(as.double(rows), 1L, NA_real_),
      replace(as.double(rows), 1L, NaN),
      replace(as.double(rows), 1L, Inf))) {
    error <- tryCatch(read_tokens(values), error = identity)
    stopifnot(inherits(error, "error"))
  }
  TRUE
}

test_engine_matrix_encoding_old_identity_contract <- function() {
  stream <- .wb_matrix_encoding_test_context()$stream
  set.seed(184)
  for (values in list(matrix(rnorm(121L), 11L),
      matrix(c(NA, NaN, 0, -0, 1, -1, 1e-307, 1e308, 1e-7), 3L),
      matrix(rep(c(TRUE, FALSE, NA), length.out = 121L), 11L),
      matrix(as.integer(c(0, 1, 10, 100, 101, .Machine$integer.max)), 3L))) {
    features <- paste0("f", seq_len(nrow(values)), "雪\n")
    cells <- paste0("c", rev(seq_len(ncol(values))), "é\"")
    expected <- .wb_matrix_encoding_old_oracle(values, features, cells)
    for (chunk in c(1L, 3L, 128L)) {
      observed <- stream(features, cells,
        function(columns) values[, columns, drop = FALSE], chunk)
      stopifnot(identical(observed, expected))
    }
  }
  # Raw matrices have never been an admitted Matrix backend input; preserve
  # rejection rather than broadening support during an encoder optimization.
  values <- matrix(raw(6L), 3L)
  expected <- tryCatch(scworkbench:::.wb_operation_pack_v3_matrix_slice_content(
    values, paste0("f", 1:3), paste0("c", 1:2)), error = identity)
  observed <- tryCatch(stream(paste0("f", 1:3), paste0("c", 1:2),
    function(columns) values[, columns, drop = FALSE], 128L), error = identity)
  stopifnot(inherits(expected, "error"), inherits(observed, "error"),
    identical(class(expected), class(observed)),
    identical(conditionMessage(expected), conditionMessage(observed)))
  TRUE
}
