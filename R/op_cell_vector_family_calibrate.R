#' Calibrate A `cell_vector_family` Across Keys
#'
#' Normalizes one keyed per-cell signal family so keys with different raw score
#' ranges become more comparable. Calibration is applied independently within
#' each key, preserving the original `(cell_id, key)` structure.
#'
#' @param signal A `cell_vector_family` primitive.
#' @param signal_keys Optional character vector of keys to consider.
#' @param method Calibration method. One of `"percentile"`, `"zscore"`, or
#'   `"robust_zscore"`.
#' @param center Logical; for `zscore`, whether to subtract the mean.
#' @param scale Logical; for `zscore`, whether to divide by the standard
#'   deviation.
#' @param ties_method Rank-tie handling used by percentile calibration.
#' @param na_rm Whether to ignore non-finite values when fitting calibration.
#'
#' @return Standard op result list with `calibrated_signal` and
#'   `calibration_summary`.
#'
#' @export
wb_op_cell_vector_family_calibrate <- function(signal,
                                               signal_keys = NULL,
                                               method = c("percentile", "zscore", "robust_zscore"),
                                               center = TRUE,
                                               scale = TRUE,
                                               ties_method = c("average", "first", "random", "max", "min"),
                                               na_rm = TRUE) {
  .wb_assert_kind(signal, "cell_vector_family")

  method <- match.arg(method)
  ties_method <- match.arg(ties_method)
  .wb_assert(is.logical(center) && length(center) == 1, "center must be length-1 logical.")
  .wb_assert(is.logical(scale) && length(scale) == 1, "scale must be length-1 logical.")
  .wb_assert(is.logical(na_rm) && length(na_rm) == 1, "na_rm must be length-1 logical.")

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
  .wb_assert(!any(dup), "signal contains duplicate cell_id/key pairs; calibrator expects one value per pair.")

  calibrate_one <- function(vals) {
    ok <- is.finite(vals)
    if (!isTRUE(na_rm)) ok <- rep(TRUE, length(vals))
    out <- rep(NA_real_, length(vals))
    fit_vals <- vals[ok]
    if (!length(fit_vals)) return(list(value = out, meta = list()))

    if (identical(method, "percentile")) {
      if (length(fit_vals) == 1L) {
        out[ok] <- 1
      } else {
        rk <- rank(fit_vals, ties.method = ties_method, na.last = "keep")
        out[ok] <- (rk - 1) / (length(fit_vals) - 1)
      }
      return(list(
        value = out,
        meta = list(center = NULL, scale = NULL, method = method)
      ))
    }

    if (identical(method, "zscore")) {
      mu <- if (isTRUE(center)) mean(fit_vals, na.rm = TRUE) else 0
      sdev <- if (isTRUE(scale)) stats::sd(fit_vals, na.rm = TRUE) else 1
      if (!is.finite(sdev) || identical(as.numeric(sdev), 0)) sdev <- 1
      out[ok] <- (fit_vals - mu) / sdev
      return(list(
        value = out,
        meta = list(center = mu, scale = sdev, method = method)
      ))
    }

    med <- stats::median(fit_vals, na.rm = TRUE)
    mad0 <- stats::mad(fit_vals, center = med, constant = 1, na.rm = TRUE)
    if (!is.finite(mad0) || identical(as.numeric(mad0), 0)) mad0 <- 1
    out[ok] <- (fit_vals - med) / mad0
    list(
      value = out,
      meta = list(center = med, scale = mad0, method = method)
    )
  }

  parts <- split(df, df$key)
  out_rows <- vector("list", length(parts))
  summary_rows <- vector("list", length(parts))
  i <- 0L

  for (key_i in names(parts)) {
    part <- parts[[key_i]]
    cal <- calibrate_one(part$value)
    i <- i + 1L

    out_rows[[i]] <- data.frame(
      key = as.character(key_i),
      cell_id = as.character(part$cell_id),
      value = as.numeric(cal$value),
      stringsAsFactors = FALSE
    )

    raw_q <- suppressWarnings(stats::quantile(part$value, probs = c(0.25, 0.5, 0.75), na.rm = TRUE, names = FALSE, type = 7))
    cal_q <- suppressWarnings(stats::quantile(cal$value, probs = c(0.25, 0.5, 0.75), na.rm = TRUE, names = FALSE, type = 7))
    summary_rows[[i]] <- data.frame(
      entity_id = as.character(key_i),
      key = as.character(key_i),
      n_cells = nrow(part),
      n_finite = sum(is.finite(part$value)),
      raw_min = suppressWarnings(min(part$value, na.rm = TRUE)),
      raw_q25 = as.numeric(raw_q[1]),
      raw_median = as.numeric(raw_q[2]),
      raw_mean = suppressWarnings(mean(part$value, na.rm = TRUE)),
      raw_q75 = as.numeric(raw_q[3]),
      raw_max = suppressWarnings(max(part$value, na.rm = TRUE)),
      calibrated_min = suppressWarnings(min(cal$value, na.rm = TRUE)),
      calibrated_q25 = as.numeric(cal_q[1]),
      calibrated_median = as.numeric(cal_q[2]),
      calibrated_mean = suppressWarnings(mean(cal$value, na.rm = TRUE)),
      calibrated_q75 = as.numeric(cal_q[3]),
      calibrated_max = suppressWarnings(max(cal$value, na.rm = TRUE)),
      calibration_center = suppressWarnings(as.numeric(cal$meta$center %||% NA_real_)),
      calibration_scale = suppressWarnings(as.numeric(cal$meta$scale %||% NA_real_)),
      stringsAsFactors = FALSE
    )
  }

  out_df <- do.call(rbind, out_rows)
  summary_tbl <- do.call(rbind, summary_rows)
  rownames(out_df) <- NULL
  rownames(summary_tbl) <- NULL

  list(
    outputs = list(
      calibrated_signal = wb_prim_cell_vector_family(
        key = as.character(out_df$key),
        cell_id = as.character(out_df$cell_id),
        value = as.numeric(out_df$value),
        value_type = "continuous"
      ),
      calibration_summary = wb_prim_obs_table(
        table = summary_tbl,
        table_type = "cell_vector_family_calibration_summary",
        entity_kind = "signal_key",
        meta = list(
          method = as.character(method),
          signal_keys = keys_use
        )
      )
    ),
    params = list(
      method = as.character(method),
      signal_keys = keys_use,
      n_keys = length(keys_use),
      n_rows = nrow(df),
      center = isTRUE(center),
      scale = isTRUE(scale),
      ties_method = as.character(ties_method),
      na_rm = isTRUE(na_rm)
    )
  )
}
