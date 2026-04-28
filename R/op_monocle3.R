.wb_monocle3_require_pkgs <- function() {
  .wb_require_pkg("monocle3", "monocle3 trajectory fitting")
  .wb_require_pkg("Matrix", "monocle3 trajectory fitting")
  .wb_require_pkg("SingleCellExperiment", "monocle3 trajectory fitting")
  .wb_require_pkg("igraph", "monocle3 trajectory lineage derivation")
}

.wb_monocle3_as_int_vec <- function(x, allow_null = TRUE, name = "dims") {
  if (is.null(x)) {
    if (allow_null) return(NULL)
    stop(name, " is required.", call. = FALSE)
  }
  if (!length(x)) return(integer(0))
  xi <- suppressWarnings(as.integer(x))
  .wb_assert(!anyNA(xi), paste0(name, " must be coercible to integer(s)."))
  xi
}

.wb_monocle3_dummy_cds <- function(cell_ids) {
  n <- length(cell_ids)
  .wb_assert(n > 0, "monocle3_fit requires at least one cell.")

  # Minimal non-zero assay to keep monocle3 internals happy while we inject a
  # scworkbench latent space into reducedDims(cds)$UMAP.
  mat <- Matrix::Matrix(1, nrow = 1L, ncol = n, sparse = TRUE)
  rownames(mat) <- "dummy_feature"
  colnames(mat) <- as.character(cell_ids)

  cell_md <- data.frame(row.names = as.character(cell_ids))
  gene_md <- data.frame(gene_short_name = "dummy_feature", row.names = "dummy_feature")
  monocle3::new_cell_data_set(
    expression_data = mat,
    cell_metadata = cell_md,
    gene_metadata = gene_md
  )
}

.wb_monocle3_lineage_paths <- function(cds) {
  pg <- monocle3::principal_graph(cds)[["UMAP"]] %||% NULL
  .wb_assert(!is.null(pg), "monocle3_fit: principal_graph(cds)[['UMAP']] is missing after learn_graph().")

  aux <- monocle3::principal_graph_aux(cds)[["UMAP"]] %||% NULL
  .wb_assert(!is.null(aux), "monocle3_fit: principal_graph_aux(cds)[['UMAP']] is missing after order_cells().")

  root_nodes <- as.character(aux$root_pr_nodes %||% character(0))
  root_nodes <- root_nodes[nzchar(root_nodes)]
  root_nodes <- unique(root_nodes)
  .wb_assert(length(root_nodes) >= 1L,
             "monocle3_fit requires at least one root principal node after order_cells().")

  vnames <- as.character(igraph::V(pg)$name %||% character(0))
  .wb_assert(length(vnames) > 0, "monocle3_fit: principal graph vertices are unnamed.")
  .wb_assert(all(root_nodes %in% vnames),
             "monocle3_fit: one or more root principal nodes not found in principal graph.")

  # V1 semantics assume a tree (no reconverging branches).
  is_conn <- isTRUE(igraph::is_connected(pg))
  is_tree <- isTRUE(igraph::is_tree(pg, mode = "all"))
  .wb_assert(is_conn && is_tree,
             "monocle3_fit v1 requires a connected tree principal graph (use close_loop=FALSE).")

  deg <- igraph::degree(pg)
  leaves_all <- as.character(names(deg)[deg == 1L])
  leaves <- setdiff(leaves_all, root_nodes)
  used_root_leaves <- FALSE
  if (!length(leaves)) {
    # Multi-root cohorts can mark all terminal leaves as roots. In that case,
    # keep leaf keys and allow root==leaf lineages so branch-membership remains
    # representable without changing the primitive contract.
    leaves <- leaves_all
    used_root_leaves <- TRUE
  }
  .wb_assert(length(leaves) >= 1L,
             "monocle3_fit: no terminal leaf nodes available for lineage derivation.")

  lineage_paths <- vector("list", length(leaves))
  lineage_roots <- character(length(leaves))
  lineage_leaves <- as.character(leaves)
  for (i in seq_along(leaves)) {
    leaf <- leaves[[i]]
    # Multi-root support: assign each leaf to the closest root in graph steps
    # (deterministic tie-break by lexicographic root node id).
    dd <- as.numeric(igraph::distances(pg, v = root_nodes, to = leaf, mode = "all"))
    .wb_assert(length(dd) == length(root_nodes), "monocle3_fit: root distance computation failed.")
    .wb_assert(any(is.finite(dd)), paste0("monocle3_fit: leaf '", leaf, "' is unreachable from all roots."))
    best <- which(is.finite(dd) & dd == min(dd[is.finite(dd)]))
    root_choice <- sort(as.character(root_nodes[best]))[[1]]
    lineage_roots[[i]] <- root_choice
    sp <- igraph::shortest_paths(pg, from = root_choice, to = leaf, output = "vpath")$vpath[[1]]
    nodes <- as.character(igraph::V(pg)[sp]$name)
    min_nodes <- if (isTRUE(used_root_leaves)) 1L else 2L
    .wb_assert(length(nodes) >= min_nodes,
               paste0("monocle3_fit: invalid root-to-leaf path for leaf '", leaf, "'."))
    lineage_paths[[i]] <- nodes
  }
  names(lineage_paths) <- paste0("root:", lineage_roots, "::lineage:", lineage_leaves)

  list(
    pg = pg,
    root_nodes = root_nodes,
    leaves = leaves,
    used_root_leaves = used_root_leaves,
    lineage_roots = lineage_roots,
    lineage_leaves = lineage_leaves,
    lineage_paths = lineage_paths
  )
}

.wb_monocle3_closest_vertex_names <- function(cds, pg) {
  aux <- monocle3::principal_graph_aux(cds)[["UMAP"]] %||% NULL
  cv <- aux$pr_graph_cell_proj_closest_vertex %||% NULL
  .wb_assert(!is.null(cv), "monocle3_fit: missing pr_graph_cell_proj_closest_vertex in principal_graph_aux.")

  if (is.matrix(cv) || is.array(cv)) {
    cell_ids <- rownames(cv) %||% character(0)
    vals <- cv[, 1, drop = TRUE]
  } else {
    vals <- cv
    cell_ids <- names(vals) %||% character(0)
  }
  cell_ids <- as.character(cell_ids)
  .wb_assert(length(cell_ids) == length(vals), "monocle3_fit: closest-vertex mapping malformed.")

  vnames <- as.character(igraph::V(pg)$name %||% character(0))
  .wb_assert(length(vnames) > 0, "monocle3_fit: principal graph vertex names missing.")

  if (is.numeric(vals) || is.integer(vals)) {
    idx <- suppressWarnings(as.integer(vals))
    ok <- !is.na(idx) & idx >= 1L & idx <= length(vnames)
    out <- rep(NA_character_, length(idx))
    out[ok] <- vnames[idx[ok]]
  } else {
    out <- as.character(vals)
    out[!(out %in% vnames)] <- NA_character_
  }

  names(out) <- cell_ids
  out
}

.wb_monocle3_branch_membership_prim <- function(cds, lineage_info) {
  pg <- lineage_info$pg
  lineage_paths <- lineage_info$lineage_paths
  closest_vertex <- .wb_monocle3_closest_vertex_names(cds, pg)
  cell_ids <- names(closest_vertex)
  .wb_assert(length(cell_ids) > 0, "monocle3_fit: no cells found in closest-vertex mapping.")

  rows <- vector("list", length(lineage_paths))
  keep_n <- 0L
  for (i in seq_along(lineage_paths)) {
    key <- names(lineage_paths)[i]
    path_nodes <- lineage_paths[[i]]
    hit <- !is.na(closest_vertex) & (closest_vertex %in% path_nodes)
    if (!any(hit)) next
    keep_n <- keep_n + 1L
    rows[[keep_n]] <- data.frame(
      key = rep(key, sum(hit)),
      cell_id = as.character(cell_ids[hit]),
      weight = rep(1, sum(hit)),
      stringsAsFactors = FALSE
    )
  }
  .wb_assert(keep_n > 0L, "monocle3_fit: derived zero branch-membership relations.")

  rel <- do.call(rbind, rows[seq_len(keep_n)])
  rownames(rel) <- NULL
  wb_prim_relation_family(
    key = rel$key,
    cell_id = rel$cell_id,
    weight = rel$weight,
    meta = list(
      key_type = "lineage",
      relation_semantics = "cell_to_lineage_membership",
      weight_semantics = "closest_vertex_path_membership_binary",
      normalized_per_cell = FALSE
    )
  )
}

#' Fit A Monocle3 Trajectory Model
#'
#' Hybrid design: scworkbench provides the fit coordinates (`space` primitive),
#' which are injected into `reducedDims(cds)$UMAP` so monocle3 can run its graph
#' learning and ordering pipeline while preserving engine-side space selection.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param fit_space_id Space id used for graph learning and pseudotime fitting.
#' @param cells Cell ids to fit.
#' @param dims Optional dimensions to take from the fit space.
#' @param root_cells Optional root cell ids.
#' @param root_pr_nodes Optional root principal-graph node ids.
#' @param k Neighborhood size passed to `monocle3::cluster_cells()`.
#' @param cluster_method Clustering method for `monocle3::cluster_cells()`.
#' @param num_iter Number of clustering iterations.
#' @param partition_qval Partition q-value threshold.
#' @param weight Whether to use weighted nearest-neighbor clustering.
#' @param resolution Optional clustering resolution.
#' @param random_seed Random seed.
#' @param use_partition Whether to use partitions during graph learning.
#' @param close_loop Whether to allow loop closure during graph learning.
#' @param verbose Whether to enable verbose monocle3 output.
#' @param nn_control Optional nearest-neighbor control list passed to monocle3.
#' @param learn_graph_control Optional control list passed to
#'   `monocle3::learn_graph()`.
#' @param ... Reserved for forward compatibility.
#'
#' @return A standard op result list with `outputs` containing `pseudotime`,
#'   `branch_membership`, and `model`, plus normalized `params`.
#'
#' @export
wb_op_monocle3_fit <- function(bundle,
                               fit_space_id,
                               cells,
                               dims = NULL,
                               root_cells = NULL,
                               root_pr_nodes = NULL,
                               k = 20,
                               cluster_method = c("leiden", "louvain"),
                               num_iter = 2,
                               partition_qval = 0.05,
                               weight = FALSE,
                               resolution = NULL,
                               random_seed = 42,
                               use_partition = FALSE,
                               close_loop = FALSE,
                               verbose = FALSE,
                               nn_control = list(),
                               learn_graph_control = NULL,
                               ...) {

  .wb_monocle3_require_pkgs()
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  cells <- unique(as.character(cells %||% character(0)))
  .wb_assert(length(cells) >= 10L, "monocle3_fit requires at least 10 cells.")
  .wb_assert(is.character(fit_space_id) && length(fit_space_id) == 1L && nzchar(fit_space_id),
             "monocle3_fit requires fit_space_id.")

  has_root_cells <- !is.null(root_cells) && length(root_cells) > 0
  has_root_pr_nodes <- !is.null(root_pr_nodes) && length(root_pr_nodes) > 0
  .wb_assert(xor(has_root_cells, has_root_pr_nodes),
             "monocle3_fit requires exactly one of root_cells or root_pr_nodes.")

  dims_use <- .wb_monocle3_as_int_vec(dims, allow_null = TRUE, name = "dims")
  cluster_method <- match.arg(cluster_method)

  sp <- wb_space(bundle, space_id = fit_space_id, cells = cells, dims = dims_use)
  X_fit <- .wb_as_coord_matrix(sp)
  .wb_assert(nrow(X_fit) == length(cells), "monocle3_fit: fit space row count mismatch with cells.")
  .wb_assert(ncol(X_fit) >= 2L, "monocle3_fit requires fit space with >=2 dimensions.")
  .wb_assert(!anyNA(X_fit), "monocle3_fit does not support NA coordinates in fit space.")

  # Monocle3 order_cells() in current versions is UMAP-slot-centric. We inject the
  # chosen scworkbench latent coordinates into reducedDims(cds)$UMAP.
  cds <- .wb_monocle3_dummy_cds(cells)
  SingleCellExperiment::reducedDims(cds)$UMAP <- X_fit

  cds <- monocle3::cluster_cells(
    cds,
    reduction_method = "UMAP",
    k = as.integer(k),
    cluster_method = cluster_method,
    num_iter = as.integer(num_iter),
    partition_qval = partition_qval,
    weight = isTRUE(weight),
    resolution = resolution,
    random_seed = as.integer(random_seed),
    verbose = isTRUE(verbose),
    nn_control = nn_control
  )

  cds <- monocle3::learn_graph(
    cds,
    use_partition = isTRUE(use_partition),
    close_loop = isTRUE(close_loop),
    learn_graph_control = learn_graph_control,
    verbose = isTRUE(verbose)
  )

  root_cells_use <- if (has_root_cells) intersect(as.character(root_cells), cells) else NULL
  if (has_root_cells) {
    .wb_assert(length(root_cells_use) > 0L, "monocle3_fit: root_cells has no overlap with fitted cells.")
  }
  root_pr_nodes_use <- if (has_root_pr_nodes) as.character(root_pr_nodes) else NULL

  cds <- monocle3::order_cells(
    cds,
    reduction_method = "UMAP",
    root_pr_nodes = root_pr_nodes_use,
    root_cells = root_cells_use,
    verbose = isTRUE(verbose)
  )

  pt <- monocle3::pseudotime(cds)
  .wb_assert(length(pt) == ncol(cds), "monocle3_fit: pseudotime length mismatch.")
  pt <- pt[colnames(cds)]
  pt_prim <- wb_prim_cell_vector(pt, value_type = "continuous")

  lineage_info <- .wb_monocle3_lineage_paths(cds)
  bm_prim <- .wb_monocle3_branch_membership_prim(cds, lineage_info)

  model_prim <- wb_prim_model_ref(
    model_space_id = fit_space_id,
    in_space_id = fit_space_id,
    engine = "monocle3"
  )
  model_prim$model_obj <- cds
  model_prim$model_type <- "monocle3_cds"
  model_prim$fit_space_id <- fit_space_id
  model_prim$cells <- as.character(colnames(cds))
  model_prim$root_pr_nodes <- as.character(lineage_info$root_nodes)
  model_prim$lineage_keys <- names(lineage_info$lineage_paths)
  model_prim$lineage_paths <- lineage_info$lineage_paths

  list(
    outputs = list(
      pseudotime = pt_prim,
      branch_membership = bm_prim,
      model = model_prim
    ),
    params = list(
      fit_space_id = fit_space_id,
      dims = as.integer(seq_len(ncol(X_fit))),
      source_dims = if (is.null(dims_use)) NULL else as.integer(dims_use),
      cells_fit = ncol(cds),
      root_input_mode = if (has_root_cells) "root_cells" else "root_pr_nodes",
      root_cells = if (has_root_cells) as.character(root_cells_use) else NULL,
      root_pr_nodes = as.character(lineage_info$root_nodes),
      k = as.integer(k),
      cluster_method = cluster_method,
      num_iter = as.integer(num_iter),
      partition_qval = partition_qval,
      weight = isTRUE(weight),
      resolution = resolution,
      random_seed = as.integer(random_seed),
      use_partition = isTRUE(use_partition),
      close_loop = isTRUE(close_loop),
      n_lineages = length(lineage_info$lineage_paths),
      lineage_keys = names(lineage_info$lineage_paths),
      lineage_roots = as.character(lineage_info$lineage_roots),
      lineage_leaves = as.character(lineage_info$lineage_leaves),
      lineage_derivation_used_root_leaves = isTRUE(lineage_info$used_root_leaves),
      lineage_paths = lineage_info$lineage_paths,
      branch_membership_key_type = "lineage",
      branch_membership_key_format = "root:<root_pr_node>::lineage:<leaf_pr_node>",
      branch_membership_method = "closest_vertex_path_membership_binary",
      lineage_root_assignment_method = if (length(lineage_info$root_nodes) > 1L) {
        "leaf_shortest_path_to_root_tie_lexicographic"
      } else {
        "single_root"
      },
      branch_membership_normalized_per_cell = FALSE,
      n_pseudotime_na = sum(is.na(as.numeric(pt)))
    )
  )
}

.wb_monocle3_lineage_curves_2d_prim <- function(cds,
                                                lineage_info,
                                                plot_xy,
                                                approx_points = 200L) {
  .wb_assert(is.matrix(plot_xy) && ncol(plot_xy) == 2L, "plot_xy must be a 2-column matrix.")
  .wb_assert(!is.null(rownames(plot_xy)), "plot_xy must have rownames (cell IDs).")

  closest_vertex <- .wb_monocle3_closest_vertex_names(cds, lineage_info$pg)
  cc <- closest_vertex[rownames(plot_xy)]
  ok_cells <- !is.na(cc)
  .wb_assert(any(ok_cells), "monocle3_project: no cells could be mapped to principal graph vertices.")

  plot_xy <- plot_xy[ok_cells, , drop = FALSE]
  cc <- as.character(cc[ok_cells])

  rows <- list()
  row_i <- 0L
  for (k in names(lineage_info$lineage_paths)) {
    nodes <- lineage_info$lineage_paths[[k]]
    xs <- numeric(0)
    ys <- numeric(0)
    pts <- integer(0)
    for (j in seq_along(nodes)) {
      hit <- which(cc == nodes[[j]])
      if (!length(hit)) next
      row_i <- row_i + 1L
      rows[[row_i]] <- data.frame(
        key = as.character(k),
        point = as.integer(length(pts) + 1L),
        x = mean(plot_xy[hit, 1], na.rm = TRUE),
        y = mean(plot_xy[hit, 2], na.rm = TRUE),
        stringsAsFactors = FALSE
      )
      pts <- c(pts, j)
    }
  }
  .wb_assert(length(rows) > 0L, "monocle3_project: failed to derive any projected lineage curves.")
  df <- do.call(rbind, rows)
  rownames(df) <- NULL

  prim <- wb_prim_path_2d_family(key = df$key, point = df$point, x = df$x, y = df$y)
  prim <- .wb_path_2d_family_compact(prim, max_points_per_lineage = approx_points)
  prim
}

#' Project A Monocle3 Trajectory Into 2D
#'
#' Consumes `model_ref(engine="monocle3")` produced by `wb_op_monocle3_fit()` and
#' emits drawable `path_2d_family` curves by mapping lineage graph nodes to
#' centroids of fitted cells in the requested 2D display space.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param monocle3_model `model_ref(engine = "monocle3")` from
#'   [wb_op_monocle3_fit()].
#' @param plot_space_id Two-dimensional space id used for display.
#' @param approx_points Maximum points retained per lineage after compaction.
#' @param ... Reserved for forward compatibility.
#'
#' @return A standard op result list with `outputs$curves` and normalized
#'   `params`.
#'
#' @export
wb_op_monocle3_project <- function(bundle,
                                   monocle3_model,
                                   plot_space_id,
                                   approx_points = 200L,
                                   ...) {
  .wb_monocle3_require_pkgs()
  .wb_assert_kind(monocle3_model, "model_ref")
  .wb_assert(identical(monocle3_model$engine %||% "", "monocle3"),
             "monocle3_project requires model_ref(engine='monocle3').")

  cds <- monocle3_model$model_obj %||% NULL
  .wb_assert(!is.null(cds),
             paste(
               "monocle3_project received a monocle3 model_ref without in-memory model payload.",
               "Promoted monocle3 model artifacts require model RDS loading."
             ))

  cells_fit <- as.character(monocle3_model$cells %||% colnames(cds) %||% character(0))
  .wb_assert(length(cells_fit) > 0L, "monocle3_project: could not recover fitted cell IDs from model.")

  sp <- wb_space(bundle, space_id = plot_space_id, cells = cells_fit)
  X_plot <- .wb_as_coord_matrix(sp)
  ii <- match(cells_fit, rownames(X_plot))
  .wb_assert(!anyNA(ii), paste0("monocle3_project: plot_space is missing ", sum(is.na(ii)), " fitted cells."))
  X_plot <- X_plot[ii, , drop = FALSE]
  rownames(X_plot) <- cells_fit
  .wb_assert(ncol(X_plot) == 2L, "monocle3_project requires a 2D plot space.")

  lineage_info <- if (!is.null(monocle3_model$lineage_paths) && length(monocle3_model$lineage_paths)) {
    list(
      pg = monocle3::principal_graph(cds)[["UMAP"]],
      lineage_paths = monocle3_model$lineage_paths
    )
  } else {
    li <- .wb_monocle3_lineage_paths(cds)
    list(pg = li$pg, lineage_paths = li$lineage_paths)
  }
  .wb_assert(!is.null(lineage_info$pg), "monocle3_project: principal graph missing from model.")
  .wb_assert(length(lineage_info$lineage_paths) > 0L, "monocle3_project: no lineage paths available in model.")

  cv_prim <- .wb_monocle3_lineage_curves_2d_prim(
    cds = cds,
    lineage_info = lineage_info,
    plot_xy = X_plot,
    approx_points = approx_points
  )
  cv_prim$plot_space_id <- as.character(plot_space_id)

  list(
    outputs = list(curves = cv_prim),
    params = list(
      fit_space_id = as.character(monocle3_model$fit_space_id %||% monocle3_model$model_space_id %||% ""),
      plot_space_id = as.character(plot_space_id),
      cells_projected = length(cells_fit),
      n_lineages = length(unique(as.character(cv_prim$key))),
      approx_points = as.integer(approx_points)
    )
  )
}
