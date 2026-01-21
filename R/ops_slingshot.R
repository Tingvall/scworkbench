# R/ops_slingshot.R
# Requires: slingshot, SingleCellExperiment
# Suggested packages for now (guard with requireNamespace)

#' Slingshot trajectory inference (PoC: 2D space like UMAP)
#'
#' scworkbench contract:
#' - universal filtering via cells/exclude_cells/(include|exclude)_datasets
#' - label filtering via (include|exclude)_clusters
#' - slingshot-native args preserved: start.clus, end.clus, stretch, ...
#'
#' @param bundle Bundle handle
#' @param space_id 2D space id (e.g. "umap")
#' @param labels data.frame with columns cell_id and cluster
#' @param cells Optional subset of cells to include (default all)
#' @param exclude_cells Optional cells to exclude
#' @param include_datasets Optional dataset_ids to keep
#' @param exclude_datasets Optional dataset_ids to drop
#' @param include_clusters Optional clusters to keep (from labels$cluster)
#' @param exclude_clusters Optional clusters to drop (from labels$cluster)
#' @param start.clus,end.clus Slingshot start/end cluster(s)
#' @param stretch,reweight,shrink,maxit Slingshot params
#' @param ... passed to slingshot::slingshot()
#' @return list(
#'   pseudotime = data.frame(cell_id, lineage_id, pseudotime),
#'   curves     = data.frame(lineage_id, point, x, y),
#'   params     = list(...)
#' )
#' @export
wb_op_slingshot <- function(bundle,
                            space_id,
                            labels,
                            cells = NULL,
                            cell_set = "core",
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
  .wb_assert(is.data.frame(labels), "labels must be a data.frame.")
  .wb_assert(all(c("cell_id", "cluster") %in% colnames(labels)),
             "labels must have columns: cell_id, cluster")

  .wb_assert(!missing(cells) && length(cells) > 0,
             "Internal: wb_op_slingshot() must be called with 'cells' (use wb_session_run_op).")
  if (is.null(cells)) {
    cells <- .wb_resolve_effective_cells_for_op(
      bundle  = bundle,
      op_name = "slingshot",
      cell_set = cell_set,
      inputs = list(space_id = space_id),
      min_cells = 10
    )
  }


  # optional manual excludes
  if (!is.null(exclude_cells)) {
    exclude_cells <- as.character(exclude_cells)
    cells_use <- setdiff(cells_use, exclude_cells)
  }
  rr <- .wb_resolve_cells(bundle = bundle, cells = cells, ...)
  cells_use <- rr$cells

  .wb_assert(length(cells_use) >= 10,
             paste0("slingshot: too few cells after filtering for cell_set=", cell_set,
                    " (need >=10, got ", length(cells_use), ")."))
  # 1) pull 2D coords from bundle (must align to requested cells)
  sp <- wb_space(bundle, space_id = space_id, cells = cells_use)
  X <- .wb_as_coord_matrix(sp)

  # Ensure row order matches cells_use (wb_space should align, but keep robust)
  if (!identical(rownames(X), cells_use)) {
    ii <- match(cells_use, rownames(X))
    .wb_assert(!anyNA(ii), "Some requested cells are missing from the selected space.")
    X <- X[ii, , drop = FALSE]
    rownames(X) <- cells_use
  }

  # 2) filter labels to the same cell universe
  labels2 <- labels[labels$cell_id %in% cells_use, , drop = FALSE]
  labels2$cell_id <- as.character(labels2$cell_id)
  labels2$cluster <- as.character(labels2$cluster)

  # Some workflows may have labels for all cells but not for all requested cells (or vice versa)
  .wb_assert(nrow(labels2) > 0, "No labels found for the selected cells.")
  .wb_assert(length(unique(labels2$cell_id)) >= 10, "Too few labeled cells after filtering (need >= 10).")

  # Ensure labels cover all cells_use (strict by default)
  missing_lab <- setdiff(cells_use, labels2$cell_id)
  .wb_assert(length(missing_lab) == 0,
             paste0("Labels missing for ", length(missing_lab), " selected cells. ",
                    "This op requires cluster labels for all selected cells."))

  # 3) cluster include/exclude filtering (labels-driven)
  fl <- .wb_filter_labels(
    labels_df = labels2,
    cells = cells_use,
    include_clusters = include_clusters,
    exclude_clusters = exclude_clusters
  )
  cells2 <- as.character(fl$cells)
  lab2   <- fl$labels
  lab2$cell_id <- as.character(lab2$cell_id)
  lab2$cluster <- as.character(lab2$cluster)

  .wb_assert(length(cells2) >= 10, "Too few cells after cluster filtering (need >= 10).")

  # subset X to filtered cells
  ii2 <- match(cells2, rownames(X))
  .wb_assert(!anyNA(ii2), "Internal error: filtered cells missing from embedding.")
  X <- X[ii2, , drop = FALSE]
  rownames(X) <- cells2

  # 4) validate start/end clusters still exist after filtering
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

  # 5) Build SCE with reducedDims
  cl <- as.factor(lab2$cluster)

  sce <- SingleCellExperiment::SingleCellExperiment(
    assays = list(dummy = matrix(0, nrow = 1, ncol = length(cells2)))
  )
  colnames(sce) <- cells2
  SingleCellExperiment::reducedDims(sce) <- S4Vectors::SimpleList(space = X)

  # 6) Run slingshot
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

  # 7) Pseudotime (n_cells x n_lineages) -> long df
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

  # 8) Curves (2D)
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

  list(
    pseudotime = pseudotime,
    curves = curves_2d,
    params = list(
      space_id = space_id,
      cell_set_n = length(cells),               # what session runner gave us
      cells_after_exclude_cells = length(cells_use),
      cells_after_cluster_filter = length(cells2),

      exclude_cells = if (is.null(exclude_cells)) NULL else as.character(exclude_cells),
      include_clusters = if (is.null(include_clusters)) NULL else as.character(include_clusters),
      exclude_clusters = if (is.null(exclude_clusters)) NULL else as.character(exclude_clusters),

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

