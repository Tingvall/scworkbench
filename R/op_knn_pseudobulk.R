#' kNN pseudobulk around query cells in latent space
#'
#' Treats query cells (for example projected bulk samples) as anchors in a shared
#' latent space, finds nearest neighbors, and aggregates expression in a matrix.
#'
#' @param bundle Bundle handle
#' @param matrix_id Matrix identifier for aggregation
#' @param space_id Space identifier used for kNN search
#' @param query_cells Character vector of query cell IDs
#' @param candidate_cells Optional candidate pool for neighbors (defaults to effective cells)
#' @param features Optional feature IDs (default all matrix features)
#' @param k Number of neighbors per query cell
#' @param include_query Include the query cell itself in neighbor pool if present
#' @param aggregate Aggregation mode: "sum" or "mean"
#' @export
wb_op_knn_pseudobulk <- function(bundle,
                                 matrix_id,
                                 space_id,
                                 query_cells,
                                 candidate_cells = NULL,
                                 features = NULL,
                                 k = 100,
                                 include_query = FALSE,
                                 aggregate = c("sum", "mean")) {
  .wb_require_pkg("Matrix", "kNN pseudobulk aggregation")

  aggregate <- match.arg(aggregate)
  .wb_assert(is.character(matrix_id) && length(matrix_id) == 1 && nzchar(matrix_id),
             "matrix_id must be a single non-empty string.")
  .wb_assert(is.character(space_id) && length(space_id) == 1 && nzchar(space_id),
             "space_id must be a single non-empty string.")
  .wb_assert(is.character(query_cells) && length(query_cells) > 0,
             "query_cells must be a non-empty character vector.")
  .wb_assert(is.numeric(k) && length(k) == 1 && as.integer(k) >= 1,
             "k must be >= 1.")

  query_cells <- unique(as.character(query_cells))
  candidate_cells <- if (is.null(candidate_cells)) character(0) else unique(as.character(candidate_cells))

  feature_ids <- if (is.null(features)) wb_feature_ids(bundle, matrix_id = matrix_id) else as.character(features)
  .wb_assert(length(feature_ids) > 0, "No features available for kNN pseudobulk.")

  base_pool <- unique(c(candidate_cells, query_cells))
  .wb_assert(length(base_pool) > 1, "Need at least two cells in query/candidate pool.")

  coords_obj <- wb_space(bundle, space_id = space_id, cells = base_pool)
  coords <- .wb_space_to_matrix(coords_obj, requested_cells = base_pool)

  # Keep only query cells present in coordinates.
  query_cells <- query_cells[query_cells %in% rownames(coords)]
  .wb_assert(length(query_cells) > 0, "None of query_cells were found in the selected space.")

  if (length(candidate_cells) == 0) {
    candidate_cells <- setdiff(rownames(coords), if (isTRUE(include_query)) character(0) else query_cells)
  } else {
    candidate_cells <- candidate_cells[candidate_cells %in% rownames(coords)]
    if (!isTRUE(include_query)) candidate_cells <- setdiff(candidate_cells, query_cells)
  }
  .wb_assert(length(candidate_cells) >= 1, "candidate_cells resolved to empty set.")

  cand_mat <- coords[candidate_cells, , drop = FALSE]

  rows <- vector("list", length(query_cells))
  dist_key <- character(0)
  dist_cell <- character(0)
  dist_val <- numeric(0)

  for (i in seq_along(query_cells)) {
    q <- query_cells[i]
    qv <- coords[q, , drop = TRUE]
    d <- sqrt(rowSums((cand_mat - matrix(qv, nrow = nrow(cand_mat), ncol = ncol(cand_mat), byrow = TRUE))^2))
    ord <- order(d, decreasing = FALSE)
    nkeep <- min(as.integer(k), length(ord))
    idx <- ord[seq_len(nkeep)]
    nn_cells <- rownames(cand_mat)[idx]
    nn_dist <- as.numeric(d[idx])

    x <- wb_slice(bundle, matrix_id = matrix_id, features = feature_ids, cells = nn_cells)
    agg <- if (identical(aggregate, "sum")) Matrix::rowSums(x) else Matrix::rowMeans(x)

    rows[[i]] <- data.frame(
      feature_id = rownames(x),
      query_cell_id = q,
      n_neighbors = length(nn_cells),
      aggregate = aggregate,
      value = as.numeric(agg),
      stringsAsFactors = FALSE
    )

    dist_key <- c(dist_key, rep(q, length(nn_cells)))
    dist_cell <- c(dist_cell, nn_cells)
    dist_val <- c(dist_val, nn_dist)
  }

  tbl <- do.call(rbind, rows)
  rownames(tbl) <- NULL

  list(
    outputs = list(
      pseudobulk_table = wb_prim_feature_table(
        table = tbl,
        table_type = "knn_pseudobulk",
        meta = list(
          matrix_id = matrix_id,
          space_id = space_id,
          k = as.integer(k),
          aggregate = aggregate
        )
      ),
      neighbor_distance = wb_prim_cell_vector_family(
        key = dist_key,
        cell_id = dist_cell,
        value = dist_val,
        value_type = "continuous"
      )
    ),
    params = list(
      matrix_id = matrix_id,
      space_id = space_id,
      n_query = length(query_cells),
      n_candidates = length(candidate_cells),
      n_features = length(feature_ids),
      k = as.integer(k),
      aggregate = aggregate,
      include_query = isTRUE(include_query)
    )
  )
}

.wb_space_to_matrix <- function(x, requested_cells = NULL) {
  if (is.matrix(x)) {
    .wb_assert(!is.null(rownames(x)), "space matrix must have rownames = cell_id")
    out <- x
  } else if (is.data.frame(x) && all(c("cell_id", "x", "y") %in% names(x))) {
    out <- as.matrix(x[, c("x", "y"), drop = FALSE])
    rownames(out) <- as.character(x$cell_id)
  } else if (is.data.frame(x) && all(c("cell_id", "dim", "value") %in% names(x))) {
    out <- .wb_as_coord_matrix(x)
  } else {
    stop("Unsupported space payload for kNN pseudobulk.", call. = FALSE)
  }

  mode(out) <- "numeric"
  if (!is.null(requested_cells)) {
    requested_cells <- as.character(requested_cells)
    keep <- requested_cells[requested_cells %in% rownames(out)]
    out <- out[keep, , drop = FALSE]
  }
  out
}

