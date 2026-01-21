# R/cell_coverage.R

#' Cells with coordinates available for a given space
#' @export
wb_cells_with_space <- function(bundle, space_id) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be a scworkbench_bundle handle")
  con <- bundle$con
  space_id <- as.character(space_id)

  info <- .wb_get_spaces_row(con, space_id)
  storage <- info$storage %||% ""
  dims_total <- as.integer(info$dims %||% NA_integer_)

  if (grepl("^wide:space_2d", storage) ||
      (!is.na(dims_total) && dims_total == 2 && .wb_table_exists(con, "space_2d"))) {
    df <- DBI::dbGetQuery(con,
                          "SELECT cell_id FROM space_2d WHERE space_id = ?;",
                          params = list(space_id)
    )
    return(as.character(df$cell_id))
  }

  .wb_assert(.wb_table_exists(con, "space_coords"), "space_coords table not found in SQLite")

  df <- DBI::dbGetQuery(con,
                        "SELECT DISTINCT cell_id FROM space_coords WHERE space_id = ?;",
                        params = list(space_id)
  )
  as.character(df$cell_id)
}

#' Cells with data available for a given matrix
#' @export
wb_cells_with_matrix <- function(bundle, matrix_id) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be a scworkbench_bundle handle")
  con <- bundle$con
  matrix_id <- as.character(matrix_id)

  # Ensure matrix exists
  .wb_get_matrices_row(con, matrix_id)

  # Future-proof hook: optional per-matrix coverage
  if (.wb_table_exists(con, "matrix_cells")) {
    df <- DBI::dbGetQuery(con,
                          "SELECT cell_id FROM matrix_cells WHERE matrix_id = ?;",
                          params = list(matrix_id)
    )
    return(as.character(df$cell_id))
  }

  # Current assumption: matrices cover all bundle cells
  wb_cells(bundle, cell_set = "all")
}

#' Coverage of required inputs within a cell_set
#'
#' @param cell_set e.g. "all", "core", "set:<name>", or NULL to mean "all"
#' @param inputs list(space_id=..., matrix_id=...) (either/both)
#' @export
wb_cell_coverage <- function(bundle, cell_set = "all", inputs = list()) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be a scworkbench_bundle handle")
  req_cells <- wb_cells(bundle, cell_set = cell_set)
  req_cells <- as.character(req_cells)

  res <- list(
    cell_set = cell_set,
    n_requested = length(req_cells),
    inputs = list(),
    n_effective = NA_integer_,
    pct_effective = NA_real_,
    cells_effective = character(0)
  )

  eff <- req_cells

  if (!is.null(inputs$space_id)) {
    sid <- as.character(inputs$space_id)
    has <- wb_cells_with_space(bundle, sid)

    res$inputs$space_id <- list(
      space_id = sid,
      n_available = length(has),
      n_in_set = sum(req_cells %in% has)
    )
    eff <- intersect(eff, has)
  }

  if (!is.null(inputs$matrix_id)) {
    mid <- as.character(inputs$matrix_id)
    has <- wb_cells_with_matrix(bundle, mid)

    res$inputs$matrix_id <- list(
      matrix_id = mid,
      n_available = length(has),
      n_in_set = sum(req_cells %in% has)
    )
    eff <- intersect(eff, has)
  }

  res$n_effective <- length(eff)
  res$pct_effective <- if (length(req_cells) == 0) 0 else (100 * length(eff) / length(req_cells))
  res$cells_effective <- eff

  class(res) <- "wb_cell_coverage"
  res
}
