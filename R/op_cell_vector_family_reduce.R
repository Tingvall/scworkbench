#' Reduce A `cell_vector_family` To A Single `cell_vector`
#'
#' Compresses a family of per-cell continuous scores into one categorical label
#' per cell using an explicit rule. The default rule is `argmax`, with optional
#' abstention thresholds on absolute score and winner margin.
#'
#' @param signal A `cell_vector_family` primitive.
#' @param signal_keys Optional character vector of keys to consider.
#' @param rule Reduction rule. Currently only `"argmax"` is implemented.
#' @param min_score Optional minimum winning score required to emit a label.
#' @param min_margin Optional minimum margin between top and second score.
#' @param unknown_label Label to emit when thresholds or tie policy abstain.
#' @param ties How to handle tied top scores: `"unknown"` or `"first"`.
#' @param tie_tol Numeric tolerance for tie detection.
#'
#' @return Standard op result list with `label`, `top_score`,
#'   `runner_up_score`, `score_margin`, `abstain_reason`, `decision_table`,
#'   `label_summary`, and normalized `params`.
#'
#' @export
wb_op_cell_vector_family_reduce <- function(signal,
                                           signal_keys = NULL,
                                           rule = c("argmax"),
                                           min_score = NULL,
                                           min_margin = NULL,
                                           unknown_label = "unknown",
                                           ties = c("unknown", "first"),
                                           tie_tol = 1e-08) {
  .wb_assert_kind(signal, "cell_vector_family")

  rule <- match.arg(rule)
  ties <- match.arg(ties)
  .wb_assert(is.null(min_score) || (is.numeric(min_score) && length(min_score) == 1),
             "min_score must be NULL or length-1 numeric.")
  .wb_assert(is.null(min_margin) || (is.numeric(min_margin) && length(min_margin) == 1),
             "min_margin must be NULL or length-1 numeric.")
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
  .wb_assert(!any(dup), "signal contains duplicate cell_id/key pairs; reducer expects one value per pair.")

  cells <- unique(as.character(df$cell_id))
  cells <- cells[nzchar(cells)]
  keys_use <- unique(as.character(keys_use))

  score_mat <- matrix(NA_real_, nrow = length(cells), ncol = length(keys_use),
                      dimnames = list(cells, keys_use))
  score_mat[cbind(match(df$cell_id, cells), match(df$key, keys_use))] <- df$value

  top_label <- rep(as.character(unknown_label)[1], length(cells))
  top_score <- rep(NA_real_, length(cells))
  runner_up_score <- rep(NA_real_, length(cells))
  score_margin <- rep(NA_real_, length(cells))
  abstain_reason <- rep("none", length(cells))

  for (i in seq_len(nrow(score_mat))) {
    vals <- score_mat[i, ]
    ok <- is.finite(vals)
    if (!any(ok)) next

    vals_ok <- vals[ok]
    keys_ok <- names(vals_ok)

    if (identical(rule, "argmax")) {
      ord <- order(vals_ok, decreasing = TRUE, na.last = TRUE)
      vals_ord <- vals_ok[ord]
      keys_ord <- keys_ok[ord]

      best <- vals_ord[1]
      second <- if (length(vals_ord) >= 2) vals_ord[2] else NA_real_
      margin <- if (length(vals_ord) >= 2) best - second else NA_real_
      ties_top <- sum(abs(vals_ord - best) <= as.numeric(tie_tol))

      top_score[i] <- best
      runner_up_score[i] <- second
      score_margin[i] <- margin

      if (ties_top > 1L && identical(ties, "unknown")) {
        abstain_reason[i] <- "tie"
        next
      }
      winner <- if (ties_top > 1L && identical(ties, "first")) sort(keys_ord[abs(vals_ord - best) <= as.numeric(tie_tol)])[1] else keys_ord[1]

      if (!is.null(min_score) && is.finite(best) && best < as.numeric(min_score)) {
        abstain_reason[i] <- "min_score"
        next
      }
      if (!is.null(min_margin) && is.finite(margin) && margin < as.numeric(min_margin)) {
        abstain_reason[i] <- "min_margin"
        next
      }

      top_label[i] <- winner
      abstain_reason[i] <- "none"
    }
  }

  decision_tbl <- data.frame(
    cell_id = cells,
    label = top_label,
    top_score = top_score,
    runner_up_score = runner_up_score,
    score_margin = score_margin,
    abstain_reason = abstain_reason,
    stringsAsFactors = FALSE
  )

  label_tbl <- data.frame(
    label = top_label,
    top_score = top_score,
    score_margin = score_margin,
    abstain_reason = abstain_reason,
    stringsAsFactors = FALSE
  )
  label_tbl <- label_tbl[!is.na(label_tbl$label) & nzchar(label_tbl$label), , drop = FALSE]

  summary_tbl <- do.call(
    rbind,
    lapply(split(label_tbl, label_tbl$label), function(x) {
      data.frame(
        label = as.character(x$label[1]),
        n_cells = nrow(x),
        pct_cells = nrow(x) / length(cells),
        mean_top_score = mean(x$top_score, na.rm = TRUE),
        mean_margin = mean(x$score_margin, na.rm = TRUE),
        n_abstained = sum(as.character(x$abstain_reason %||% "") != "none"),
        stringsAsFactors = FALSE
      )
    })
  )
  rownames(summary_tbl) <- NULL
  summary_tbl <- summary_tbl[order(summary_tbl$n_cells, decreasing = TRUE, summary_tbl$label), , drop = FALSE]

  list(
    outputs = list(
      label = wb_prim_cell_vector(stats::setNames(top_label, cells), value_type = "categorical"),
      top_score = wb_prim_cell_vector(stats::setNames(top_score, cells), value_type = "continuous"),
      runner_up_score = wb_prim_cell_vector(stats::setNames(runner_up_score, cells), value_type = "continuous"),
      score_margin = wb_prim_cell_vector(stats::setNames(score_margin, cells), value_type = "continuous"),
      abstain_reason = wb_prim_cell_vector(stats::setNames(abstain_reason, cells), value_type = "categorical"),
      decision_table = wb_prim_obs_table(
        table = decision_tbl,
        table_type = "cell_vector_family_reduce_decision_table",
        entity_kind = "cell",
        meta = list(
          rule = as.character(rule),
          unknown_label = as.character(unknown_label)[1],
          signal_keys = keys_use
        )
      ),
      label_summary = wb_prim_obs_table(
        table = summary_tbl,
        table_type = "cell_vector_family_reduce_summary",
        entity_kind = "label",
        meta = list(
          rule = as.character(rule),
          unknown_label = as.character(unknown_label)[1],
          signal_keys = keys_use
        )
      )
    ),
    params = list(
      rule = as.character(rule),
      signal_keys = keys_use,
      n_keys = length(keys_use),
      n_cells = length(cells),
      n_unknown = sum(top_label == as.character(unknown_label)[1], na.rm = TRUE),
      min_score = if (is.null(min_score)) NULL else as.numeric(min_score),
      min_margin = if (is.null(min_margin)) NULL else as.numeric(min_margin),
      unknown_label = as.character(unknown_label)[1],
      ties = as.character(ties),
      tie_tol = as.numeric(tie_tol)
    )
  )
}
