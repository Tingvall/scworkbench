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
