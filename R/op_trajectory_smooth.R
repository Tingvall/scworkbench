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

.wb_trajectory_membership_cells <- function(bundle, membership = NULL) {
  if (is.null(membership)) return(NULL)
  aid <- .wb_ref_to_artifact_id(membership)
  if (!is.null(aid) && nzchar(as.character(aid)[1])) {
    prim <- wb_art_load(bundle, as.character(aid)[1], expected_kind = "cell_vector")
    return(.wb_trajectory_membership_cells(bundle, prim))
  }
  if (.wb_is_primitive(membership)) {
    .wb_assert_kind(membership, "cell_vector", where = " for membership")
    vals <- as.character(membership$value %||% character(0))
    cells <- as.character(membership$cell_id %||% character(0))
    keep <- nzchar(cells) & !is.na(vals) & nzchar(vals)
    return(unique(cells[keep]))
  }
  if (is.character(membership)) {
    x <- as.character(membership)
    x <- x[nzchar(x)]
    if (length(x) == 1L && startsWith(x, "artifact:")) {
      prim <- wb_art_load(bundle, sub("^artifact:", "", x), expected_kind = "cell_vector")
      return(.wb_trajectory_membership_cells(bundle, prim))
    }
    if (length(x) == 1L && (identical(x, "all") || startsWith(x, "set:"))) {
      return(as.character(wb_cells(bundle, cell_set = x)))
    }
    return(unique(x))
  }
  stop("trajectory dynamics: membership must be a cell_vector primitive, artifact:<id>, cell set, or cell_id vector.", call. = FALSE)
}

.wb_trajectory_input_artifact_id <- function(x) {
  aid <- .wb_ref_to_artifact_id(x)
  if (!is.null(aid) && nzchar(as.character(aid)[1])) return(as.character(aid)[1])
  if (.wb_is_primitive(x)) {
    aid <- as.character(x$meta$artifact_id %||% x$artifact_id %||% "")[1]
    if (nzchar(aid)) return(aid)
  }
  ""
}

.wb_trajectory_resolve_explicit_pseudotime <- function(pseudotime, pseudotime_key = NULL, lineage = NULL, cells = NULL) {
  .wb_assert(.wb_is_primitive(pseudotime), "trajectory dynamics: pseudotime must be a primitive.")
  .wb_assert_kind(pseudotime, "cell_vector_family", where = " for explicit pseudotime")
  pt_tbl <- wb_primitive_to_table(pseudotime, include_context = FALSE)
  .wb_assert(all(c("key", "cell_id", "value") %in% names(pt_tbl)),
             "trajectory dynamics: explicit pseudotime table must contain key, cell_id, value.")
  names(pt_tbl)[names(pt_tbl) == "key"] <- "lineage_id"
  names(pt_tbl)[names(pt_tbl) == "value"] <- "pseudotime"
  pt_tbl$lineage_id <- as.character(pt_tbl$lineage_id)
  pt_tbl$cell_id <- as.character(pt_tbl$cell_id)
  pt_tbl$pseudotime <- suppressWarnings(as.numeric(pt_tbl$pseudotime))
  pt_tbl <- pt_tbl[nzchar(pt_tbl$lineage_id) & nzchar(pt_tbl$cell_id) & is.finite(pt_tbl$pseudotime), , drop = FALSE]
  .wb_assert(nrow(pt_tbl) > 0L, "trajectory dynamics: explicit pseudotime has no finite rows.")

  key <- pseudotime_key %||% lineage
  if (!is.null(key)) {
    key <- unique(as.character(key))
    key <- key[nzchar(key)]
    .wb_assert(length(key) > 0L, "trajectory dynamics: pseudotime_key/lineage is empty after cleaning.")
  } else {
    key <- sort(unique(as.character(pt_tbl$lineage_id)))
    .wb_assert(length(key) == 1L,
               "trajectory dynamics: explicit pseudotime has multiple keys; provide pseudotime_key or lineage.")
  }
  missing <- setdiff(key, unique(as.character(pt_tbl$lineage_id)))
  .wb_assert(length(missing) == 0L,
             paste0("trajectory dynamics: explicit pseudotime key(s) not found: ", paste(missing, collapse = ", ")))
  pt_tbl <- pt_tbl[pt_tbl$lineage_id %in% key, , drop = FALSE]

  if (!is.null(cells)) {
    keep_cells <- unique(as.character(cells))
    pt_tbl <- pt_tbl[pt_tbl$cell_id %in% keep_cells, , drop = FALSE]
  }
  .wb_assert(nrow(pt_tbl) > 0L, "trajectory dynamics: no explicit pseudotime rows remain after filters.")
  split(pt_tbl[, c("lineage_id", "cell_id", "pseudotime"), drop = FALSE], as.character(pt_tbl$lineage_id))
}

.wb_trajectory_dynamics_resolve_lineages <- function(bundle,
                                                     model = NULL,
                                                     pseudotime = NULL,
                                                     pseudotime_key = NULL,
                                                     membership = NULL,
                                                     lineage = NULL,
                                                     cells = NULL,
                                                     pseudotime_artifact_id = "",
                                                     membership_artifact_id = "") {
  has_model <- !is.null(model)
  has_pt <- !is.null(pseudotime)
  .wb_assert(xor(has_model, has_pt),
             "trajectory dynamics requires exactly one pseudotime source: model or explicit pseudotime.")

  membership_cells <- .wb_trajectory_membership_cells(bundle, membership)
  cells_use <- cells
  if (!is.null(membership_cells)) {
    cells_use <- if (is.null(cells_use)) membership_cells else intersect(as.character(cells_use), membership_cells)
  }

  if (has_model) {
    .wb_assert_kind(model, "model_ref")
    lineages <- .wb_trajectory_smooth_resolve_lineages(model = model, lineage = lineage, cells = cells_use)
    source_kind <- "model_ref"
    source_key <- as.character(lineage %||% names(lineages))
    pseudotime_cells_total <- length(unique(unlist(lapply(lineages, function(x) as.character(x$cell_id)), use.names = FALSE)))
  } else {
    lineages <- .wb_trajectory_resolve_explicit_pseudotime(
      pseudotime = pseudotime,
      pseudotime_key = pseudotime_key,
      lineage = lineage,
      cells = cells_use
    )
    source_kind <- "cell_vector_family"
    source_key <- as.character(pseudotime_key %||% lineage %||% names(lineages))
    all_pt <- wb_primitive_to_table(pseudotime, include_context = FALSE)
    pseudotime_cells_total <- length(unique(as.character(all_pt$cell_id[is.finite(suppressWarnings(as.numeric(all_pt$value)))])))
  }

  list(
    lineages = lineages,
    meta = list(
      pseudotime_source_kind = source_kind,
      pseudotime_artifact_id = as.character(pseudotime_artifact_id %||% "")[1],
      pseudotime_key = paste(unique(source_key[nzchar(source_key)]), collapse = ","),
      membership_artifact_id = as.character(membership_artifact_id %||% "")[1],
      n_pseudotime_cells = as.integer(pseudotime_cells_total),
      n_membership_cells = if (is.null(membership_cells)) NA_integer_ else as.integer(length(unique(membership_cells)))
    )
  )
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

#' @keywords internal
.wb_trajectory_geneset_dynamic_metrics <- function(curve) {
  yy <- suppressWarnings(as.numeric(curve$value))
  se <- if ("value_se" %in% colnames(curve)) {
    suppressWarnings(as.numeric(curve$value_se))
  } else {
    rep(NA_real_, length(yy))
  }
  xx <- suppressWarnings(as.numeric(curve$pseudotime))
  bb <- suppressWarnings(as.integer(curve$bin))
  keep <- is.finite(yy) & is.finite(xx) & is.finite(bb)
  yy <- yy[keep]
  se <- se[keep]
  xx <- xx[keep]
  bb <- bb[keep]

  if (!length(yy)) {
    return(list(
      n_bins_observed = 0L,
      amplitude = NA_real_,
      min_score = NA_real_,
      max_score = NA_real_,
      mean_score = NA_real_,
      auc_score = NA_real_,
      relative_amplitude = NA_real_,
      sd_value = NA_real_,
      mean_se = NA_real_,
      signal_to_noise = NA_real_,
      early_mean = NA_real_,
      late_mean = NA_real_,
      late_minus_early = NA_real_,
      spearman_rho = NA_real_,
      dynamic_score = NA_real_,
      peak_bin = NA_integer_,
      trough_bin = NA_integer_,
      peak_pseudotime = NA_real_,
      trough_pseudotime = NA_real_
    ))
  }

  oo <- order(bb, xx)
  yy <- yy[oo]
  xx <- xx[oo]
  bb <- bb[oo]

  n <- length(yy)
  qn <- max(1L, ceiling(n * 0.2))
  early <- yy[seq_len(qn)]
  late <- yy[seq.int(max(1L, n - qn + 1L), n)]
  pk <- which.max(yy)
  tr <- which.min(yy)
  amp <- suppressWarnings(max(yy, na.rm = TRUE) - min(yy, na.rm = TRUE))
  min_score <- suppressWarnings(min(yy, na.rm = TRUE))
  max_score <- suppressWarnings(max(yy, na.rm = TRUE))
  mean_score <- suppressWarnings(mean(yy, na.rm = TRUE))
  auc_score <- mean_score
  relative_amplitude <- if (is.finite(mean_score)) amp / (abs(mean_score) + 1e-8) else NA_real_
  sdv <- if (n >= 2L) suppressWarnings(stats::sd(yy, na.rm = TRUE)) else 0
  mean_se <- suppressWarnings(mean(se[is.finite(se)], na.rm = TRUE))
  if (!is.finite(mean_se)) mean_se <- NA_real_
  signal_to_noise <- if (is.finite(mean_se) && mean_se > 0) amp / mean_se else NA_real_
  rho <- if (n >= 3L && stats::sd(xx) > 0 && stats::sd(yy) > 0) {
    suppressWarnings(stats::cor(xx, yy, method = "spearman", use = "complete.obs"))
  } else {
    NA_real_
  }
  delta <- suppressWarnings(mean(late, na.rm = TRUE) - mean(early, na.rm = TRUE))
  dyn <- amp + sdv + abs(delta) + if (is.finite(rho)) abs(rho) * sdv else 0

  list(
    n_bins_observed = as.integer(n),
    amplitude = as.numeric(amp),
    min_score = as.numeric(min_score),
    max_score = as.numeric(max_score),
    mean_score = as.numeric(mean_score),
    auc_score = as.numeric(auc_score),
    relative_amplitude = as.numeric(relative_amplitude),
    sd_value = as.numeric(sdv),
    mean_se = as.numeric(mean_se),
    signal_to_noise = as.numeric(signal_to_noise),
    early_mean = as.numeric(mean(early, na.rm = TRUE)),
    late_mean = as.numeric(mean(late, na.rm = TRUE)),
    late_minus_early = as.numeric(delta),
    spearman_rho = as.numeric(rho),
    dynamic_score = as.numeric(dyn),
    peak_bin = as.integer(bb[pk]),
    trough_bin = as.integer(bb[tr]),
    peak_pseudotime = as.numeric(xx[pk]),
    trough_pseudotime = as.numeric(xx[tr])
  )
}

#' @keywords internal
.wb_trajectory_geneset_curve_class <- function(late_minus_early,
                                               spearman_rho,
                                               amplitude = NA_real_,
                                               peak_bin,
                                               trough_bin,
                                               n_bins_observed,
                                               on_off_min_delta = 0,
                                               monotonic_min_abs_rho = 0.5,
                                               class_min_amplitude = 0) {
  delta <- suppressWarnings(as.numeric(late_minus_early)[1])
  rho <- suppressWarnings(as.numeric(spearman_rho)[1])
  amp <- suppressWarnings(as.numeric(amplitude)[1])
  peak_bin <- suppressWarnings(as.integer(peak_bin)[1])
  trough_bin <- suppressWarnings(as.integer(trough_bin)[1])
  n_bins <- suppressWarnings(as.integer(n_bins_observed)[1])
  if (!is.finite(delta)) delta <- 0
  if (!is.finite(rho)) rho <- 0
  if (!is.finite(amp)) amp <- 0
  if (!is.finite(on_off_min_delta) || on_off_min_delta < 0) on_off_min_delta <- 0
  if (!is.finite(monotonic_min_abs_rho) || monotonic_min_abs_rho < 0) monotonic_min_abs_rho <- 0.5
  if (!is.finite(class_min_amplitude) || class_min_amplitude < 0) class_min_amplitude <- 0

  peak_internal <- is.finite(peak_bin) && is.finite(n_bins) && peak_bin > 1L && peak_bin < n_bins
  trough_internal <- is.finite(trough_bin) && is.finite(n_bins) && trough_bin > 1L && trough_bin < n_bins

  if (amp < class_min_amplitude) return("flat_or_noisy")
  if (abs(delta) >= on_off_min_delta && rho >= monotonic_min_abs_rho) return("turns_on")
  if (abs(delta) >= on_off_min_delta && rho <= -monotonic_min_abs_rho) return("turns_off")
  if (peak_internal && amp >= class_min_amplitude) return("transient_peak")
  if (trough_internal && amp >= class_min_amplitude) return("transient_dip")
  if (delta > 0) return("weak_on")
  if (delta < 0) return("weak_off")
  "flat_or_noisy"
}

#' @keywords internal
.wb_trajectory_geneset_smooth_fun <- function(smooth_method) {
  sm <- as.character(smooth_method %||% "none")[1]
  if (!nzchar(sm)) sm <- "none"
  .wb_assert(sm %in% c("none", "loess", "spline"),
             "trajectory_geneset_dynamics: smooth_method must be 'none', 'loess', or 'spline'.")
  sm
}

#' @keywords internal
.wb_trajectory_geneset_score_values <- function(m, score_method, rank_bg = NULL) {
  score_method <- as.character(score_method %||% "mean")[1]
  if (!nzchar(score_method)) score_method <- "mean"
  .wb_assert(score_method %in% c("mean", "sum", "rank_mean"),
             "trajectory_geneset_dynamics: score_method must be 'mean', 'sum', or 'rank_mean'.")
  if (identical(score_method, "sum")) return(colSums(m, na.rm = TRUE))
  if (identical(score_method, "rank_mean")) {
    bg <- rank_bg
    if (is.null(bg)) bg <- m
    .wb_assert(is.matrix(bg) || is.data.frame(bg), "trajectory_geneset_dynamics: rank_mean background must be matrix-like.")
    bg <- as.matrix(bg)
    rr <- apply(bg, 2L, function(z) rank(z, ties.method = "average", na.last = "keep"))
    if (is.null(dim(rr))) rr <- matrix(rr, ncol = 1L, dimnames = list(rownames(bg), colnames(bg)))
    idx <- match(rownames(m), rownames(rr))
    idx <- idx[is.finite(idx)]
    .wb_assert(length(idx) > 0L, "trajectory_geneset_dynamics: rank_mean set has no overlap with rank background.")
    return(colMeans(rr[idx, , drop = FALSE], na.rm = TRUE))
  }
  colMeans(m, na.rm = TRUE)
}

#' @keywords internal
.wb_trajectory_geneset_apply_smoothing <- function(agg, smooth_method = "none", loess_span = 0.5) {
  if (is.null(agg) || !nrow(agg)) return(agg)
  smooth_method <- .wb_trajectory_geneset_smooth_fun(smooth_method)
  agg$value_raw <- suppressWarnings(as.numeric(agg$value))
  agg$value_smooth <- agg$value_raw
  if (!identical(smooth_method, "none") && nrow(agg) >= 5L) {
    xx <- suppressWarnings(as.numeric(agg$pseudotime))
    yy <- suppressWarnings(as.numeric(agg$value_raw))
    keep <- is.finite(xx) & is.finite(yy)
    if (sum(keep) >= 5L && stats::sd(xx[keep]) > 0 && stats::sd(yy[keep]) > 0) {
      pred <- rep(NA_real_, length(yy))
      if (identical(smooth_method, "loess")) {
        sp <- suppressWarnings(as.numeric(loess_span)[1])
        if (!is.finite(sp) || sp <= 0 || sp > 1) sp <- 0.5
        fit <- try(stats::loess(yy[keep] ~ xx[keep], span = sp, degree = 2L, surface = "direct"), silent = TRUE)
        if (!inherits(fit, "try-error")) pred[keep] <- suppressWarnings(stats::predict(fit, newdata = xx[keep]))
      } else if (identical(smooth_method, "spline")) {
        fit <- try(stats::smooth.spline(x = xx[keep], y = yy[keep]), silent = TRUE)
        if (!inherits(fit, "try-error")) pred[keep] <- suppressWarnings(stats::predict(fit, x = xx[keep])$y)
      }
      ok <- is.finite(pred)
      agg$value_smooth[ok] <- pred[ok]
    }
  }
  agg$value <- if (identical(smooth_method, "none")) agg$value_raw else agg$value_smooth
  agg
}

#' @keywords internal
.wb_trajectory_geneset_bootstrap_ci <- function(pt,
                                                values,
                                                bins,
                                                n_bins_used,
                                                summary_fun = "mean",
                                                bootstrap_n = 0L,
                                                ci_level = 0.95,
                                                seed = 1L) {
  bootstrap_n <- suppressWarnings(as.integer(bootstrap_n))
  if (!is.finite(bootstrap_n) || bootstrap_n <= 0L) {
    return(data.frame(bin = seq_len(n_bins_used), value_se = NA_real_, value_ci_low = NA_real_,
                      value_ci_high = NA_real_, stringsAsFactors = FALSE))
  }
  ci_level <- suppressWarnings(as.numeric(ci_level)[1])
  if (!is.finite(ci_level) || ci_level <= 0 || ci_level >= 1) ci_level <- 0.95
  ss_fun <- if (identical(summary_fun, "median")) stats::median else base::mean
  alpha <- (1 - ci_level) / 2
  old_seed <- if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) get(".Random.seed", envir = .GlobalEnv) else NULL
  on.exit({
    if (!is.null(old_seed)) assign(".Random.seed", old_seed, envir = .GlobalEnv)
  }, add = TRUE)
  seed <- suppressWarnings(as.integer(seed)[1])
  if (!is.finite(seed)) seed <- 1L
  set.seed(seed)
  rows <- lapply(seq_len(n_bins_used), function(bb) {
    idx <- which(is.finite(pt) & is.finite(values) & is.finite(bins) & bins == bb)
    if (!length(idx)) {
      return(data.frame(bin = bb, value_se = NA_real_, value_ci_low = NA_real_, value_ci_high = NA_real_))
    }
    vals <- as.numeric(values[idx])
    boot <- replicate(bootstrap_n, ss_fun(sample(vals, length(vals), replace = TRUE), na.rm = TRUE))
    data.frame(
      bin = as.integer(bb),
      value_se = as.numeric(stats::sd(boot, na.rm = TRUE)),
      value_ci_low = as.numeric(stats::quantile(boot, probs = alpha, na.rm = TRUE, names = FALSE)),
      value_ci_high = as.numeric(stats::quantile(boot, probs = 1 - alpha, na.rm = TRUE, names = FALSE)),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

#' @keywords internal
.wb_trajectory_geneset_curve <- function(entity_id,
                                         lineage_id,
                                         pt,
                                         values,
                                         bins,
                                         n_bins_used,
                                         min_cells_per_bin,
                                         summary_fun,
                                         smooth_method,
                                         loess_span,
                                         bootstrap_n,
                                         ci_level,
                                         seed) {
  agg <- .wb_trajectory_smooth_aggregate_one(
    entity_id = entity_id,
    lineage_id = lineage_id,
    pt = pt,
    values = values,
    bins = bins,
    min_cells_per_bin = min_cells_per_bin,
    value_col = "value",
    summary_fun = summary_fun
  )
  if (is.null(agg) || !nrow(agg)) return(NULL)
  agg <- .wb_trajectory_geneset_apply_smoothing(agg, smooth_method = smooth_method, loess_span = loess_span)
  ci <- .wb_trajectory_geneset_bootstrap_ci(
    pt = pt,
    values = values,
    bins = bins,
    n_bins_used = n_bins_used,
    summary_fun = summary_fun,
    bootstrap_n = bootstrap_n,
    ci_level = ci_level,
    seed = seed
  )
  merge(agg, ci, by = "bin", all.x = TRUE, sort = FALSE)
}

#' @keywords internal
.wb_trajectory_geneset_null_dynamic_scores <- function(entity_id,
                                                       lineage_id,
                                                       pt,
                                                       values,
                                                       bins,
                                                       min_cells_per_bin,
                                                       summary_fun,
                                                       smooth_method,
                                                       loess_span,
                                                       n_permutations) {
  n_permutations <- suppressWarnings(as.integer(n_permutations)[1])
  if (!is.finite(n_permutations) || n_permutations <= 0L) return(numeric(0))
  values <- suppressWarnings(as.numeric(values))
  ok <- is.finite(values) & is.finite(pt) & is.finite(bins)
  if (sum(ok) < min_cells_per_bin) return(rep(NA_real_, n_permutations))

  out <- rep(NA_real_, n_permutations)
  for (ii in seq_len(n_permutations)) {
    perm_values <- values
    perm_values[ok] <- sample(values[ok], length(values[ok]), replace = FALSE)
    agg <- .wb_trajectory_smooth_aggregate_one(
      entity_id = entity_id,
      lineage_id = lineage_id,
      pt = pt,
      values = perm_values,
      bins = bins,
      min_cells_per_bin = min_cells_per_bin,
      value_col = "value",
      summary_fun = summary_fun
    )
    if (is.null(agg) || !nrow(agg)) next
    agg <- .wb_trajectory_geneset_apply_smoothing(agg, smooth_method = smooth_method, loess_span = loess_span)
    mm <- .wb_trajectory_geneset_dynamic_metrics(agg)
    out[ii] <- suppressWarnings(as.numeric(mm$dynamic_score)[1])
  }
  out
}

#' Screen Feature-Set Dynamics Along A Trajectory
#'
#' Scores every feature set in a namespace per cell, smooths the scores over
#' trajectory pseudotime bins, and ranks feature sets by dynamic behavior.
#'
#' This is a discovery op for broad pathway or GSEA-style libraries already
#' imported into the bundle as feature sets.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param matrix_id Matrix identifier.
#' @param model Optional `model_ref` primitive from trajectory fitting. Supply
#'   this in model-backed mode, or use explicit `pseudotime` mode instead.
#' @param pseudotime Optional `cell_vector_family` pseudotime primitive or
#'   compatible reference for model-free/composite trajectory analysis.
#' @param pseudotime_key Optional key selecting the explicit pseudotime family
#'   member. It is required when explicit pseudotime has multiple keys.
#' @param membership Optional cell-vector, cell-set, or compatible restriction
#'   intersected with cells having finite pseudotime.
#' @param namespace Feature-set namespace to screen. Required for gene-set
#'   scoring and resolved against `matrix_id`.
#' @param pseudotime_artifact_id Optional promoted pseudotime artifact id stored
#'   in explicit-pseudotime provenance metadata.
#' @param membership_artifact_id Optional promoted membership artifact id stored
#'   in explicit-pseudotime provenance metadata.
#' @param cells Optional effective cell IDs to restrict analysis.
#' @param lineage Optional lineage key subset.
#' @param feature_sets Optional explicit feature-set subset within `namespace`.
#' @param score_method One of `"mean"`, `"sum"`, or `"rank_mean"` across genes within each cell.
#' @param n_bins Number of pseudotime bins.
#' @param summary_fun One of `"mean"` or `"median"` across cells within each bin.
#' @param min_cells_per_bin Minimum cells required for an output bin.
#' @param min_set_size Minimum feature-set size after matrix intersection.
#' @param max_set_size Maximum feature-set size after matrix intersection.
#' @param top_n Optional number of top-ranked sets retained in `top_sets`.
#' @param on_off_min_delta Minimum absolute late-early delta for on/off classes.
#' @param monotonic_min_abs_rho Minimum absolute Spearman rho for on/off classes.
#' @param top_driver_genes Number of top member genes retained as curve drivers.
#' @param pseudotime_direction One of `"as_is"` or `"invert"`.
#' @param start_label Optional label for the biological start of pseudotime.
#' @param end_label Optional label for the biological end of pseudotime.
#' @param min_amplitude Minimum amplitude required for `passes_filters`.
#' @param min_bins_observed Minimum binned curve rows required for `passes_filters`.
#' @param min_features_detected Minimum number of detected set members.
#' @param min_detected_fraction Minimum fraction of detected set members.
#' @param min_mean_score Optional minimum mean smoothed score required for `passes_filters`.
#' @param min_max_score Optional minimum maximum smoothed score required for `passes_filters`.
#' @param min_signal_to_noise Optional minimum amplitude divided by mean bootstrap SE required for `passes_filters`.
#' @param low_abundance_max_score Maximum score threshold used to flag low-abundance dynamic candidates.
#' @param smooth_method One of `"none"`, `"loess"`, or `"spline"`.
#' @param loess_span Span for loess smoothing.
#' @param bootstrap_n Bootstrap replicates per bin for confidence bands. Disabled when 0.
#' @param bootstrap_seed Random seed for bootstrap confidence bands.
#' @param ci_level Confidence interval level for bootstrap bands.
#' @param class_min_amplitude Minimum amplitude for non-flat curve classes.
#' @param n_permutations Number of pseudotime-association permutations for
#'   empirical dynamic-score p-values. Disabled when 0.
#' @param permutation_seed Random seed for empirical dynamic-score permutations.
#' @param p_adjust_method Multiple-testing correction method for `q_dynamic`.
#'
#' @return A standard op result list with `outputs` containing `signature_table`,
#'   `dynamics_table`, `top_sets`, `driver_table`, `driver_curve_table`, and
#'   `fit_summary`.
#'
#' @export
wb_op_trajectory_geneset_dynamics <- function(bundle,
                                              matrix_id,
                                              model = NULL,
                                              pseudotime = NULL,
                                              pseudotime_key = NULL,
                                              membership = NULL,
                                              namespace = NULL,
                                              pseudotime_artifact_id = NULL,
                                              membership_artifact_id = NULL,
                                              cells = NULL,
                                              lineage = NULL,
                                              feature_sets = NULL,
                                              score_method = "mean",
                                              n_bins = 50L,
                                              summary_fun = "mean",
                                              min_cells_per_bin = 5L,
                                              min_set_size = 5L,
                                              max_set_size = 5000L,
                                              top_n = 50L,
                                              on_off_min_delta = 0,
                                              monotonic_min_abs_rho = 0.5,
                                              top_driver_genes = 5L,
                                              pseudotime_direction = "as_is",
                                              start_label = NULL,
                                              end_label = NULL,
                                              min_amplitude = 0,
                                              min_bins_observed = 5L,
                                              min_features_detected = 1L,
                                              min_detected_fraction = 0,
                                              min_mean_score = 0,
                                              min_max_score = 0,
                                              min_signal_to_noise = 0,
                                              low_abundance_max_score = 0.1,
                                              smooth_method = "none",
                                              loess_span = 0.5,
                                              bootstrap_n = 0L,
                                              bootstrap_seed = 1L,
                                              ci_level = 0.95,
                                              class_min_amplitude = 0,
                                              n_permutations = 0L,
                                              permutation_seed = 1L,
                                              p_adjust_method = "BH") {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert(is.character(matrix_id) && length(matrix_id) == 1 && nzchar(matrix_id), "matrix_id invalid")
  .wb_assert(is.character(namespace) && length(namespace) == 1 && nzchar(namespace), "namespace invalid")

  score_method <- as.character(score_method %||% "mean")[1]
  if (!nzchar(score_method)) score_method <- "mean"
  .wb_assert(score_method %in% c("mean", "sum", "rank_mean"),
             "trajectory_geneset_dynamics: score_method must be 'mean', 'sum', or 'rank_mean'.")
  summary_fun <- .wb_trajectory_smooth_summary_fun(summary_fun)
  min_cells_per_bin <- suppressWarnings(as.integer(min_cells_per_bin))
  min_set_size <- suppressWarnings(as.integer(min_set_size))
  max_set_size <- suppressWarnings(as.integer(max_set_size))
  top_n <- suppressWarnings(as.integer(top_n))
  on_off_min_delta <- suppressWarnings(as.numeric(on_off_min_delta))
  monotonic_min_abs_rho <- suppressWarnings(as.numeric(monotonic_min_abs_rho))
  top_driver_genes <- suppressWarnings(as.integer(top_driver_genes))
  pseudotime_direction <- as.character(pseudotime_direction %||% "as_is")[1]
  if (!nzchar(pseudotime_direction)) pseudotime_direction <- "as_is"
  .wb_assert(pseudotime_direction %in% c("as_is", "invert"),
             "trajectory_geneset_dynamics: pseudotime_direction must be 'as_is' or 'invert'.")
  start_label <- as.character(start_label %||% NA_character_)[1]
  end_label <- as.character(end_label %||% NA_character_)[1]
  min_amplitude <- suppressWarnings(as.numeric(min_amplitude)[1])
  min_bins_observed <- suppressWarnings(as.integer(min_bins_observed)[1])
  min_features_detected <- suppressWarnings(as.integer(min_features_detected)[1])
  min_detected_fraction <- suppressWarnings(as.numeric(min_detected_fraction)[1])
  min_mean_score <- suppressWarnings(as.numeric(min_mean_score)[1])
  min_max_score <- suppressWarnings(as.numeric(min_max_score)[1])
  min_signal_to_noise <- suppressWarnings(as.numeric(min_signal_to_noise)[1])
  low_abundance_max_score <- suppressWarnings(as.numeric(low_abundance_max_score)[1])
  smooth_method <- .wb_trajectory_geneset_smooth_fun(smooth_method)
  loess_span <- suppressWarnings(as.numeric(loess_span)[1])
  bootstrap_n <- suppressWarnings(as.integer(bootstrap_n)[1])
  bootstrap_seed <- suppressWarnings(as.integer(bootstrap_seed)[1])
  ci_level <- suppressWarnings(as.numeric(ci_level)[1])
  class_min_amplitude <- suppressWarnings(as.numeric(class_min_amplitude)[1])
  n_permutations <- suppressWarnings(as.integer(n_permutations)[1])
  permutation_seed <- suppressWarnings(as.integer(permutation_seed)[1])
  p_adjust_method <- as.character(p_adjust_method %||% "BH")[1]
  if (!nzchar(p_adjust_method)) p_adjust_method <- "BH"
  .wb_assert(is.finite(min_cells_per_bin) && min_cells_per_bin >= 1L,
             "trajectory_geneset_dynamics: min_cells_per_bin must be >= 1.")
  .wb_assert(is.finite(min_set_size) && min_set_size >= 1L,
             "trajectory_geneset_dynamics: min_set_size must be >= 1.")
  .wb_assert(is.finite(max_set_size) && max_set_size >= min_set_size,
             "trajectory_geneset_dynamics: max_set_size must be >= min_set_size.")
  if (!is.finite(top_n) || top_n < 1L) top_n <- 50L
  if (!is.finite(on_off_min_delta) || on_off_min_delta < 0) on_off_min_delta <- 0
  if (!is.finite(monotonic_min_abs_rho) || monotonic_min_abs_rho < 0) monotonic_min_abs_rho <- 0.5
  if (!is.finite(top_driver_genes) || top_driver_genes < 0L) top_driver_genes <- 5L
  if (!is.finite(min_amplitude) || min_amplitude < 0) min_amplitude <- 0
  if (!is.finite(min_bins_observed) || min_bins_observed < 1L) min_bins_observed <- 5L
  if (!is.finite(min_features_detected) || min_features_detected < 0L) min_features_detected <- 1L
  if (!is.finite(min_detected_fraction) || min_detected_fraction < 0) min_detected_fraction <- 0
  if (min_detected_fraction > 1) min_detected_fraction <- 1
  if (!is.finite(min_mean_score) || min_mean_score < 0) min_mean_score <- 0
  if (!is.finite(min_max_score) || min_max_score < 0) min_max_score <- 0
  if (!is.finite(min_signal_to_noise) || min_signal_to_noise < 0) min_signal_to_noise <- 0
  if (!is.finite(low_abundance_max_score) || low_abundance_max_score < 0) low_abundance_max_score <- 0.1
  if (!is.finite(loess_span) || loess_span <= 0 || loess_span > 1) loess_span <- 0.5
  if (!is.finite(bootstrap_n) || bootstrap_n < 0L) bootstrap_n <- 0L
  if (!is.finite(bootstrap_seed)) bootstrap_seed <- 1L
  if (!is.finite(ci_level) || ci_level <= 0 || ci_level >= 1) ci_level <- 0.95
  if (!is.finite(class_min_amplitude) || class_min_amplitude < 0) class_min_amplitude <- 0
  if (!is.finite(n_permutations) || n_permutations < 0L) n_permutations <- 0L
  if (!is.finite(permutation_seed)) permutation_seed <- 1L
  .wb_assert(p_adjust_method %in% stats::p.adjust.methods,
             "trajectory_geneset_dynamics: p_adjust_method must be one of stats::p.adjust.methods.")

  fs_info <- wb_feature_sets(bundle, matrix_id = matrix_id, namespace = namespace)
  .wb_assert(is.data.frame(fs_info) && nrow(fs_info) > 0L,
             paste0("trajectory_geneset_dynamics: no feature sets found for namespace='", namespace, "'."))
  set_names <- unique(as.character(fs_info$feature_set))
  set_names <- set_names[nzchar(set_names)]
  if (!is.null(feature_sets)) {
    feature_sets <- unique(as.character(feature_sets))
    feature_sets <- feature_sets[nzchar(feature_sets)]
    .wb_assert(length(feature_sets) > 0L, "trajectory_geneset_dynamics: feature_sets is empty after cleaning.")
    set_names <- intersect(set_names, feature_sets)
  }
  .wb_assert(length(set_names) > 0L, "trajectory_geneset_dynamics: no feature sets remain after filtering.")

  universe <- unique(as.character(wb_feature_ids(bundle, matrix_id = matrix_id)))
  universe <- universe[nzchar(universe)]
  .wb_assert(length(universe) > 0L, "trajectory_geneset_dynamics: no feature universe for matrix_id.")

  set_members <- list()
  for (sn in set_names) {
    feats <- unique(intersect(as.character(wb_feature_set_get(bundle, feature_set = sn, matrix_id = matrix_id)), universe))
    feats <- feats[nzchar(feats)]
    if (length(feats) < min_set_size || length(feats) > max_set_size) next
    set_members[[sn]] <- feats
  }
  .wb_assert(length(set_members) > 0L, "trajectory_geneset_dynamics: no feature sets pass size filters.")

  pt_res <- .wb_trajectory_dynamics_resolve_lineages(
    bundle = bundle,
    model = model,
    pseudotime = pseudotime,
    pseudotime_key = pseudotime_key,
    membership = membership,
    lineage = lineage,
    cells = cells,
    pseudotime_artifact_id = pseudotime_artifact_id %||% .wb_trajectory_input_artifact_id(pseudotime),
    membership_artifact_id = membership_artifact_id %||% .wb_trajectory_input_artifact_id(membership)
  )
  lineages <- pt_res$lineages
  pt_meta <- pt_res$meta

  curve_rows <- list()
  dyn_rows <- list()
  driver_rows <- list()
  driver_curve_rows <- list()
  fit_rows <- list()
  ci <- 0L
  di <- 0L
  gi <- 0L
  dci <- 0L
  si <- 0L
  if (n_permutations > 0L) {
    old_seed <- if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) get(".Random.seed", envir = .GlobalEnv) else NULL
    on.exit({
      if (!is.null(old_seed)) assign(".Random.seed", old_seed, envir = .GlobalEnv)
    }, add = TRUE)
    set.seed(permutation_seed)
  }

  for (lin in names(lineages)) {
    df_lin <- lineages[[lin]]
    pt <- suppressWarnings(as.numeric(df_lin$pseudotime))
    names(pt) <- as.character(df_lin$cell_id)
    keep <- is.finite(pt)
    pt <- pt[keep]
    if (identical(pseudotime_direction, "invert")) {
      pt <- max(pt, na.rm = TRUE) - pt
    }
    cells_lin <- as.character(names(pt))
    .wb_assert(length(cells_lin) >= 10L,
               paste0("trajectory_geneset_dynamics: lineage '", lin, "' has <10 finite pseudotime cells."))
    .wb_assert(stats::sd(pt) > 0,
               paste0("trajectory_geneset_dynamics: lineage '", lin, "' has zero pseudotime variance."))

    bb <- .wb_trajectory_smooth_bins(pt, n_bins = n_bins)
    bins <- bb$bins
    n_bins_used <- bb$n_bins
    n_sets_with_rows <- 0L
    n_curve_rows <- 0L
    rank_bg <- NULL
    if (identical(score_method, "rank_mean")) {
      bg_feats <- unique(unlist(set_members, use.names = FALSE))
      bg_feats <- bg_feats[nzchar(bg_feats)]
      rank_bg <- as.matrix(wb_slice(bundle, matrix_id = matrix_id, features = bg_feats, cells = cells_lin))
    }

    for (sn in names(set_members)) {
      feats <- set_members[[sn]]
      x <- wb_slice(bundle, matrix_id = matrix_id, features = feats, cells = cells_lin)
      m <- as.matrix(x)
      n_features_detected <- as.integer(sum(rowSums(m > 0, na.rm = TRUE) > 0))
      detected_fraction <- if (nrow(m) > 0L) n_features_detected / nrow(m) else 0
      sig <- .wb_trajectory_geneset_score_values(m, score_method = score_method, rank_bg = rank_bg)

      agg <- .wb_trajectory_geneset_curve(
        entity_id = sn,
        lineage_id = lin,
        pt = pt,
        values = as.numeric(sig),
        bins = bins,
        n_bins_used = n_bins_used,
        min_cells_per_bin = min_cells_per_bin,
        summary_fun = summary_fun,
        smooth_method = smooth_method,
        loess_span = loess_span,
        bootstrap_n = bootstrap_n,
        ci_level = ci_level,
        seed = bootstrap_seed + di + 1L
      )
      if (is.null(agg) || !nrow(agg)) next

      agg$feature_set <- as.character(agg$entity_id)
      agg$namespace <- as.character(namespace)
      agg$n_features <- as.integer(length(feats))
      agg$n_features_detected <- as.integer(n_features_detected)
      agg$detected_fraction <- as.numeric(detected_fraction)
      agg$label <- as.character(agg$feature_set)
      agg <- agg[, c("feature_set", "namespace", "lineage_id", "bin", "pseudotime", "pseudotime_min",
                     "pseudotime_max", "value", "value_raw", "value_smooth", "value_se", "value_ci_low",
                     "value_ci_high", "n_cells", "n_features", "n_features_detected",
                     "detected_fraction", "label"), drop = FALSE]

      mm <- .wb_trajectory_geneset_dynamic_metrics(agg)
      null_scores <- .wb_trajectory_geneset_null_dynamic_scores(
        entity_id = sn,
        lineage_id = lin,
        pt = pt,
        values = as.numeric(sig),
        bins = bins,
        min_cells_per_bin = min_cells_per_bin,
        summary_fun = summary_fun,
        smooth_method = smooth_method,
        loess_span = loess_span,
        n_permutations = n_permutations
      )
      null_scores <- null_scores[is.finite(null_scores)]
      p_dynamic <- if (length(null_scores) > 0L && is.finite(mm$dynamic_score)) {
        (1 + sum(null_scores >= mm$dynamic_score, na.rm = TRUE)) / (1 + length(null_scores))
      } else {
        NA_real_
      }
      null_mean_dynamic_score <- if (length(null_scores)) mean(null_scores, na.rm = TRUE) else NA_real_
      null_sd_dynamic_score <- if (length(null_scores) >= 2L) stats::sd(null_scores, na.rm = TRUE) else NA_real_
      z_dynamic_score <- if (is.finite(null_sd_dynamic_score) && null_sd_dynamic_score > 0) {
        (mm$dynamic_score - null_mean_dynamic_score) / null_sd_dynamic_score
      } else {
        NA_real_
      }
      curve_class <- .wb_trajectory_geneset_curve_class(
        late_minus_early = mm$late_minus_early,
        spearman_rho = mm$spearman_rho,
        amplitude = mm$amplitude,
        peak_bin = mm$peak_bin,
        trough_bin = mm$trough_bin,
        n_bins_observed = mm$n_bins_observed,
        on_off_min_delta = on_off_min_delta,
        monotonic_min_abs_rho = monotonic_min_abs_rho,
        class_min_amplitude = class_min_amplitude
      )
      filter_reasons <- character(0)
      if (!is.finite(mm$amplitude) || mm$amplitude < min_amplitude) filter_reasons <- c(filter_reasons, "low_amplitude")
      if (!is.finite(mm$n_bins_observed) || mm$n_bins_observed < min_bins_observed) filter_reasons <- c(filter_reasons, "too_few_bins")
      if (n_features_detected < min_features_detected) filter_reasons <- c(filter_reasons, "too_few_detected_features")
      if (detected_fraction < min_detected_fraction) filter_reasons <- c(filter_reasons, "low_detected_fraction")
      if (min_mean_score > 0 && (!is.finite(mm$mean_score) || mm$mean_score < min_mean_score)) filter_reasons <- c(filter_reasons, "low_mean_score")
      if (min_max_score > 0 && (!is.finite(mm$max_score) || mm$max_score < min_max_score)) filter_reasons <- c(filter_reasons, "low_max_score")
      if (min_signal_to_noise > 0 && (!is.finite(mm$signal_to_noise) || mm$signal_to_noise < min_signal_to_noise)) filter_reasons <- c(filter_reasons, "low_signal_to_noise")
      passes_filters <- length(filter_reasons) == 0L
      low_abundance_flag <- is.finite(mm$max_score) && mm$max_score < low_abundance_max_score
      di <- di + 1L
      dyn_rows[[di]] <- data.frame(
        feature_set = as.character(sn),
        namespace = as.character(namespace),
        lineage_id = as.character(lin),
        curve_class = as.character(curve_class),
        n_features = as.integer(length(feats)),
        n_features_detected = as.integer(n_features_detected),
        detected_fraction = as.numeric(detected_fraction),
        n_bins_observed = as.integer(mm$n_bins_observed),
        passes_filters = as.logical(passes_filters),
        filter_reason = if (passes_filters) "" else paste(filter_reasons, collapse = ";"),
        amplitude = as.numeric(mm$amplitude),
        min_score = as.numeric(mm$min_score),
        max_score = as.numeric(mm$max_score),
        mean_score = as.numeric(mm$mean_score),
        auc_score = as.numeric(mm$auc_score),
        relative_amplitude = as.numeric(mm$relative_amplitude),
        sd_value = as.numeric(mm$sd_value),
        mean_se = as.numeric(mm$mean_se),
        signal_to_noise = as.numeric(mm$signal_to_noise),
        low_abundance_flag = as.logical(low_abundance_flag),
        early_mean = as.numeric(mm$early_mean),
        late_mean = as.numeric(mm$late_mean),
        late_minus_early = as.numeric(mm$late_minus_early),
        spearman_rho = as.numeric(mm$spearman_rho),
        abs_spearman_rho = as.numeric(abs(mm$spearman_rho)),
        dynamic_score = as.numeric(mm$dynamic_score),
        p_dynamic = as.numeric(p_dynamic),
        q_dynamic = NA_real_,
        null_mean_dynamic_score = as.numeric(null_mean_dynamic_score),
        null_sd_dynamic_score = as.numeric(null_sd_dynamic_score),
        z_dynamic_score = as.numeric(z_dynamic_score),
        n_permutations = as.integer(length(null_scores)),
        peak_bin = as.integer(mm$peak_bin),
        trough_bin = as.integer(mm$trough_bin),
        peak_pseudotime = as.numeric(mm$peak_pseudotime),
        trough_pseudotime = as.numeric(mm$trough_pseudotime),
        stringsAsFactors = FALSE
      )

      if (top_driver_genes > 0L && length(feats) > 0L) {
        gene_rows <- list()
        gene_curve_by_feature <- list()
        for (g in seq_len(nrow(m))) {
          gagg <- .wb_trajectory_geneset_curve(
            entity_id = rownames(m)[g],
            lineage_id = lin,
            pt = pt,
            values = as.numeric(m[g, ]),
            bins = bins,
            n_bins_used = n_bins_used,
            min_cells_per_bin = min_cells_per_bin,
            summary_fun = summary_fun,
            smooth_method = smooth_method,
            loess_span = loess_span,
            bootstrap_n = bootstrap_n,
            ci_level = ci_level,
            seed = bootstrap_seed + di + g + 1L
          )
          if (is.null(gagg) || !nrow(gagg)) next
          gm <- .wb_trajectory_geneset_dynamic_metrics(gagg)
          gene_curve_by_feature[[as.character(rownames(m)[g])]] <- gagg
          gene_rows[[length(gene_rows) + 1L]] <- data.frame(
            feature_set = as.character(sn),
            namespace = as.character(namespace),
            lineage_id = as.character(lin),
            feature_id = as.character(rownames(m)[g]),
            n_bins_observed = as.integer(gm$n_bins_observed),
            amplitude = as.numeric(gm$amplitude),
            late_minus_early = as.numeric(gm$late_minus_early),
            spearman_rho = as.numeric(gm$spearman_rho),
            dynamic_score = as.numeric(gm$dynamic_score),
            stringsAsFactors = FALSE
          )
        }
        if (length(gene_rows)) {
          gt <- do.call(rbind, gene_rows)
          gt <- gt[order(-gt$dynamic_score, -gt$amplitude), , drop = FALSE]
          gt$driver_rank <- seq_len(nrow(gt))
          gt <- head(gt, min(top_driver_genes, nrow(gt)))
          gi <- gi + 1L
          driver_rows[[gi]] <- gt
          for (ii in seq_len(nrow(gt))) {
            fid <- as.character(gt$feature_id[ii])
            gcurve <- gene_curve_by_feature[[fid]]
            if (is.null(gcurve) || !nrow(gcurve)) next
            gcurve$feature_set <- as.character(sn)
            gcurve$namespace <- as.character(namespace)
            gcurve$feature_id <- fid
            gcurve$driver_rank <- as.integer(gt$driver_rank[ii])
            gcurve$label <- fid
            gcurve <- gcurve[, c("feature_set", "namespace", "feature_id", "driver_rank", "lineage_id",
                                 "bin", "pseudotime", "pseudotime_min", "pseudotime_max", "value",
                                 "value_raw", "value_smooth", "value_se", "value_ci_low", "value_ci_high",
                                 "n_cells", "label"), drop = FALSE]
            dci <- dci + 1L
            driver_curve_rows[[dci]] <- gcurve
          }
        }
      }

      ci <- ci + 1L
      curve_rows[[ci]] <- agg
      n_sets_with_rows <- n_sets_with_rows + 1L
      n_curve_rows <- n_curve_rows + nrow(agg)
    }

    si <- si + 1L
    fit_rows[[si]] <- data.frame(
      lineage_id = as.character(lin),
      namespace = as.character(namespace),
      pseudotime_source_kind = as.character(pt_meta$pseudotime_source_kind),
      pseudotime_artifact_id = as.character(pt_meta$pseudotime_artifact_id),
      pseudotime_key = as.character(pt_meta$pseudotime_key),
      membership_artifact_id = as.character(pt_meta$membership_artifact_id),
      n_pseudotime_cells = as.integer(pt_meta$n_pseudotime_cells),
      n_membership_cells = as.integer(pt_meta$n_membership_cells),
      n_cells_used = as.integer(length(cells_lin)),
      n_feature_sets_input = as.integer(length(set_names)),
      n_feature_sets_screened = as.integer(length(set_members)),
      n_feature_sets_with_rows = as.integer(n_sets_with_rows),
      n_rows = as.integer(n_curve_rows),
      n_bins = as.integer(n_bins_used),
      score_method = as.character(score_method),
      summary_fun = as.character(summary_fun),
      min_cells_per_bin = as.integer(min_cells_per_bin),
      min_set_size = as.integer(min_set_size),
      max_set_size = as.integer(max_set_size),
      on_off_min_delta = as.numeric(on_off_min_delta),
      monotonic_min_abs_rho = as.numeric(monotonic_min_abs_rho),
      pseudotime_direction = as.character(pseudotime_direction),
      start_label = as.character(start_label),
      end_label = as.character(end_label),
      min_amplitude = as.numeric(min_amplitude),
      min_bins_observed = as.integer(min_bins_observed),
      min_features_detected = as.integer(min_features_detected),
      min_detected_fraction = as.numeric(min_detected_fraction),
      min_mean_score = as.numeric(min_mean_score),
      min_max_score = as.numeric(min_max_score),
      min_signal_to_noise = as.numeric(min_signal_to_noise),
      low_abundance_max_score = as.numeric(low_abundance_max_score),
      smooth_method = as.character(smooth_method),
      loess_span = as.numeric(loess_span),
      bootstrap_n = as.integer(bootstrap_n),
      ci_level = as.numeric(ci_level),
      class_min_amplitude = as.numeric(class_min_amplitude),
      n_permutations = as.integer(n_permutations),
      permutation_seed = as.integer(permutation_seed),
      p_adjust_method = as.character(p_adjust_method),
      top_driver_genes = as.integer(top_driver_genes),
      matrix_id = as.character(matrix_id),
      stringsAsFactors = FALSE
    )
  }

  curve_tbl <- if (ci == 0L) {
    data.frame(
      feature_set = character(0), namespace = character(0), lineage_id = character(0),
      bin = integer(0), pseudotime = numeric(0), pseudotime_min = numeric(0),
      pseudotime_max = numeric(0), value = numeric(0), value_raw = numeric(0),
      value_smooth = numeric(0), value_se = numeric(0), value_ci_low = numeric(0),
      value_ci_high = numeric(0), n_cells = integer(0), n_features = integer(0),
      n_features_detected = integer(0), detected_fraction = numeric(0),
      label = character(0), stringsAsFactors = FALSE
    )
  } else {
    out <- do.call(rbind, curve_rows[seq_len(ci)])
    rownames(out) <- NULL
    out
  }
  dyn_tbl <- if (di == 0L) {
    data.frame(
      feature_set = character(0), namespace = character(0), lineage_id = character(0),
      curve_class = character(0), n_features = integer(0), n_features_detected = integer(0),
      detected_fraction = numeric(0), n_bins_observed = integer(0), passes_filters = logical(0),
      filter_reason = character(0), amplitude = numeric(0),
      min_score = numeric(0), max_score = numeric(0), mean_score = numeric(0),
      auc_score = numeric(0), relative_amplitude = numeric(0),
      sd_value = numeric(0), mean_se = numeric(0), signal_to_noise = numeric(0),
      low_abundance_flag = logical(0), early_mean = numeric(0), late_mean = numeric(0),
      late_minus_early = numeric(0), spearman_rho = numeric(0), abs_spearman_rho = numeric(0),
      dynamic_score = numeric(0), peak_bin = integer(0), trough_bin = integer(0),
      p_dynamic = numeric(0), q_dynamic = numeric(0), null_mean_dynamic_score = numeric(0),
      null_sd_dynamic_score = numeric(0), z_dynamic_score = numeric(0), n_permutations = integer(0),
      peak_pseudotime = numeric(0), trough_pseudotime = numeric(0), rank = integer(0),
      stringsAsFactors = FALSE
    )
  } else {
    out <- do.call(rbind, dyn_rows[seq_len(di)])
    out$q_dynamic <- NA_real_
    finite_p <- is.finite(out$p_dynamic)
    if (any(finite_p)) out$q_dynamic[finite_p] <- stats::p.adjust(out$p_dynamic[finite_p], method = p_adjust_method)
    out <- out[order(as.character(out$lineage_id), -out$dynamic_score, -out$amplitude, -out$sd_value), , drop = FALSE]
    out$rank <- ave(seq_len(nrow(out)), as.character(out$lineage_id), FUN = seq_along)
    rownames(out) <- NULL
    out
  }
  eligible_dyn <- dyn_tbl[dyn_tbl$passes_filters %in% TRUE, , drop = FALSE]
  if (!nrow(eligible_dyn)) eligible_dyn <- dyn_tbl
  driver_tbl <- if (gi == 0L) {
    data.frame(
      feature_set = character(0), namespace = character(0), lineage_id = character(0),
      feature_id = character(0), n_bins_observed = integer(0), amplitude = numeric(0),
      late_minus_early = numeric(0), spearman_rho = numeric(0), dynamic_score = numeric(0),
      driver_rank = integer(0), stringsAsFactors = FALSE
    )
  } else {
    out <- do.call(rbind, driver_rows[seq_len(gi)])
    rownames(out) <- NULL
    out
  }
  driver_curve_tbl <- if (dci == 0L) {
    data.frame(
      feature_set = character(0), namespace = character(0), feature_id = character(0),
      driver_rank = integer(0), lineage_id = character(0), bin = integer(0),
      pseudotime = numeric(0), pseudotime_min = numeric(0), pseudotime_max = numeric(0),
      value = numeric(0), value_raw = numeric(0), value_smooth = numeric(0),
      value_se = numeric(0), value_ci_low = numeric(0), value_ci_high = numeric(0),
      n_cells = integer(0), label = character(0), stringsAsFactors = FALSE
    )
  } else {
    out <- do.call(rbind, driver_curve_rows[seq_len(dci)])
    rownames(out) <- NULL
    out
  }
  top_tbl <- head(eligible_dyn[order(as.character(eligible_dyn$lineage_id), eligible_dyn$rank), , drop = FALSE], top_n)
  fit_summary <- do.call(rbind, fit_rows[seq_len(si)])
  rownames(fit_summary) <- NULL

  list(
    outputs = list(
      signature_table = wb_prim_obs_table(
        table = curve_tbl,
        table_type = "trajectory_geneset_dynamics_curve",
        entity_kind = "trajectory_bin",
        meta = list(
          matrix_id = as.character(matrix_id),
          namespace = as.character(namespace),
          pseudotime_source_kind = as.character(pt_meta$pseudotime_source_kind),
          pseudotime_artifact_id = as.character(pt_meta$pseudotime_artifact_id),
          pseudotime_key = as.character(pt_meta$pseudotime_key),
          membership_artifact_id = as.character(pt_meta$membership_artifact_id),
          score_method = as.character(score_method),
          summary_fun = as.character(summary_fun),
          min_cells_per_bin = as.integer(min_cells_per_bin),
          min_set_size = as.integer(min_set_size),
          max_set_size = as.integer(max_set_size),
          on_off_min_delta = as.numeric(on_off_min_delta),
          monotonic_min_abs_rho = as.numeric(monotonic_min_abs_rho),
          pseudotime_direction = as.character(pseudotime_direction),
          start_label = as.character(start_label),
          end_label = as.character(end_label),
          min_amplitude = as.numeric(min_amplitude),
          min_bins_observed = as.integer(min_bins_observed),
          min_features_detected = as.integer(min_features_detected),
          min_detected_fraction = as.numeric(min_detected_fraction),
          min_mean_score = as.numeric(min_mean_score),
          min_max_score = as.numeric(min_max_score),
          min_signal_to_noise = as.numeric(min_signal_to_noise),
          low_abundance_max_score = as.numeric(low_abundance_max_score),
          smooth_method = as.character(smooth_method),
          loess_span = as.numeric(loess_span),
          bootstrap_n = as.integer(bootstrap_n),
          ci_level = as.numeric(ci_level),
          n_permutations = as.integer(n_permutations),
          permutation_seed = as.integer(permutation_seed),
          p_adjust_method = as.character(p_adjust_method),
          n_bins = as.integer(unique(fit_summary$n_bins %||% n_bins)[1] %||% n_bins)
        )
      ),
      dynamics_table = wb_prim_obs_table(
        table = dyn_tbl,
        table_type = "trajectory_geneset_dynamics",
        entity_kind = "feature_set",
        meta = list(
          matrix_id = as.character(matrix_id),
          namespace = as.character(namespace),
          pseudotime_source_kind = as.character(pt_meta$pseudotime_source_kind),
          pseudotime_artifact_id = as.character(pt_meta$pseudotime_artifact_id),
          pseudotime_key = as.character(pt_meta$pseudotime_key),
          membership_artifact_id = as.character(pt_meta$membership_artifact_id),
          dynamic_score = "amplitude + sd_value + abs(late_minus_early) + abs(spearman_rho) * sd_value",
          abundance_metrics = "mean_score, max_score, min_score, auc_score, relative_amplitude, mean_se, signal_to_noise, low_abundance_flag",
          empirical_significance = "p_dynamic and q_dynamic from permuting cell-level scores relative to fixed pseudotime/bin structure; disabled when n_permutations=0",
          curve_class = "turns_on/turns_off/transient_peak/transient_dip/weak_on/weak_off/flat_or_noisy",
          passes_filters = "min_amplitude, min_bins_observed, min_features_detected, min_detected_fraction, min_mean_score, min_max_score, min_signal_to_noise"
        )
      ),
      top_sets = wb_prim_obs_table(
        table = top_tbl,
        table_type = "trajectory_geneset_dynamics_top",
        entity_kind = "feature_set",
        meta = list(
          matrix_id = as.character(matrix_id),
          namespace = as.character(namespace),
          top_n = as.integer(top_n)
        )
      ),
      driver_table = wb_prim_obs_table(
        table = driver_tbl,
        table_type = "trajectory_geneset_dynamics_drivers",
        entity_kind = "feature",
        meta = list(
          matrix_id = as.character(matrix_id),
          namespace = as.character(namespace),
          top_driver_genes = as.integer(top_driver_genes)
        )
      ),
      driver_curve_table = wb_prim_obs_table(
        table = driver_curve_tbl,
        table_type = "trajectory_geneset_dynamics_driver_curve",
        entity_kind = "trajectory_bin",
        meta = list(
          matrix_id = as.character(matrix_id),
          namespace = as.character(namespace),
          top_driver_genes = as.integer(top_driver_genes),
          smooth_method = as.character(smooth_method),
          bootstrap_n = as.integer(bootstrap_n)
        )
      ),
      fit_summary = wb_prim_obs_table(
        table = fit_summary,
        table_type = "trajectory_geneset_dynamics_summary",
        entity_kind = "lineage"
      )
    ),
    params = list(
      matrix_id = as.character(matrix_id),
      namespace = as.character(namespace),
      pseudotime_source_kind = as.character(pt_meta$pseudotime_source_kind),
      pseudotime_artifact_id = as.character(pt_meta$pseudotime_artifact_id),
      pseudotime_key = as.character(pt_meta$pseudotime_key),
      membership_artifact_id = as.character(pt_meta$membership_artifact_id),
      n_feature_sets_input = as.integer(length(set_names)),
      n_feature_sets_screened = as.integer(length(set_members)),
      n_lineages = as.integer(length(lineages)),
      n_bins = as.integer(unique(fit_summary$n_bins %||% n_bins)[1] %||% n_bins),
      score_method = as.character(score_method),
      summary_fun = as.character(summary_fun),
      min_cells_per_bin = as.integer(min_cells_per_bin),
      min_set_size = as.integer(min_set_size),
      max_set_size = as.integer(max_set_size),
      top_n = as.integer(top_n),
      on_off_min_delta = as.numeric(on_off_min_delta),
      monotonic_min_abs_rho = as.numeric(monotonic_min_abs_rho),
      top_driver_genes = as.integer(top_driver_genes),
      pseudotime_direction = as.character(pseudotime_direction),
      start_label = as.character(start_label),
      end_label = as.character(end_label),
      min_amplitude = as.numeric(min_amplitude),
      min_bins_observed = as.integer(min_bins_observed),
      min_features_detected = as.integer(min_features_detected),
      min_detected_fraction = as.numeric(min_detected_fraction),
      min_mean_score = as.numeric(min_mean_score),
      min_max_score = as.numeric(min_max_score),
      min_signal_to_noise = as.numeric(min_signal_to_noise),
      low_abundance_max_score = as.numeric(low_abundance_max_score),
      smooth_method = as.character(smooth_method),
      loess_span = as.numeric(loess_span),
      bootstrap_n = as.integer(bootstrap_n),
      ci_level = as.numeric(ci_level),
      class_min_amplitude = as.numeric(class_min_amplitude),
      n_permutations = as.integer(n_permutations),
      permutation_seed = as.integer(permutation_seed),
      p_adjust_method = as.character(p_adjust_method)
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

#' Screen Cell-Level Signal Dynamics Along A Trajectory
#'
#' Ranks precomputed cell-level signals, such as UCell scores, chromVAR scores,
#' or module scores, by dynamic behavior along trajectory pseudotime.
#'
#' This is the signal-family sibling of `trajectory_geneset_dynamics`: it
#' consumes a `cell_vector_family` directly instead of recomputing scores from a
#' matrix and feature-set registry.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param signal A `cell_vector_family` primitive. Direct `cell_vector`
#'   primitives are accepted and lifted to a single-key family.
#' @param model A `model_ref` primitive from trajectory fitting.
#' @param cells Optional effective cell IDs to restrict analysis.
#' @param lineage Optional lineage key subset.
#' @param signal_keys Optional signal-key subset within `signal`.
#' @param n_bins Number of pseudotime bins.
#' @param summary_fun One of `"mean"` or `"median"` across cells within each bin.
#' @param min_cells_per_bin Minimum cells required for an output bin.
#' @param top_n Number of top-ranked signals retained in `top_signals`.
#' @param on_off_min_delta Minimum absolute late-early delta for on/off classes.
#' @param monotonic_min_abs_rho Minimum absolute Spearman rho for on/off classes.
#' @param pseudotime_direction One of `"as_is"` or `"invert"`.
#' @param start_label Optional biological start label.
#' @param end_label Optional biological end label.
#' @param min_amplitude Minimum amplitude required for `passes_filters`.
#' @param min_bins_observed Minimum binned rows required for `passes_filters`.
#' @param smooth_method One of `"none"`, `"loess"`, or `"spline"`.
#' @param loess_span Span for loess smoothing.
#' @param bootstrap_n Bootstrap replicates per bin for confidence bands.
#' @param bootstrap_seed Random seed for bootstrap confidence bands.
#' @param ci_level Confidence interval level for bootstrap bands.
#' @param class_min_amplitude Minimum amplitude for non-flat curve classes.
#'
#' @return A standard op result list with `outputs` containing `signal_table`,
#'   `dynamics_table`, `top_signals`, and `fit_summary`.
#'
#' @export
wb_op_trajectory_signal_dynamics <- function(bundle,
                                             signal,
                                             model = NULL,
                                             pseudotime = NULL,
                                             pseudotime_key = NULL,
                                             membership = NULL,
                                             pseudotime_artifact_id = NULL,
                                             membership_artifact_id = NULL,
                                             cells = NULL,
                                             lineage = NULL,
                                             signal_keys = NULL,
                                             n_bins = 50L,
                                             summary_fun = "mean",
                                             min_cells_per_bin = 5L,
                                             top_n = 50L,
                                             on_off_min_delta = 0,
                                             monotonic_min_abs_rho = 0.5,
                                             pseudotime_direction = "as_is",
                                             start_label = NULL,
                                             end_label = NULL,
                                             min_amplitude = 0,
                                             min_bins_observed = 5L,
                                             smooth_method = "none",
                                             loess_span = 0.5,
                                             bootstrap_n = 0L,
                                             bootstrap_seed = 1L,
                                             ci_level = 0.95,
                                             class_min_amplitude = 0) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert(.wb_is_primitive(signal), "trajectory_signal_dynamics: signal must be a primitive.")

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
  top_n <- suppressWarnings(as.integer(top_n))
  on_off_min_delta <- suppressWarnings(as.numeric(on_off_min_delta))
  monotonic_min_abs_rho <- suppressWarnings(as.numeric(monotonic_min_abs_rho))
  pseudotime_direction <- as.character(pseudotime_direction %||% "as_is")[1]
  if (!nzchar(pseudotime_direction)) pseudotime_direction <- "as_is"
  .wb_assert(pseudotime_direction %in% c("as_is", "invert"),
             "trajectory_signal_dynamics: pseudotime_direction must be 'as_is' or 'invert'.")
  start_label <- as.character(start_label %||% NA_character_)[1]
  end_label <- as.character(end_label %||% NA_character_)[1]
  min_amplitude <- suppressWarnings(as.numeric(min_amplitude)[1])
  min_bins_observed <- suppressWarnings(as.integer(min_bins_observed)[1])
  smooth_method <- .wb_trajectory_geneset_smooth_fun(smooth_method)
  loess_span <- suppressWarnings(as.numeric(loess_span)[1])
  bootstrap_n <- suppressWarnings(as.integer(bootstrap_n)[1])
  bootstrap_seed <- suppressWarnings(as.integer(bootstrap_seed)[1])
  ci_level <- suppressWarnings(as.numeric(ci_level)[1])
  class_min_amplitude <- suppressWarnings(as.numeric(class_min_amplitude)[1])
  .wb_assert(is.finite(min_cells_per_bin) && min_cells_per_bin >= 1L,
             "trajectory_signal_dynamics: min_cells_per_bin must be >= 1.")
  if (!is.finite(top_n) || top_n < 1L) top_n <- 50L
  if (!is.finite(on_off_min_delta) || on_off_min_delta < 0) on_off_min_delta <- 0
  if (!is.finite(monotonic_min_abs_rho) || monotonic_min_abs_rho < 0) monotonic_min_abs_rho <- 0.5
  if (!is.finite(min_amplitude) || min_amplitude < 0) min_amplitude <- 0
  if (!is.finite(min_bins_observed) || min_bins_observed < 1L) min_bins_observed <- 5L
  if (!is.finite(loess_span) || loess_span <= 0 || loess_span > 1) loess_span <- 0.5
  if (!is.finite(bootstrap_n) || bootstrap_n < 0L) bootstrap_n <- 0L
  if (!is.finite(bootstrap_seed)) bootstrap_seed <- 1L
  if (!is.finite(ci_level) || ci_level <= 0 || ci_level >= 1) ci_level <- 0.95
  if (!is.finite(class_min_amplitude) || class_min_amplitude < 0) class_min_amplitude <- 0

  sig_tbl <- wb_primitive_to_table(signal, include_context = FALSE)
  .wb_assert(all(c("key", "cell_id", "value") %in% colnames(sig_tbl)),
             "trajectory_signal_dynamics: signal family table missing key/cell_id/value.")
  sig_tbl$key <- as.character(sig_tbl$key)
  sig_tbl$cell_id <- as.character(sig_tbl$cell_id)
  sig_tbl$value <- suppressWarnings(as.numeric(sig_tbl$value))
  sig_tbl <- sig_tbl[nzchar(sig_tbl$key) & nzchar(sig_tbl$cell_id) & is.finite(sig_tbl$value), , drop = FALSE]
  .wb_assert(nrow(sig_tbl) > 0L, "trajectory_signal_dynamics: signal has no finite rows.")

  if (!is.null(signal_keys)) {
    signal_keys <- unique(as.character(signal_keys))
    signal_keys <- signal_keys[nzchar(signal_keys)]
    .wb_assert(length(signal_keys) > 0L, "trajectory_signal_dynamics: signal_keys is empty after cleaning.")
    sig_tbl <- sig_tbl[sig_tbl$key %in% signal_keys, , drop = FALSE]
    .wb_assert(nrow(sig_tbl) > 0L, "trajectory_signal_dynamics: no signal rows remain after signal_keys filtering.")
  }
  signal_keys <- unique(as.character(sig_tbl$key))

  pt_res <- .wb_trajectory_dynamics_resolve_lineages(
    bundle = bundle,
    model = model,
    pseudotime = pseudotime,
    pseudotime_key = pseudotime_key,
    membership = membership,
    lineage = lineage,
    cells = cells,
    pseudotime_artifact_id = pseudotime_artifact_id %||% .wb_trajectory_input_artifact_id(pseudotime),
    membership_artifact_id = membership_artifact_id %||% .wb_trajectory_input_artifact_id(membership)
  )
  lineages <- pt_res$lineages
  pt_meta <- pt_res$meta

  curve_rows <- list()
  dyn_rows <- list()
  fit_rows <- list()
  ci <- 0L
  di <- 0L
  si <- 0L

  for (lin in names(lineages)) {
    df_lin <- lineages[[lin]]
    pt <- suppressWarnings(as.numeric(df_lin$pseudotime))
    names(pt) <- as.character(df_lin$cell_id)
    keep <- is.finite(pt)
    pt <- pt[keep]
    if (identical(pseudotime_direction, "invert")) {
      pt <- max(pt, na.rm = TRUE) - pt
    }
    cells_lin <- as.character(names(pt))
    .wb_assert(length(cells_lin) >= 10L,
               paste0("trajectory_signal_dynamics: lineage '", lin, "' has <10 finite pseudotime cells."))
    .wb_assert(stats::sd(pt) > 0,
               paste0("trajectory_signal_dynamics: lineage '", lin, "' has zero pseudotime variance."))

    bb <- .wb_trajectory_smooth_bins(pt, n_bins = n_bins)
    bins <- bb$bins
    n_bins_used <- bb$n_bins
    n_rows_lineage <- 0L
    n_signals_with_rows <- 0L
    sig_lin <- sig_tbl[sig_tbl$cell_id %in% cells_lin, c("key", "cell_id", "value"), drop = FALSE]
    .wb_assert(nrow(sig_lin) > 0L,
               paste0("trajectory_signal_dynamics: no signal rows overlap lineage '", lin, "'."))

    for (sig_key in signal_keys) {
      sub <- sig_lin[sig_lin$key == sig_key, , drop = FALSE]
      if (!nrow(sub)) next
      vals <- sub$value[match(cells_lin, sub$cell_id)]
      keep2 <- is.finite(vals) & is.finite(pt) & is.finite(bins)
      if (sum(keep2) < min_cells_per_bin) next

      agg <- .wb_trajectory_geneset_curve(
        entity_id = sig_key,
        lineage_id = lin,
        pt = pt[keep2],
        values = vals[keep2],
        bins = bins[keep2],
        n_bins_used = n_bins_used,
        min_cells_per_bin = min_cells_per_bin,
        summary_fun = summary_fun,
        smooth_method = smooth_method,
        loess_span = loess_span,
        bootstrap_n = bootstrap_n,
        ci_level = ci_level,
        seed = bootstrap_seed + di + 1L
      )
      if (is.null(agg) || !nrow(agg)) next

      agg$signal_key <- as.character(agg$entity_id)
      agg$feature_set <- as.character(agg$signal_key)
      agg$label <- as.character(agg$signal_key)
      agg <- agg[, c("signal_key", "feature_set", "lineage_id", "bin", "pseudotime",
                     "pseudotime_min", "pseudotime_max", "value", "value_raw",
                     "value_smooth", "value_se", "value_ci_low", "value_ci_high",
                     "n_cells", "label"), drop = FALSE]

      mm <- .wb_trajectory_geneset_dynamic_metrics(agg)
      curve_class <- .wb_trajectory_geneset_curve_class(
        late_minus_early = mm$late_minus_early,
        spearman_rho = mm$spearman_rho,
        amplitude = mm$amplitude,
        peak_bin = mm$peak_bin,
        trough_bin = mm$trough_bin,
        n_bins_observed = mm$n_bins_observed,
        on_off_min_delta = on_off_min_delta,
        monotonic_min_abs_rho = monotonic_min_abs_rho,
        class_min_amplitude = class_min_amplitude
      )
      filter_reasons <- character(0)
      if (!is.finite(mm$amplitude) || mm$amplitude < min_amplitude) filter_reasons <- c(filter_reasons, "low_amplitude")
      if (!is.finite(mm$n_bins_observed) || mm$n_bins_observed < min_bins_observed) filter_reasons <- c(filter_reasons, "too_few_bins")
      passes_filters <- length(filter_reasons) == 0L

      di <- di + 1L
      dyn_rows[[di]] <- data.frame(
        signal_key = as.character(sig_key),
        feature_set = as.character(sig_key),
        lineage_id = as.character(lin),
        curve_class = as.character(curve_class),
        n_bins_observed = as.integer(mm$n_bins_observed),
        passes_filters = as.logical(passes_filters),
        filter_reason = if (passes_filters) "" else paste(filter_reasons, collapse = ";"),
        amplitude = as.numeric(mm$amplitude),
        sd_value = as.numeric(mm$sd_value),
        early_mean = as.numeric(mm$early_mean),
        late_mean = as.numeric(mm$late_mean),
        late_minus_early = as.numeric(mm$late_minus_early),
        spearman_rho = as.numeric(mm$spearman_rho),
        abs_spearman_rho = as.numeric(abs(mm$spearman_rho)),
        dynamic_score = as.numeric(mm$dynamic_score),
        peak_bin = as.integer(mm$peak_bin),
        trough_bin = as.integer(mm$trough_bin),
        peak_pseudotime = as.numeric(mm$peak_pseudotime),
        trough_pseudotime = as.numeric(mm$trough_pseudotime),
        stringsAsFactors = FALSE
      )

      ci <- ci + 1L
      curve_rows[[ci]] <- agg
      n_signals_with_rows <- n_signals_with_rows + 1L
      n_rows_lineage <- n_rows_lineage + nrow(agg)
    }

    si <- si + 1L
    fit_rows[[si]] <- data.frame(
      lineage_id = as.character(lin),
      pseudotime_source_kind = as.character(pt_meta$pseudotime_source_kind),
      pseudotime_artifact_id = as.character(pt_meta$pseudotime_artifact_id),
      pseudotime_key = as.character(pt_meta$pseudotime_key),
      membership_artifact_id = as.character(pt_meta$membership_artifact_id),
      n_pseudotime_cells = as.integer(pt_meta$n_pseudotime_cells),
      n_membership_cells = as.integer(pt_meta$n_membership_cells),
      n_cells_used = as.integer(length(cells_lin)),
      n_signal_keys_input = as.integer(length(signal_keys)),
      n_signal_keys_with_rows = as.integer(n_signals_with_rows),
      n_rows = as.integer(n_rows_lineage),
      n_bins = as.integer(n_bins_used),
      summary_fun = as.character(summary_fun),
      min_cells_per_bin = as.integer(min_cells_per_bin),
      on_off_min_delta = as.numeric(on_off_min_delta),
      monotonic_min_abs_rho = as.numeric(monotonic_min_abs_rho),
      pseudotime_direction = as.character(pseudotime_direction),
      start_label = as.character(start_label),
      end_label = as.character(end_label),
      min_amplitude = as.numeric(min_amplitude),
      min_bins_observed = as.integer(min_bins_observed),
      smooth_method = as.character(smooth_method),
      loess_span = as.numeric(loess_span),
      bootstrap_n = as.integer(bootstrap_n),
      ci_level = as.numeric(ci_level),
      class_min_amplitude = as.numeric(class_min_amplitude),
      stringsAsFactors = FALSE
    )
  }

  curve_tbl <- if (ci == 0L) {
    data.frame(
      signal_key = character(0), feature_set = character(0), lineage_id = character(0),
      bin = integer(0), pseudotime = numeric(0), pseudotime_min = numeric(0),
      pseudotime_max = numeric(0), value = numeric(0), value_raw = numeric(0),
      value_smooth = numeric(0), value_se = numeric(0), value_ci_low = numeric(0),
      value_ci_high = numeric(0), n_cells = integer(0), label = character(0),
      stringsAsFactors = FALSE
    )
  } else {
    out <- do.call(rbind, curve_rows[seq_len(ci)])
    rownames(out) <- NULL
    out
  }
  dyn_tbl <- if (di == 0L) {
    data.frame(
      signal_key = character(0), feature_set = character(0), lineage_id = character(0),
      curve_class = character(0), n_bins_observed = integer(0), passes_filters = logical(0),
      filter_reason = character(0), amplitude = numeric(0), sd_value = numeric(0),
      early_mean = numeric(0), late_mean = numeric(0), late_minus_early = numeric(0),
      spearman_rho = numeric(0), abs_spearman_rho = numeric(0), dynamic_score = numeric(0),
      peak_bin = integer(0), trough_bin = integer(0), peak_pseudotime = numeric(0),
      trough_pseudotime = numeric(0), rank = integer(0), stringsAsFactors = FALSE
    )
  } else {
    out <- do.call(rbind, dyn_rows[seq_len(di)])
    out <- out[order(as.character(out$lineage_id), -out$dynamic_score, -out$amplitude, -out$sd_value), , drop = FALSE]
    out$rank <- ave(seq_len(nrow(out)), as.character(out$lineage_id), FUN = seq_along)
    rownames(out) <- NULL
    out
  }
  eligible_dyn <- dyn_tbl[dyn_tbl$passes_filters %in% TRUE, , drop = FALSE]
  if (!nrow(eligible_dyn)) eligible_dyn <- dyn_tbl
  top_tbl <- head(eligible_dyn[order(as.character(eligible_dyn$lineage_id), eligible_dyn$rank), , drop = FALSE], top_n)
  fit_summary <- do.call(rbind, fit_rows[seq_len(si)])
  rownames(fit_summary) <- NULL

  list(
    outputs = list(
      signal_table = wb_prim_obs_table(
        table = curve_tbl,
        table_type = "trajectory_signal_dynamics_curve",
        entity_kind = "trajectory_bin",
        meta = list(
          signal_kind = as.character(signal$kind),
          pseudotime_source_kind = as.character(pt_meta$pseudotime_source_kind),
          pseudotime_artifact_id = as.character(pt_meta$pseudotime_artifact_id),
          pseudotime_key = as.character(pt_meta$pseudotime_key),
          membership_artifact_id = as.character(pt_meta$membership_artifact_id),
          n_signal_keys = as.integer(length(signal_keys)),
          summary_fun = as.character(summary_fun),
          min_cells_per_bin = as.integer(min_cells_per_bin),
          on_off_min_delta = as.numeric(on_off_min_delta),
          monotonic_min_abs_rho = as.numeric(monotonic_min_abs_rho),
          pseudotime_direction = as.character(pseudotime_direction),
          start_label = as.character(start_label),
          end_label = as.character(end_label),
          min_amplitude = as.numeric(min_amplitude),
          min_bins_observed = as.integer(min_bins_observed),
          smooth_method = as.character(smooth_method),
          loess_span = as.numeric(loess_span),
          bootstrap_n = as.integer(bootstrap_n),
          ci_level = as.numeric(ci_level),
          n_bins = as.integer(unique(fit_summary$n_bins %||% n_bins)[1] %||% n_bins)
        )
      ),
      dynamics_table = wb_prim_obs_table(
        table = dyn_tbl,
        table_type = "trajectory_signal_dynamics",
        entity_kind = "signal",
        meta = list(
          dynamic_score = "amplitude + sd_value + abs(late_minus_early) + abs(spearman_rho) * sd_value",
          pseudotime_source_kind = as.character(pt_meta$pseudotime_source_kind),
          pseudotime_artifact_id = as.character(pt_meta$pseudotime_artifact_id),
          pseudotime_key = as.character(pt_meta$pseudotime_key),
          membership_artifact_id = as.character(pt_meta$membership_artifact_id),
          curve_class = "turns_on/turns_off/transient_peak/transient_dip/weak_on/weak_off/flat_or_noisy",
          passes_filters = "min_amplitude, min_bins_observed"
        )
      ),
      top_signals = wb_prim_obs_table(
        table = top_tbl,
        table_type = "trajectory_signal_dynamics_top",
        entity_kind = "signal",
        meta = list(top_n = as.integer(top_n))
      ),
      fit_summary = wb_prim_obs_table(
        table = fit_summary,
        table_type = "trajectory_signal_dynamics_summary",
        entity_kind = "lineage"
      )
    ),
    params = list(
      signal_kind = as.character(signal$kind),
      pseudotime_source_kind = as.character(pt_meta$pseudotime_source_kind),
      pseudotime_artifact_id = as.character(pt_meta$pseudotime_artifact_id),
      pseudotime_key = as.character(pt_meta$pseudotime_key),
      membership_artifact_id = as.character(pt_meta$membership_artifact_id),
      signal_keys = as.character(signal_keys),
      n_signal_keys_input = as.integer(length(signal_keys)),
      n_lineages = as.integer(length(lineages)),
      n_bins = as.integer(unique(fit_summary$n_bins %||% n_bins)[1] %||% n_bins),
      summary_fun = as.character(summary_fun),
      min_cells_per_bin = as.integer(min_cells_per_bin),
      top_n = as.integer(top_n),
      on_off_min_delta = as.numeric(on_off_min_delta),
      monotonic_min_abs_rho = as.numeric(monotonic_min_abs_rho),
      pseudotime_direction = as.character(pseudotime_direction),
      start_label = as.character(start_label),
      end_label = as.character(end_label),
      min_amplitude = as.numeric(min_amplitude),
      min_bins_observed = as.integer(min_bins_observed),
      smooth_method = as.character(smooth_method),
      loess_span = as.numeric(loess_span),
      bootstrap_n = as.integer(bootstrap_n),
      ci_level = as.numeric(ci_level),
      class_min_amplitude = as.numeric(class_min_amplitude)
    )
  )
}
