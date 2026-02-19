.wb_runner_leiden <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  .wb_assert(!is.null(resolved$space), "leiden runner: missing resolved$space (space primitive).")
  .wb_assert(!is.null(effective_cells) && length(effective_cells) > 0,
             "leiden runner: effective_cells is empty.")

  space_id <- resolved$space$space_id
  raw <- wb_op_leiden(
    bundle = bundle,
    space_id = space_id,
    cells = as.character(effective_cells),
    k = inputs$k %||% 30,
    dims = inputs$dims %||% NULL,
    resolution = inputs$resolution %||% 1.0,
    n_iterations = inputs$n_iterations %||% 2,
    seed = inputs$seed %||% NULL,
    weight = inputs$weight %||% TRUE
  )

  .wb_assert(is.list(raw) && is.list(raw$outputs),
             "leiden must return list(outputs=<list>, params=<list>).")
  raw
}

.wb_runner_slingshot <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  .wb_assert(!is.null(resolved$space_2d), "slingshot runner: missing resolved$space_2d.")
  .wb_assert(!is.null(resolved$clusters), "slingshot runner: missing resolved$clusters.")
  .wb_assert(!is.null(effective_cells) && length(effective_cells) > 0,
             "slingshot runner: effective_cells is empty.")

  space_id <- resolved$space_2d$space_id
  clp <- resolved$clusters
  clusters_vec <- as.character(clp$value)
  names(clusters_vec) <- as.character(clp$cell_id)

  raw <- wb_op_slingshot(
    bundle = bundle,
    space_id = space_id,
    clusters = clusters_vec,
    cells = as.character(effective_cells),
    exclude_clusters = inputs$exclude_clusters %||% character(0),
    start.clus = inputs$start.clus %||% NULL,
    end.clus = inputs$end.clus %||% NULL,
    stretch = inputs$stretch %||% 2,
    reweight = inputs$reweight %||% TRUE
  )

  .wb_assert(is.list(raw) && is.list(raw$outputs),
             "slingshot must return list(outputs=<list>, params=<list>).")
  raw
}

.wb_runner_umap_fit <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  .wb_assert(!is.null(resolved$space), "umap_fit runner: missing resolved$space.")
  .wb_assert(!is.null(effective_cells) && length(effective_cells) > 0,
             "umap_fit runner: effective_cells is empty.")

  source_space_id <- resolved$space$space_id

  raw <- wb_op_umap_fit(
    bundle = bundle,
    source_space_id = source_space_id,
    cells = as.character(effective_cells),
    dims = inputs$dims %||% NULL,
    space_id_out = inputs$space_id_out %||% paste0("umap.", source_space_id),
    n_neighbors = inputs$n_neighbors %||% 30,
    min_dist = inputs$min_dist %||% 0.3,
    metric = inputs$metric %||% "euclidean",
    nn_method = inputs$nn_method %||% "nndescent",
    spread = inputs$spread %||% 1.0,
    seed = inputs$seed %||% 1
  )

  .wb_assert(is.list(raw) && is.list(raw$outputs),
             "umap_fit must return list(outputs=<list>, params=<list>).")
  raw
}

.wb_runner_umap_transform <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  .wb_assert(!is.null(resolved$model), "umap_transform runner: missing resolved$model.")
  .wb_assert(length(effective_cells) > 0, "umap_transform runner: effective_cells is empty.")

  mr <- resolved$model
  model_space_id <- mr$model_space_id %||% mr$space_id
  fit_in_space_id <- mr$in_space_id %||% ""

  .wb_assert(nzchar(model_space_id), "model_ref must contain model_space_id (or space_id).")

  if (!nzchar(fit_in_space_id)) {
    sm <- wb_space_model(bundle, model_space_id)
    fit_in_space_id <- as.character(sm$source_space_id[1] %||% "")
  }

  in_space_id <- inputs$in_space_id %||% inputs$in_space %||% fit_in_space_id
  if (is.list(in_space_id) && !is.null(in_space_id$space_id)) {
    in_space_id <- in_space_id$space_id
  }
  in_space_id <- as.character(in_space_id)[1]
  .wb_assert(nzchar(in_space_id), "Could not resolve in_space_id from model_ref or inputs.")

  raw <- wb_op_umap_transform(
    bundle = bundle,
    model_space_id = model_space_id,
    in_space_id = in_space_id,
    cells = as.character(effective_cells),
    dims = inputs$dims %||% NULL,
    overwrite = inputs$overwrite %||% TRUE
  )

  .wb_assert(is.list(raw) && is.list(raw$outputs),
             "umap_transform must return list(outputs=<list>, params=<list>).")
  raw
}

.wb_runner_addmodulescore <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  .wb_assert(!is.null(resolved$matrix), "addmodulescore runner: missing resolved$matrix.")
  .wb_assert(!is.null(effective_cells) && length(effective_cells) > 0,
             "addmodulescore runner: effective_cells is empty.")
  .wb_assert(!is.null(inputs$features),
             "addmodulescore runner: inputs$features is required.")

  matrix_id <- resolved$matrix$matrix_id
  .wb_assert(is.character(matrix_id) && length(matrix_id) == 1 && nzchar(matrix_id),
             "addmodulescore runner: resolved matrix primitive missing matrix_id.")

  raw <- wb_op_addmodulescore(
    bundle = bundle,
    matrix_id = matrix_id,
    features = inputs$features,
    pool = inputs$pool %||% NULL,
    cells = as.character(effective_cells),
    nbin = inputs$nbin %||% 24,
    ctrl = inputs$ctrl %||% 100,
    name = inputs$name %||% "Module",
    seed = inputs$seed %||% 1
  )

  .wb_assert(is.list(raw) && is.list(raw$outputs),
             "addmodulescore must return list(outputs=<list>, params=<list>).")
  raw
}

.wb_runner_de_wilcox <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  .wb_assert(!is.null(resolved$matrix), "de_wilcox runner: missing resolved$matrix.")
  .wb_assert(!is.null(inputs$group_a), "de_wilcox runner: inputs$group_a is required.")
  .wb_assert(!is.null(inputs$group_b), "de_wilcox runner: inputs$group_b is required.")

  matrix_id <- resolved$matrix$matrix_id
  cells_a <- .wb_resolve_group_cells(bundle, inputs$group_a, effective_cells)
  cells_b <- .wb_resolve_group_cells(bundle, inputs$group_b, effective_cells)

  .wb_assert(length(cells_a) >= 2, "de_wilcox runner: group_a resolved to <2 cells.")
  .wb_assert(length(cells_b) >= 2, "de_wilcox runner: group_b resolved to <2 cells.")

  raw <- wb_op_de_wilcox(
    bundle = bundle,
    matrix_id = matrix_id,
    cells_a = cells_a,
    cells_b = cells_b,
    features = inputs$features %||% NULL,
    min_pct = inputs$min_pct %||% 0,
    p_adjust_method = inputs$p_adjust_method %||% "BH"
  )

  .wb_assert(is.list(raw) && is.list(raw$outputs),
             "de_wilcox must return list(outputs=<list>, params=<list>).")
  raw
}

.wb_runner_markers_topn <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  .wb_assert(!is.null(resolved$matrix), "markers_topn runner: missing resolved$matrix.")
  .wb_assert(!is.null(resolved$clusters), "markers_topn runner: missing resolved$clusters.")

  matrix_id <- resolved$matrix$matrix_id
  clp <- resolved$clusters
  clusters_vec <- as.character(clp$value)
  names(clusters_vec) <- as.character(clp$cell_id)

  raw <- wb_op_markers_topn(
    bundle = bundle,
    matrix_id = matrix_id,
    clusters = clusters_vec,
    cells = as.character(effective_cells),
    features = inputs$features %||% NULL,
    top_n = inputs$top_n %||% 20,
    min_pct = inputs$min_pct %||% 0.1,
    p_adjust_method = inputs$p_adjust_method %||% "BH"
  )

  .wb_assert(is.list(raw) && is.list(raw$outputs),
             "markers_topn must return list(outputs=<list>, params=<list>).")
  raw
}

.wb_runner_knn_pseudobulk <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  .wb_assert(!is.null(resolved$matrix), "knn_pseudobulk runner: missing resolved$matrix.")
  .wb_assert(!is.null(resolved$space), "knn_pseudobulk runner: missing resolved$space.")
  .wb_assert(!is.null(inputs$query_cells), "knn_pseudobulk runner: inputs$query_cells is required.")

  matrix_id <- resolved$matrix$matrix_id
  space_id <- resolved$space$space_id

  query_cells <- .wb_resolve_group_cells(bundle, inputs$query_cells, effective_cells)
  candidate_cells <- if (!is.null(inputs$candidate_cells)) {
    .wb_resolve_group_cells(bundle, inputs$candidate_cells, effective_cells)
  } else {
    as.character(wb_cells(bundle, cell_set = "all"))
  }

  raw <- wb_op_knn_pseudobulk(
    bundle = bundle,
    matrix_id = matrix_id,
    space_id = space_id,
    query_cells = query_cells,
    candidate_cells = candidate_cells,
    features = inputs$features %||% NULL,
    k = inputs$k %||% 100,
    include_query = inputs$include_query %||% FALSE,
    aggregate = inputs$aggregate %||% "sum"
  )

  .wb_assert(is.list(raw) && is.list(raw$outputs),
             "knn_pseudobulk must return list(outputs=<list>, params=<list>).")
  raw
}

.wb_runner_knn_neighbors <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  .wb_assert(!is.null(resolved$space), "knn_neighbors runner: missing resolved$space.")
  .wb_assert(!is.null(inputs$query_cells), "knn_neighbors runner: inputs$query_cells is required.")

  space_id <- resolved$space$space_id
  query_cells <- .wb_resolve_group_cells(bundle, inputs$query_cells, effective_cells)
  candidate_cells <- if (!is.null(inputs$candidate_cells)) {
    .wb_resolve_group_cells(bundle, inputs$candidate_cells, effective_cells)
  } else {
    as.character(wb_cells(bundle, cell_set = "all"))
  }

  raw <- wb_op_knn_neighbors(
    bundle = bundle,
    space_id = space_id,
    query_cells = query_cells,
    candidate_cells = candidate_cells,
    k = inputs$k %||% 100,
    include_query = inputs$include_query %||% FALSE
  )

  .wb_assert(is.list(raw) && is.list(raw$outputs),
             "knn_neighbors must return list(outputs=<list>, params=<list>).")
  raw
}

# Canonical op catalog.
# Add new ops in one place only: contract + wrangler + interface metadata.
.wb_op_catalog <- function() {
  list(
    leiden = list(
      op_name = "leiden",
      title = "Leiden clustering",
      description = "Graph clustering on a kNN graph derived from an embedding space.",
      intent = c("cluster"),
      requires = list(space = "space"),
      produces = list(clusters = "cell_vector"),
      promotable = c("clusters"),
      runner = .wb_runner_leiden,
      inputs = list(
        space = list(required = TRUE, must_be_2d = FALSE, dims_min = 2)
      ),
      params = list(
        list(name = "dims", type = "int_range", default = "1:30",
             help = "Which dimensions of the space to use (1-indexed)."),
        list(name = "k", type = "int", default = 30, min = 5, max = 200,
             help = "Number of neighbors for kNN graph."),
        list(name = "resolution", type = "dbl", default = 1.0, min = 0.01, max = 10,
             help = "Leiden resolution parameter."),
        list(name = "seed", type = "int", default = 1,
             help = "Random seed.")
      ),
      interface_produces = list(
        clusters = list(
          kind = "cell_vector",
          description = "Cluster label per cell (categorical cell vector).",
          colorable = TRUE,
          color_type = "categorical",
          label = "Leiden clusters"
        )
      )
    ),
    umap_fit = list(
      op_name = "umap_fit",
      title = "UMAP fit (train model)",
      description = "Fit a UMAP model on a space and store it for future projection.",
      intent = c("umap", "fit"),
      requires = list(space = "space"),
      produces = list(model = "model_ref", space_2d = "space_2d"),
      promotable = c("space_2d", "model"),
      runner = .wb_runner_umap_fit,
      inputs = list(
        space = list(required = TRUE, must_be_2d = FALSE, dims_min = 2)
      ),
      params = list(
        list(name = "dims", type = "int_range", default = NULL, help = "Dims to use (e.g. 2:30)."),
        list(name = "overwrite", type = "bool", default = TRUE, help = "Overwrite existing model/coords.")
      ),
      interface_produces = list(
        model = list(kind = "model_ref", description = "Reference to the fitted UMAP model."),
        space_2d = list(kind = "space_2d", description = "The fitted 2D embedding space id.")
      )
    ),
    umap_transform = list(
      op_name = "umap_transform",
      title = "UMAP transform (project cells)",
      description = "Project cells into an existing UMAP using a stored model.",
      intent = c("projection", "umap"),
      requires = list(model = "model_ref"),
      produces = list(space_2d = "space_2d"),
      promotable = c("space_2d"),
      runner = .wb_runner_umap_transform,
      inputs = list(
        model = list(required = TRUE, kind = "model_ref"),
        in_space = list(required = FALSE, must_be_2d = FALSE, dims_min = 2)
      ),
      params = list(
        list(name = "dims", type = "int_range", default = NULL,
             help = "Dims to use from the input space (e.g. 2:30)."),
        list(name = "overwrite", type = "bool", default = TRUE,
             help = "Overwrite existing projected coordinates for those cells.")
      ),
      interface_produces = list(
        space_2d = list(kind = "space_2d", description = "Projected x/y in the target UMAP space.")
      )
    ),
    addmodulescore = list(
      op_name = "addmodulescore",
      title = "Add module score",
      description = "Seurat-style module scoring using matched control features by expression bin.",
      intent = c("expression", "signature", "score"),
      requires = list(matrix = "matrix"),
      produces = list(module_scores = "cell_vector_family"),
      promotable = c("module_scores"),
      runner = .wb_runner_addmodulescore,
      inputs = list(
        matrix = list(required = TRUE, kind = "matrix")
      ),
      params = list(
        list(name = "features", type = "string_vec_or_list", default = NULL,
             help = "Module feature IDs: character vector or list of vectors."),
        list(name = "pool", type = "string_vec", default = NULL,
             help = "Optional control feature pool; defaults to all matrix features."),
        list(name = "nbin", type = "int", default = 24, min = 2, max = 200,
             help = "Number of expression bins for control matching."),
        list(name = "ctrl", type = "int", default = 100, min = 1, max = 1000,
             help = "Control features sampled per module feature."),
        list(name = "name", type = "string", default = "Module",
             help = "Prefix for module names when features are unnamed."),
        list(name = "seed", type = "int", default = 1,
             help = "Random seed for control sampling.")
      ),
      interface_produces = list(
        module_scores = list(
          kind = "cell_vector_family",
          value_kind = "continuous",
          key = "module",
          description = "Per-cell module scores for one or more signatures."
        )
      )
    ),
    de_wilcox = list(
      op_name = "de_wilcox",
      title = "Differential Expression (Wilcoxon)",
      description = "Wilcoxon rank-sum DE between two cell groups (A vs B).",
      intent = c("de", "markers", "comparison"),
      requires = list(matrix = "matrix"),
      produces = list(de_table = "feature_table"),
      promotable = c("de_table"),
      runner = .wb_runner_de_wilcox,
      inputs = list(
        matrix = list(required = TRUE, kind = "matrix")
      ),
      params = list(
        list(name = "group_a", type = "cell_ids_or_set", default = NULL,
             help = "Group A cells: vector of cell IDs or 'set:<name>'."),
        list(name = "group_b", type = "cell_ids_or_set", default = NULL,
             help = "Group B cells: vector of cell IDs or 'set:<name>'."),
        list(name = "features", type = "string_vec", default = NULL,
             help = "Optional feature subset."),
        list(name = "min_pct", type = "dbl", default = 0, min = 0, max = 1,
             help = "Minimum detection fraction in either group."),
        list(name = "p_adjust_method", type = "string", default = "BH",
             help = "Method passed to p.adjust.")
      ),
      interface_produces = list(
        de_table = list(
          kind = "feature_table",
          description = "Feature-level DE statistics table."
        )
      )
    ),
    markers_topn = list(
      op_name = "markers_topn",
      title = "Top Markers Per Cluster",
      description = "One-vs-rest Wilcoxon marker ranking for each cluster.",
      intent = c("markers", "cluster"),
      requires = list(matrix = "matrix", clusters = "cell_vector"),
      produces = list(markers = "feature_table"),
      promotable = c("markers"),
      runner = .wb_runner_markers_topn,
      inputs = list(
        matrix = list(required = TRUE, kind = "matrix"),
        clusters = list(required = TRUE, kind = "cell_vector")
      ),
      params = list(
        list(name = "features", type = "string_vec", default = NULL,
             help = "Optional feature subset."),
        list(name = "top_n", type = "int", default = 20, min = 1, max = 1000,
             help = "Top markers retained per cluster."),
        list(name = "min_pct", type = "dbl", default = 0.1, min = 0, max = 1,
             help = "Minimum detection fraction in either group."),
        list(name = "p_adjust_method", type = "string", default = "BH",
             help = "Method passed to p.adjust.")
      ),
      interface_produces = list(
        markers = list(
          kind = "feature_table",
          description = "Cluster-marker table with per-feature statistics."
        )
      )
    ),
    knn_pseudobulk = list(
      op_name = "knn_pseudobulk",
      title = "kNN Pseudobulk Around Query Cell(s)",
      description = "Find k nearest neighbors in latent space around query cells and aggregate matrix values.",
      intent = c("pseudobulk", "neighbors", "projection"),
      requires = list(matrix = "matrix", space = "space"),
      produces = list(
        pseudobulk_table = "feature_table",
        neighbor_distance = "cell_vector_family"
      ),
      promotable = c("pseudobulk_table", "neighbor_distance"),
      runner = .wb_runner_knn_pseudobulk,
      inputs = list(
        matrix = list(required = TRUE, kind = "matrix"),
        space = list(required = TRUE, kind = "space")
      ),
      params = list(
        list(name = "query_cells", type = "cell_ids_or_set", default = NULL,
             help = "Query cells: explicit IDs or 'set:<name>'"),
        list(name = "candidate_cells", type = "cell_ids_or_set", default = NULL,
             help = "Optional candidate neighbor pool; defaults to all cells."),
        list(name = "features", type = "string_vec", default = NULL,
             help = "Optional feature subset for pseudobulk output."),
        list(name = "k", type = "int", default = 100, min = 1, max = 50000,
             help = "Nearest neighbors per query cell."),
        list(name = "include_query", type = "bool", default = FALSE,
             help = "Include query cells themselves when they are in candidate pool."),
        list(name = "aggregate", type = "string", default = "sum",
             help = "Aggregation mode: sum or mean.")
      ),
      interface_produces = list(
        pseudobulk_table = list(
          kind = "feature_table",
          description = "Feature-level pseudobulk values keyed by query cell."
        ),
        neighbor_distance = list(
          kind = "cell_vector_family",
          value_kind = "continuous",
          key = "query_cell_id",
          description = "Neighbor distances per query cell."
        )
      )
    ),
    knn_neighbors = list(
      op_name = "knn_neighbors",
      title = "kNN neighbors around query cell(s)",
      description = "Find nearest neighbors in a latent space without requiring matrix aggregation.",
      intent = c("neighbors", "geometry", "projection"),
      requires = list(space = "space"),
      produces = list(
        neighbors = "obs_table",
        neighbor_distance = "cell_vector_family"
      ),
      promotable = c("neighbors", "neighbor_distance"),
      runner = .wb_runner_knn_neighbors,
      inputs = list(
        space = list(required = TRUE, kind = "space")
      ),
      params = list(
        list(name = "query_cells", type = "cell_ids_or_set", default = NULL,
             help = "Query cells: explicit IDs or 'set:<name>'"),
        list(name = "candidate_cells", type = "cell_ids_or_set", default = NULL,
             help = "Optional candidate neighbor pool; defaults to all cells."),
        list(name = "k", type = "int", default = 100, min = 1, max = 50000,
             help = "Nearest neighbors per query cell."),
        list(name = "include_query", type = "bool", default = FALSE,
             help = "Include query cells themselves when they are in candidate pool.")
      ),
      interface_produces = list(
        neighbors = list(
          kind = "obs_table",
          description = "Per-query neighbor table (cell_id, rank, distance)."
        ),
        neighbor_distance = list(
          kind = "cell_vector_family",
          value_kind = "continuous",
          key = "query_cell_id",
          description = "Neighbor distances per query cell."
        )
      )
    ),
    slingshot = list(
      op_name = "slingshot",
      title = "Slingshot trajectory",
      description = "Infer lineage curves and pseudotime from clusters in a 2D space.",
      intent = c("trajectory"),
      requires = list(space_2d = "space_2d", clusters = "cell_vector"),
      produces = list(
        pseudotime = "cell_vector_family",
        curves = "path_2d_family"
      ),
      promotable = c("pseudotime", "curves"),
      runner = .wb_runner_slingshot,
      inputs = list(
        space = list(required = TRUE, must_be_2d = FALSE, dims_min = 2),
        plot_space = list(required = FALSE, must_be_2d = TRUE, dims_min = 2, dims_max = 2),
        clusters = list(required = TRUE, kind = "cell_vector")
      ),
      params = list(
        list(name = "start.clus", type = "string", default = NULL,
             help = "Starting cluster id."),
        list(name = "end.clus", type = "string_vec", default = NULL,
             help = "Ending cluster id(s)."),
        list(name = "exclude_clusters", type = "string_vec", default = character(0),
             help = "Cluster id(s) to exclude before fitting."),
        list(name = "stretch", type = "dbl", default = 2, min = 0, max = 10,
             help = "Slingshot curve stretching."),
        list(name = "reweight", type = "bool", default = TRUE,
             help = "Whether to reweight assignments during fitting.")
      ),
      interface_produces = list(
        pseudotime = list(
          kind = "cell_vector_family",
          value_kind = "continuous",
          key = "lineage_id",
          description = "Lineage-specific pseudotime values per cell."
        ),
        curves = list(
          kind = "path_2d_family",
          key = "lineage_id",
          description = "Lineage curve paths in 2D."
        )
      )
    )
  )
}
