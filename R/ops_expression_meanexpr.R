#' Mean expression per cell over a set of features
#'
#' Returns a per-cell score suitable for coloring a 2D space.
#'
#' @param bundle Bundle handle
#' @param matrix_id Matrix id (RNA counts / data)
#' @param features Character vector of feature IDs
#' @param cells Optional cell subset (default all)
#' @param cell_set Named bundle cell set used to resolve the analysis universe
#' @param na_rm If TRUE, ignore NA values in the mean
#' @export
wb_op_meanexpr <- function(bundle, matrix_id, features,  cells = NULL,
                           cell_set = "core", na_rm = TRUE) {
  .wb_assert(is.character(matrix_id) && length(matrix_id) == 1 && nzchar(matrix_id),
             "matrix_id must be a single non-empty string.")
  .wb_assert(is.character(features) && length(features) >= 1,
             "features must be a non-empty character vector.")

  .wb_assert(!missing(cells) && length(cells) > 0,
             "Internal: wb_op_meanexpr() must be called with 'cells' (use wb_session_run_op).")
  if (is.null(cells)) {
    cells <- .wb_resolve_effective_cells_for_op(
      bundle  = bundle,
      op_name = "meanexpr",
      cell_set = cell_set,
      inputs = list(matrix_id = matrix_id),
      min_cells = 1
    )
  }
  cells <- as.character(cells)
  # Slice: features x cells (sparse Matrix)
  x <- wb_slice(bundle, matrix_id = matrix_id, features = features, cells = cells)

  .wb_assert(inherits(x, "Matrix") || is.matrix(x),
             "wb_slice() must return a matrix-like object.")

  v <- Matrix::colMeans(x, na.rm = na_rm)
  v <- as.numeric(v)
  names(v) <- colnames(x)

  scores <- data.frame(
    cell_id = names(v),
    value = v,
    stringsAsFactors = FALSE
  )

  list(
    scores = scores,
    params = list(
      matrix_id = matrix_id,
      n_features = length(features),
      n_cells = length(cells),
      na_rm = isTRUE(na_rm)
    )
  )
}
