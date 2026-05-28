#' Associate a continuous cell vector with a categorical cell vector
#'
#' Computes per-group summaries and omnibus association tests.
#'
#' @param vector_cont Named numeric vector (names are cell IDs).
#' @param vector_group Named categorical vector (names are cell IDs).
#' @param min_n_per_group Minimum cells per group to keep.
#' @export
wb_op_cell_vector_assoc <- function(vector_cont,
                                    vector_group,
                                    min_n_per_group = 3L) {
  .wb_assert(is.atomic(vector_cont) && !is.null(names(vector_cont)),
             "vector_cont must be a named vector.")
  .wb_assert(is.atomic(vector_group) && !is.null(names(vector_group)),
             "vector_group must be a named vector.")
  .wb_assert(is.numeric(min_n_per_group) && length(min_n_per_group) == 1 && min_n_per_group >= 1,
             "min_n_per_group must be >=1.")

  df <- data.frame(
    cell_id = intersect(names(vector_cont), names(vector_group)),
    stringsAsFactors = FALSE
  )
  .wb_assert(nrow(df) > 0, "No overlapping cells between vectors.")
  df$value <- suppressWarnings(as.numeric(vector_cont[df$cell_id]))
  df$group <- as.character(vector_group[df$cell_id])
  df <- df[is.finite(df$value) & !is.na(df$group) & nzchar(df$group), , drop = FALSE]
  .wb_assert(nrow(df) > 0, "No finite values after filtering.")

  gtab <- as.data.frame(table(df$group), stringsAsFactors = FALSE)
  keep_groups <- as.character(gtab$Var1[gtab$Freq >= as.integer(min_n_per_group)])
  df <- df[df$group %in% keep_groups, , drop = FALSE]
  .wb_assert(length(unique(df$group)) >= 2, "Need at least two groups after min_n_per_group filtering.")

  per_group <- do.call(
    rbind,
    lapply(split(df$value, df$group), function(v) {
      data.frame(
        n = length(v),
        mean = mean(v),
        median = stats::median(v),
        sd = stats::sd(v),
        stringsAsFactors = FALSE
      )
    })
  )
  per_group$group <- rownames(per_group)
  rownames(per_group) <- NULL
  per_group <- per_group[, c("group", "n", "mean", "median", "sd"), drop = FALSE]

  kw <- stats::kruskal.test(value ~ group, data = df)
  fit <- stats::lm(value ~ group, data = df)
  a <- stats::anova(fit)
  ss_total <- sum((df$value - mean(df$value))^2)
  ss_group <- if ("group" %in% rownames(a)) as.numeric(a["group", "Sum Sq"]) else NA_real_
  eta2 <- if (is.finite(ss_group) && is.finite(ss_total) && ss_total > 0) ss_group / ss_total else NA_real_

  summary_tbl <- data.frame(
    feature_id = "value_by_group",
    n_cells = nrow(df),
    n_groups = length(unique(df$group)),
    kruskal_p = as.numeric(kw$p.value),
    anova_p = as.numeric(stats::pf(a["group", "F value"], a["group", "Df"], a["Residuals", "Df"], lower.tail = FALSE)),
    eta2 = as.numeric(eta2),
    stringsAsFactors = FALSE
  )

  list(
    outputs = list(
      assoc_summary = wb_prim_feature_table(
        table = summary_tbl,
        table_type = "cell_vector_assoc",
        meta = list(test = "kruskal+anova", min_n_per_group = as.integer(min_n_per_group))
      ),
      group_stats = wb_prim_obs_table(
        table = per_group,
        table_type = "cell_vector_assoc_group_stats",
        entity_kind = "group"
      )
    ),
    params = list(
      n_cells = nrow(df),
      n_groups = length(unique(df$group)),
      min_n_per_group = as.integer(min_n_per_group)
    )
  )
}
