.wb_slingshot_require_pkgs <- function() {
  .wb_require_pkg("SingleCellExperiment", "Slingshot container")
  .wb_require_pkg("S4Vectors", "ReducedDims container")
  .wb_require_pkg("slingshot", "Trajectory inference")
}

.wb_slingshot_prepare_fit <- function(bundle,
                                      fit_space_id,
                                      clusters,
                                      cells,
                                      exclude_cells = NULL,
                                      include_clusters = NULL,
                                      exclude_clusters = NULL) {
  .wb_assert(is.character(fit_space_id) && length(fit_space_id) == 1 && nzchar(fit_space_id),
             "fit_space_id must be a single non-empty string.")

  .wb_assert(is.atomic(clusters) && !is.null(names(clusters)),
             "clusters must be a named vector (names=cell_id, values=cluster).")
  clusters <- setNames(as.character(clusters), names(clusters))
  .wb_assert(all(nzchar(names(clusters))), "clusters has empty cell_id names.")
  .wb_assert(length(clusters) > 0, "clusters is empty.")

  .wb_assert(!missing(cells) && length(cells) > 0,
             "slingshot fit must be called with 'cells' (effective_cells).")

  cells_use <- as.character(cells)
  if (!is.null(exclude_cells)) {
    cells_use <- setdiff(cells_use, as.character(exclude_cells))
  }
  .wb_assert(length(cells_use) >= 10, "Too few cells after exclude_cells (need >= 10).")

  clust_sub <- clusters[cells_use]
  missing_lab <- cells_use[is.na(clust_sub)]
  .wb_assert(length(missing_lab) == 0,
             paste0("Clusters missing for ", length(missing_lab), " selected cells."))

  labels2 <- data.frame(
    cell_id = cells_use,
    cluster = as.character(clust_sub),
    stringsAsFactors = FALSE
  )

  sp <- wb_space(bundle, space_id = fit_space_id, cells = cells_use)
  X <- .wb_as_coord_matrix(sp)

  if (!identical(rownames(X), cells_use)) {
    ii <- match(cells_use, rownames(X))
    .wb_assert(!anyNA(ii), "Some requested cells are missing from the selected fit space.")
    X <- X[ii, , drop = FALSE]
    rownames(X) <- cells_use
  }

  fl <- .wb_filter_labels(
    labels_df = labels2,
    cells = cells_use,
    include_clusters = include_clusters,
    exclude_clusters = exclude_clusters
  )
  cells2 <- as.character(fl$cells)
  lab2   <- fl$labels
  .wb_assert(length(cells2) >= 10, "Too few cells after cluster filtering (need >= 10).")

  ii2 <- match(cells2, rownames(X))
  .wb_assert(!anyNA(ii2), "Internal error: filtered cells missing from fit space.")
  X <- X[ii2, , drop = FALSE]
  rownames(X) <- cells2

  cl <- factor(lab2$cluster[match(cells2, lab2$cell_id)])
  .wb_assert(!anyNA(cl), "Internal: NA cluster labels after filtering.")

  list(
    fit_space_id = fit_space_id,
    cells_in = as.character(cells),
    cells_after_exclude_cells = cells_use,
    cells_fit = cells2,
    X_fit = X,
    cluster_labels = cl,
    labels_df = lab2,
    present_clusters = sort(unique(as.character(lab2$cluster)))
  )
}

.wb_slingshot_run_fit <- function(X_fit,
                                  cells_fit,
                                  cluster_labels,
                                  start.clus = NULL,
                                  end.clus = NULL,
                                  stretch = 2,
                                  reweight = TRUE,
                                  shrink = 1,
                                  maxit = 10,
                                  ...) {
  present_clusters <- sort(unique(as.character(cluster_labels)))
  if (!is.null(start.clus)) {
    .wb_assert(length(start.clus) == 1, "start.clus must be length 1 or NULL.")
    .wb_assert(as.character(start.clus) %in% present_clusters,
               paste0("start.clus not present after filtering: ", start.clus))
  }
  if (!is.null(end.clus)) {
    endv <- as.character(end.clus)
    .wb_assert(length(endv) >= 1, "end.clus must be length >= 1 or NULL.")
    missing_end <- setdiff(endv, present_clusters)
    .wb_assert(length(missing_end) == 0,
               paste0("end.clus not present after filtering: ", paste(missing_end, collapse = ",")))
  }

  sce <- SingleCellExperiment::SingleCellExperiment(
    assays = list(dummy = matrix(0, nrow = 1, ncol = length(cells_fit)))
  )
  colnames(sce) <- cells_fit
  SingleCellExperiment::reducedDims(sce) <- S4Vectors::SimpleList(space = X_fit)

  slingshot::slingshot(
    sce,
    clusterLabels = cluster_labels,
    reducedDim = "space",
    start.clus = start.clus,
    end.clus = end.clus,
    stretch = stretch,
    reweight = reweight,
    shrink = shrink,
    maxit = maxit,
    ...
  )
}

.wb_slingshot_pseudotime_prim <- function(sds) {
  pt <- slingshot::slingPseudotime(sds)
  n_lin <- ncol(pt)
  lineage_ids <- paste0("L", seq_len(n_lin))
  cells_fit <- rownames(pt)

  pseudotime <- do.call(rbind, lapply(seq_len(n_lin), function(j) {
    data.frame(
      cell_id = cells_fit,
      lineage_id = lineage_ids[j],
      pseudotime = as.numeric(pt[, j]),
      stringsAsFactors = FALSE
    )
  }))
  pseudotime <- pseudotime[!is.na(pseudotime$pseudotime), , drop = FALSE]

  wb_prim_cell_vector_family(
    key = pseudotime$lineage_id,
    cell_id = pseudotime$cell_id,
    value = pseudotime$pseudotime,
    value_type = "continuous",
    meta = list(
      family_kind = "trajectory_pseudotime",
      engine = "slingshot",
      value_semantics = "lineage_specific_pseudotime"
    )
  )
}

.wb_slingshot_lineage_weights_prim <- function(sds) {
  w <- slingshot::slingCurveWeights(sds)
  .wb_assert(!is.null(w) && length(w) > 0, "slingshot lineage weights are empty.")
  w <- as.matrix(w)
  n_lin <- ncol(w)
  .wb_assert(n_lin >= 1L, "slingshot lineage weights have no lineage columns.")
  lineage_ids <- paste0("L", seq_len(n_lin))
  cells_fit <- rownames(w)
  .wb_assert(!is.null(cells_fit) && length(cells_fit) == nrow(w),
             "slingshot lineage weights are missing cell rownames.")

  weights <- do.call(rbind, lapply(seq_len(n_lin), function(j) {
    data.frame(
      cell_id = cells_fit,
      lineage_id = lineage_ids[j],
      weight = as.numeric(w[, j]),
      stringsAsFactors = FALSE
    )
  }))
  weights <- weights[!is.na(weights$weight), , drop = FALSE]
  vals <- suppressWarnings(as.numeric(weights$weight))
  bad <- is.finite(vals) & (vals < -1e-8 | vals > 1 + 1e-8)
  .wb_assert(!any(bad), "slingshot lineage weights must be in [0, 1] when finite.")
  weights$weight <- pmin(1, pmax(0, vals))

  wb_prim_cell_vector_family(
    key = weights$lineage_id,
    cell_id = weights$cell_id,
    value = weights$weight,
    value_type = "continuous",
    meta = list(
      family_kind = "trajectory_membership_weight",
      engine = "slingshot",
      value_semantics = "lineage_membership_weight",
      range = c(0, 1),
      promoted = FALSE
    )
  )
}

.wb_slingshot_curves_prim <- function(sds) {
  curves <- slingshot::slingCurves(sds)
  lineage_ids <- paste0("L", seq_along(curves))
  curves_2d <- do.call(rbind, lapply(seq_along(curves), function(j) {
    s <- curves[[j]]$s
    data.frame(
      lineage_id = lineage_ids[j],
      point = seq_len(nrow(s)),
      x = as.numeric(s[, 1]),
      y = as.numeric(s[, 2]),
      stringsAsFactors = FALSE
    )
  }))

  wb_prim_path_2d_family(
    key = curves_2d$lineage_id,
    point = curves_2d$point,
    x = curves_2d$x,
    y = curves_2d$y
  )
}

.wb_path_2d_family_compact <- function(curves_prim, max_points_per_lineage = NULL) {
  .wb_assert_kind(curves_prim, "path_2d_family")
  if (is.null(max_points_per_lineage)) return(curves_prim)

  nmax <- suppressWarnings(as.integer(max_points_per_lineage)[1])
  if (is.na(nmax) || nmax <= 0) return(curves_prim)

  key <- as.character(curves_prim$key %||% character(0))
  point <- as.integer(curves_prim$point %||% integer(0))
  x <- as.numeric(curves_prim$x %||% numeric(0))
  y <- as.numeric(curves_prim$y %||% numeric(0))
  .wb_assert(length(key) == length(point) && length(point) == length(x) && length(x) == length(y),
             ".wb_path_2d_family_compact(): malformed path_2d_family lengths.")

  if (!length(key)) return(curves_prim)

  out_rows <- lapply(unique(key), function(k) {
    ii <- which(key == k)
    if (!length(ii)) return(NULL)
    # Respect incoming point order first; fall back to row order for ties/NAs.
    ord <- order(ifelse(is.na(point[ii]), seq_along(ii), point[ii]), seq_along(ii))
    ii <- ii[ord]
    n <- length(ii)
    if (n > nmax) {
      keep_idx <- unique(round(seq.int(1, n, length.out = nmax)))
      ii <- ii[keep_idx]
      n <- length(ii)
    }
    data.frame(
      key = rep(k, n),
      point = seq_len(n),
      x = x[ii],
      y = y[ii],
      stringsAsFactors = FALSE
    )
  })

  out <- do.call(rbind, out_rows)
  if (is.null(out) || !nrow(out)) return(curves_prim)
  rownames(out) <- NULL
  wb_prim_path_2d_family(key = out$key, point = out$point, x = out$x, y = out$y)
}

#' Slingshot fit (trajectory inference in fit space)
#'
#' Returns lineage pseudotime and a session-chainable `model_ref(engine="slingshot")`.
#' Model promotion is not yet supported; this phase is for fit/project split semantics.
#'
#' @export
wb_op_slingshot_fit <- function(bundle,
                                fit_space_id,
                                clusters,
                                cells,
                                exclude_cells = NULL,
                                include_clusters = NULL,
                                exclude_clusters = NULL,
                                start.clus = NULL,
                                end.clus = NULL,
                                stretch = 2,
                                reweight = TRUE,
                                shrink = 1,
                                maxit = 10,
                                ...) {

  .wb_slingshot_require_pkgs()

  prep <- .wb_slingshot_prepare_fit(
    bundle = bundle,
    fit_space_id = fit_space_id,
    clusters = clusters,
    cells = cells,
    exclude_cells = exclude_cells,
    include_clusters = include_clusters,
    exclude_clusters = exclude_clusters
  )

  sds <- .wb_slingshot_run_fit(
    X_fit = prep$X_fit,
    cells_fit = prep$cells_fit,
    cluster_labels = prep$cluster_labels,
    start.clus = start.clus,
    end.clus = end.clus,
    stretch = stretch,
    reweight = reweight,
    shrink = shrink,
    maxit = maxit,
    ...
  )

  pt_prim <- .wb_slingshot_pseudotime_prim(sds)
  weight_prim <- .wb_slingshot_lineage_weights_prim(sds)
  model_prim <- wb_prim_model_ref(
    model_space_id = fit_space_id,
    in_space_id = fit_space_id,
    engine = "slingshot"
  )
  # Session-chainable payload and metadata. Provenance JSON summarizes model_ref only.
  model_prim$model_obj <- sds
  model_prim$model_type <- "slingshot"
  model_prim$fit_space_id <- fit_space_id
  model_prim$cells <- prep$cells_fit
  model_prim$n_lineages <- length(unique(pt_prim$key))
  model_prim$lineage_weight_family_kind <- "trajectory_membership_weight"

  list(
    outputs = list(
      pseudotime = pt_prim,
      lineage_weights = weight_prim,
      model = model_prim
    ),
    params = list(
      fit_space_id = fit_space_id,
      cells_in = length(prep$cells_in),
      cells_after_exclude_cells = length(prep$cells_after_exclude_cells),
      cells_after_cluster_filter = length(prep$cells_fit),
      start.clus = start.clus,
      end.clus = end.clus,
      stretch = stretch,
      reweight = reweight,
      shrink = shrink,
      maxit = maxit,
      n_lineages = model_prim$n_lineages
    )
  )
}

#' Project a fitted slingshot model into a 2D display space
#'
#' Consumes `model_ref(engine="slingshot")` produced by `wb_op_slingshot_fit()`
#' and emits drawable 2D curves (`path_2d_family`) using `slingshot::embedCurves()`.
#'
#' @export
wb_op_slingshot_project <- function(bundle,
                                    slingshot_model,
                                    plot_space_id,
                                    stretch = NULL,
                                    shrink = NULL,
                                    approx_points = 200L,
                                    ...) {
  .wb_slingshot_require_pkgs()
  .wb_assert_kind(slingshot_model, "model_ref")
  .wb_assert(identical(slingshot_model$engine %||% "", "slingshot"),
             "slingshot_project requires model_ref(engine='slingshot').")

  sds <- slingshot_model$model_obj %||% NULL
  .wb_assert(!is.null(sds),
             paste(
               "slingshot_project received a slingshot model_ref without in-memory model payload.",
               "Promoted slingshot model artifacts are not yet supported in this phase."
             ))

  cells_fit <- as.character(slingshot_model$cells %||% character(0))
  if (!length(cells_fit)) {
    pt <- slingshot::slingPseudotime(sds)
    cells_fit <- rownames(pt) %||% character(0)
  }
  .wb_assert(length(cells_fit) > 0,
             "slingshot_project could not recover fitted cell IDs from slingshot model.")

  sp <- wb_space(bundle, space_id = plot_space_id, cells = cells_fit)
  X_plot <- .wb_as_coord_matrix(sp)
  ii <- match(cells_fit, rownames(X_plot))
  .wb_assert(!anyNA(ii),
             paste0("plot_space_id is missing ", sum(is.na(ii)), " fitted cells."))
  X_plot <- X_plot[ii, , drop = FALSE]
  rownames(X_plot) <- cells_fit
  .wb_assert(ncol(X_plot) == 2, "slingshot_project requires a 2D plot space.")

  sds_proj <- slingshot::embedCurves(
    sds,
    X_plot,
    stretch = stretch,
    shrink = shrink,
    approx_points = approx_points,
    ...
  )

  cv_prim <- .wb_slingshot_curves_prim(sds_proj)
  cv_prim <- .wb_path_2d_family_compact(cv_prim, max_points_per_lineage = approx_points)
  list(
    outputs = list(curves = cv_prim),
    params = list(
      fit_space_id = as.character(slingshot_model$fit_space_id %||% slingshot_model$model_space_id %||% ""),
      plot_space_id = plot_space_id,
      cells_projected = length(cells_fit),
      n_lineages = length(unique(cv_prim$key)),
      stretch = stretch,
      shrink = shrink,
      approx_points = approx_points
    )
  )
}

#' Slingshot trajectory inference (legacy single-op fit+project in one space)
#'
#' clusters:
#' - named vector: names = cell_id, values = cluster label
#'
#' cells MUST be provided (effective_cells computed by session).
#'
#' @export
wb_op_slingshot <- function(bundle,
                            space_id,
                            clusters,
                            cells,
                            exclude_cells = NULL,
                            include_clusters = NULL,
                            exclude_clusters = NULL,
                            start.clus = NULL,
                            end.clus = NULL,
                            stretch = 2,
                            reweight = TRUE,
                            shrink = 1,
                            maxit = 10,
                            ...) {

  .wb_slingshot_require_pkgs()

  prep <- .wb_slingshot_prepare_fit(
    bundle = bundle,
    fit_space_id = space_id,
    clusters = clusters,
    cells = cells,
    exclude_cells = exclude_cells,
    include_clusters = include_clusters,
    exclude_clusters = exclude_clusters
  )
  sds <- .wb_slingshot_run_fit(
    X_fit = prep$X_fit,
    cells_fit = prep$cells_fit,
    cluster_labels = prep$cluster_labels,
    start.clus = start.clus,
    end.clus = end.clus,
    stretch = stretch,
    reweight = reweight,
    shrink = shrink,
    maxit = maxit,
    ...
  )

  pt_prim <- .wb_slingshot_pseudotime_prim(sds)
  cv_prim <- .wb_slingshot_curves_prim(sds)
  n_lin <- length(unique(pt_prim$key))

  list(
    outputs = list(
      pseudotime = pt_prim,
      curves     = cv_prim
    ),
    params = list(
      space_id = space_id,
      cells_in = length(prep$cells_in),
      cells_after_exclude_cells = length(prep$cells_after_exclude_cells),
      cells_after_cluster_filter = length(prep$cells_fit),
      start.clus = start.clus,
      end.clus = end.clus,
      stretch = stretch,
      reweight = reweight,
      shrink = shrink,
      maxit = maxit,
      n_lineages = n_lin
    )
  )
}
