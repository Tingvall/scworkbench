.wb_as_coord_matrix <- function(space_obj) {
  if (is.data.frame(space_obj)) {
    .wb_assert(all(c("cell_id", "x", "y") %in% colnames(space_obj)),
               "2D space data.frame must have columns cell_id, x, y")
    X <- cbind(space_obj$x, space_obj$y)
    rownames(X) <- space_obj$cell_id
    colnames(X) <- c("dim1", "dim2")
    return(X)
  }
  if (is.matrix(space_obj)) {
    .wb_assert(!is.null(rownames(space_obj)), "Space matrix must have rownames = cell_id")
    return(space_obj)
  }
  stop("Unsupported space object type returned by wb_space().", call. = FALSE)
}

.wb_space_2d_safe <- function(bundle, space_id, cells = NULL) {
  con <- bundle$con

  # Pull all coords for this space (fast enough for 50k; and avoids IN(...) limits)
  df <- DBI::dbGetQuery(
    con,
    "SELECT cell_id, x, y FROM space_2d WHERE space_id = ?;",
    params = list(space_id)
  )

  if (!nrow(df)) {
    return(df)
  }

  df$cell_id <- as.character(df$cell_id)

  if (!is.null(cells)) {
    cells <- as.character(cells)
    ii <- match(cells, df$cell_id)
    keep <- !is.na(ii)
    df <- df[ii[keep], , drop = FALSE]   # preserves requested order
    # Note: missing cells are silently dropped (projection-friendly)
  }

  df
}
