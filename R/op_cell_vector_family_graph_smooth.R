#' Smooth A Cell Vector Family Over Local Cell Geometry
#'
#' Uses nearest neighbors in a bundle space to smooth each key of a
#' `cell_vector_family` independently. The operation is generic: keys can be
#' UCell signatures, chromVAR motifs, classifier probabilities, module scores,
#' or any other numeric per-cell signal family.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param signal `cell_vector_family` primitive.
#' @param space_id Bundle space identifier used for nearest-neighbor geometry.
#' @param cells Optional cell subset. Defaults to cells present in `signal`.
#' @param signal_keys Optional key subset.
#' @param dims Optional integer dimensions of `space_id`. `NULL` uses all dims.
#' @param k Number of neighbors per cell.
#' @param alpha Raw/smoothed blend weight in `[0, 1]`.
#' @param distance_metric Distance metric. Currently only `"euclidean"`.
#' @param query_chunk_size Number of query cells per RANN query chunk.
#' @param include_self Include each cell itself in its neighbor set.
#' @param na_policy Missing score handling: `"ignore"`, `"zero"`, or
#'   `"propagate"`.
#' @param cell_set Optional label copied into metadata.
#' @param source_signal_artifact_id Optional source artifact ID copied into
#'   metadata.
#' @param source_run_id Optional source run ID copied into metadata.
#' @param source_snapshot_id Optional source provenance snapshot ID copied into
#'   metadata.
#'
#' @return Standard op result with `outputs$smoothed_signal` as a
#'   `cell_vector_family` and `outputs$smoothing_summary` as an `obs_table`.
#' @export
wb_op_cell_vector_family_graph_smooth <- function(bundle,
                                                  signal,
                                                  space_id,
                                                  cells = NULL,
                                                  signal_keys = NULL,
                                                  dims = NULL,
                                                  k = 30L,
                                                  alpha = 0.5,
                                                  distance_metric = c("euclidean"),
                                                  query_chunk_size = 512L,
                                                  include_self = FALSE,
                                                  na_policy = c("ignore", "zero", "propagate"),
                                                  cell_set = NULL,
                                                  source_signal_artifact_id = NULL,
                                                  source_run_id = NULL,
                                                  source_snapshot_id = NULL) {
  .wb_require_pkg("RANN", "cell_vector_family_graph_smooth nearest-neighbor smoothing")
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle.")
  .wb_assert_kind(signal, "cell_vector_family")

  distance_metric <- match.arg(distance_metric)
  na_policy <- match.arg(na_policy)
  .wb_assert(identical(distance_metric, "euclidean"),
             "cell_vector_family_graph_smooth currently supports only distance_metric='euclidean'.")

  k <- suppressWarnings(as.integer(k)[1])
  query_chunk_size <- suppressWarnings(as.integer(query_chunk_size)[1])
  alpha <- suppressWarnings(as.numeric(alpha)[1])
  .wb_assert(is.finite(k) && k >= 1L, "k must be a positive integer.")
  .wb_assert(is.finite(query_chunk_size) && query_chunk_size >= 1L,
             "query_chunk_size must be a positive integer.")
  .wb_assert(is.finite(alpha) && alpha >= 0 && alpha <= 1,
             "alpha must be a finite number in [0, 1].")

  sm <- .wb_cell_vector_family_score_matrix(signal, signal_keys = signal_keys)
  score_mat <- sm$matrix
  keys <- sm$keys

  if (!is.null(cells)) {
    cells <- unique(as.character(cells))
    cells <- cells[nzchar(cells)]
    keep <- intersect(cells, rownames(score_mat))
    .wb_assert(length(keep) > 1L, "Need at least two selected cells with signal rows for graph smoothing.")
    score_mat <- score_mat[keep, , drop = FALSE]
  }

  coords <- .wb_cvf_graph_smooth_coords(
    bundle = bundle,
    space_id = space_id,
    cells = rownames(score_mat),
    dims = dims
  )
  keep_cells <- intersect(rownames(score_mat), rownames(coords))
  .wb_assert(length(keep_cells) > 1L, "Need at least two cells with both signal and space coordinates.")
  score_mat <- score_mat[keep_cells, , drop = FALSE]
  coords <- coords[keep_cells, , drop = FALSE]

  finite_coord <- stats::complete.cases(coords)
  .wb_assert(any(finite_coord), "No cells have complete finite coordinates in the selected space/dims.")
  if (!all(finite_coord)) {
    score_mat <- score_mat[finite_coord, , drop = FALSE]
    coords <- coords[finite_coord, , drop = FALSE]
  }
  .wb_assert(nrow(coords) > 1L, "Need at least two cells with complete coordinates for graph smoothing.")

  smooth <- .wb_cvf_graph_smooth_matrix(
    score_mat = score_mat,
    coords = coords,
    k = k,
    alpha = alpha,
    query_chunk_size = query_chunk_size,
    include_self = isTRUE(include_self),
    na_policy = na_policy
  )

  out_mat <- smooth$smoothed
  long <- .wb_cvf_graph_smooth_long(out_mat, keys = keys)

  method <- paste0("smoothed_score = alpha * raw_score + (1 - alpha) * neighbor_mean_score")
  dims_meta <- if (is.null(dims)) NULL else as.integer(dims)
  meta <- list(
    source_signal_artifact_id = as.character(source_signal_artifact_id %||% NA_character_)[1],
    source_run_id = as.character(source_run_id %||% NA_character_)[1],
    source_snapshot_id = as.character(source_snapshot_id %||% NA_character_)[1],
    source_space_id = as.character(space_id)[1],
    neighbor_artifact_id = NA_character_,
    selected_keys = keys,
    selected_cells = as.character(cell_set %||% NA_character_)[1],
    n_cells_input_signal = nrow(sm$matrix),
    n_cells_smoothed = nrow(out_mat),
    dims = dims_meta,
    k = k,
    alpha = alpha,
    smoothing_method = "knn_neighbor_mean_blend",
    smoothing_formula = method,
    distance_metric = distance_metric,
    query_chunk_size = query_chunk_size,
    include_self = isTRUE(include_self),
    na_policy = na_policy,
    scworkbench_version = as.character(utils::packageVersion("scworkbench"))
  )

  summary <- .wb_cvf_graph_smooth_summary(
    raw = score_mat,
    smoothed = out_mat,
    neighbor_counts = smooth$neighbor_counts,
    keys = keys,
    meta = meta
  )

  list(
    outputs = list(
      smoothed_signal = wb_prim_cell_vector_family(
        key = long$key,
        cell_id = long$cell_id,
        value = long$value,
        value_type = as.character(signal$value_type %||% "continuous")[1]
      ),
      smoothing_summary = wb_prim_obs_table(
        table = summary,
        table_type = "cell_vector_family_graph_smooth_summary",
        entity_kind = "signal_key",
        meta = meta
      )
    ),
    params = list(
      signal_keys = keys,
      n_keys = length(keys),
      n_cells = nrow(out_mat),
      source_space_id = as.character(space_id)[1],
      dims = dims_meta,
      k = k,
      alpha = alpha,
      smoothing_method = "knn_neighbor_mean_blend",
      distance_metric = distance_metric,
      query_chunk_size = query_chunk_size,
      include_self = isTRUE(include_self),
      na_policy = na_policy
    )
  )
}

.wb_cvf_graph_smooth_coords <- function(bundle, space_id, cells, dims = NULL) {
  space_id <- as.character(space_id)[1]
  .wb_assert(nzchar(space_id), "space_id must be a non-empty string.")
  cells <- unique(as.character(cells))
  cells <- cells[nzchar(cells)]
  .wb_assert(length(cells) > 1L, "Need at least two cells for graph smoothing.")
  if (!is.null(dims)) {
    dims <- suppressWarnings(as.integer(dims))
    .wb_assert(length(dims) > 0L && !anyNA(dims), "dims must be NULL or a non-empty integer vector.")
  }

  X <- .wb_as_coord_matrix(wb_space(bundle, space_id = space_id, cells = cells, dims = dims))
  if (!identical(rownames(X), cells)) {
    ii <- match(cells, rownames(X))
    .wb_assert(!anyNA(ii), "Some selected cells are missing in the selected space.")
    X <- X[ii, , drop = FALSE]
    rownames(X) <- cells
  }
  mode(X) <- "numeric"
  X
}

.wb_cvf_graph_smooth_matrix <- function(score_mat,
                                        coords,
                                        k,
                                        alpha,
                                        query_chunk_size,
                                        include_self,
                                        na_policy) {
  .wb_assert(identical(rownames(score_mat), rownames(coords)),
             "Internal: score matrix and coordinate matrix must have identical rownames.")
  n <- nrow(coords)
  k_eff <- min(as.integer(k), if (isTRUE(include_self)) n else n - 1L)
  .wb_assert(k_eff >= 1L, "Not enough cells to compute requested neighbors.")
  kk <- min(n, k_eff + if (isTRUE(include_self)) 0L else 1L)

  smoothed <- matrix(NA_real_, nrow = nrow(score_mat), ncol = ncol(score_mat),
                     dimnames = dimnames(score_mat))
  neighbor_counts <- integer(n)
  chunks <- split(seq_len(n), ceiling(seq_len(n) / as.integer(query_chunk_size)))

  for (idx in chunks) {
    nn <- RANN::nn2(data = coords, query = coords[idx, , drop = FALSE], k = kk)
    for (j in seq_along(idx)) {
      i <- idx[j]
      nbr <- as.integer(nn$nn.idx[j, ])
      nbr <- nbr[nbr >= 1L & nbr <= n]
      if (!isTRUE(include_self)) nbr <- nbr[nbr != i]
      if (length(nbr) > k_eff) nbr <- nbr[seq_len(k_eff)]
      neighbor_counts[i] <- length(nbr)
      if (!length(nbr)) {
        smoothed[i, ] <- score_mat[i, ]
        next
      }

      vals <- score_mat[nbr, , drop = FALSE]
      neighbor_mean <- .wb_cvf_graph_neighbor_mean(vals, na_policy = na_policy)
      raw <- score_mat[i, ]
      smoothed[i, ] <- .wb_cvf_graph_blend(raw, neighbor_mean, alpha = alpha, na_policy = na_policy)
    }
  }

  list(smoothed = smoothed, neighbor_counts = neighbor_counts)
}

.wb_cvf_graph_neighbor_mean <- function(vals, na_policy) {
  if (identical(na_policy, "zero")) {
    vals2 <- vals
    vals2[!is.finite(vals2)] <- 0
    return(colMeans(vals2))
  }
  if (identical(na_policy, "propagate")) {
    out <- colMeans(vals)
    out[colSums(!is.finite(vals)) > 0L] <- NA_real_
    return(out)
  }
  suppressWarnings(colMeans(vals, na.rm = TRUE))
}

.wb_cvf_graph_blend <- function(raw, neighbor_mean, alpha, na_policy) {
  raw <- as.numeric(raw)
  neighbor_mean <- as.numeric(neighbor_mean)
  if (identical(na_policy, "zero")) {
    raw[!is.finite(raw)] <- 0
    neighbor_mean[!is.finite(neighbor_mean)] <- 0
    return(alpha * raw + (1 - alpha) * neighbor_mean)
  }
  out <- alpha * raw + (1 - alpha) * neighbor_mean
  raw_ok <- is.finite(raw)
  nbr_ok <- is.finite(neighbor_mean)
  out[raw_ok & !nbr_ok] <- raw[raw_ok & !nbr_ok]
  out[!raw_ok & nbr_ok] <- neighbor_mean[!raw_ok & nbr_ok]
  out[!raw_ok & !nbr_ok] <- NA_real_
  out
}

.wb_cvf_graph_smooth_long <- function(mat, keys) {
  cells <- rownames(mat)
  key <- rep(keys, each = length(cells))
  cell_id <- rep(cells, times = length(keys))
  value <- as.numeric(mat[cbind(cell_id, key)])
  data.frame(key = key, cell_id = cell_id, value = value, stringsAsFactors = FALSE)
}

.wb_cvf_graph_smooth_summary <- function(raw, smoothed, neighbor_counts, keys, meta) {
  rows <- lapply(keys, function(key) {
    rv <- raw[, key]
    sv <- smoothed[, key]
    data.frame(
      key = key,
      n_cells = length(rv),
      n_cells_smoothed = sum(is.finite(sv)),
      n_missing_before = sum(!is.finite(rv)),
      n_missing_after = sum(!is.finite(sv)),
      raw_mean = mean(rv, na.rm = TRUE),
      smoothed_mean = mean(sv, na.rm = TRUE),
      raw_sd = stats::sd(rv, na.rm = TRUE),
      smoothed_sd = stats::sd(sv, na.rm = TRUE),
      avg_neighbor_count = mean(neighbor_counts),
      k = as.integer(meta$k),
      alpha = as.numeric(meta$alpha),
      smoothing_method = as.character(meta$smoothing_method),
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}
