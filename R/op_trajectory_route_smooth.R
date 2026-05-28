#' @keywords internal
.wb_route_smooth_resolve_features <- function(bundle, matrix_id, feature_set = NULL, features = NULL) {
  fs_feats <- NULL
  if (!is.null(feature_set)) {
    fs_name <- as.character(feature_set)[1]
    .wb_assert(nzchar(fs_name), "trajectory_route_smooth: feature_set must be a non-empty string when provided.")
    fs_feats <- unique(as.character(wb_feature_set_get(bundle, feature_set = fs_name, matrix_id = matrix_id)))
    fs_feats <- fs_feats[nzchar(fs_feats)]
    .wb_assert(length(fs_feats) > 0,
               paste0("trajectory_route_smooth: feature_set '", fs_name, "' has no members in matrix '", matrix_id, "'."))
  }

  vec_feats <- NULL
  if (!is.null(features)) {
    vec_feats <- unique(as.character(features))
    vec_feats <- vec_feats[nzchar(vec_feats)]
    .wb_assert(length(vec_feats) > 0, "trajectory_route_smooth: features is empty after cleaning.")
  }

  if (is.null(fs_feats) && is.null(vec_feats)) {
    stop("trajectory_route_smooth requires features or feature_set.", call. = FALSE)
  }
  if (!is.null(fs_feats) && is.null(vec_feats)) return(fs_feats)
  if (is.null(fs_feats) && !is.null(vec_feats)) return(vec_feats)

  out <- intersect(fs_feats, vec_feats)
  .wb_assert(length(out) > 0, "trajectory_route_smooth: feature_set and features intersection is empty.")
  out
}

#' @keywords internal
.wb_route_smooth_resolve_route <- function(pseudotime,
                                           branch_membership,
                                           route_key,
                                           cells = NULL,
                                           weight_mode = "probability",
                                           prob_min = 0) {
  .wb_assert_kind(pseudotime, "cell_vector")
  .wb_assert_kind(branch_membership, "relation_family")

  route_key <- as.character(route_key)[1]
  .wb_assert(nzchar(route_key), "trajectory_route_smooth: route_key is required.")

  pt <- suppressWarnings(as.numeric(pseudotime$value))
  names(pt) <- as.character(pseudotime$cell_id)
  keep_pt <- is.finite(pt) & nzchar(names(pt))
  pt <- pt[keep_pt]
  .wb_assert(length(pt) > 0L, "trajectory_route_smooth: pseudotime has no finite named values.")

  bm_tbl <- wb_primitive_to_table(branch_membership, include_context = FALSE)
  .wb_assert(is.data.frame(bm_tbl) && nrow(bm_tbl) > 0L, "trajectory_route_smooth: branch_membership is empty.")
  .wb_assert(all(c("key", "cell_id") %in% colnames(bm_tbl)),
             "trajectory_route_smooth: branch_membership table missing key/cell_id.")

  bm_tbl$key <- as.character(bm_tbl$key)
  bm_tbl$cell_id <- as.character(bm_tbl$cell_id)
  bm_tbl$weight_use <- if ("weight" %in% colnames(bm_tbl)) suppressWarnings(as.numeric(bm_tbl$weight)) else 1
  bm_tbl$weight_use[!is.finite(bm_tbl$weight_use)] <- 0
  bm_tbl <- bm_tbl[bm_tbl$key == route_key & nzchar(bm_tbl$cell_id), c("cell_id", "weight_use"), drop = FALSE]
  .wb_assert(nrow(bm_tbl) > 0L,
             paste0("trajectory_route_smooth: no branch_membership rows found for route_key '", route_key, "'."))

  if (!is.null(cells)) {
    keep_cells <- unique(as.character(cells))
    bm_tbl <- bm_tbl[bm_tbl$cell_id %in% keep_cells, , drop = FALSE]
  }
  .wb_assert(nrow(bm_tbl) > 0L, "trajectory_route_smooth: no route rows remain after cells restriction.")

  agg <- stats::aggregate(weight_use ~ cell_id, data = bm_tbl, FUN = max)
  names(agg)[names(agg) == "weight_use"] <- "route_weight"
  agg <- agg[agg$cell_id %in% names(pt), , drop = FALSE]
  .wb_assert(nrow(agg) > 0L, "trajectory_route_smooth: no overlap between route cells and pseudotime cells.")

  weight_mode <- match.arg(as.character(weight_mode)[1], c("probability", "binary_threshold"))
  prob_min <- as.numeric(prob_min)[1]
  if (!is.finite(prob_min)) prob_min <- 0
  prob_min <- max(0, min(1, prob_min))

  if (identical(weight_mode, "binary_threshold")) {
    agg <- agg[is.finite(agg$route_weight) & agg$route_weight >= prob_min, , drop = FALSE]
    agg$route_weight <- 1
  } else {
    agg <- agg[is.finite(agg$route_weight) & agg$route_weight > 0 & agg$route_weight >= prob_min, , drop = FALSE]
  }
  .wb_assert(nrow(agg) >= 10L,
             paste0("trajectory_route_smooth: route '", route_key, "' has fewer than 10 cells after weighting/filtering."))

  agg$pseudotime <- unname(pt[agg$cell_id])
  agg <- agg[is.finite(agg$pseudotime), , drop = FALSE]
  .wb_assert(nrow(agg) >= 10L,
             paste0("trajectory_route_smooth: route '", route_key, "' has fewer than 10 finite-pseudotime cells."))
  .wb_assert(stats::sd(agg$pseudotime) > 0,
             paste0("trajectory_route_smooth: route '", route_key, "' has zero pseudotime variance."))

  agg[order(agg$pseudotime, agg$cell_id), c("cell_id", "pseudotime", "route_weight"), drop = FALSE]
}

#' @keywords internal
.wb_route_smooth_aggregate_one <- function(entity_id,
                                           route_key,
                                           pt,
                                           values,
                                           bins,
                                           weights,
                                           min_cells_per_bin,
                                           value_col = "expr",
                                           summary_fun = "mean",
                                           weight_mode = "probability") {
  dd <- data.frame(
    entity_id = rep(as.character(entity_id), length(pt)),
    route_key = rep(as.character(route_key), length(pt)),
    pseudotime = as.numeric(pt),
    value = as.numeric(values),
    bin = as.integer(bins),
    route_weight = as.numeric(weights),
    stringsAsFactors = FALSE
  )
  dd <- dd[is.finite(dd$pseudotime) & is.finite(dd$value) & is.finite(dd$bin) & is.finite(dd$route_weight), , drop = FALSE]
  if (!nrow(dd)) return(NULL)

  sf <- as.character(summary_fun)[1]
  use_weighted <- identical(as.character(weight_mode)[1], "probability")
  if (use_weighted && identical(sf, "median")) {
    stop("trajectory_route_smooth: summary_fun='median' is not supported for weight_mode='probability'.", call. = FALSE)
  }
  ss_fun <- if (identical(sf, "median")) stats::median else base::mean

  split_idx <- interaction(dd$entity_id, dd$route_key, dd$bin, drop = TRUE, lex.order = TRUE)
  chunks <- split(dd, split_idx)
  rows <- lapply(chunks, function(z) {
    n_cells <- nrow(z)
    if (n_cells < as.integer(min_cells_per_bin)) return(NULL)
    route_weight_sum <- sum(z$route_weight, na.rm = TRUE)
    if (use_weighted && (!is.finite(route_weight_sum) || route_weight_sum <= 0)) return(NULL)

    val_use <- if (use_weighted) {
      stats::weighted.mean(z$value, w = z$route_weight, na.rm = TRUE)
    } else {
      ss_fun(z$value, na.rm = TRUE)
    }
    pt_use <- if (use_weighted) {
      stats::weighted.mean(z$pseudotime, w = z$route_weight, na.rm = TRUE)
    } else {
      ss_fun(z$pseudotime, na.rm = TRUE)
    }

    data.frame(
      entity_id = as.character(z$entity_id[1]),
      route_key = as.character(z$route_key[1]),
      bin = as.integer(z$bin[1]),
      pseudotime = as.numeric(pt_use),
      pseudotime_min = suppressWarnings(min(z$pseudotime, na.rm = TRUE)),
      pseudotime_max = suppressWarnings(max(z$pseudotime, na.rm = TRUE)),
      value = as.numeric(val_use),
      n_cells = as.integer(n_cells),
      route_weight_sum = as.numeric(route_weight_sum),
      stringsAsFactors = FALSE
    )
  })
  rows <- Filter(Negate(is.null), rows)
  if (!length(rows)) return(NULL)

  out <- do.call(rbind, rows)
  names(out)[names(out) == "value"] <- value_col
  out[order(out$bin), , drop = FALSE]
}

#' Compute Per-Feature Route Smoothing
#'
#' Summarizes per-feature expression along an explicit route using global
#' pseudotime plus route membership weights. This is the generic surface needed
#' for methods such as Palantir that emit global pseudotime and route
#' probabilities rather than lineage-specific pseudotime families.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param matrix_id Matrix identifier.
#' @param pseudotime A `cell_vector` primitive with global pseudotime.
#' @param branch_membership A `relation_family` primitive with route/branch
#'   membership weights.
#' @param route_key Route key within `branch_membership` to summarize.
#' @param cells Optional effective cell IDs to restrict analysis.
#' @param feature_set Optional feature set name in bundle feature-set registry.
#' @param features Optional explicit feature subset.
#' @param n_bins Number of pseudotime bins.
#' @param summary_fun One of `"mean"` or `"median"` across cells within each bin.
#' @param min_cells_per_bin Minimum cells required for an output bin.
#' @param weight_mode One of `"probability"` or `"binary_threshold"`.
#' @param prob_min Minimum route probability required to include a cell.
#' @param chunk_size Feature chunk size for slicing.
#'
#' @return Standard op result with `outputs$trend_table` and `outputs$fit_summary`.
#' @export
wb_op_trajectory_route_smooth <- function(bundle,
                                          matrix_id,
                                          pseudotime,
                                          branch_membership,
                                          route_key,
                                          cells = NULL,
                                          feature_set = NULL,
                                          features = NULL,
                                          n_bins = 50L,
                                          summary_fun = "mean",
                                          min_cells_per_bin = 5L,
                                          weight_mode = "probability",
                                          prob_min = 0,
                                          chunk_size = 128L) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert(is.character(matrix_id) && length(matrix_id) == 1L && nzchar(matrix_id), "matrix_id invalid")
  .wb_assert_kind(pseudotime, "cell_vector")
  .wb_assert_kind(branch_membership, "relation_family")

  summary_fun <- .wb_trajectory_smooth_summary_fun(summary_fun)
  min_cells_per_bin <- suppressWarnings(as.integer(min_cells_per_bin))
  .wb_assert(is.finite(min_cells_per_bin) && min_cells_per_bin >= 1L,
             "trajectory_route_smooth: min_cells_per_bin must be >= 1.")
  weight_mode <- match.arg(as.character(weight_mode)[1], c("probability", "binary_threshold"))

  feats <- .wb_route_smooth_resolve_features(
    bundle = bundle,
    matrix_id = matrix_id,
    feature_set = feature_set,
    features = features
  )
  route_df <- .wb_route_smooth_resolve_route(
    pseudotime = pseudotime,
    branch_membership = branch_membership,
    route_key = route_key,
    cells = cells,
    weight_mode = weight_mode,
    prob_min = prob_min
  )

  pt <- route_df$pseudotime
  cells_route <- as.character(route_df$cell_id)
  weights_route <- as.numeric(route_df$route_weight)
  bb <- .wb_trajectory_smooth_bins(pt, n_bins = n_bins)
  bins <- bb$bins
  n_bins_used <- bb$n_bins

  rows <- list()
  ri <- 0L
  for (i in seq(1L, length(feats), by = as.integer(chunk_size))) {
    j <- min(i + as.integer(chunk_size) - 1L, length(feats))
    ff <- feats[i:j]
    x <- wb_slice(bundle, matrix_id = matrix_id, features = ff, cells = cells_route)
    m <- as.matrix(x)
    for (k in seq_len(nrow(m))) {
      agg <- .wb_route_smooth_aggregate_one(
        entity_id = rownames(m)[k],
        route_key = as.character(route_key),
        pt = pt,
        values = as.numeric(m[k, ]),
        bins = bins,
        weights = weights_route,
        min_cells_per_bin = min_cells_per_bin,
        value_col = "expr",
        summary_fun = summary_fun,
        weight_mode = weight_mode
      )
      if (is.null(agg) || !nrow(agg)) next
      agg$feature_id <- as.character(agg$entity_id)
      agg$label <- as.character(agg$feature_id)
      agg <- agg[, c("feature_id", "route_key", "bin", "pseudotime", "pseudotime_min", "pseudotime_max", "expr", "n_cells", "route_weight_sum", "label"), drop = FALSE]
      ri <- ri + 1L
      rows[[ri]] <- agg
    }
  }

  tbl <- if (ri == 0L) {
    data.frame(
      feature_id = character(0),
      route_key = character(0),
      bin = integer(0),
      pseudotime = numeric(0),
      pseudotime_min = numeric(0),
      pseudotime_max = numeric(0),
      expr = numeric(0),
      n_cells = integer(0),
      route_weight_sum = numeric(0),
      label = character(0),
      stringsAsFactors = FALSE
    )
  } else {
    out <- do.call(rbind, rows[seq_len(ri)])
    rownames(out) <- NULL
    out
  }

  fit_summary <- data.frame(
    route_key = as.character(route_key),
    n_cells_route = as.integer(length(cells_route)),
    route_weight_sum = as.numeric(sum(weights_route, na.rm = TRUE)),
    n_features_input = as.integer(length(feats)),
    n_features_tested = as.integer(length(unique(as.character(tbl$feature_id %||% character(0))))),
    n_features_with_rows = as.integer(length(unique(as.character(tbl$feature_id %||% character(0))))),
    n_rows = as.integer(nrow(tbl)),
    n_bins = as.integer(n_bins_used),
    summary_fun = as.character(summary_fun),
    min_cells_per_bin = as.integer(min_cells_per_bin),
    weight_mode = as.character(weight_mode),
    prob_min = as.numeric(prob_min)[1],
    matrix_id = as.character(matrix_id),
    stringsAsFactors = FALSE
  )

  list(
    outputs = list(
      trend_table = wb_prim_obs_table(
        table = tbl,
        table_type = "trajectory_route_smooth",
        entity_kind = "trajectory_bin",
        meta = list(
          matrix_id = matrix_id,
          route_key = as.character(route_key),
          summary_fun = as.character(summary_fun),
          min_cells_per_bin = as.integer(min_cells_per_bin),
          n_bins = as.integer(n_bins_used),
          weight_mode = as.character(weight_mode),
          prob_min = as.numeric(prob_min)[1]
        )
      ),
      fit_summary = wb_prim_obs_table(
        table = fit_summary,
        table_type = "trajectory_route_smooth_summary",
        entity_kind = "route"
      )
    ),
    params = list(
      matrix_id = matrix_id,
      route_key = as.character(route_key),
      feature_set = as.character(feature_set %||% NA_character_)[1],
      n_features_input = as.integer(length(feats)),
      n_cells_route = as.integer(length(cells_route)),
      n_bins = as.integer(n_bins_used),
      summary_fun = as.character(summary_fun),
      min_cells_per_bin = as.integer(min_cells_per_bin),
      weight_mode = as.character(weight_mode),
      prob_min = as.numeric(prob_min)[1]
    )
  )
}
