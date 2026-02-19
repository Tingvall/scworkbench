#' Cells with available coordinates for a space
#'
#' Returns the cell IDs that have coordinates available for `space_id`.
#' For `wide:space_2d`, this is any cell present in `space_2d`.
#' For `long:space_coords`, this is any cell with all requested dimensions.
#'
#' @param bundle scworkbench bundle handle.
#' @param space_id Space identifier.
#' @param dims Optional integer vector of required dimensions for long-form spaces.
#'
#' @return Character vector of `cell_id`.
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
#'
#' Returns cell IDs that are available for `matrix_id`.
#' In current bundles, matrices are assumed aligned to canonical bundle cell order.
#'
#' @param bundle scworkbench bundle handle.
#' @param matrix_id Matrix identifier.
#'
#' @return Character vector of `cell_id` in canonical order, or empty if matrix_id is unknown.
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
#'
#' Computes how many cells in `cell_set` are covered by required inputs
#' (currently `space_id` and/or `matrix_id`) and returns a compact summary.
#'
#' @param bundle scworkbench bundle handle.
#' @param cell_set Cell set selector (e.g. `"core"`, `"all"`, `"set:<name>"`).
#' @param inputs Named list of required inputs. Recognized keys include
#'   `space_id`, `matrix_id`, and optional `dims` for space coverage.
#'
#' @return List with fields:
#'   `requested`, `per_input`, `effective`, `percent`.
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

  # NEW: explicit cell_ids override the "requested" universe
  requested_cells <- NULL
  if (!is.null(inputs$cell_ids)) {
    requested_cells <- as.character(inputs$cell_ids)
    requested_cells <- unique(requested_cells[nzchar(requested_cells)])
    .wb_assert(length(requested_cells) > 0, "inputs$cell_ids provided but empty.")
  } else {
    requested_cells <- wb_cells(bundle, cell_set = cell_set)
  }

  cov <- wb_cell_coverage(bundle, cell_set, inputs)  # you may want to also let coverage use cell_ids (optional)

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
  cells <- requested_cells

  # apply per-input availability intersections
  for (k in names(inputs)) {
    if (k == "space_id") {
      cells <- intersect(cells, wb_cells_with_space(bundle, inputs$space_id, inputs$dims %||% NULL))
    }
    if (k == "matrix_id") {
      cells <- intersect(cells, wb_cells_with_matrix(bundle, inputs$matrix_id))
    }
  }

  .wb_assert(length(cells) >= min_cells,
             paste0("Op '", op_name, "' cannot run: effective cells < min_cells after intersections."))

  cells
}



.wb_resolve_effective_cells_for_op <- function(bundle, op_name, cell_set,
                                               inputs = list(),
                                               min_cells = 10) {
  cell_set <- cell_set %||% "core"
  .wb_assert(is.character(cell_set) && length(cell_set) == 1 && nzchar(cell_set),
             "cell_set must be a single non-empty string.")

  .wb_effective_cells(
    bundle = bundle,
    cell_set = cell_set,
    inputs = inputs,
    op_name = op_name,
    min_cells = min_cells
  )
}


