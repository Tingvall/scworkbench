#' Cells with available coordinates for a space
#' @export
wb_cells_with_space <- function(bundle, space_id, dims = NULL) {
  con <- bundle$con
  sp <- wb_spaces(bundle)
  row <- sp[sp$space_id == space_id, , drop = FALSE]
  .wb_assert(nrow(row) == 1, "Unknown space_id")

  if (row$storage == "wide:space_2d") {
    return(DBI::dbGetQuery(
      con,
      "SELECT cell_id FROM space_2d WHERE space_id = ?;",
      params = list(space_id)
    )$cell_id)
  }

  # long:space_coords
  if (is.null(dims)) {
    return(DBI::dbGetQuery(
      con,
      "SELECT DISTINCT cell_id FROM space_coords WHERE space_id = ?;",
      params = list(space_id)
    )$cell_id)
  }

  cl <- .wb_sql_in_clause(dims)
  q <- paste0(
    "SELECT cell_id FROM space_coords ",
    "WHERE space_id = ? AND dim ", cl$sql,
    " GROUP BY cell_id HAVING COUNT(DISTINCT dim) = ?;"
  )

  DBI::dbGetQuery(
    con, q,
    params = c(list(space_id), cl$params, length(dims))
  )$cell_id
}

#' Cells available for a given matrix
#' @export
wb_cells_with_matrix <- function(bundle, matrix_id) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be a scworkbench_bundle")
  .wb_assert(is.character(matrix_id) && length(matrix_id) == 1 && nzchar(matrix_id),
             "matrix_id must be a single non-empty string")

  con <- bundle$con
  .wb_assert(.wb_table_exists(con, "matrices"), "matrices table not found in SQLite")

  row <- DBI::dbGetQuery(con, "SELECT matrix_id, n_cells FROM matrices WHERE matrix_id = ?;",
                         params = list(matrix_id))
  if (nrow(row) == 0) return(character(0))

  # If matrix exists, assume it is aligned to canonical bundle cell order.
  # (This matches wb_slice() behavior today.)
  wb_cells(bundle, cell_set = "all")
}


#' Report coverage of required inputs for a cell set
#' @export
wb_cell_coverage <- function(bundle, cell_set, inputs = list()) {
  cells <- wb_cells(bundle, cell_set = cell_set)
  res <- list(
    requested = length(cells),
    per_input = list()
  )

  current <- cells

  if (!is.null(inputs$space_id)) {
    have <- wb_cells_with_space(bundle, inputs$space_id, inputs$dims %||% NULL)
    res$per_input$space <- list(
      have = length(have),
      intersect = length(intersect(current, have))
    )
    current <- intersect(current, have)
  }

  if (!is.null(inputs$matrix_id)) {
    have <- wb_cells_with_matrix(bundle, inputs$matrix_id)
    res$per_input$matrix <- list(
      have = length(have),
      intersect = length(intersect(current, have))
    )
    current <- intersect(current, have)
  }

  res$effective <- length(current)
  res$percent <- round(100 * res$effective / res$requested, 1)
  res
}

.wb_effective_cells <- function(bundle, cell_set, inputs, op_name, min_cells = 10) {
  cov <- wb_cell_coverage(bundle, cell_set, inputs)

  if (cov$effective < min_cells) {
    msg <- paste0(
      "Op '", op_name, "' cannot run:\n",
      "  requested cells: ", cov$requested, "\n",
      "  effective cells: ", cov$effective, "\n",
      "  coverage:\n",
      paste(
        vapply(names(cov$per_input), function(k) {
          x <- cov$per_input[[k]]
          paste0("    ", k, ": ", x$intersect, "/", x$have)
        }, character(1)),
        collapse = "\n"
      )
    )
    stop(msg, call. = FALSE)
  }

  # return actual cell IDs
  cells <- wb_cells(bundle, cell_set = cell_set)
  for (k in names(inputs)) {
    if (k == "space_id") {
      cells <- intersect(cells, wb_cells_with_space(bundle, inputs$space_id, inputs$dims %||% NULL))
    }
    if (k == "matrix_id") {
      cells <- intersect(cells, wb_cells_with_matrix(bundle, inputs$matrix_id))
    }
  }
  cells
}



