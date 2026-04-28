#' QC A `cell_vector_family`
#'
#' Computes generic quality-control summaries for one keyed per-cell signal
#' family, including per-key distribution statistics and pairwise key
#' relationships derived from shared cells.
#'
#' @param signal A `cell_vector_family` primitive.
#' @param signal_keys Optional character vector of keys to consider.
#' @param grouping Optional categorical `cell_vector` used to compute grouped QC
#'   summaries.
#' @param correlation_methods Correlation methods to compute for pairwise key
#'   relationships. Any subset of `"pearson"` and `"spearman"`.
#' @param tie_tol Numeric tolerance used when counting top-key ties.
#'
#' @return Standard op result list with `key_summary`, `pairwise_summary`, and
#'   `group_summary`.
#'
#' @export
wb_op_cell_vector_family_qc <- function(signal,
                                        signal_keys = NULL,
                                        grouping = NULL,
                                        correlation_methods = c("pearson", "spearman"),
                                        tie_tol = 1e-08) {
  .wb_assert_kind(signal, "cell_vector_family")
  if (!is.null(grouping)) .wb_assert_kind(grouping, "cell_vector")

  corr_methods <- unique(as.character(correlation_methods %||% character(0)))
  .wb_assert(length(corr_methods) >= 1L, "correlation_methods must be non-empty.")
  .wb_assert(all(corr_methods %in% c("pearson", "spearman")),
             "correlation_methods must be drawn from: pearson, spearman.")
  .wb_assert(is.numeric(tie_tol) && length(tie_tol) == 1 && is.finite(tie_tol) && tie_tol >= 0,
             "tie_tol must be a single non-negative finite numeric.")

  keys_all <- unique(as.character(signal$key))
  keys_all <- keys_all[nzchar(keys_all)]
  .wb_assert(length(keys_all) > 0, "signal has no non-empty keys.")

  keys_use <- if (is.null(signal_keys)) keys_all else intersect(as.character(signal_keys), keys_all)
  .wb_assert(length(keys_use) > 0, "No signal_keys remain after filtering.")

  df <- data.frame(
    cell_id = as.character(signal$cell_id),
    key = as.character(signal$key),
    value = as.numeric(signal$value),
    stringsAsFactors = FALSE
  )
  df <- df[df$key %in% keys_use, , drop = FALSE]
  .wb_assert(nrow(df) > 0, "No rows remain after signal_keys filtering.")

  dup <- duplicated(df[, c("cell_id", "key")])
  .wb_assert(!any(dup), "signal contains duplicate cell_id/key pairs; QC expects one value per pair.")

  cells <- unique(as.character(df$cell_id))
  cells <- cells[nzchar(cells)]
  keys_use <- unique(as.character(keys_use))

  score_mat <- matrix(NA_real_, nrow = length(cells), ncol = length(keys_use),
                      dimnames = list(cells, keys_use))
  score_mat[cbind(match(df$cell_id, cells), match(df$key, keys_use))] <- df$value

  winner_count <- stats::setNames(integer(length(keys_use)), keys_use)
  winner_tied_count <- stats::setNames(integer(length(keys_use)), keys_use)
  for (i in seq_len(nrow(score_mat))) {
    vals <- score_mat[i, ]
    ok <- is.finite(vals)
    if (!any(ok)) next
    vals_ok <- vals[ok]
    best <- max(vals_ok)
    top_keys <- names(vals_ok)[abs(vals_ok - best) <= as.numeric(tie_tol)]
    if (!length(top_keys)) next
    if (length(top_keys) == 1L) {
      winner_count[top_keys] <- winner_count[top_keys] + 1L
    } else {
      winner_tied_count[top_keys] <- winner_tied_count[top_keys] + 1L
    }
  }

  key_rows <- vector("list", length(keys_use))
  for (i in seq_along(keys_use)) {
    key_i <- keys_use[i]
    vals <- score_mat[, key_i]
    finite_vals <- vals[is.finite(vals)]
    q <- if (length(finite_vals)) {
      stats::quantile(finite_vals, probs = c(0.25, 0.5, 0.75), na.rm = TRUE, names = FALSE, type = 7)
    } else {
      c(NA_real_, NA_real_, NA_real_)
    }
    key_rows[[i]] <- data.frame(
      entity_id = key_i,
      key = key_i,
      n_cells_total = length(vals),
      n_finite = length(finite_vals),
      pct_finite = length(finite_vals) / max(1L, length(vals)),
      score_min = suppressWarnings(if (length(finite_vals)) min(finite_vals, na.rm = TRUE) else NA_real_),
      score_q25 = as.numeric(q[1]),
      score_median = as.numeric(q[2]),
      score_mean = suppressWarnings(if (length(finite_vals)) mean(finite_vals, na.rm = TRUE) else NA_real_),
      score_q75 = as.numeric(q[3]),
      score_max = suppressWarnings(if (length(finite_vals)) max(finite_vals, na.rm = TRUE) else NA_real_),
      score_sd = suppressWarnings(if (length(finite_vals) >= 2L) stats::sd(finite_vals, na.rm = TRUE) else NA_real_),
      dynamic_range = suppressWarnings(if (length(finite_vals)) max(finite_vals, na.rm = TRUE) - min(finite_vals, na.rm = TRUE) else NA_real_),
      top1_count = as.integer(winner_count[[key_i]] %||% 0L),
      top1_pct = as.numeric((winner_count[[key_i]] %||% 0L) / max(1L, nrow(score_mat))),
      tied_top_count = as.integer(winner_tied_count[[key_i]] %||% 0L),
      stringsAsFactors = FALSE
    )
  }
  key_summary <- do.call(rbind, key_rows)
  rownames(key_summary) <- NULL

  pair_rows <- list()
  idx <- 0L
  if (length(keys_use) >= 2L) {
    for (i in seq_len(length(keys_use) - 1L)) {
      for (j in seq.int(i + 1L, length(keys_use))) {
        key_a <- keys_use[i]
        key_b <- keys_use[j]
        va <- score_mat[, key_a]
        vb <- score_mat[, key_b]
        keep <- is.finite(va) & is.finite(vb)
        n_overlap <- sum(keep)
        pearson <- NA_real_
        spearman <- NA_real_
        if (n_overlap >= 2L) {
          if ("pearson" %in% corr_methods) pearson <- suppressWarnings(stats::cor(va[keep], vb[keep], method = "pearson"))
          if ("spearman" %in% corr_methods) spearman <- suppressWarnings(stats::cor(va[keep], vb[keep], method = "spearman"))
        }
        idx <- idx + 1L
        pair_rows[[idx]] <- data.frame(
          key_a = key_a,
          key_b = key_b,
          n_overlap = as.integer(n_overlap),
          pearson_cor = as.numeric(pearson),
          spearman_cor = as.numeric(spearman),
          stringsAsFactors = FALSE
        )
      }
    }
  }
  pairwise_summary <- if (length(pair_rows)) do.call(rbind, pair_rows) else data.frame(
    key_a = character(0),
    key_b = character(0),
    n_overlap = integer(0),
    pearson_cor = numeric(0),
    spearman_cor = numeric(0),
    stringsAsFactors = FALSE
  )
  rownames(pairwise_summary) <- NULL

  group_summary <- data.frame(
    entity_id = character(0),
    group_id = character(0),
    key = character(0),
    n_cells_group = integer(0),
    n_finite = integer(0),
    pct_finite = numeric(0),
    score_min = numeric(0),
    score_q25 = numeric(0),
    score_median = numeric(0),
    score_mean = numeric(0),
    score_q75 = numeric(0),
    score_max = numeric(0),
    score_sd = numeric(0),
    dynamic_range = numeric(0),
    top1_count = integer(0),
    top1_pct = numeric(0),
    tied_top_count = integer(0),
    stringsAsFactors = FALSE
  )

  grouping_levels <- character(0)
  if (!is.null(grouping)) {
    gvals <- as.character(grouping$value)
    names(gvals) <- as.character(grouping$cell_id)
    gvals <- gvals[cells]
    keep_group <- !is.na(gvals) & nzchar(gvals)
    gvals <- gvals[keep_group]
    if (length(gvals) > 0L) {
      grouping_levels <- unique(as.character(gvals))
      group_rows <- vector("list", length(grouping_levels) * length(keys_use))
      gi <- 0L
      for (grp in grouping_levels) {
        grp_cells <- names(gvals)[gvals == grp]
        grp_mat <- score_mat[grp_cells, , drop = FALSE]
        grp_winner_count <- stats::setNames(integer(length(keys_use)), keys_use)
        grp_tied_count <- stats::setNames(integer(length(keys_use)), keys_use)
        for (i in seq_len(nrow(grp_mat))) {
          vals <- grp_mat[i, ]
          ok <- is.finite(vals)
          if (!any(ok)) next
          vals_ok <- vals[ok]
          best <- max(vals_ok)
          top_keys <- names(vals_ok)[abs(vals_ok - best) <= as.numeric(tie_tol)]
          if (!length(top_keys)) next
          if (length(top_keys) == 1L) {
            grp_winner_count[top_keys] <- grp_winner_count[top_keys] + 1L
          } else {
            grp_tied_count[top_keys] <- grp_tied_count[top_keys] + 1L
          }
        }

        for (key_i in keys_use) {
          vals <- grp_mat[, key_i]
          finite_vals <- vals[is.finite(vals)]
          q <- if (length(finite_vals)) {
            stats::quantile(finite_vals, probs = c(0.25, 0.5, 0.75), na.rm = TRUE, names = FALSE, type = 7)
          } else {
            c(NA_real_, NA_real_, NA_real_)
          }
          gi <- gi + 1L
          group_rows[[gi]] <- data.frame(
            entity_id = paste0(grp, "::", key_i),
            group_id = grp,
            key = key_i,
            n_cells_group = length(vals),
            n_finite = length(finite_vals),
            pct_finite = length(finite_vals) / max(1L, length(vals)),
            score_min = suppressWarnings(if (length(finite_vals)) min(finite_vals, na.rm = TRUE) else NA_real_),
            score_q25 = as.numeric(q[1]),
            score_median = as.numeric(q[2]),
            score_mean = suppressWarnings(if (length(finite_vals)) mean(finite_vals, na.rm = TRUE) else NA_real_),
            score_q75 = as.numeric(q[3]),
            score_max = suppressWarnings(if (length(finite_vals)) max(finite_vals, na.rm = TRUE) else NA_real_),
            score_sd = suppressWarnings(if (length(finite_vals) >= 2L) stats::sd(finite_vals, na.rm = TRUE) else NA_real_),
            dynamic_range = suppressWarnings(if (length(finite_vals)) max(finite_vals, na.rm = TRUE) - min(finite_vals, na.rm = TRUE) else NA_real_),
            top1_count = as.integer(grp_winner_count[[key_i]] %||% 0L),
            top1_pct = as.numeric((grp_winner_count[[key_i]] %||% 0L) / max(1L, nrow(grp_mat))),
            tied_top_count = as.integer(grp_tied_count[[key_i]] %||% 0L),
            stringsAsFactors = FALSE
          )
        }
      }
      group_summary <- do.call(rbind, group_rows[seq_len(gi)])
      rownames(group_summary) <- NULL
    }
  }

  list(
    outputs = list(
      key_summary = wb_prim_obs_table(
        table = key_summary,
        table_type = "cell_vector_family_qc_key_summary",
        entity_kind = "signal_key",
        meta = list(
          signal_keys = keys_use,
          tie_tol = as.numeric(tie_tol)
        )
      ),
      pairwise_summary = wb_prim_obs_table(
        table = pairwise_summary,
        table_type = "cell_vector_family_qc_pairwise_summary",
        entity_kind = "signal_key_pair",
        meta = list(
          signal_keys = keys_use,
          correlation_methods = corr_methods
        )
      ),
      group_summary = wb_prim_obs_table(
        table = group_summary,
        table_type = "cell_vector_family_qc_group_summary",
        entity_kind = "signal_key_group",
        meta = list(
          signal_keys = keys_use,
          grouping_levels = grouping_levels,
          has_grouping = !is.null(grouping)
        )
      )
    ),
    params = list(
      signal_keys = keys_use,
      n_keys = length(keys_use),
      n_cells = length(cells),
      has_grouping = !is.null(grouping),
      n_groups = length(grouping_levels),
      correlation_methods = corr_methods,
      tie_tol = as.numeric(tie_tol)
    )
  )
}
