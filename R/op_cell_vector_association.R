#' Associate two typed cell vectors
#'
#' @param a First `cell_vector` primitive.
#' @param b Second `cell_vector` primitive.
#' @param cells Optional cell restriction.
#' @param min_n_per_group Minimum retained cells per categorical group.
#' @param method Optional association method; `"auto"` dispatches by types.
#' @export
wb_op_cell_vector_association <- function(a, b, cells = NULL,
                                          min_n_per_group = 3L, method = "auto") {
  .wb_assert_kind(a, "cell_vector")
  .wb_assert_kind(b, "cell_vector")
  .wb_assert(is.numeric(min_n_per_group) && length(min_n_per_group) == 1L && min_n_per_group >= 1L,
             "min_n_per_group must be >= 1.")
  method <- as.character(method)[1]
  .wb_assert(method %in% c("auto", "chisq", "fisher", "kruskal_anova", "correlation"),
             "method must be auto, chisq, fisher, kruskal_anova, or correlation.")
  type_a <- as.character(a$value_type %||% "categorical")[1]
  type_b <- as.character(b$value_type %||% "categorical")[1]
  .wb_assert(type_a %in% c("categorical", "continuous") && type_b %in% c("categorical", "continuous"),
             "cell_vector_association supports categorical and continuous vectors only.")
  ids <- intersect(as.character(a$cell_id), as.character(b$cell_id))
  if (!is.null(cells)) ids <- intersect(ids, as.character(cells))
  .wb_assert(length(ids) > 0L, "cell_vector_association has no overlapping cells.")
  av <- a$value[match(ids, a$cell_id)]; bv <- b$value[match(ids, b$cell_id)]

  if (identical(type_a, "categorical") && identical(type_b, "categorical")) {
    .wb_assert(method %in% c("auto", "chisq", "fisher"),
               "categorical x categorical association supports method auto, chisq, or fisher.")
    df <- data.frame(cell_id = ids, a = as.character(av), b = as.character(bv), stringsAsFactors = FALSE)
    df <- df[!is.na(df$a) & nzchar(df$a) & !is.na(df$b) & nzchar(df$b), , drop = FALSE]
    .wb_assert(nrow(df) >= 2L && length(unique(df$a)) >= 2L && length(unique(df$b)) >= 2L,
               "categorical x categorical association requires at least two non-missing levels in each vector.")
    tab <- table(df$a, df$b)
    chi <- suppressWarnings(stats::chisq.test(tab, correct = FALSE))
    expected <- chi$expected
    use_fisher <- identical(method, "fisher") || (identical(method, "auto") && any(expected < 5))
    test <- if (use_fisher) stats::fisher.test(tab) else chi
    n <- sum(tab); phi2 <- as.numeric(chi$statistic) / n
    denom <- min(nrow(tab) - 1L, ncol(tab) - 1L)
    cramers_v <- if (denom > 0L) sqrt(phi2 / denom) else NA_real_
    detail <- as.data.frame(as.table(tab), stringsAsFactors = FALSE)
    names(detail) <- c("a_level", "b_level", "observed")
    exp_df <- as.data.frame(as.table(expected), stringsAsFactors = FALSE)
    detail$expected <- as.numeric(exp_df$Freq)
    detail$pearson_residual <- (detail$observed - detail$expected) / sqrt(detail$expected)
    summary <- data.frame(
      association_type = "categorical_x_categorical", method = if (use_fisher) "fisher_exact" else "chi_square",
      n_cells = n, n_a_levels = nrow(tab), n_b_levels = ncol(tab), statistic = as.numeric(chi$statistic),
      p_value = as.numeric(test$p.value), effect_size = cramers_v, effect_size_name = "cramers_v",
      min_expected = min(expected), n_expected_lt_5 = sum(expected < 5), expected_count_ok = all(expected >= 5),
      stringsAsFactors = FALSE
    )
    return(list(outputs = list(summary = wb_prim_obs_table(summary, "cell_vector_association_summary", "vector_pair"),
                               detail = wb_prim_obs_table(detail, "cell_vector_association_contingency", "contingency_cell")),
                params = list(association_type = "categorical_x_categorical", method = summary$method[1], min_n_per_group = as.integer(min_n_per_group), n_cells = n)))
  }

  if (xor(identical(type_a, "continuous"), identical(type_b, "continuous"))) {
    .wb_assert(method %in% c("auto", "kruskal_anova"),
               "continuous x categorical association supports method auto or kruskal_anova.")
    cont <- if (identical(type_a, "continuous")) a else b
    grp <- if (identical(type_a, "categorical")) a else b
    x <- suppressWarnings(as.numeric(cont$value)); names(x) <- as.character(cont$cell_id)
    g <- as.character(grp$value); names(g) <- as.character(grp$cell_id)
    raw <- wb_op_cell_vector_assoc(x[ids], g[ids], min_n_per_group = min_n_per_group)
    summary <- raw$outputs$assoc_summary$table
    summary$association_type <- "continuous_x_categorical"; summary$method <- "kruskal_anova"; summary$effect_size_name <- "eta2"
    raw$outputs$summary <- wb_prim_obs_table(summary, "cell_vector_association_summary", "vector_pair")
    raw$outputs$assoc_summary <- NULL; names(raw$outputs)[names(raw$outputs) == "group_stats"] <- "detail"
    raw$params$association_type <- "continuous_x_categorical"; raw$params$method <- "kruskal_anova"
    return(raw)
  }

  xa <- suppressWarnings(as.numeric(av)); xb <- suppressWarnings(as.numeric(bv))
  .wb_assert(method %in% c("auto", "correlation"),
             "continuous x continuous association supports method auto or correlation.")
  keep <- is.finite(xa) & is.finite(xb)
  .wb_assert(sum(keep) >= 3L, "continuous x continuous association requires at least 3 shared finite values.")
  xa <- xa[keep]; xb <- xb[keep]; ids <- ids[keep]
  .wb_assert(stats::sd(xa) > 0 && stats::sd(xb) > 0, "continuous x continuous association requires non-constant vectors.")
  pearson <- stats::cor.test(xa, xb, method = "pearson")
  spearman <- suppressWarnings(stats::cor.test(xa, xb, method = "spearman", exact = FALSE))
  summary <- data.frame(association_type = "continuous_x_continuous", method = "correlation", n_cells = length(ids),
                        pearson = as.numeric(pearson$estimate), pearson_p = pearson$p.value,
                        spearman = as.numeric(spearman$estimate), spearman_p = spearman$p.value,
                        effect_size = as.numeric(pearson$estimate), effect_size_name = "pearson_r", stringsAsFactors = FALSE)
  detail <- data.frame(cell_id = ids, a = xa, b = xb, stringsAsFactors = FALSE)
  list(outputs = list(summary = wb_prim_obs_table(summary, "cell_vector_association_summary", "vector_pair"),
                      detail = wb_prim_obs_table(detail, "cell_vector_association_cells", "cell")),
       params = list(association_type = "continuous_x_continuous", method = "correlation", n_cells = length(ids)))
}
