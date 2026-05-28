#' Compare two cell-level signals on shared cells
#'
#' @param a `cell_vector` primitive.
#' @param b `cell_vector` primitive.
#' @param cells Optional cell restriction.
#' @param compare_space Either `"raw"` or `"rank"`.
#' @param ties_method Passed to base `rank()` when `compare_space = "rank"`.
#' @param signal_a Optional label recorded in summary output.
#' @param signal_b Optional label recorded in summary output.
#'
#' @export
wb_op_cell_vector_compare <- function(a,
                                      b,
                                      cells = NULL,
                                      compare_space = "rank",
                                      ties_method = "average",
                                      signal_a = "a",
                                      signal_b = "b") {
  .wb_assert_kind(a, "cell_vector")
  .wb_assert_kind(b, "cell_vector")
  compare_space <- as.character(compare_space)[1]
  .wb_assert(compare_space %in% c("raw", "rank"),
             "compare_space must be one of: raw, rank.")
  ties_method <- as.character(ties_method)[1]
  .wb_assert(nzchar(ties_method), "ties_method must be a non-empty string.")

  xa <- suppressWarnings(as.numeric(a$value))
  xb <- suppressWarnings(as.numeric(b$value))
  names(xa) <- as.character(a$cell_id)
  names(xb) <- as.character(b$cell_id)

  keep <- intersect(names(xa), names(xb))
  if (!is.null(cells)) keep <- intersect(keep, as.character(cells))
  .wb_assert(length(keep) >= 3L, "cell_vector_compare requires at least 3 shared cells.")

  df <- data.frame(
    cell_id = keep,
    a = as.numeric(xa[keep]),
    b = as.numeric(xb[keep]),
    stringsAsFactors = FALSE
  )
  df <- df[is.finite(df$a) & is.finite(df$b), , drop = FALSE]
  .wb_assert(nrow(df) >= 3L, "cell_vector_compare requires at least 3 shared finite values.")

  if (identical(compare_space, "rank")) {
    df$a_cmp <- rank(df$a, ties.method = ties_method)
    df$b_cmp <- rank(df$b, ties.method = ties_method)
  } else {
    df$a_cmp <- df$a
    df$b_cmp <- df$b
  }

  df$delta <- df$a_cmp - df$b_cmp
  df$abs_delta <- abs(df$delta)

  .safe_cor <- function(x, y, method) {
    ok <- is.finite(x) & is.finite(y)
    x <- x[ok]
    y <- y[ok]
    if (length(x) < 3L) return(NA_real_)
    if (stats::sd(x) == 0 || stats::sd(y) == 0) return(NA_real_)
    suppressWarnings(as.numeric(stats::cor(x, y, method = method)))
  }

  summary_tbl <- data.frame(
    signal_a = as.character(signal_a)[1],
    signal_b = as.character(signal_b)[1],
    compare_space = compare_space,
    n_shared_cells = nrow(df),
    pearson = .safe_cor(df$a_cmp, df$b_cmp, "pearson"),
    spearman = .safe_cor(df$a_cmp, df$b_cmp, "spearman"),
    kendall = .safe_cor(df$a_cmp, df$b_cmp, "kendall"),
    mean_delta = mean(df$delta),
    mean_abs_delta = mean(df$abs_delta),
    median_abs_delta = stats::median(df$abs_delta),
    rmse = sqrt(mean(df$delta^2)),
    max_abs_delta = max(df$abs_delta),
    stringsAsFactors = FALSE
  )

  list(
    outputs = list(
      summary = wb_prim_obs_table(
        table = summary_tbl,
        table_type = "cell_vector_compare_summary",
        entity_kind = "signal_pair",
        meta = list(
          compare_space = compare_space,
          ties_method = ties_method
        )
      ),
      comparison = wb_prim_obs_table(
        table = df[, c("cell_id", "a", "b", "a_cmp", "b_cmp", "delta", "abs_delta"), drop = FALSE],
        table_type = "cell_vector_compare",
        entity_kind = "cell",
        meta = list(
          compare_space = compare_space,
          ties_method = ties_method
        )
      )
    ),
    params = list(
      compare_space = compare_space,
      ties_method = ties_method,
      signal_a = as.character(signal_a)[1],
      signal_b = as.character(signal_b)[1],
      n_shared_cells = nrow(df)
    )
  )
}
