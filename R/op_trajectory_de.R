#' @keywords internal
.wb_trajectory_de_load_model_obj <- function(model) {
  .wb_assert_kind(model, "model_ref")
  obj <- model$model_obj %||% NULL
  if (!is.null(obj)) return(obj)

  path <- as.character(model$model_path %||% "")[1]
  .wb_assert(nzchar(path) && file.exists(path),
             "trajectory_de requires model_ref with in-memory model_obj or readable model_path.")
  readRDS(path)
}

#' @keywords internal
.wb_trajectory_de_pt_from_slingshot <- function(model) {
  .wb_require_pkg("slingshot", "trajectory_de for slingshot models")
  sds <- .wb_trajectory_de_load_model_obj(model)
  pt <- slingshot::slingPseudotime(sds)
  .wb_assert(is.matrix(pt) || is.data.frame(pt), "trajectory_de: invalid slingshot pseudotime payload.")

  n_lin <- ncol(pt)
  .wb_assert(n_lin >= 1L, "trajectory_de: slingshot model has no lineages.")
  cells <- rownames(pt) %||% character(0)
  .wb_assert(length(cells) == nrow(pt), "trajectory_de: slingshot pseudotime rownames missing.")

  # Keep lineage key semantics aligned with wb_op_slingshot_fit output.
  keys <- paste0("L", seq_len(n_lin))
  out <- lapply(seq_len(n_lin), function(j) {
    data.frame(
      lineage_id = as.character(keys[j]),
      cell_id = as.character(cells),
      pseudotime = as.numeric(pt[, j]),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, out)
}

#' @keywords internal
.wb_trajectory_de_pt_from_monocle3 <- function(model) {
  .wb_monocle3_require_pkgs()
  cds <- .wb_trajectory_de_load_model_obj(model)

  pt <- monocle3::pseudotime(cds)
  pt <- suppressWarnings(as.numeric(pt))
  names(pt) <- as.character(names(monocle3::pseudotime(cds)) %||% names(pt))
  .wb_assert(length(pt) > 0, "trajectory_de: monocle3 pseudotime is empty.")
  .wb_assert(!is.null(names(pt)) && all(nzchar(names(pt))), "trajectory_de: monocle3 pseudotime names missing.")

  lin <- .wb_monocle3_lineage_paths(cds)
  rel <- .wb_monocle3_branch_membership_prim(cds, lin)
  rel_tbl <- wb_primitive_to_table(rel, include_context = FALSE)
  .wb_assert(is.data.frame(rel_tbl) && nrow(rel_tbl) > 0,
             "trajectory_de: monocle3 branch membership is empty.")

  keep <- as.character(rel_tbl$cell_id) %in% names(pt)
  rel_tbl <- rel_tbl[keep, c("key", "cell_id"), drop = FALSE]
  .wb_assert(nrow(rel_tbl) > 0, "trajectory_de: no overlap between monocle3 branch members and pseudotime.")

  data.frame(
    lineage_id = as.character(rel_tbl$key),
    cell_id = as.character(rel_tbl$cell_id),
    pseudotime = as.numeric(pt[as.character(rel_tbl$cell_id)]),
    stringsAsFactors = FALSE
  )
}

#' @keywords internal
.wb_trajectory_de_resolve_pt <- function(model) {
  engine <- as.character(model$engine %||% "")[1]
  .wb_assert(nzchar(engine), "trajectory_de: model_ref is missing engine.")

  if (identical(engine, "slingshot")) return(.wb_trajectory_de_pt_from_slingshot(model))
  if (identical(engine, "monocle3")) return(.wb_trajectory_de_pt_from_monocle3(model))

  stop(
    "trajectory_de currently supports model_ref engines 'slingshot' and 'monocle3'. ",
    "Received engine='", engine, "'.",
    call. = FALSE
  )
}

#' @keywords internal
.wb_trajectory_de_one_lineage <- function(bundle,
                                          matrix_id,
                                          lineage_id,
                                          pt_named,
                                          features = NULL,
                                          min_pct_nonzero = 0,
                                          min_sd = 0,
                                          chunk_size = 128L) {
  .wb_assert(is.atomic(pt_named) && !is.null(names(pt_named)),
             "trajectory_de internal: pt_named must be a named vector.")

  pt <- suppressWarnings(as.numeric(pt_named))
  names(pt) <- as.character(names(pt_named))
  keep <- is.finite(pt)
  pt <- pt[keep]
  cells <- as.character(names(pt))
  .wb_assert(length(cells) >= 10L, paste0("trajectory_de: lineage '", lineage_id, "' has <10 finite pseudotime cells."))
  .wb_assert(stats::sd(pt) > 0, paste0("trajectory_de: lineage '", lineage_id, "' has zero pseudotime variance."))

  feats <- if (is.null(features)) wb_feature_ids(bundle, matrix_id = matrix_id) else as.character(features)
  feats <- feats[nzchar(feats)]
  .wb_assert(length(feats) > 0, "trajectory_de: no features selected.")

  out <- vector("list", length(feats))
  oi <- 0L
  n_filtered_min_cells <- 0L
  n_filtered_min_pct_nonzero <- 0L
  n_filtered_min_sd <- 0L

  for (i in seq(1L, length(feats), by = as.integer(chunk_size))) {
    j <- min(i + as.integer(chunk_size) - 1L, length(feats))
    f <- feats[i:j]
    x <- wb_slice(bundle, matrix_id = matrix_id, features = f, cells = cells)
    m <- as.matrix(x)
    for (k in seq_len(nrow(m))) {
      y0 <- as.numeric(m[k, ])
      ok <- is.finite(y0) & is.finite(pt)
      n_used <- sum(ok)
      n_dropped_na <- length(ok) - n_used
      if (n_used < 10L) {
        n_filtered_min_cells <- n_filtered_min_cells + 1L
        next
      }

      y <- y0[ok]
      pt_ok <- pt[ok]

      nz <- mean(y > 0)
      if (is.finite(min_pct_nonzero) && min_pct_nonzero > 0 && nz < as.numeric(min_pct_nonzero)) {
        n_filtered_min_pct_nonzero <- n_filtered_min_pct_nonzero + 1L
        next
      }

      sd_y <- stats::sd(y)
      if (!is.finite(sd_y) || sd_y < as.numeric(min_sd)) {
        n_filtered_min_sd <- n_filtered_min_sd + 1L
        next
      }

      rho <- suppressWarnings(stats::cor(y, pt_ok, method = "spearman"))
      if (!is.finite(rho)) next

      if (abs(rho) >= 1) {
        pval <- 0
      } else {
        tval <- rho * sqrt((n_used - 2) / pmax(1 - rho^2, .Machine$double.eps))
        pval <- 2 * stats::pt(abs(tval), df = n_used - 2, lower.tail = FALSE)
      }
      slope <- tryCatch(as.numeric(stats::coef(stats::lm(y ~ pt_ok))[2]), error = function(e) NA_real_)

      oi <- oi + 1L
      out[[oi]] <- data.frame(
        lineage_id = as.character(lineage_id),
        feature_id = rownames(m)[k],
        rho = rho,
        abs_rho = abs(rho),
        direction = ifelse(rho > 0, "up", ifelse(rho < 0, "down", "flat")),
        slope = slope,
        p_val = pval,
        pct_nonzero = nz,
        sd_expr = sd_y,
        mean_expr = mean(y),
        n_used = as.integer(n_used),
        n_dropped_na = as.integer(n_dropped_na),
        stringsAsFactors = FALSE
      )
    }
  }

  tbl <- if (oi == 0L) {
    data.frame(
      lineage_id = character(0),
      feature_id = character(0),
      rho = numeric(0),
      abs_rho = numeric(0),
      direction = character(0),
      slope = numeric(0),
      p_val = numeric(0),
      p_val_adj = numeric(0),
      pct_nonzero = numeric(0),
      sd_expr = numeric(0),
      mean_expr = numeric(0),
      n_used = integer(0),
      n_dropped_na = integer(0),
      stringsAsFactors = FALSE
    )
  } else {
    do.call(rbind, out[seq_len(oi)])
  }

  list(
    table = tbl,
    summary = data.frame(
      lineage_id = as.character(lineage_id),
      n_cells_input = as.integer(length(pt_named)),
      n_cells_used = as.integer(length(cells)),
      n_features_input = as.integer(length(feats)),
      n_features_tested = as.integer(nrow(tbl)),
      n_filtered_min_cells = as.integer(n_filtered_min_cells),
      n_filtered_min_pct_nonzero = as.integer(n_filtered_min_pct_nonzero),
      n_filtered_min_sd = as.integer(n_filtered_min_sd),
      stringsAsFactors = FALSE
    )
  )
}

#' @keywords internal
.wb_trajectory_de_resolve_features <- function(bundle, matrix_id, feature_set = NULL, features = NULL) {
  fs_feats <- NULL
  if (!is.null(feature_set)) {
    fs_name <- as.character(feature_set)[1]
    .wb_assert(nzchar(fs_name), "trajectory_de: feature_set must be a non-empty string when provided.")
    fs_feats <- unique(as.character(wb_feature_set_get(bundle, feature_set = fs_name, matrix_id = matrix_id)))
    fs_feats <- fs_feats[nzchar(fs_feats)]
    .wb_assert(length(fs_feats) > 0,
               paste0("trajectory_de: feature_set '", fs_name, "' has no members in matrix '", matrix_id, "'."))
  }

  vec_feats <- NULL
  if (!is.null(features)) {
    vec_feats <- unique(as.character(features))
    vec_feats <- vec_feats[nzchar(vec_feats)]
    .wb_assert(length(vec_feats) > 0, "trajectory_de: features is empty after cleaning.")
  }

  if (is.null(fs_feats) && is.null(vec_feats)) return(NULL)
  if (!is.null(fs_feats) && is.null(vec_feats)) return(fs_feats)
  if (is.null(fs_feats) && !is.null(vec_feats)) return(vec_feats)

  out <- intersect(fs_feats, vec_feats)
  .wb_assert(length(out) > 0,
             "trajectory_de: feature_set and features intersection is empty.")
  out
}

#' Run Per-Lineage Trajectory DE
#'
#' v1 supports `model_ref(engine = "slingshot" | "monocle3")` and computes
#' feature-level trends against lineage pseudotime.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param matrix_id Matrix identifier.
#' @param model A `model_ref` primitive from trajectory fitting.
#' @param cells Optional effective cell IDs to restrict analysis.
#' @param lineage Optional lineage key subset.
#' @param feature_set Optional feature set name in bundle feature-set registry.
#' @param features Optional feature ID subset.
#' @param test Statistical test name. v1 supports `"spearman"` only.
#' @param min_pct_nonzero Optional minimum nonzero fraction filter.
#' @param min_sd Optional minimum feature SD filter.
#' @param p_adjust_method Method for p.adjust.
#' @param chunk_size Feature chunk size for slicing.
#'
#' @return A standard op result list with `outputs` containing `de_table` and
#'   `fit_summary`, plus normalized `params`.
#'
#' @export
wb_op_trajectory_de <- function(bundle,
                                matrix_id,
                                model,
                                cells = NULL,
                                lineage = NULL,
                                feature_set = NULL,
                                features = NULL,
                                test = "spearman",
                                min_pct_nonzero = 0,
                                min_sd = 0,
                                p_adjust_method = "BH",
                                chunk_size = 128L) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert(is.character(matrix_id) && length(matrix_id) == 1 && nzchar(matrix_id), "matrix_id invalid")
  .wb_assert_kind(model, "model_ref")
  .wb_assert(identical(as.character(test %||% "spearman")[1], "spearman"),
             "trajectory_de currently supports test='spearman' only.")

  features_resolved <- .wb_trajectory_de_resolve_features(
    bundle = bundle,
    matrix_id = matrix_id,
    feature_set = feature_set,
    features = features
  )

  pt_tbl <- .wb_trajectory_de_resolve_pt(model)
  .wb_assert(is.data.frame(pt_tbl) && nrow(pt_tbl) > 0, "trajectory_de: resolved pseudotime table is empty.")

  pt_tbl <- pt_tbl[is.finite(pt_tbl$pseudotime), , drop = FALSE]
  .wb_assert(nrow(pt_tbl) > 0, "trajectory_de: no finite pseudotime values after filtering.")

  if (!is.null(cells)) {
    keep_cells <- unique(as.character(cells))
    pt_tbl <- pt_tbl[as.character(pt_tbl$cell_id) %in% keep_cells, , drop = FALSE]
  }

  lin_all <- sort(unique(as.character(pt_tbl$lineage_id)))
  .wb_assert(length(lin_all) > 0, "trajectory_de: no lineage keys found after cell filtering.")

  if (!is.null(lineage)) {
    requested <- unique(as.character(lineage))
    requested <- requested[nzchar(requested)]
    .wb_assert(length(requested) > 0, "trajectory_de: lineage parameter is empty after cleaning.")
    missing <- setdiff(requested, lin_all)
    .wb_assert(length(missing) == 0,
               paste0("trajectory_de: requested lineage key(s) not found: ", paste(missing, collapse = ", ")))
    lin_use <- requested
  } else {
    lin_use <- lin_all
  }

  de_parts <- vector("list", length(lin_use))
  sum_parts <- vector("list", length(lin_use))
  out_i <- 0L
  sum_i <- 0L

  for (lin in lin_use) {
    sub <- pt_tbl[as.character(pt_tbl$lineage_id) == lin, c("cell_id", "pseudotime"), drop = FALSE]
    if (!nrow(sub)) next
    pt_vec <- as.numeric(sub$pseudotime)
    names(pt_vec) <- as.character(sub$cell_id)
    pt_vec <- pt_vec[!duplicated(names(pt_vec))]
    if (length(pt_vec) < 10L) next
    if (!is.finite(stats::sd(pt_vec)) || stats::sd(pt_vec) <= 0) next

    one <- .wb_trajectory_de_one_lineage(
      bundle = bundle,
      matrix_id = matrix_id,
      lineage_id = lin,
      pt_named = pt_vec,
      features = features_resolved,
      min_pct_nonzero = min_pct_nonzero,
      min_sd = min_sd,
      chunk_size = chunk_size
    )

    out_i <- out_i + 1L
    de_parts[[out_i]] <- one$table
    sum_i <- sum_i + 1L
    sum_parts[[sum_i]] <- one$summary
  }

  .wb_assert(out_i > 0L, "trajectory_de: no lineage produced testable cells/features (need >=10 cells with non-zero pseudotime variance).")
  de_tbl <- do.call(rbind, de_parts[seq_len(out_i)])
  sum_tbl <- do.call(rbind, sum_parts[seq_len(sum_i)])

  de_tbl$p_val_adj <- ave(
    de_tbl$p_val,
    de_tbl$lineage_id,
    FUN = function(x) stats::p.adjust(x, method = as.character(p_adjust_method)[1])
  )
  de_tbl <- de_tbl[order(de_tbl$lineage_id, de_tbl$p_val_adj, -de_tbl$abs_rho), , drop = FALSE]
  rownames(de_tbl) <- NULL
  rownames(sum_tbl) <- NULL

  list(
    outputs = list(
      de_table = wb_prim_feature_table(
        table = de_tbl,
        table_type = "trajectory_de",
        meta = list(
          matrix_id = matrix_id,
          model_engine = as.character(model$engine %||% "")[1],
          n_lineages_input = as.integer(length(lin_all)),
          n_lineages_tested = as.integer(length(unique(as.character(de_tbl$lineage_id)))),
          n_features_tested = as.integer(nrow(de_tbl)),
          feature_set = as.character(feature_set %||% "")[1],
          min_pct_nonzero = as.numeric(min_pct_nonzero),
          min_sd = as.numeric(min_sd),
          p_adjust_method = as.character(p_adjust_method)[1],
          test = "spearman"
        )
      ),
      fit_summary = wb_prim_obs_table(
        table = sum_tbl,
        table_type = "trajectory_de_summary",
        entity_kind = "lineage",
        meta = list(
          matrix_id = matrix_id,
          model_engine = as.character(model$engine %||% "")[1],
          test = "spearman"
        )
      )
    ),
    params = list(
      matrix_id = matrix_id,
      model_engine = as.character(model$engine %||% "")[1],
      lineage = as.character(lin_use),
      n_lineages_input = as.integer(length(lin_all)),
      n_lineages_tested = as.integer(length(unique(as.character(de_tbl$lineage_id)))),
      n_features_tested = as.integer(nrow(de_tbl)),
      feature_set = as.character(feature_set %||% "")[1],
      min_pct_nonzero = as.numeric(min_pct_nonzero),
      min_sd = as.numeric(min_sd),
      p_adjust_method = as.character(p_adjust_method)[1],
      test = "spearman"
    )
  )
}
