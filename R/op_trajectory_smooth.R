#' @keywords internal
.wb_trajectory_smooth_resolve_lineages <- function(model, lineage = NULL, cells = NULL) {
  pt_df <- .wb_trajectory_de_resolve_pt(model)
  .wb_assert(is.data.frame(pt_df) && nrow(pt_df) > 0L,
             "trajectory_smooth: resolved pseudotime is empty.")

  if (!is.null(cells)) {
    keep_cells <- unique(as.character(cells))
    pt_df <- pt_df[as.character(pt_df$cell_id) %in% keep_cells, , drop = FALSE]
  }

  if (!is.null(lineage)) {
    lineage <- unique(as.character(lineage))
    lineage <- lineage[nzchar(lineage)]
    .wb_assert(length(lineage) > 0L, "trajectory_smooth: lineage is empty after cleaning.")
    pt_df <- pt_df[as.character(pt_df$lineage_id) %in% lineage, , drop = FALSE]
  }

  .wb_assert(nrow(pt_df) > 0L, "trajectory_smooth: no pseudotime rows remain after filters.")
  split(pt_df, as.character(pt_df$lineage_id))
}

#' @keywords internal
.wb_trajectory_smooth_feature_ids <- function(bundle, matrix_id, feature_set = NULL, features = NULL) {
  fs_feats <- NULL
  if (!is.null(feature_set)) {
    fs_name <- as.character(feature_set)[1]
    .wb_assert(nzchar(fs_name), "trajectory_smooth: feature_set must be a non-empty string when provided.")
    fs_feats <- unique(as.character(wb_feature_set_get(bundle, feature_set = fs_name, matrix_id = matrix_id)))
    fs_feats <- fs_feats[nzchar(fs_feats)]
    .wb_assert(length(fs_feats) > 0L,
               paste0("trajectory_smooth: feature_set '", fs_name, "' has no members in matrix '", matrix_id, "'."))
  }

  vec_feats <- NULL
  if (!is.null(features)) {
    vec_feats <- unique(as.character(features))
    vec_feats <- vec_feats[nzchar(vec_feats)]
    .wb_assert(length(vec_feats) > 0L, "trajectory_smooth: features is empty after cleaning.")
  }

  if (is.null(fs_feats) && is.null(vec_feats)) {
    stop("trajectory_smooth requires features or feature_set.", call. = FALSE)
  }
  if (!is.null(fs_feats) && is.null(vec_feats)) return(fs_feats)
  if (is.null(fs_feats) && !is.null(vec_feats)) return(vec_feats)

  out <- intersect(fs_feats, vec_feats)
  .wb_assert(length(out) > 0L,
             "trajectory_smooth: feature_set and features intersection is empty.")
  out
}

#' @keywords internal
.wb_trajectory_smooth_summary_fun <- function(summary_fun) {
  sf <- as.character(summary_fun %||% "mean")[1]
  if (!nzchar(sf)) sf <- "mean"
  .wb_assert(sf %in% c("mean", "median"),
             "trajectory_smooth: summary_fun must be 'mean' or 'median'.")
  sf
}

#' @keywords internal
.wb_trajectory_signature_score_fun <- function(score_method) {
  sm <- as.character(score_method %||% "mean")[1]
  if (!nzchar(sm)) sm <- "mean"
  .wb_assert(sm %in% c("mean", "sum"),
             "trajectory_signature_smooth: score_method must be 'mean' or 'sum'.")
  sm
}

#' @keywords internal
.wb_trajectory_smooth_bins <- function(pt, n_bins) {
  n_bins <- suppressWarnings(as.integer(n_bins))
  if (!is.finite(n_bins) || n_bins < 5L) n_bins <- 50L
  n_bins <- min(n_bins, max(5L, length(unique(pt))))
  bins <- as.integer(cut(pt, breaks = n_bins, include.lowest = TRUE, labels = FALSE))
  .wb_assert(all(is.finite(bins)), "trajectory_smooth: failed to build pseudotime bins.")
  list(bins = bins, n_bins = as.integer(n_bins))
}

#' @keywords internal
.wb_trajectory_smooth_aggregate_one <- function(entity_id,
                                                lineage_id,
                                                pt,
                                                values,
                                                bins,
                                                min_cells_per_bin,
                                                value_col = "expr",
                                                summary_fun = "mean") {
  dd <- data.frame(
    entity_id = rep(as.character(entity_id), length(pt)),
    lineage_id = rep(as.character(lineage_id), length(pt)),
    pseudotime = as.numeric(pt),
    value = as.numeric(values),
    bin = as.integer(bins),
    stringsAsFactors = FALSE
  )
  dd <- dd[is.finite(dd$pseudotime) & is.finite(dd$value) & is.finite(dd$bin), , drop = FALSE]
  if (!nrow(dd)) return(NULL)

  ss_fun <- if (identical(summary_fun, "median")) stats::median else base::mean
  agg <- stats::aggregate(
    dd[, c("pseudotime", "value")],
    by = list(entity_id = dd$entity_id, lineage_id = dd$lineage_id, bin = dd$bin),
    FUN = function(z) ss_fun(z, na.rm = TRUE)
  )
  nn <- stats::aggregate(
    dd$value,
    by = list(entity_id = dd$entity_id, lineage_id = dd$lineage_id, bin = dd$bin),
    FUN = function(z) as.integer(sum(is.finite(z)))
  )
  names(nn)[names(nn) == "x"] <- "n_cells"
  out <- merge(agg, nn, by = c("entity_id", "lineage_id", "bin"), all.x = TRUE, sort = FALSE)

  pmin <- stats::aggregate(
    dd$pseudotime,
    by = list(entity_id = dd$entity_id, lineage_id = dd$lineage_id, bin = dd$bin),
    FUN = function(z) suppressWarnings(min(z, na.rm = TRUE))
  )
  pmax <- stats::aggregate(
    dd$pseudotime,
    by = list(entity_id = dd$entity_id, lineage_id = dd$lineage_id, bin = dd$bin),
    FUN = function(z) suppressWarnings(max(z, na.rm = TRUE))
  )
  names(pmin)[names(pmin) == "x"] <- "pseudotime_min"
  names(pmax)[names(pmax) == "x"] <- "pseudotime_max"
  out <- merge(out, pmin, by = c("entity_id", "lineage_id", "bin"), all.x = TRUE, sort = FALSE)
  out <- merge(out, pmax, by = c("entity_id", "lineage_id", "bin"), all.x = TRUE, sort = FALSE)

  names(out)[names(out) == "value"] <- value_col
  out <- out[is.finite(out$n_cells) & out$n_cells >= as.integer(min_cells_per_bin), , drop = FALSE]
  if (!nrow(out)) return(NULL)
  out[order(out$bin), , drop = FALSE]
}

#' Compute Per-Feature Trajectory Smoothing
#'
#' Computes per-feature expression summaries along lineage pseudotime from a trajectory model.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param matrix_id Matrix identifier.
#' @param model A `model_ref` primitive from trajectory fitting.
#' @param cells Optional effective cell IDs to restrict analysis.
#' @param lineage Optional lineage key subset.
#' @param feature_set Optional feature set name in bundle feature-set registry.
#' @param features Optional explicit feature subset (intersected with `feature_set` when both provided).
#' @param n_bins Number of pseudotime bins.
#' @param summary_fun One of `"mean"` or `"median"`.
#' @param min_cells_per_bin Minimum cells required for an output bin.
#' @param chunk_size Feature chunk size for slicing.
#'
#' @return A standard op result list with `outputs` containing `trend_table` and
#'   `fit_summary`, plus normalized `params`.
#'
#' @export
wb_op_trajectory_smooth <- function(bundle,
                                    matrix_id,
                                    model,
                                    cells = NULL,
                                    lineage = NULL,
                                    feature_set = NULL,
                                    features = NULL,
                                    n_bins = 50L,
                                    summary_fun = "mean",
                                    min_cells_per_bin = 5L,
                                    chunk_size = 128L) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert(is.character(matrix_id) && length(matrix_id) == 1 && nzchar(matrix_id), "matrix_id invalid")
  .wb_assert_kind(model, "model_ref")

  summary_fun <- .wb_trajectory_smooth_summary_fun(summary_fun)
  min_cells_per_bin <- suppressWarnings(as.integer(min_cells_per_bin))
  .wb_assert(is.finite(min_cells_per_bin) && min_cells_per_bin >= 1L,
             "trajectory_smooth: min_cells_per_bin must be >= 1.")

  feats <- .wb_trajectory_smooth_feature_ids(
    bundle = bundle,
    matrix_id = matrix_id,
    feature_set = feature_set,
    features = features
  )
  lineages <- .wb_trajectory_smooth_resolve_lineages(model = model, lineage = lineage, cells = cells)

  rows <- list()
  fit_rows <- list()
  ri <- 0L
  si <- 0L

  for (lin in names(lineages)) {
    df_lin <- lineages[[lin]]
    pt <- suppressWarnings(as.numeric(df_lin$pseudotime))
    names(pt) <- as.character(df_lin$cell_id)
    keep <- is.finite(pt)
    pt <- pt[keep]
    cells_lin <- as.character(names(pt))
    .wb_assert(length(cells_lin) >= 10L,
               paste0("trajectory_smooth: lineage '", lin, "' has <10 finite pseudotime cells."))
    .wb_assert(stats::sd(pt) > 0,
               paste0("trajectory_smooth: lineage '", lin, "' has zero pseudotime variance."))

    bb <- .wb_trajectory_smooth_bins(pt, n_bins = n_bins)
    bins <- bb$bins
    n_bins_used <- bb$n_bins
    n_rows_lineage <- 0L
    n_entities_with_rows <- 0L

    for (i in seq(1L, length(feats), by = as.integer(chunk_size))) {
      j <- min(i + as.integer(chunk_size) - 1L, length(feats))
      ff <- feats[i:j]
      x <- wb_slice(bundle, matrix_id = matrix_id, features = ff, cells = cells_lin)
      m <- as.matrix(x)
      for (k in seq_len(nrow(m))) {
        agg <- .wb_trajectory_smooth_aggregate_one(
          entity_id = rownames(m)[k],
          lineage_id = lin,
          pt = pt,
          values = as.numeric(m[k, ]),
          bins = bins,
          min_cells_per_bin = min_cells_per_bin,
          value_col = "expr",
          summary_fun = summary_fun
        )
        if (is.null(agg) || !nrow(agg)) next
        agg$feature_id <- as.character(agg$entity_id)
        agg$label <- as.character(agg$feature_id)
        agg <- agg[, c("feature_id", "lineage_id", "bin", "pseudotime", "pseudotime_min", "pseudotime_max", "expr", "n_cells", "label"), drop = FALSE]
        ri <- ri + 1L
        rows[[ri]] <- agg
        n_rows_lineage <- n_rows_lineage + nrow(agg)
        n_entities_with_rows <- n_entities_with_rows + 1L
      }
    }

    si <- si + 1L
    fit_rows[[si]] <- data.frame(
      lineage_id = as.character(lin),
      n_cells_used = as.integer(length(cells_lin)),
      n_features_input = as.integer(length(feats)),
      n_features_with_rows = as.integer(n_entities_with_rows),
      n_rows = as.integer(n_rows_lineage),
      n_bins = as.integer(n_bins_used),
      summary_fun = as.character(summary_fun),
      min_cells_per_bin = as.integer(min_cells_per_bin),
      matrix_id = as.character(matrix_id),
      stringsAsFactors = FALSE
    )
  }

  tbl <- if (ri == 0L) {
    data.frame(
      feature_id = character(0),
      lineage_id = character(0),
      bin = integer(0),
      pseudotime = numeric(0),
      pseudotime_min = numeric(0),
      pseudotime_max = numeric(0),
      expr = numeric(0),
      n_cells = integer(0),
      label = character(0),
      stringsAsFactors = FALSE
    )
  } else {
    out <- do.call(rbind, rows[seq_len(ri)])
    rownames(out) <- NULL
    out
  }
  fit_summary <- do.call(rbind, fit_rows[seq_len(si)])
  rownames(fit_summary) <- NULL

  list(
    outputs = list(
      trend_table = wb_prim_obs_table(
        table = tbl,
        table_type = "trajectory_smooth",
        entity_kind = "trajectory_bin",
        meta = list(
          matrix_id = matrix_id,
          summary_fun = as.character(summary_fun),
          min_cells_per_bin = as.integer(min_cells_per_bin),
          n_bins = as.integer(unique(fit_summary$n_bins %||% n_bins)[1] %||% n_bins)
        )
      ),
      fit_summary = wb_prim_obs_table(
        table = fit_summary,
        table_type = "trajectory_smooth_summary",
        entity_kind = "lineage"
      )
    ),
    params = list(
      matrix_id = matrix_id,
      feature_set = as.character(feature_set %||% NA_character_)[1],
      n_features_input = as.integer(length(feats)),
      n_lineages = as.integer(length(lineages)),
      n_bins = as.integer(unique(fit_summary$n_bins %||% n_bins)[1] %||% n_bins),
      summary_fun = as.character(summary_fun),
      min_cells_per_bin = as.integer(min_cells_per_bin)
    )
  )
}

#' Compute Feature-Set Trajectory Signatures
#'
#' Computes per-cell signature scores from a feature set, then summarizes those scores
#' along lineage pseudotime from a trajectory model.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param matrix_id Matrix identifier.
#' @param model A `model_ref` primitive from trajectory fitting.
#' @param feature_set Feature set name in bundle feature-set registry.
#' @param cells Optional effective cell IDs to restrict analysis.
#' @param lineage Optional lineage key subset.
#' @param score_method One of `"mean"` or `"sum"` across features within each cell.
#' @param n_bins Number of pseudotime bins.
#' @param summary_fun One of `"mean"` or `"median"` across cells within each bin.
#' @param min_cells_per_bin Minimum cells required for an output bin.
#'
#' @return A standard op result list with `outputs` containing `signature_table`
#'   and `fit_summary`, plus normalized `params`.
#'
#' @export
wb_op_trajectory_signature_smooth <- function(bundle,
                                              matrix_id,
                                              model,
                                              feature_set,
                                              cells = NULL,
                                              lineage = NULL,
                                              score_method = "mean",
                                              n_bins = 50L,
                                              summary_fun = "mean",
                                              min_cells_per_bin = 5L) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert(is.character(matrix_id) && length(matrix_id) == 1 && nzchar(matrix_id), "matrix_id invalid")
  .wb_assert_kind(model, "model_ref")
  fs_name <- as.character(feature_set)[1]
  .wb_assert(nzchar(fs_name), "trajectory_signature_smooth: feature_set is required.")

  score_method <- .wb_trajectory_signature_score_fun(score_method)
  summary_fun <- .wb_trajectory_smooth_summary_fun(summary_fun)
  min_cells_per_bin <- suppressWarnings(as.integer(min_cells_per_bin))
  .wb_assert(is.finite(min_cells_per_bin) && min_cells_per_bin >= 1L,
             "trajectory_signature_smooth: min_cells_per_bin must be >= 1.")

  feats <- .wb_trajectory_smooth_feature_ids(
    bundle = bundle,
    matrix_id = matrix_id,
    feature_set = fs_name,
    features = NULL
  )
  lineages <- .wb_trajectory_smooth_resolve_lineages(model = model, lineage = lineage, cells = cells)

  rows <- list()
  fit_rows <- list()
  ri <- 0L
  si <- 0L

  for (lin in names(lineages)) {
    df_lin <- lineages[[lin]]
    pt <- suppressWarnings(as.numeric(df_lin$pseudotime))
    names(pt) <- as.character(df_lin$cell_id)
    keep <- is.finite(pt)
    pt <- pt[keep]
    cells_lin <- as.character(names(pt))
    .wb_assert(length(cells_lin) >= 10L,
               paste0("trajectory_signature_smooth: lineage '", lin, "' has <10 finite pseudotime cells."))
    .wb_assert(stats::sd(pt) > 0,
               paste0("trajectory_signature_smooth: lineage '", lin, "' has zero pseudotime variance."))

    bb <- .wb_trajectory_smooth_bins(pt, n_bins = n_bins)
    bins <- bb$bins
    n_bins_used <- bb$n_bins

    x <- wb_slice(bundle, matrix_id = matrix_id, features = feats, cells = cells_lin)
    m <- as.matrix(x)
    sig <- if (identical(score_method, "sum")) {
      colSums(m, na.rm = TRUE)
    } else {
      colMeans(m, na.rm = TRUE)
    }

    agg <- .wb_trajectory_smooth_aggregate_one(
      entity_id = fs_name,
      lineage_id = lin,
      pt = pt,
      values = as.numeric(sig),
      bins = bins,
      min_cells_per_bin = min_cells_per_bin,
      value_col = "value",
      summary_fun = summary_fun
    )
    .wb_assert(!is.null(agg) && nrow(agg) > 0L,
               paste0("trajectory_signature_smooth: no output rows for lineage '", lin, "'."))

    agg$feature_set <- as.character(agg$entity_id)
    agg$label <- as.character(agg$feature_set)
    agg <- agg[, c("feature_set", "lineage_id", "bin", "pseudotime", "pseudotime_min", "pseudotime_max", "value", "n_cells", "label"), drop = FALSE]
    ri <- ri + 1L
    rows[[ri]] <- agg

    si <- si + 1L
    fit_rows[[si]] <- data.frame(
      lineage_id = as.character(lin),
      feature_set = as.character(fs_name),
      n_cells_used = as.integer(length(cells_lin)),
      n_features = as.integer(length(feats)),
      n_rows = as.integer(nrow(agg)),
      n_bins = as.integer(n_bins_used),
      score_method = as.character(score_method),
      summary_fun = as.character(summary_fun),
      min_cells_per_bin = as.integer(min_cells_per_bin),
      matrix_id = as.character(matrix_id),
      stringsAsFactors = FALSE
    )
  }

  tbl <- do.call(rbind, rows[seq_len(ri)])
  fit_summary <- do.call(rbind, fit_rows[seq_len(si)])
  rownames(tbl) <- NULL
  rownames(fit_summary) <- NULL

  list(
    outputs = list(
      signature_table = wb_prim_obs_table(
        table = tbl,
        table_type = "trajectory_signature_smooth",
        entity_kind = "trajectory_bin",
        meta = list(
          matrix_id = matrix_id,
          feature_set = fs_name,
          n_features = as.integer(length(feats)),
          score_method = as.character(score_method),
          summary_fun = as.character(summary_fun),
          min_cells_per_bin = as.integer(min_cells_per_bin),
          n_bins = as.integer(unique(fit_summary$n_bins %||% n_bins)[1] %||% n_bins)
        )
      ),
      fit_summary = wb_prim_obs_table(
        table = fit_summary,
        table_type = "trajectory_signature_smooth_summary",
        entity_kind = "lineage"
      )
    ),
    params = list(
      matrix_id = matrix_id,
      feature_set = fs_name,
      n_features = as.integer(length(feats)),
      n_lineages = as.integer(length(lineages)),
      n_bins = as.integer(unique(fit_summary$n_bins %||% n_bins)[1] %||% n_bins),
      score_method = as.character(score_method),
      summary_fun = as.character(summary_fun),
      min_cells_per_bin = as.integer(min_cells_per_bin)
    )
  )
}

#' Compute Trajectory Smoothing For Cell-Level Signals
#'
#' Summarizes one or more cell-level signals along lineage pseudotime from a
#' trajectory model. This is the generic smoothing surface for
#' `cell_vector_family`-style outputs such as chromVAR motif activity, module
#' scores, or other per-cell signal families.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param signal A `cell_vector_family` primitive. Direct `cell_vector`
#'   primitives are also accepted by the implementation and are lifted to a
#'   single-key family.
#' @param model A `model_ref` primitive from trajectory fitting.
#' @param cells Optional effective cell IDs to restrict analysis.
#' @param lineage Optional lineage key subset.
#' @param signal_keys Optional signal-key subset within `signal`.
#' @param n_bins Number of pseudotime bins.
#' @param summary_fun One of `"mean"` or `"median"` across cells within each bin.
#' @param min_cells_per_bin Minimum cells required for an output bin.
#'
#' @return A standard op result list with `outputs` containing `signal_table`
#'   and `fit_summary`, plus normalized `params`.
#'
#' @export
wb_op_trajectory_vector_smooth <- function(bundle,
                                           signal,
                                           model,
                                           cells = NULL,
                                           lineage = NULL,
                                           signal_keys = NULL,
                                           n_bins = 50L,
                                           summary_fun = "mean",
                                           min_cells_per_bin = 5L) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert_kind(model, "model_ref")
  .wb_assert(.wb_is_primitive(signal), "trajectory_vector_smooth: signal must be a primitive.")

  if (identical(as.character(signal$kind %||% "")[1], "cell_vector")) {
    label <- as.character(signal$label %||% "signal")[1]
    if (!nzchar(label)) label <- "signal"
    signal <- wb_prim_cell_vector_family(
      key = rep(label, length(signal$cell_id)),
      cell_id = as.character(signal$cell_id),
      value = as.numeric(signal$value),
      value_type = as.character(signal$value_type %||% "continuous")[1]
    )
  }
  .wb_assert_kind(signal, "cell_vector_family")

  summary_fun <- .wb_trajectory_smooth_summary_fun(summary_fun)
  min_cells_per_bin <- suppressWarnings(as.integer(min_cells_per_bin))
  .wb_assert(is.finite(min_cells_per_bin) && min_cells_per_bin >= 1L,
             "trajectory_vector_smooth: min_cells_per_bin must be >= 1.")

  sig_tbl <- wb_primitive_to_table(signal, include_context = FALSE)
  .wb_assert(all(c("key", "cell_id", "value") %in% colnames(sig_tbl)),
             "trajectory_vector_smooth: signal family table missing key/cell_id/value.")
  sig_tbl$key <- as.character(sig_tbl$key)
  sig_tbl$cell_id <- as.character(sig_tbl$cell_id)
  sig_tbl$value <- suppressWarnings(as.numeric(sig_tbl$value))
  sig_tbl <- sig_tbl[nzchar(sig_tbl$key) & nzchar(sig_tbl$cell_id) & is.finite(sig_tbl$value), , drop = FALSE]
  .wb_assert(nrow(sig_tbl) > 0L, "trajectory_vector_smooth: signal has no finite rows.")

  if (!is.null(signal_keys)) {
    signal_keys <- unique(as.character(signal_keys))
    signal_keys <- signal_keys[nzchar(signal_keys)]
    .wb_assert(length(signal_keys) > 0L, "trajectory_vector_smooth: signal_keys is empty after cleaning.")
    sig_tbl <- sig_tbl[sig_tbl$key %in% signal_keys, , drop = FALSE]
    .wb_assert(nrow(sig_tbl) > 0L, "trajectory_vector_smooth: no signal rows remain after signal_keys filtering.")
  }
  signal_keys <- unique(as.character(sig_tbl$key))

  lineages <- .wb_trajectory_smooth_resolve_lineages(model = model, lineage = lineage, cells = cells)

  rows <- list()
  fit_rows <- list()
  ri <- 0L
  si <- 0L

  for (lin in names(lineages)) {
    df_lin <- lineages[[lin]]
    pt <- suppressWarnings(as.numeric(df_lin$pseudotime))
    names(pt) <- as.character(df_lin$cell_id)
    keep <- is.finite(pt)
    pt <- pt[keep]
    cells_lin <- as.character(names(pt))
    .wb_assert(length(cells_lin) >= 10L,
               paste0("trajectory_vector_smooth: lineage '", lin, "' has <10 finite pseudotime cells."))
    .wb_assert(stats::sd(pt) > 0,
               paste0("trajectory_vector_smooth: lineage '", lin, "' has zero pseudotime variance."))

    bb <- .wb_trajectory_smooth_bins(pt, n_bins = n_bins)
    bins <- bb$bins
    n_bins_used <- bb$n_bins
    n_rows_lineage <- 0L
    n_signals_with_rows <- 0L

    sig_lin <- sig_tbl[sig_tbl$cell_id %in% cells_lin, c("key", "cell_id", "value"), drop = FALSE]
    .wb_assert(nrow(sig_lin) > 0L,
               paste0("trajectory_vector_smooth: no signal rows overlap lineage '", lin, "'."))

    for (sig_key in signal_keys) {
      sub <- sig_lin[sig_lin$key == sig_key, , drop = FALSE]
      if (!nrow(sub)) next
      vals <- sub$value[match(cells_lin, sub$cell_id)]
      keep2 <- is.finite(vals) & is.finite(pt)
      if (sum(keep2) < min_cells_per_bin) next

      agg <- .wb_trajectory_smooth_aggregate_one(
        entity_id = sig_key,
        lineage_id = lin,
        pt = pt[keep2],
        values = vals[keep2],
        bins = bins[keep2],
        min_cells_per_bin = min_cells_per_bin,
        value_col = "value",
        summary_fun = summary_fun
      )
      if (is.null(agg) || !nrow(agg)) next

      agg$signal_key <- as.character(agg$entity_id)
      agg$label <- as.character(agg$signal_key)
      agg <- agg[, c("signal_key", "lineage_id", "bin", "pseudotime", "pseudotime_min", "pseudotime_max", "value", "n_cells", "label"), drop = FALSE]
      ri <- ri + 1L
      rows[[ri]] <- agg
      n_rows_lineage <- n_rows_lineage + nrow(agg)
      n_signals_with_rows <- n_signals_with_rows + 1L
    }

    si <- si + 1L
    fit_rows[[si]] <- data.frame(
      lineage_id = as.character(lin),
      n_cells_used = as.integer(length(cells_lin)),
      n_signal_keys_input = as.integer(length(signal_keys)),
      n_signal_keys_with_rows = as.integer(n_signals_with_rows),
      n_rows = as.integer(n_rows_lineage),
      n_bins = as.integer(n_bins_used),
      summary_fun = as.character(summary_fun),
      min_cells_per_bin = as.integer(min_cells_per_bin),
      stringsAsFactors = FALSE
    )
  }

  tbl <- if (ri == 0L) {
    data.frame(
      signal_key = character(0),
      lineage_id = character(0),
      bin = integer(0),
      pseudotime = numeric(0),
      pseudotime_min = numeric(0),
      pseudotime_max = numeric(0),
      value = numeric(0),
      n_cells = integer(0),
      label = character(0),
      stringsAsFactors = FALSE
    )
  } else {
    out <- do.call(rbind, rows[seq_len(ri)])
    rownames(out) <- NULL
    out
  }
  fit_summary <- do.call(rbind, fit_rows[seq_len(si)])
  rownames(fit_summary) <- NULL

  list(
    outputs = list(
      signal_table = wb_prim_obs_table(
        table = tbl,
        table_type = "trajectory_vector_smooth",
        entity_kind = "trajectory_bin",
        meta = list(
          signal_kind = as.character(signal$kind),
          n_signal_keys = as.integer(length(signal_keys)),
          summary_fun = as.character(summary_fun),
          min_cells_per_bin = as.integer(min_cells_per_bin),
          n_bins = as.integer(unique(fit_summary$n_bins %||% n_bins)[1] %||% n_bins)
        )
      ),
      fit_summary = wb_prim_obs_table(
        table = fit_summary,
        table_type = "trajectory_vector_smooth_summary",
        entity_kind = "lineage"
      )
    ),
    params = list(
      signal_kind = as.character(signal$kind),
      signal_keys = as.character(signal_keys),
      n_signal_keys_input = as.integer(length(signal_keys)),
      n_lineages = as.integer(length(lineages)),
      n_bins = as.integer(unique(fit_summary$n_bins %||% n_bins)[1] %||% n_bins),
      summary_fun = as.character(summary_fun),
      min_cells_per_bin = as.integer(min_cells_per_bin)
    )
  )
}
