# R/ops_expression.R
# scworkbench: Expression ops (built strictly on getters + cell ops)
#
# Exports:
# - wb_op_expr_slice
# - wb_op_expr_vector
# - wb_op_expr_avg_by
# - wb_op_expr_frac_nonzero_by
# - wb_op_expr_zscore_by_feature
# - wb_op_expr_pseudobulk_by
#
# These ops never touch SQLite directly; they use wb_* getters and cell ops.

.wb_is_nonneg <- function(x) all(is.finite(x) & x >= 0)

#' Slice an expression matrix (thin wrapper over wb_slice)
#'
#' @param bundle Bundle handle
#' @param matrix_id Matrix identifier
#' @param features Optional feature_ids
#' @param cells Optional cell_ids
#' @return Sparse Matrix (dgCMatrix)
#' @export
wb_op_expr_slice <- function(bundle, matrix_id, features = NULL, cells = NULL) {
  wb_slice(bundle, matrix_id = matrix_id, features = features, cells = cells)
}

#' Get one feature vector across cells (thin wrapper over wb_vector)
#'
#' @param bundle Bundle handle
#' @param matrix_id Matrix identifier
#' @param feature_id Feature ID
#' @param cells Optional cell_ids
#' @return Named numeric vector
#' @export
wb_op_expr_vector <- function(bundle, matrix_id, feature_id, cells = NULL) {
  wb_vector(bundle, matrix_id = matrix_id, feature_id = feature_id, cells = cells)
}

#' Average expression by group
#'
#' Computes per-group feature means using sparse rowMeans on slices.
#' Returns a feature x group table (wide).
#'
#' @param bundle Bundle handle
#' @param matrix_id Matrix identifier
#' @param by Metadata column name (string)
#' @param features Optional feature_ids (default all for assay)
#' @param cells Optional cell_ids to restrict analysis
#' @param drop_na Drop NA groups?
#' @return data.frame with columns: feature_id, <group1>, <group2>, ...
#' @export
wb_op_expr_avg_by <- function(bundle, matrix_id, by, features = NULL, cells = NULL, drop_na = TRUE) {
  meta <- wb_meta(bundle, cells = cells, cols = c("cell_id", by))
  .wb_require_cols(meta, c("cell_id", by), "metadata")

  if (isTRUE(drop_na)) meta <- meta[!is.na(meta[[by]]), , drop = FALSE]
  .wb_assert(nrow(meta) > 0, "No cells left after filtering (check by/drop_na/cells).")

  groups <- split(meta$cell_id, meta[[by]])

  # Compute means per group
  out <- lapply(groups, function(cell_ids) {
    x <- wb_slice(bundle, matrix_id = matrix_id, features = features, cells = cell_ids)
    Matrix::rowMeans(x)
  })

  mat <- do.call(cbind, out)
  colnames(mat) <- names(groups)

  data.frame(feature_id = rownames(mat), mat, row.names = NULL, check.names = FALSE, stringsAsFactors = FALSE)
}

#' Fraction of non-zero expression by group
#'
#' For count-like matrices, this corresponds to detection rate.
#'
#' @param bundle Bundle handle
#' @param matrix_id Matrix identifier
#' @param by Metadata column name (string)
#' @param features Optional feature_ids
#' @param cells Optional cell_ids
#' @param drop_na Drop NA groups?
#' @return data.frame with columns: feature_id, <group1>, <group2>, ...
#' @export
wb_op_expr_frac_nonzero_by <- function(bundle, matrix_id, by, features = NULL, cells = NULL, drop_na = TRUE) {
  meta <- wb_meta(bundle, cells = cells, cols = c("cell_id", by))
  .wb_require_cols(meta, c("cell_id", by), "metadata")

  if (isTRUE(drop_na)) meta <- meta[!is.na(meta[[by]]), , drop = FALSE]
  .wb_assert(nrow(meta) > 0, "No cells left after filtering (check by/drop_na/cells).")

  groups <- split(meta$cell_id, meta[[by]])

  out <- lapply(groups, function(cell_ids) {
    x <- wb_slice(bundle, matrix_id = matrix_id, features = features, cells = cell_ids)
    # detection fraction per feature
    Matrix::rowMeans(x != 0)
  })

  mat <- do.call(cbind, out)
  colnames(mat) <- names(groups)

  data.frame(feature_id = rownames(mat), mat, row.names = NULL, check.names = FALSE, stringsAsFactors = FALSE)
}

#' Z-score normalize features (row-wise) on a slice
#'
#' Returns a dense matrix (features x cells) because z-scoring typically densifies.
#' Use only for reasonably small feature/cell subsets.
#'
#' @param bundle Bundle handle
#' @param matrix_id Matrix identifier
#' @param features Feature IDs (required)
#' @param cells Optional cell IDs
#' @param center Center each feature?
#' @param scale Scale each feature by sd?
#' @return Numeric matrix (features x cells), z-scored per feature
#' @export
wb_op_expr_zscore_by_feature <- function(bundle, matrix_id, features, cells = NULL, center = TRUE, scale = TRUE) {
  .wb_assert(!is.null(features) && length(features) > 0, "features must be provided for z-scoring.")
  x <- wb_slice(bundle, matrix_id = matrix_id, features = features, cells = cells)

  # densify
  xd <- as.matrix(x)

  # row-wise scale: operate on transposed to use base::scale
  zt <- scale(t(xd), center = center, scale = scale)
  z <- t(zt)

  rownames(z) <- rownames(x)
  colnames(z) <- colnames(x)
  z
}

#' Pseudobulk by group (sum of counts per feature)
#'
#' Intended for count-like matrices (non-negative).
#' Returns a feature x group table (wide) of sums.
#'
#' @param bundle Bundle handle
#' @param matrix_id Matrix identifier
#' @param by Metadata column name (string)
#' @param features Optional feature_ids
#' @param cells Optional cell_ids
#' @param drop_na Drop NA groups?
#' @return data.frame with columns: feature_id, <group1>, <group2>, ...
#' @export
wb_op_expr_pseudobulk_by <- function(bundle, matrix_id, by, features = NULL, cells = NULL, drop_na = TRUE) {
  meta <- wb_meta(bundle, cells = cells, cols = c("cell_id", by))
  .wb_require_cols(meta, c("cell_id", by), "metadata")

  if (isTRUE(drop_na)) meta <- meta[!is.na(meta[[by]]), , drop = FALSE]
  .wb_assert(nrow(meta) > 0, "No cells left after filtering (check by/drop_na/cells).")

  groups <- split(meta$cell_id, meta[[by]])

  out <- lapply(groups, function(cell_ids) {
    x <- wb_slice(bundle, matrix_id = matrix_id, features = features, cells = cell_ids)
    # Pseudobulk sums: sparse rowSums
    Matrix::rowSums(x)
  })

  mat <- do.call(cbind, out)
  colnames(mat) <- names(groups)

  data.frame(feature_id = rownames(mat), mat, row.names = NULL, check.names = FALSE, stringsAsFactors = FALSE)
}


