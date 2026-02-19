#' Slingshot trajectory inference (2D space like UMAP)
#'
#' clusters:
#' - named vector: names = cell_id, values = cluster label
#'
#' cells MUST be provided (effective_cells computed by session).
#'
#' @export
wb_op_slingshot <- function(bundle,
                            space_id,
                            clusters,          # named vector: names=cell_id, values=cluster
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

  .wb_require_pkg("SingleCellExperiment", "Slingshot container")
  .wb_require_pkg("S4Vectors", "ReducedDims container")
  .wb_require_pkg("slingshot", "Trajectory inference")

  .wb_assert(is.character(space_id) && length(space_id) == 1 && nzchar(space_id),
             "space_id must be a single non-empty string.")

  .wb_assert(is.atomic(clusters) && !is.null(names(clusters)),
             "clusters must be a named vector (names=cell_id, values=cluster).")
  clusters <- setNames(as.character(clusters), names(clusters))

  .wb_assert(all(nzchar(names(clusters))), "clusters has empty cell_id names.")
  .wb_assert(length(clusters) > 0, "clusters is empty.")

  .wb_assert(!missing(cells) && length(cells) > 0,
             "wb_op_slingshot() must be called with 'cells' (effective_cells).")

  cells_use <- as.character(cells)

  # optional excludes
  if (!is.null(exclude_cells)) {
    cells_use <- setdiff(cells_use, as.character(exclude_cells))
  }
  .wb_assert(length(cells_use) >= 10, "Too few cells after exclude_cells (need >= 10).")

  # align clusters to cells_use (THIS WAS YOUR BROKEN PART)
  clust_sub <- clusters[cells_use]
  missing_lab <- cells_use[is.na(clust_sub)]
  .wb_assert(length(missing_lab) == 0,
             paste0("Clusters missing for ", length(missing_lab), " selected cells."))

  labels2 <- data.frame(
    cell_id = cells_use,
    cluster = as.character(clust_sub),
    stringsAsFactors = FALSE
  )

  # pull 2D coords
  sp <- wb_space(bundle, space_id = space_id, cells = cells_use)
  X <- .wb_as_coord_matrix(sp)

  if (!identical(rownames(X), cells_use)) {
    ii <- match(cells_use, rownames(X))
    .wb_assert(!anyNA(ii), "Some requested cells are missing from the selected space.")
    X <- X[ii, , drop = FALSE]
    rownames(X) <- cells_use
  }

  # filter by include/exclude clusters (reuse your helper)
  fl <- .wb_filter_labels(
    labels_df = labels2,
    cells = cells_use,
    include_clusters = include_clusters,
    exclude_clusters = exclude_clusters
  )
  cells2 <- as.character(fl$cells)
  lab2   <- fl$labels
  .wb_assert(length(cells2) >= 10, "Too few cells after cluster filtering (need >= 10).")

  # subset X to filtered cells
  ii2 <- match(cells2, rownames(X))
  .wb_assert(!anyNA(ii2), "Internal error: filtered cells missing from embedding.")
  X <- X[ii2, , drop = FALSE]
  rownames(X) <- cells2

  # validate start/end clusters exist after filtering
  present_clusters <- sort(unique(as.character(lab2$cluster)))
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

  # Build SCE aligned to cells2
  cl <- factor(lab2$cluster[match(cells2, lab2$cell_id)])
  .wb_assert(!anyNA(cl), "Internal: NA cluster labels after filtering.")

  sce <- SingleCellExperiment::SingleCellExperiment(
    assays = list(dummy = matrix(0, nrow = 1, ncol = length(cells2)))
  )
  colnames(sce) <- cells2
  SingleCellExperiment::reducedDims(sce) <- S4Vectors::SimpleList(space = X)

  sds <- slingshot::slingshot(
    sce,
    clusterLabels = cl,
    reducedDim = "space",
    start.clus = start.clus,
    end.clus = end.clus,
    stretch = stretch,
    reweight = reweight,
    shrink = shrink,
    maxit = maxit,
    ...
  )

  pt <- slingshot::slingPseudotime(sds)
  n_lin <- ncol(pt)
  lineage_ids <- paste0("L", seq_len(n_lin))

  pseudotime <- do.call(rbind, lapply(seq_len(n_lin), function(j) {
    data.frame(
      cell_id = cells2,
      lineage_id = lineage_ids[j],
      pseudotime = as.numeric(pt[, j]),
      stringsAsFactors = FALSE
    )
  }))
  pseudotime <- pseudotime[!is.na(pseudotime$pseudotime), , drop = FALSE]

  curves <- slingshot::slingCurves(sds)
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

  pt_prim <- wb_prim_cell_vector_family(
    key       = pseudotime$lineage_id,
    cell_id   = pseudotime$cell_id,
    value     = pseudotime$pseudotime,
    value_type = "continuous"
  )

  # curves df -> primitive path_2d_family
  cv_prim <- wb_prim_path_2d_family(
    key   = curves_2d$lineage_id,
    point = curves_2d$point,
    x     = curves_2d$x,
    y     = curves_2d$y
  )

  list(
    outputs = list(
      pseudotime = pt_prim,
      curves     = cv_prim
    ),
    params = list(
      space_id = space_id,
      cells_in = length(cells),
      cells_after_exclude_cells = length(cells_use),
      cells_after_cluster_filter = length(cells2),
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

