# R/ops_geometry.R
# scworkbench: Geometry ops (kNN graph + Leiden clustering)
#
# Exports:
# - wb_op_knn_graph
# - wb_op_leiden
#
# Notes:
# - Space-driven: works on any space_id (LSI, PeakVI, UMAP, etc.)
# - Ephemeral: returns results in memory; no persistence here.
# - Uses Suggests: igraph, RANN

.wb_select_dims <- function(X, dims = NULL) {
  if (is.null(dims)) return(X)
  dims <- as.integer(dims)
  .wb_assert(length(dims) >= 1, "dims must be a non-empty integer vector")
  .wb_assert(all(dims >= 1 & dims <= ncol(X)), "dims out of bounds for this space")
  X[, dims, drop = FALSE]
}

#' Build a kNN graph from a space
#'
#' Constructs an undirected kNN graph over cells using coordinates from `space_id`.
#' The graph is returned as an igraph object. Edges connect each cell to its k nearest
#' neighbors (excluding itself). Optionally stores a weight derived from distance.
#'
#' @param bundle Bundle handle
#' @param space_id Which space to use (e.g. "lsi", "peakvi", "umap")
#' @param cells Optional cell_ids to restrict the graph to (order preserved)
#' @param k Number of nearest neighbors
#' @param dims Optional dims to use (e.g. 1:30 for LSI/latent). If NULL, use all dims.
#' @param metric Currently only "euclidean" (RANN)
#' @param weight If TRUE, assign edge weights as 1/(1+dist)
#' @return A list with:
#'   - graph: igraph graph
#'   - cells: cell_ids used (canonical order or user-provided order)
#'   - params: list(space_id, k, dims, metric, weight)
#' @export
wb_op_knn_graph <- function(bundle,
                            space_id,
                            cells,
                            k = 30,
                            dims = NULL,
                            metric = c("euclidean"),
                            weight = TRUE) {
  metric <- match.arg(metric)

  .wb_require_pkg("igraph", "kNN graph construction")
  .wb_require_pkg("RANN", "fast kNN search")

  .wb_assert(!missing(cells) && length(cells) > 0,
             "Internal: wb_op_knn_graph() must be called with 'cells' (use wb_session_run_op).")
  cells <- as.character(cells)

  .wb_assert(is.numeric(k) && length(k) == 1 && k >= 1, "k must be a positive integer")
  k <- as.integer(k)

  # Pull coordinates aligned to cells (space coverage already enforced upstream)
  S <- wb_space(bundle, space_id = space_id, cells = cells)
  X <- .wb_as_coord_matrix(S)

  # Ensure X rows align to `cells`
  if (!identical(rownames(X), cells)) {
    ii <- match(cells, rownames(X))
    .wb_assert(!anyNA(ii), "Some requested cells are missing in the selected space.")
    X <- X[ii, , drop = FALSE]
    rownames(X) <- cells
  }

  X <- .wb_select_dims(X, dims)

  # kNN: ask for k+1 because nearest neighbor is the point itself
  kk <- min(k + 1L, nrow(X))
  .wb_assert(kk >= 2, "Not enough cells to compute neighbors.")
  .wb_assert(!anyNA(X), "Space coordinates contain NA values; cannot run kNN/Leiden.")

  nn <- RANN::nn2(data = X, query = X, k = kk)

  idx <- nn$nn.idx  # n x (k+1)
  dist <- nn$nn.dists

  # Build directed edge list excluding self (first neighbor typically self)
  n <- nrow(X)
  from <- rep(seq_len(n), each = kk - 1L)
  to   <- as.vector(t(idx[, -1, drop = FALSE]))  # row-wise flatten

  # Remove any accidental self-links
  keep <- from != to
  from <- from[keep]
  to   <- to[keep]

  # Convert to undirected by sorting endpoints and unique
  a <- pmin(from, to)
  b <- pmax(from, to)
  key <- paste(a, b, sep = "_")
  uniq <- !duplicated(key)
  a <- a[uniq]
  b <- b[uniq]

  edges <- c(rbind(a, b))

  g <- igraph::make_empty_graph(n = n, directed = FALSE)
  g <- igraph::add_edges(g, edges)
  igraph::V(g)$name <- cells

  if (isTRUE(weight)) {
    # derive weights from the directed distances and take first occurrence per undirected edge
    d_from <- rep(seq_len(n), each = kk - 1L)
    d_to   <- as.vector(t(idx[, -1, drop = FALSE]))
    d_val  <- as.vector(t(dist[, -1, drop = FALSE]))

    d_keep <- d_from != d_to
    d_from <- d_from[d_keep]
    d_to   <- d_to[d_keep]
    d_val  <- d_val[d_keep]

    da <- pmin(d_from, d_to)
    db <- pmax(d_from, d_to)
    dkey <- paste(da, db, sep = "_")

    first <- !duplicated(dkey)
    d_tbl <- data.frame(key = dkey[first], d = d_val[first], stringsAsFactors = FALSE)

    ekey <- paste(a, b, sep = "_")
    dd <- d_tbl$d[match(ekey, d_tbl$key)]
    dd[is.na(dd)] <- 1

    igraph::E(g)$weight <- 1 / (1 + dd)
  }

  list(
    graph = g,
    cells = cells,
    params = list(space_id = space_id, k = k, dims = dims, metric = metric, weight = weight)
  )
}


#' Leiden clustering on a space
#'
#' Runs Leiden clustering using a kNN graph constructed from `space_id`.
#' Returns per-cell cluster labels (ephemeral).
#'
#' @param bundle Bundle handle
#' @param space_id Which space to use
#' @param cells Optional cell_ids (default all)
#' @param k kNN parameter for graph construction
#' @param dims Optional dims to use (e.g. 1:30)
#' @param resolution Leiden resolution parameter
#' @param n_iterations Number of Leiden iterations (-1 for until convergence)
#' @param seed Optional seed for reproducibility
#' @param weight Use distance-derived edge weights?
#' @return A list with:
#'   - labels: data.frame(cell_id, cluster)
#'   - graph: igraph graph used
#'   - params: list(space_id,k,dims,resolution,n_iterations,seed,weight)
#' @export
wb_op_leiden <- function(bundle,
                         space_id,
                         cells,
                         k = 30,
                         dims = NULL,
                         resolution = 1.0,
                         n_iterations = 2,
                         seed = NULL,
                         weight = TRUE) {
  .wb_require_pkg("igraph", "Leiden clustering")

  .wb_assert(!missing(cells) && length(cells) > 0,
             "Internal: wb_op_leiden() must be called with 'cells' (use wb_session_run_op).")

  .wb_assert(is.numeric(resolution) && length(resolution) == 1 && resolution > 0,
             "resolution must be a single positive number")

  if (!is.null(seed)) {
    old <- if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) .Random.seed else NULL
    on.exit({ if (!is.null(old)) .Random.seed <<- old }, add = TRUE)
    set.seed(as.integer(seed))
  }

  knn <- wb_op_knn_graph(
    bundle = bundle,
    space_id = space_id,
    cells = as.character(cells),
    k = k,
    dims = dims,
    weight = weight
  )

  g <- knn$graph

  # Use weights if present
  use_w <- isTRUE(weight) && "weight" %in% igraph::edge_attr_names(g)

  cl <- igraph::cluster_leiden(
    g,
    weights = if (use_w) igraph::E(g)$weight else NULL,
    resolution_parameter = resolution,
    n_iterations = as.integer(n_iterations),
    objective_function = "modularity"
  )

  memb <- igraph::membership(cl)

  # membership is named by vertex sequence; map to cell IDs
  cell_ids <- igraph::V(g)$name
  clusters <- as.integer(memb)

  labels <- data.frame(
    cell_id = cell_ids,
    cluster = as.character(clusters),
    stringsAsFactors = FALSE
  )

  list(
    labels = labels,
    graph = g,
    params = list(
      space_id = space_id,
      cell_set_n = length(cells),
      k = k,
      dims = dims,
      resolution = resolution,
      n_iterations = n_iterations,
      seed = seed,
      weight = weight
    )
  )
}

