#' @keywords internal
.wb_branch_compare_resolve_features <- function(bundle, matrix_id, feature_set = NULL, features = NULL) {
  fs_feats <- NULL
  if (!is.null(feature_set)) {
    fs_name <- as.character(feature_set)[1]
    .wb_assert(nzchar(fs_name), "trajectory_branch_compare: feature_set must be a non-empty string when provided.")
    fs_feats <- unique(as.character(wb_feature_set_get(bundle, feature_set = fs_name, matrix_id = matrix_id)))
    fs_feats <- fs_feats[nzchar(fs_feats)]
    .wb_assert(length(fs_feats) > 0,
               paste0("trajectory_branch_compare: feature_set '", fs_name, "' has no members in matrix '", matrix_id, "'."))
  }

  vec_feats <- NULL
  if (!is.null(features)) {
    vec_feats <- unique(as.character(features))
    vec_feats <- vec_feats[nzchar(vec_feats)]
    .wb_assert(length(vec_feats) > 0, "trajectory_branch_compare: features is empty after cleaning.")
  }

  if (is.null(fs_feats) && is.null(vec_feats)) return(NULL)
  if (!is.null(fs_feats) && is.null(vec_feats)) return(fs_feats)
  if (is.null(fs_feats) && !is.null(vec_feats)) return(vec_feats)

  out <- intersect(fs_feats, vec_feats)
  .wb_assert(length(out) > 0, "trajectory_branch_compare: feature_set and features intersection is empty.")
  out
}

#' @keywords internal
.wb_branch_compare_resolve_cells <- function(branch_membership, branch_a, branch_b, effective_cells = NULL) {
  .wb_assert_kind(branch_membership, "relation_family")
  tbl <- wb_primitive_to_table(branch_membership, include_context = FALSE)
  .wb_assert(is.data.frame(tbl) && nrow(tbl) > 0, "trajectory_branch_compare: branch_membership is empty.")
  .wb_assert(all(c("key", "cell_id") %in% colnames(tbl)),
             "trajectory_branch_compare: branch_membership table missing key/cell_id.")

  tbl <- tbl[as.character(tbl$key) %in% c(as.character(branch_a), as.character(branch_b)), , drop = FALSE]
  .wb_assert(nrow(tbl) > 0, "trajectory_branch_compare: no branch_membership rows for requested branches.")

  if (!is.null(effective_cells)) {
    tbl <- tbl[as.character(tbl$cell_id) %in% as.character(effective_cells), , drop = FALSE]
  }
  .wb_assert(nrow(tbl) > 0, "trajectory_branch_compare: no branch_membership rows remain after effective_cells restriction.")

  tbl$key <- as.character(tbl$key)
  tbl$cell_id <- as.character(tbl$cell_id)
  tbl$weight_use <- if ("weight" %in% colnames(tbl)) suppressWarnings(as.numeric(tbl$weight)) else 1
  tbl$weight_use[!is.finite(tbl$weight_use)] <- 1

  agg <- stats::aggregate(
    weight_use ~ cell_id + key,
    data = tbl,
    FUN = max
  )
  names(agg)[names(agg) == "weight_use"] <- "weight"

  a_tbl <- agg[agg$key == as.character(branch_a), c("cell_id", "weight"), drop = FALSE]
  b_tbl <- agg[agg$key == as.character(branch_b), c("cell_id", "weight"), drop = FALSE]
  names(a_tbl)[2] <- "weight_a"
  names(b_tbl)[2] <- "weight_b"

  merged <- merge(a_tbl, b_tbl, by = "cell_id", all = TRUE)
  merged$in_a <- !is.na(merged$weight_a)
  merged$in_b <- !is.na(merged$weight_b)
  merged$assignment <- NA_character_
  merged$assignment[merged$in_a & !merged$in_b] <- "a"
  merged$assignment[!merged$in_a & merged$in_b] <- "b"
  both <- merged$in_a & merged$in_b
  merged$assignment[both & merged$weight_a > merged$weight_b] <- "a"
  merged$assignment[both & merged$weight_b > merged$weight_a] <- "b"

  cells_a <- as.character(merged$cell_id[merged$assignment == "a"])
  cells_b <- as.character(merged$cell_id[merged$assignment == "b"])
  overlap_dropped <- as.character(merged$cell_id[both & is.na(merged$assignment)])

  list(
    cells_a = unique(cells_a[nzchar(cells_a)]),
    cells_b = unique(cells_b[nzchar(cells_b)]),
    n_overlap_dropped = as.integer(length(overlap_dropped))
  )
}

#' @keywords internal
.wb_branch_compare_pt_summary <- function(pseudotime, branch_a, branch_b, cells_a, cells_b) {
  .wb_assert(.wb_is_primitive(pseudotime), "trajectory_branch_compare: pseudotime must be a primitive.")
  kind <- as.character(pseudotime$kind %||% "")[1]

  if (identical(kind, "cell_vector")) {
    vals <- suppressWarnings(as.numeric(pseudotime$value))
    names(vals) <- as.character(pseudotime$cell_id)
    va <- vals[as.character(cells_a)]
    vb <- vals[as.character(cells_b)]
    return(list(
      mean_pt_a = mean(va[is.finite(va)]),
      mean_pt_b = mean(vb[is.finite(vb)]),
      median_pt_a = stats::median(va[is.finite(va)]),
      median_pt_b = stats::median(vb[is.finite(vb)])
    ))
  }

  if (identical(kind, "cell_vector_family")) {
    tbl <- wb_primitive_to_table(pseudotime, include_context = FALSE)
    .wb_assert(all(c("key", "cell_id", "value") %in% colnames(tbl)),
               "trajectory_branch_compare: pseudotime family table missing key/cell_id/value.")
    tbl$key <- as.character(tbl$key)
    tbl$cell_id <- as.character(tbl$cell_id)
    tbl$value <- suppressWarnings(as.numeric(tbl$value))
    va <- tbl$value[tbl$key == as.character(branch_a) & tbl$cell_id %in% as.character(cells_a)]
    vb <- tbl$value[tbl$key == as.character(branch_b) & tbl$cell_id %in% as.character(cells_b)]
    return(list(
      mean_pt_a = mean(va[is.finite(va)]),
      mean_pt_b = mean(vb[is.finite(vb)]),
      median_pt_a = stats::median(va[is.finite(va)]),
      median_pt_b = stats::median(vb[is.finite(vb)])
    ))
  }

  stop("trajectory_branch_compare: pseudotime must be cell_vector or cell_vector_family.", call. = FALSE)
}

#' Compare Two Trajectory Branches
#'
#' Branch-aware first-pass comparison between two lineage/branch memberships.
#' v1 performs a Wilcoxon feature comparison after resolving branch-specific cell
#' assignments and emits a feature-centric comparison table plus a one-row
#' summary table.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param matrix_id Matrix identifier.
#' @param pseudotime A `cell_vector` or `cell_vector_family` primitive.
#' @param branch_membership A `relation_family` primitive with branch/lineage keys.
#' @param branch_a Branch/lineage key A.
#' @param branch_b Branch/lineage key B.
#' @param cells Optional effective cell restriction.
#' @param feature_set Optional feature set name.
#' @param features Optional explicit feature IDs.
#' @param min_pct Minimum detection fraction in either branch.
#' @param p_adjust_method P-value adjustment method.
#'
#' @return Standard op result with `outputs$branch_de_table` and
#'   `outputs$branch_summary`.
#'
#' @export
wb_op_trajectory_branch_compare <- function(bundle,
                                            matrix_id,
                                            pseudotime,
                                            branch_membership,
                                            branch_a,
                                            branch_b,
                                            cells = NULL,
                                            feature_set = NULL,
                                            features = NULL,
                                            min_pct = 0,
                                            p_adjust_method = "BH") {
  .wb_assert(is.character(matrix_id) && length(matrix_id) == 1L && nzchar(matrix_id),
             "trajectory_branch_compare: matrix_id must be a non-empty string.")
  .wb_assert(.wb_is_primitive(pseudotime), "trajectory_branch_compare: pseudotime must be a primitive.")
  .wb_assert_kind(branch_membership, "relation_family")
  branch_a <- as.character(branch_a)[1]
  branch_b <- as.character(branch_b)[1]
  .wb_assert(nzchar(branch_a) && nzchar(branch_b), "trajectory_branch_compare: branch_a and branch_b are required.")
  .wb_assert(!identical(branch_a, branch_b), "trajectory_branch_compare: branch_a and branch_b must differ.")

  feature_ids <- .wb_branch_compare_resolve_features(
    bundle = bundle,
    matrix_id = matrix_id,
    feature_set = feature_set,
    features = features
  )
  if (is.null(feature_ids)) feature_ids <- wb_feature_ids(bundle, matrix_id = matrix_id)
  feature_ids <- unique(as.character(feature_ids))
  feature_ids <- feature_ids[nzchar(feature_ids)]
  .wb_assert(length(feature_ids) > 0, "trajectory_branch_compare: no features selected.")

  cell_res <- .wb_branch_compare_resolve_cells(
    branch_membership = branch_membership,
    branch_a = branch_a,
    branch_b = branch_b,
    effective_cells = cells
  )
  cells_a <- cell_res$cells_a
  cells_b <- cell_res$cells_b
  .wb_assert(length(cells_a) >= 2L, "trajectory_branch_compare: branch_a has fewer than 2 assigned cells.")
  .wb_assert(length(cells_b) >= 2L, "trajectory_branch_compare: branch_b has fewer than 2 assigned cells.")

  de <- .wb_de_wilcox_core(
    bundle = bundle,
    matrix_id = matrix_id,
    features = feature_ids,
    cells_a = cells_a,
    cells_b = cells_b
  )
  if (!is.null(min_pct) && is.finite(min_pct) && min_pct > 0) {
    de <- de[pmax(de$pct_a, de$pct_b) >= as.numeric(min_pct), , drop = FALSE]
  }
  if (nrow(de) > 0) {
    de$p_val_adj <- stats::p.adjust(de$p_val, method = as.character(p_adjust_method)[1])
  } else {
    de$p_val_adj <- numeric(0)
  }

  de$branch_a <- as.character(branch_a)
  de$branch_b <- as.character(branch_b)
  de$n_cells_a <- as.integer(length(cells_a))
  de$n_cells_b <- as.integer(length(cells_b))
  de <- de[order(de$p_val_adj, -de$avg_log1p_fc), , drop = FALSE]
  rownames(de) <- NULL

  pt_summary <- .wb_branch_compare_pt_summary(
    pseudotime = pseudotime,
    branch_a = branch_a,
    branch_b = branch_b,
    cells_a = cells_a,
    cells_b = cells_b
  )

  summary_tbl <- data.frame(
    branch_a = as.character(branch_a),
    branch_b = as.character(branch_b),
    n_cells_a = as.integer(length(cells_a)),
    n_cells_b = as.integer(length(cells_b)),
    n_overlap_dropped = as.integer(cell_res$n_overlap_dropped),
    n_features_input = as.integer(length(feature_ids)),
    n_features_tested = as.integer(nrow(de)),
    mean_pt_a = as.numeric(pt_summary$mean_pt_a %||% NA_real_),
    mean_pt_b = as.numeric(pt_summary$mean_pt_b %||% NA_real_),
    median_pt_a = as.numeric(pt_summary$median_pt_a %||% NA_real_),
    median_pt_b = as.numeric(pt_summary$median_pt_b %||% NA_real_),
    stringsAsFactors = FALSE
  )

  list(
    outputs = list(
      branch_de_table = wb_prim_feature_table(
        table = de,
        table_type = "trajectory_branch_compare",
        meta = list(
          matrix_id = matrix_id,
          branch_a = branch_a,
          branch_b = branch_b
        )
      ),
      branch_summary = wb_prim_obs_table(
        table = summary_tbl,
        table_type = "trajectory_branch_compare_summary",
        entity_kind = "branch_pair",
        meta = list(
          matrix_id = matrix_id,
          branch_a = branch_a,
          branch_b = branch_b
        )
      )
    ),
    params = list(
      matrix_id = matrix_id,
      branch_a = branch_a,
      branch_b = branch_b,
      n_cells_a = length(cells_a),
      n_cells_b = length(cells_b),
      n_overlap_dropped = as.integer(cell_res$n_overlap_dropped),
      n_features = nrow(de),
      min_pct = as.numeric(min_pct),
      p_adjust_method = as.character(p_adjust_method)[1]
    )
  )
}
