# R/ops_cells.R
# scworkbench: Cell ops (fundament)
#
# These ops are pure, deterministic, and side-effect free:
# - They call getters (wb_cells, wb_meta)
# - They return cell_id vectors and/or small data.frames
#
# Exports:
# - wb_op_cells_all
# - wb_op_cells_in_dataset
# - wb_op_cells_filter
# - wb_op_cells_sample
# - wb_op_cells_intersect
# - wb_op_cells_union
# - wb_op_cells_setdiff
# - wb_op_cells_order_like
# - wb_op_cells_split_by
# - wb_op_cells_counts_by
# - wb_op_cells_top_n_by

.wb_cells_canonical <- function(bundle) {
  # Canonical cell order is defined by wb_cells(bundle)
  wb_cells(bundle)
}

.wb_cells_validate_exist <- function(bundle, cells) {
  canon <- .wb_cells_canonical(bundle)
  ii <- match(cells, canon)
  .wb_assert(!anyNA(ii), "Some cell_ids do not exist in bundle.")
  invisible(TRUE)
}

#' All cells (canonical order)
#'
#' @param bundle Bundle handle from `wb_open_bundle()`
#' @return Character vector of cell_ids in canonical bundle order
#' @export
wb_op_cells_all <- function(bundle) {
  .wb_cells_canonical(bundle)
}

#' Cells in a dataset (canonical order)
#'
#' @param bundle Bundle handle
#' @param dataset_id Dataset identifier
#' @return Character vector of cell_ids in canonical order
#' @export
wb_op_cells_in_dataset <- function(bundle, dataset_id) {
  wb_cells(bundle, dataset_id = dataset_id)
}

#' Filter cells by a predicate on metadata
#'
#' Evaluates `predicate` in the context of the cell metadata (wb_meta(bundle)).
#' Returns cell_ids for which the predicate is TRUE.
#'
#' Examples:
#'   wb_op_cells_filter(b, dataset_id == "1" & seurat_clusters == "3")
#'   wb_op_cells_filter(b, nCount_RNA > 2000 & percent.mt < 10)
#'
#' @param bundle Bundle handle
#' @param predicate A logical expression evaluated in metadata columns
#' @param cells Optional cell_ids to restrict filtering to (order preserved)
#' @param na_value Value to use when predicate returns NA (default FALSE)
#' @return Character vector of filtered cell_ids (order preserved)
#' @export
wb_op_cells_filter <- function(bundle, predicate, cells = NULL, na_value = FALSE) {
  meta <- if (is.null(cells)) wb_meta(bundle) else wb_meta(bundle, cells = cells)
  .wb_require_cols(meta, "cell_id", "metadata")

  keep <- eval(substitute(predicate), meta, parent.frame())

  .wb_assert(is.logical(keep), "predicate must evaluate to a logical vector.")
  .wb_assert(length(keep) == nrow(meta), "predicate must return one logical per cell.")

  keep[is.na(keep)] <- isTRUE(na_value)
  meta$cell_id[keep]
}

#' Sample cells (stable/reproducible)
#'
#' @param bundle Bundle handle
#' @param n Number of cells to sample
#' @param cells Optional input cell_ids to sample from (default all cells)
#' @param seed Optional integer seed for reproducibility
#' @param replace Sample with replacement?
#' @return Character vector of sampled cell_ids (in sampled order)
#' @export
wb_op_cells_sample <- function(bundle, n, cells = NULL, seed = NULL, replace = FALSE) {
  .wb_assert(is.numeric(n) && length(n) == 1 && n >= 0, "n must be a single non-negative number.")
  n <- as.integer(n)

  pool <- if (is.null(cells)) .wb_cells_canonical(bundle) else cells
  .wb_assert(length(pool) > 0 || n == 0, "No cells available to sample from.")

  if (!is.null(seed)) {
    old <- .Random.seed
    on.exit({ if (!is.null(old)) .Random.seed <<- old }, add = TRUE)
    set.seed(as.integer(seed))
  }

  sample(pool, size = n, replace = isTRUE(replace))
}

#' Intersect cell sets (preserve canonical order)
#'
#' @param bundle Bundle handle
#' @param ... One or more character vectors of cell_ids
#' @return Character vector of intersected cell_ids in canonical order
#' @export
wb_op_cells_intersect <- function(bundle, ...) {
  sets <- list(...)
  .wb_assert(length(sets) >= 1, "Provide at least one cell set.")
  canon <- .wb_cells_canonical(bundle)

  keep <- Reduce(intersect, sets)
  canon[canon %in% keep]
}

#' Union cell sets (preserve canonical order)
#'
#' @param bundle Bundle handle
#' @param ... One or more character vectors of cell_ids
#' @return Character vector of unioned cell_ids in canonical order
#' @export
wb_op_cells_union <- function(bundle, ...) {
  sets <- list(...)
  .wb_assert(length(sets) >= 1, "Provide at least one cell set.")
  canon <- .wb_cells_canonical(bundle)

  keep <- unique(unlist(sets, use.names = FALSE))
  canon[canon %in% keep]
}

#' Set difference of cell sets (A \\ B), preserving canonical order
#'
#' @param bundle Bundle handle
#' @param a Character vector (minuend)
#' @param b Character vector (subtrahend)
#' @return Character vector of cell_ids in canonical order
#' @export
wb_op_cells_setdiff <- function(bundle, a, b) {
  canon <- .wb_cells_canonical(bundle)
  keep <- setdiff(a, b)
  canon[canon %in% keep]
}

#' Reorder a cell vector to match canonical bundle order
#'
#' @param bundle Bundle handle
#' @param cells Character vector of cell_ids
#' @return `cells` reordered to canonical order (dropping unknowns is an error)
#' @export
wb_op_cells_order_like <- function(bundle, cells) {
  canon <- .wb_cells_canonical(bundle)
  ii <- match(cells, canon)
  .wb_assert(!anyNA(ii), "Some cell_ids do not exist in bundle.")
  canon[sort(ii)]
}

#' Split cells by a metadata column
#'
#' Returns a named list: group -> cell_ids (each group in canonical order).
#'
#' @param bundle Bundle handle
#' @param by Metadata column name (string)
#' @param cells Optional cell_ids to restrict splitting to
#' @param drop_na Drop NA groups?
#' @return Named list of character vectors
#' @export
wb_op_cells_split_by <- function(bundle, by, cells = NULL, drop_na = TRUE) {
  meta <- if (is.null(cells)) wb_meta(bundle, cols = c("cell_id", by)) else wb_meta(bundle, cells = cells, cols = c("cell_id", by))
  .wb_require_cols(meta, c("cell_id", by), "metadata")

  if (isTRUE(drop_na)) meta <- meta[!is.na(meta[[by]]), , drop = FALSE]

  canon <- .wb_cells_canonical(bundle)
  # preserve canonical order by ordering meta by canonical index
  ord <- match(meta$cell_id, canon)
  meta <- meta[order(ord), , drop = FALSE]

  split(meta$cell_id, meta[[by]])
}

#' Count cells by a metadata column
#'
#' @param bundle Bundle handle
#' @param by Metadata column name (string)
#' @param cells Optional cell_ids to restrict counting to
#' @param drop_na Drop NA groups?
#' @return data.frame with columns: group, n_cells
#' @export
wb_op_cells_counts_by <- function(bundle, by, cells = NULL, drop_na = TRUE) {
  groups <- wb_op_cells_split_by(bundle, by = by, cells = cells, drop_na = drop_na)
  data.frame(
    group = names(groups),
    n_cells = as.integer(vapply(groups, length, integer(1))),
    row.names = NULL,
    stringsAsFactors = FALSE
  )
}

#' Top-N groups by cell count for a metadata column
#'
#' Useful for fast "largest clusters" selection.
#'
#' @param bundle Bundle handle
#' @param by Metadata column name (string)
#' @param n Number of top groups to return
#' @param cells Optional cell_ids to restrict counting to
#' @param drop_na Drop NA groups?
#' @return Character vector of group names (length <= n)
#' @export
wb_op_cells_top_n_by <- function(bundle, by, n = 10, cells = NULL, drop_na = TRUE) {
  .wb_assert(is.numeric(n) && length(n) == 1 && n >= 1, "n must be a single positive number.")
  n <- as.integer(n)

  tab <- wb_op_cells_counts_by(bundle, by = by, cells = cells, drop_na = drop_na)
  tab <- tab[order(tab$n_cells, decreasing = TRUE), , drop = FALSE]
  head(tab$group, n)
}


