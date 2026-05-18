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

.wb_runner_slingshot_fit <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  .wb_assert(!is.null(resolved$fit_space), "slingshot_fit runner: missing resolved$fit_space.")
  .wb_assert(!is.null(resolved$clusters), "slingshot_fit runner: missing resolved$clusters.")
  .wb_assert(!is.null(effective_cells) && length(effective_cells) > 0,
             "slingshot_fit runner: effective_cells is empty.")

  fit_space_id <- resolved$fit_space$space_id
  clp <- resolved$clusters
  clusters_vec <- as.character(clp$value)
  names(clusters_vec) <- as.character(clp$cell_id)

  raw <- wb_op_slingshot_fit(
    bundle = bundle,
    fit_space_id = fit_space_id,
    clusters = clusters_vec,
    cells = as.character(effective_cells),
    exclude_cells = inputs$exclude_cells %||% NULL,
    include_clusters = inputs$include_clusters %||% NULL,
    exclude_clusters = inputs$exclude_clusters %||% character(0),
    start.clus = inputs$start.clus %||% NULL,
    end.clus = inputs$end.clus %||% NULL,
    stretch = inputs$stretch %||% 2,
    reweight = inputs$reweight %||% TRUE,
    shrink = inputs$shrink %||% 1,
    maxit = inputs$maxit %||% 10
  )

  .wb_assert(is.list(raw) && is.list(raw$outputs),
             "slingshot_fit must return list(outputs=<list>, params=<list>).")
  raw
}

.wb_runner_slingshot_project <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  .wb_assert(!is.null(resolved$model), "slingshot_project runner: missing resolved$model.")
  .wb_assert(!is.null(resolved$plot_space), "slingshot_project runner: missing resolved$plot_space.")

  mr <- resolved$model
  .wb_assert(identical(mr$engine %||% "", "slingshot"),
             "slingshot_project runner: model_ref must have engine='slingshot'.")
  plot_space_id <- resolved$plot_space$space_id

  raw <- wb_op_slingshot_project(
    bundle = bundle,
    slingshot_model = mr,
    plot_space_id = plot_space_id,
    stretch = inputs$stretch %||% NULL,
    shrink = inputs$shrink %||% NULL,
    approx_points = inputs$approx_points %||% 200L
  )

  .wb_assert(is.list(raw) && is.list(raw$outputs),
             "slingshot_project must return list(outputs=<list>, params=<list>).")
  raw
}

.wb_runner_monocle3_fit <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  .wb_assert(!is.null(resolved$fit_space), "monocle3_fit runner: missing resolved$fit_space.")
  .wb_assert(!is.null(effective_cells) && length(effective_cells) > 0,
             "monocle3_fit runner: effective_cells is empty.")

  fit_space_id <- resolved$fit_space$space_id

  dims <- inputs$dims %||% NULL
  if (!is.null(dims)) {
    dims <- suppressWarnings(as.integer(dims))
    .wb_assert(!anyNA(dims), "monocle3_fit runner: dims must be integer-like.")
  }

  raw <- wb_op_monocle3_fit(
    bundle = bundle,
    fit_space_id = fit_space_id,
    cells = as.character(effective_cells),
    dims = dims,
    root_cells = inputs$root_cells %||% NULL,
    root_pr_nodes = inputs$root_pr_nodes %||% NULL,
    k = inputs$k %||% 20,
    cluster_method = inputs$cluster_method %||% "leiden",
    num_iter = inputs$num_iter %||% 2,
    partition_qval = inputs$partition_qval %||% 0.05,
    weight = inputs$weight %||% FALSE,
    resolution = inputs$resolution %||% NULL,
    random_seed = inputs$random_seed %||% 42,
    use_partition = inputs$use_partition %||% FALSE,
    close_loop = inputs$close_loop %||% FALSE,
    verbose = inputs$verbose %||% FALSE
  )

  .wb_assert(is.list(raw) && is.list(raw$outputs),
             "monocle3_fit must return list(outputs=<list>, params=<list>).")
  raw
}

.wb_runner_monocle3_project <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  .wb_assert(!is.null(resolved$model), "monocle3_project runner: missing resolved$model.")
  .wb_assert(!is.null(resolved$plot_space), "monocle3_project runner: missing resolved$plot_space.")

  mr <- resolved$model
  .wb_assert(identical(mr$engine %||% "", "monocle3"),
             "monocle3_project runner: model_ref must have engine='monocle3'.")
  plot_space_id <- resolved$plot_space$space_id

  raw <- wb_op_monocle3_project(
    bundle = bundle,
    monocle3_model = mr,
    plot_space_id = plot_space_id,
    approx_points = inputs$approx_points %||% 200L
  )

  .wb_assert(is.list(raw) && is.list(raw$outputs),
             "monocle3_project must return list(outputs=<list>, params=<list>).")
  raw
}

.wb_runner_palantir_fit <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  .wb_assert(!is.null(resolved$fit_space), "palantir_fit runner: missing resolved$fit_space.")
  .wb_assert(!is.null(effective_cells) && length(effective_cells) > 0,
             "palantir_fit runner: effective_cells is empty.")

  fit_space_id <- resolved$fit_space$space_id
  root_cell <- as.character(inputs$root_cell %||% "")[1]
  .wb_assert(nzchar(root_cell), "palantir_fit runner: root_cell is required.")
  .wb_assert(root_cell %in% as.character(effective_cells),
             "palantir_fit runner: root_cell must be present in effective_cells.")

  dims <- inputs$dims %||% NULL
  if (!is.null(dims)) {
    dims <- suppressWarnings(as.integer(dims))
    .wb_assert(!anyNA(dims), "palantir_fit runner: dims must be integer-like.")
  }

  raw <- wb_op_palantir_fit(
    bundle = bundle,
    fit_space_id = fit_space_id,
    cells = as.character(effective_cells),
    root_cell = root_cell,
    terminal_cells = inputs$terminal_cells %||% NULL,
    dims = dims,
    knn = inputs$knn %||% 30L,
    n_diffusion_components = inputs$n_diffusion_components %||% 10L,
    n_waypoints = inputs$n_waypoints %||% 300L,
    use_early_cell_as_start = inputs$use_early_cell_as_start %||% TRUE,
    seed = inputs$seed %||% 20L,
    cell_set = inputs$cell_set %||% "all"
  )

  .wb_assert(is.list(raw) && is.list(raw$outputs),
             "palantir_fit must return list(outputs=<list>, params=<list>).")
  raw
}

.wb_runner_palantir_project <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  .wb_assert(!is.null(resolved$model), "palantir_project runner: missing resolved$model.")
  .wb_assert(!is.null(resolved$plot_space), "palantir_project runner: missing resolved$plot_space.")

  raw <- wb_op_palantir_project(
    bundle = bundle,
    model = resolved$model,
    plot_space_id = resolved$plot_space$space_id,
    prob_min = inputs$prob_min %||% 0.05,
    smoothness = inputs$smoothness %||% 1.0,
    min_cells_per_branch = inputs$min_cells_per_branch %||% 50L,
    approx_points = inputs$approx_points %||% 200L
  )

  .wb_assert(is.list(raw) && is.list(raw$outputs),
             "palantir_project must return list(outputs=<list>, params=<list>).")
  raw
}

.wb_runner_peakvi_fit <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  .wb_assert(!is.null(resolved$matrix), "peakvi_fit runner: missing resolved$matrix.")
  .wb_assert(!is.null(effective_cells) && length(effective_cells) > 0,
             "peakvi_fit runner: effective_cells is empty.")

  matrix_id <- as.character(resolved$matrix$matrix_id %||% "")[1]
  .wb_assert(nzchar(matrix_id), "peakvi_fit runner: resolved matrix primitive missing matrix_id.")

  raw <- wb_op_peakvi_fit(
    bundle = bundle,
    matrix_id = matrix_id,
    cells = as.character(effective_cells),
    n_latent = inputs$n_latent %||% 20L,
    n_layers = inputs$n_layers %||% 2L,
    n_hidden = inputs$n_hidden %||% 256L,
    dropout = inputs$dropout %||% 0.2,
    batch_key = inputs$batch_key %||% NULL,
    max_epochs = inputs$max_epochs %||% 500L,
    lr = inputs$lr %||% 1e-3,
    early_stopping = inputs$early_stopping %||% TRUE,
    seed = inputs$seed %||% 1L,
    use_gpu = inputs$use_gpu %||% FALSE,
    space_id_out = inputs$space_id_out %||% "peakvi_space",
    cell_set = inputs$cell_set %||% "all"
  )

  .wb_assert(is.list(raw) && is.list(raw$outputs),
             "peakvi_fit must return list(outputs=<list>, params=<list>).")
  raw
}

.wb_runner_peakvi_project <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  .wb_assert(!is.null(resolved$matrix), "peakvi_project runner: missing resolved$matrix.")
  .wb_assert(!is.null(resolved$model), "peakvi_project runner: missing resolved$model.")
  .wb_assert(!is.null(effective_cells) && length(effective_cells) > 0,
             "peakvi_project runner: effective_cells is empty.")
  .wb_assert(identical(as.character(resolved$model$engine %||% "")[1], "peakvi"),
             "peakvi_project runner: model_ref must have engine='peakvi'.")

  matrix_id <- as.character(resolved$matrix$matrix_id %||% "")[1]
  .wb_assert(nzchar(matrix_id), "peakvi_project runner: resolved matrix primitive missing matrix_id.")

  raw <- wb_op_peakvi_project(
    bundle = bundle,
    peakvi_model = resolved$model,
    matrix_id = matrix_id,
    cells = as.character(effective_cells),
    batch_key = inputs$batch_key %||% NULL,
    use_gpu = inputs$use_gpu %||% FALSE,
    space_id_out = inputs$space_id_out %||% "peakvi_project_space"
  )

  .wb_assert(is.list(raw) && is.list(raw$outputs),
             "peakvi_project must return list(outputs=<list>, params=<list>).")
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

.wb_runner_ucell <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  .wb_assert(!is.null(resolved$matrix), "ucell runner: missing resolved$matrix.")
  .wb_assert(!is.null(effective_cells) && length(effective_cells) > 0,
             "ucell runner: effective_cells is empty.")
  .wb_assert(!is.null(inputs$features),
             "ucell runner: inputs$features is required.")

  matrix_id <- resolved$matrix$matrix_id
  .wb_assert(is.character(matrix_id) && length(matrix_id) == 1 && nzchar(matrix_id),
             "ucell runner: resolved matrix primitive missing matrix_id.")

  signatures <- .wb_ucell_normalize_signatures(
    features = inputs$features,
    name = inputs$name %||% "Signature"
  )
  missing_features_policy <- inputs$missing_features_policy %||% "drop"
  sig_meta <- .wb_ucell_signature_meta(
    bundle = bundle,
    matrix_id = matrix_id,
    signatures = signatures,
    missing_features_policy = missing_features_policy
  )

  run_one <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
    wb_op_ucell(
      bundle = bundle,
      matrix_id = matrix_id,
      features = inputs$features,
      cells = as.character(effective_cells),
      name = inputs$name %||% "Signature",
      max_rank = inputs$max_rank %||% 1500L,
      ncores = inputs$ncores %||% 1L,
      parallel_backend = inputs$parallel_backend %||% "auto",
      missing_features_policy = inputs$missing_features_policy %||% "drop"
    )
  }

  chunk_size <- suppressWarnings(as.integer(inputs$chunk_size %||% NA_integer_)[1])
  if (is.finite(chunk_size) && chunk_size > 0L && length(effective_cells) > chunk_size) {
    raw_chunked <- .wb_run_op_in_chunks(
      bundle = bundle,
      resolved = resolved,
      effective_cells = as.character(effective_cells),
      inputs = inputs,
      runner = run_one,
      chunk_axis = "cells",
      chunk_size = chunk_size,
      merge_spec = list(
        signature_scores = "row_bind_cell_vector_family"
      ),
      context = list(
        signature_scores = list(
          cell_order = as.character(effective_cells),
          key_order = names(signatures)
        )
      )
    )

    raw <- list(
      outputs = list(
        signature_scores = raw_chunked$outputs$signature_scores,
        signature_summary = .wb_ucell_summary_prim(
          sig_meta = sig_meta,
          score_prim = raw_chunked$outputs$signature_scores,
          matrix_id = matrix_id,
          missing_features_policy = missing_features_policy
        )
      ),
      params = list(
        matrix_id = matrix_id,
        n_signatures = length(signatures),
        signature_names = names(signatures),
        n_cells = length(effective_cells),
        max_rank = as.integer(inputs$max_rank %||% 1500L),
        ncores = as.integer(inputs$ncores %||% 1L),
        parallel_backend = as.character(inputs$parallel_backend %||% "auto")[1],
        missing_features_policy = as.character(missing_features_policy)[1],
        chunking = raw_chunked$params$chunking
      )
    )
  } else {
    raw <- run_one(
      bundle = bundle,
      resolved = resolved,
      effective_cells = effective_cells,
      inputs = inputs
    )
  }

  .wb_assert(is.list(raw) && is.list(raw$outputs),
             "ucell must return list(outputs=<list>, params=<list>).")
  raw
}

.wb_runner_chromvar <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  .wb_assert(!is.null(resolved$matrix), "chromvar runner: missing resolved$matrix.")
  .wb_assert(!is.null(effective_cells) && length(effective_cells) > 1,
             "chromvar runner: effective_cells must contain at least 2 cells.")

  matrix_id <- resolved$matrix$matrix_id
  .wb_assert(is.character(matrix_id) && length(matrix_id) == 1 && nzchar(matrix_id),
             "chromvar runner: resolved matrix primitive missing matrix_id.")

  raw <- wb_op_chromvar(
    bundle = bundle,
    matrix_id = matrix_id,
    cells = as.character(effective_cells),
    motif_library = inputs$motif_library,
    motifs = inputs$motifs %||% NULL,
    motif_match_set = inputs$motif_match_set %||% NULL,
    min_motif_peaks = inputs$min_motif_peaks %||% 10L,
    max_motif_peaks = inputs$max_motif_peaks %||% NULL,
    motif_p_cutoff = inputs$motif_p_cutoff %||% 5e-05,
    motif_w = inputs$motif_w %||% 7L,
    seqlevels_mode = inputs$seqlevels_mode %||% "standard",
    seqlevels_include = inputs$seqlevels_include %||% NULL,
    seqlevels_exclude = inputs$seqlevels_exclude %||% NULL,
    background_iterations = inputs$background_iterations %||% 50L,
    background_w = inputs$background_w %||% 0.1,
    background_bs = inputs$background_bs %||% 50L
  )

  .wb_assert(is.list(raw) && is.list(raw$outputs),
             "chromvar must return list(outputs=<list>, params=<list>).")
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

.wb_runner_pathway_enrich <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  .wb_assert(!is.null(resolved$matrix), "pathway_enrich runner: missing resolved$matrix.")
  .wb_assert(!is.null(resolved$feature_table), "pathway_enrich runner: missing resolved$feature_table.")
  .wb_assert(!is.null(inputs$namespace), "pathway_enrich runner: inputs$namespace is required.")

  matrix_id <- resolved$matrix$matrix_id
  ft <- resolved$feature_table$table
  .wb_assert(is.data.frame(ft), "pathway_enrich runner: resolved feature_table has no data.frame table payload.")

  raw <- wb_op_pathway_enrich(
    bundle = bundle,
    matrix_id = matrix_id,
    feature_table = ft,
    namespace = as.character(inputs$namespace)[1],
    feature_col = inputs$feature_col %||% "feature_id",
    p_adj_col = inputs$p_adj_col %||% "p_val_adj",
    p_adj_max = inputs$p_adj_max %||% 0.05,
    lfc_col = inputs$lfc_col %||% "avg_log1p_fc",
    direction = inputs$direction %||% "any",
    lfc_min_abs = inputs$lfc_min_abs %||% 0,
    lfc_min = inputs$lfc_min %||% 0.25,
    min_set_size = inputs$min_set_size %||% 5,
    max_set_size = inputs$max_set_size %||% 5000,
    p_adjust_method = inputs$p_adjust_method %||% "BH"
  )

  .wb_assert(is.list(raw) && is.list(raw$outputs),
             "pathway_enrich must return list(outputs=<list>, params=<list>).")
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

.wb_runner_cell_suffix_label <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  raw <- wb_op_cell_suffix_label(
    bundle = bundle,
    cells = as.character(effective_cells),
    sep = inputs$sep %||% "-",
    mapping = inputs$mapping %||% NULL,
    default_label = inputs$default_label %||% "UNKNOWN"
  )
  .wb_assert(is.list(raw) && is.list(raw$outputs),
             "cell_suffix_label must return list(outputs=<list>, params=<list>).")
  raw
}

.wb_runner_cell_vector_assoc <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  .wb_assert(!is.null(resolved$vector_cont), "cell_vector_assoc runner: missing resolved$vector_cont.")
  .wb_assert(!is.null(resolved$vector_group), "cell_vector_assoc runner: missing resolved$vector_group.")

  vc <- resolved$vector_cont
  vg <- resolved$vector_group
  x <- suppressWarnings(as.numeric(vc$value))
  names(x) <- as.character(vc$cell_id)
  g <- as.character(vg$value)
  names(g) <- as.character(vg$cell_id)

  keep <- intersect(as.character(effective_cells), intersect(names(x), names(g)))
  x <- x[keep]
  g <- g[keep]

  raw <- wb_op_cell_vector_assoc(
    vector_cont = x,
    vector_group = g,
    min_n_per_group = inputs$min_n_per_group %||% 3
  )

  .wb_assert(is.list(raw) && is.list(raw$outputs),
             "cell_vector_assoc must return list(outputs=<list>, params=<list>).")
  raw
}

.wb_runner_cell_vector_compare <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  .wb_assert(!is.null(resolved$a), "cell_vector_compare runner: missing resolved$a.")
  .wb_assert(!is.null(resolved$b), "cell_vector_compare runner: missing resolved$b.")

  raw <- wb_op_cell_vector_compare(
    a = resolved$a,
    b = resolved$b,
    cells = as.character(effective_cells),
    compare_space = inputs$compare_space %||% "rank",
    ties_method = inputs$ties_method %||% "average",
    signal_a = inputs$signal_a %||% "a",
    signal_b = inputs$signal_b %||% "b"
  )

  .wb_assert(is.list(raw) && is.list(raw$outputs),
             "cell_vector_compare must return list(outputs=<list>, params=<list>).")
  raw
}

.wb_runner_cell_vector_family_reduce <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  .wb_assert(!is.null(resolved$signal), "cell_vector_family_reduce runner: missing resolved$signal.")

  sig <- resolved$signal
  keep <- intersect(as.character(sig$cell_id), as.character(effective_cells))
  ii <- as.character(sig$cell_id) %in% keep
  sig_use <- wb_prim_cell_vector_family(
    key = as.character(sig$key[ii]),
    cell_id = as.character(sig$cell_id[ii]),
    value = as.numeric(sig$value[ii]),
    value_type = as.character(sig$value_type %||% "continuous")[1]
  )

  raw <- wb_op_cell_vector_family_reduce(
    signal = sig_use,
    signal_keys = inputs$signal_keys %||% NULL,
    rule = inputs$rule %||% "argmax",
    min_score = inputs$min_score %||% NULL,
    min_margin = inputs$min_margin %||% NULL,
    unknown_label = inputs$unknown_label %||% "unknown",
    ties = inputs$ties %||% "unknown",
    tie_tol = inputs$tie_tol %||% 1e-08
  )

  .wb_assert(is.list(raw) && is.list(raw$outputs),
             "cell_vector_family_reduce must return list(outputs=<list>, params=<list>).")
  raw
}

.wb_runner_cell_vector_family_calibrate <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  .wb_assert(!is.null(resolved$signal), "cell_vector_family_calibrate runner: missing resolved$signal.")

  sig <- resolved$signal
  keep <- intersect(as.character(sig$cell_id), as.character(effective_cells))
  ii <- as.character(sig$cell_id) %in% keep
  sig_use <- wb_prim_cell_vector_family(
    key = as.character(sig$key[ii]),
    cell_id = as.character(sig$cell_id[ii]),
    value = as.numeric(sig$value[ii]),
    value_type = as.character(sig$value_type %||% "continuous")[1]
  )

  raw <- wb_op_cell_vector_family_calibrate(
    signal = sig_use,
    signal_keys = inputs$signal_keys %||% NULL,
    method = inputs$method %||% "percentile",
    center = inputs$center %||% TRUE,
    scale = inputs$scale %||% TRUE,
    ties_method = inputs$ties_method %||% "average",
    na_rm = inputs$na_rm %||% TRUE
  )

  .wb_assert(is.list(raw) && is.list(raw$outputs),
             "cell_vector_family_calibrate must return list(outputs=<list>, params=<list>).")
  raw
}

.wb_runner_cell_vector_family_qc <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  .wb_assert(!is.null(resolved$signal), "cell_vector_family_qc runner: missing resolved$signal.")

  sig <- resolved$signal
  keep <- intersect(as.character(sig$cell_id), as.character(effective_cells))
  ii <- as.character(sig$cell_id) %in% keep
  sig_use <- wb_prim_cell_vector_family(
    key = as.character(sig$key[ii]),
    cell_id = as.character(sig$cell_id[ii]),
    value = as.numeric(sig$value[ii]),
    value_type = as.character(sig$value_type %||% "continuous")[1]
  )

  grouping_use <- NULL
  if (!is.null(resolved$grouping)) {
    grp <- resolved$grouping
    keep_grp <- intersect(as.character(grp$cell_id), keep)
    gi <- as.character(grp$cell_id) %in% keep_grp
    gx <- grp$value[gi]
    names(gx) <- as.character(grp$cell_id[gi])
    grouping_use <- wb_prim_cell_vector(
      gx,
      value_type = as.character(grp$value_type %||% "categorical")[1]
    )
  }

  raw <- wb_op_cell_vector_family_qc(
    signal = sig_use,
    grouping = grouping_use,
    signal_keys = inputs$signal_keys %||% NULL,
    correlation_methods = inputs$correlation_methods %||% c("pearson", "spearman"),
    tie_tol = inputs$tie_tol %||% 1e-08
  )

  .wb_assert(is.list(raw) && is.list(raw$outputs),
             "cell_vector_family_qc must return list(outputs=<list>, params=<list>).")
  raw
}

.wb_runner_feature_trend_spearman <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  .wb_assert(!is.null(resolved$matrix), "feature_trend_spearman runner: missing resolved$matrix.")
  .wb_assert(!is.null(resolved$pseudotime), "feature_trend_spearman runner: missing resolved$pseudotime.")

  matrix_id <- resolved$matrix$matrix_id
  ptp <- resolved$pseudotime
  pt <- suppressWarnings(as.numeric(ptp$value))
  names(pt) <- as.character(ptp$cell_id)
  features_use <- inputs$features %||% wb_feature_ids(bundle, matrix_id = matrix_id)
  features_use <- as.character(features_use)
  features_use <- features_use[nzchar(features_use)]
  .wb_assert(length(features_use) > 0L, "feature_trend_spearman runner: no features selected.")

  run_one <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
    chunk_feats <- as.character(inputs$features %||% character(0))
    .wb_assert(length(chunk_feats) > 0L, "feature_trend_spearman chunk runner: no features for chunk.")
    wb_op_feature_trend_spearman(
      bundle = bundle,
      matrix_id = matrix_id,
      pseudotime = pt,
      cells = as.character(effective_cells),
      features = chunk_feats,
      min_pct_nonzero = inputs$min_pct_nonzero %||% 0,
      min_sd = inputs$min_sd %||% 0,
      p_adjust_method = inputs$p_adjust_method %||% "BH",
      chunk_size = max(length(chunk_feats), 1L)
    )
  }

  chunk_size <- suppressWarnings(as.integer(inputs$chunk_size %||% 128L)[1])
  if (is.finite(chunk_size) && chunk_size > 0L && length(features_use) > chunk_size) {
    raw_chunked <- .wb_run_op_in_chunks(
      bundle = bundle,
      resolved = resolved,
      effective_cells = as.character(effective_cells),
      inputs = utils::modifyList(inputs, list(features = features_use)),
      runner = run_one,
      chunk_axis = "features",
      chunk_size = chunk_size,
      merge_spec = list(
        trend_table = "row_bind_feature_table"
      ),
      context = list(
        trend_table = list(feature_order = features_use)
      )
    )

    tbl <- raw_chunked$outputs$trend_table$table
    if (nrow(tbl) > 0L && "p_val" %in% colnames(tbl)) {
      tbl$p_val_adj <- stats::p.adjust(tbl$p_val, method = as.character(inputs$p_adjust_method %||% "BH")[1])
      ord <- order(tbl$p_val_adj, -tbl$abs_rho, na.last = TRUE)
      tbl <- tbl[ord, , drop = FALSE]
      rownames(tbl) <- NULL
    }

    chunk_params <- lapply(raw_chunked$chunk_results, `[[`, "params")
    first_params <- chunk_params[[1]]
    raw <- list(
      outputs = list(
        trend_table = wb_prim_feature_table(
          table = tbl,
          table_type = "feature_trend_spearman",
          meta = list(
            matrix_id = matrix_id,
            n_cells_input = as.integer(first_params$n_cells_input %||% NA_integer_),
            n_cells_used = as.integer(first_params$n_cells_used %||% NA_integer_),
            n_features_input = as.integer(length(features_use)),
            n_features_tested = as.integer(nrow(tbl)),
            min_pct_nonzero = as.numeric(inputs$min_pct_nonzero %||% 0),
            min_sd = as.numeric(inputs$min_sd %||% 0),
            p_adjust_method = as.character(inputs$p_adjust_method %||% "BH")[1],
            n_filtered_min_cells = sum(vapply(chunk_params, function(x) as.integer(x$n_filtered_min_cells %||% 0L), integer(1))),
            n_filtered_min_pct_nonzero = sum(vapply(chunk_params, function(x) as.integer(x$n_filtered_min_pct_nonzero %||% 0L), integer(1))),
            n_filtered_min_sd = sum(vapply(chunk_params, function(x) as.integer(x$n_filtered_min_sd %||% 0L), integer(1)))
          )
        )
      ),
      params = list(
        matrix_id = matrix_id,
        n_cells_input = as.integer(first_params$n_cells_input %||% NA_integer_),
        n_cells_used = as.integer(first_params$n_cells_used %||% NA_integer_),
        n_features_input = as.integer(length(features_use)),
        n_features_tested = as.integer(nrow(tbl)),
        min_pct_nonzero = as.numeric(inputs$min_pct_nonzero %||% 0),
        min_sd = as.numeric(inputs$min_sd %||% 0),
        p_adjust_method = as.character(inputs$p_adjust_method %||% "BH")[1],
        n_filtered_min_cells = sum(vapply(chunk_params, function(x) as.integer(x$n_filtered_min_cells %||% 0L), integer(1))),
        n_filtered_min_pct_nonzero = sum(vapply(chunk_params, function(x) as.integer(x$n_filtered_min_pct_nonzero %||% 0L), integer(1))),
        n_filtered_min_sd = sum(vapply(chunk_params, function(x) as.integer(x$n_filtered_min_sd %||% 0L), integer(1))),
        chunking = raw_chunked$params$chunking
      )
    )
  } else {
    raw <- wb_op_feature_trend_spearman(
      bundle = bundle,
      matrix_id = matrix_id,
      pseudotime = pt,
      cells = as.character(effective_cells),
      features = features_use,
      min_pct_nonzero = inputs$min_pct_nonzero %||% 0,
      min_sd = inputs$min_sd %||% 0,
      p_adjust_method = inputs$p_adjust_method %||% "BH",
      chunk_size = inputs$chunk_size %||% 128L
    )
  }

  .wb_assert(is.list(raw) && is.list(raw$outputs),
             "feature_trend_spearman must return list(outputs=<list>, params=<list>).")
  raw
}

.wb_runner_trajectory_de <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  .wb_assert(!is.null(resolved$matrix), "trajectory_de runner: missing resolved$matrix.")
  .wb_assert(!is.null(resolved$model), "trajectory_de runner: missing resolved$model.")

  matrix_id <- resolved$matrix$matrix_id
  model <- resolved$model

  raw <- wb_op_trajectory_de(
    bundle = bundle,
    matrix_id = matrix_id,
    model = model,
    cells = as.character(effective_cells),
    lineage = inputs$lineage %||% NULL,
    feature_set = inputs$feature_set %||% NULL,
    features = inputs$features %||% NULL,
    test = inputs$test %||% "spearman",
    min_pct_nonzero = inputs$min_pct_nonzero %||% 0,
    min_sd = inputs$min_sd %||% 0,
    p_adjust_method = inputs$p_adjust_method %||% "BH",
    chunk_size = inputs$chunk_size %||% 128L
  )

  .wb_assert(is.list(raw) && is.list(raw$outputs),
             "trajectory_de must return list(outputs=<list>, params=<list>).")
  raw
}

.wb_runner_trajectory_smooth <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  .wb_assert(!is.null(resolved$matrix), "trajectory_smooth runner: missing resolved$matrix.")
  .wb_assert(!is.null(resolved$model), "trajectory_smooth runner: missing resolved$model.")

  raw <- wb_op_trajectory_smooth(
    bundle = bundle,
    matrix_id = resolved$matrix$matrix_id,
    model = resolved$model,
    cells = as.character(effective_cells),
    lineage = inputs$lineage %||% NULL,
    feature_set = inputs$feature_set %||% NULL,
    features = inputs$features %||% NULL,
    n_bins = inputs$n_bins %||% 50L,
    summary_fun = inputs$summary_fun %||% "mean",
    min_cells_per_bin = inputs$min_cells_per_bin %||% 5L,
    chunk_size = inputs$chunk_size %||% 128L
  )

  .wb_assert(is.list(raw) && is.list(raw$outputs),
             "trajectory_smooth must return list(outputs=<list>, params=<list>).")
  raw
}

.wb_runner_trajectory_branch_compare <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  .wb_assert(!is.null(resolved$matrix), "trajectory_branch_compare runner: missing resolved$matrix.")
  .wb_assert(!is.null(resolved$pseudotime), "trajectory_branch_compare runner: missing resolved$pseudotime.")
  .wb_assert(!is.null(resolved$branch_membership), "trajectory_branch_compare runner: missing resolved$branch_membership.")

  raw <- wb_op_trajectory_branch_compare(
    bundle = bundle,
    matrix_id = resolved$matrix$matrix_id,
    pseudotime = resolved$pseudotime,
    branch_membership = resolved$branch_membership,
    branch_a = inputs$branch_a %||% NULL,
    branch_b = inputs$branch_b %||% NULL,
    cells = as.character(effective_cells),
    feature_set = inputs$feature_set %||% NULL,
    features = inputs$features %||% NULL,
    min_pct = inputs$min_pct %||% 0,
    p_adjust_method = inputs$p_adjust_method %||% "BH"
  )

  .wb_assert(is.list(raw) && is.list(raw$outputs),
             "trajectory_branch_compare must return list(outputs=<list>, params=<list>).")
  raw
}

.wb_runner_trajectory_signature_smooth <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  .wb_assert(!is.null(resolved$matrix), "trajectory_signature_smooth runner: missing resolved$matrix.")
  .wb_assert(!is.null(resolved$model), "trajectory_signature_smooth runner: missing resolved$model.")

  raw <- wb_op_trajectory_signature_smooth(
    bundle = bundle,
    matrix_id = resolved$matrix$matrix_id,
    model = resolved$model,
    feature_set = inputs$feature_set,
    cells = as.character(effective_cells),
    lineage = inputs$lineage %||% NULL,
    score_method = inputs$score_method %||% "mean",
    n_bins = inputs$n_bins %||% 50L,
    summary_fun = inputs$summary_fun %||% "mean",
    min_cells_per_bin = inputs$min_cells_per_bin %||% 5L
  )

  .wb_assert(is.list(raw) && is.list(raw$outputs),
             "trajectory_signature_smooth must return list(outputs=<list>, params=<list>).")
  raw
}

.wb_runner_trajectory_geneset_dynamics <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  .wb_assert(!is.null(resolved$matrix), "trajectory_geneset_dynamics runner: missing resolved$matrix.")
  .wb_assert(!is.null(resolved$model), "trajectory_geneset_dynamics runner: missing resolved$model.")

  raw <- wb_op_trajectory_geneset_dynamics(
    bundle = bundle,
    matrix_id = resolved$matrix$matrix_id,
    model = resolved$model,
    namespace = inputs$namespace,
    cells = as.character(effective_cells),
    lineage = inputs$lineage %||% NULL,
    feature_sets = inputs$feature_sets %||% NULL,
    score_method = inputs$score_method %||% "mean",
    n_bins = inputs$n_bins %||% 50L,
    summary_fun = inputs$summary_fun %||% "mean",
    min_cells_per_bin = inputs$min_cells_per_bin %||% 5L,
    min_set_size = inputs$min_set_size %||% 5L,
    max_set_size = inputs$max_set_size %||% 5000L,
    top_n = inputs$top_n %||% 50L,
    on_off_min_delta = inputs$on_off_min_delta %||% 0,
    monotonic_min_abs_rho = inputs$monotonic_min_abs_rho %||% 0.5,
    top_driver_genes = inputs$top_driver_genes %||% 5L,
    pseudotime_direction = inputs$pseudotime_direction %||% "as_is",
    start_label = inputs$start_label %||% NULL,
    end_label = inputs$end_label %||% NULL,
    min_amplitude = inputs$min_amplitude %||% 0,
    min_bins_observed = inputs$min_bins_observed %||% 5L,
    min_features_detected = inputs$min_features_detected %||% 1L,
    min_detected_fraction = inputs$min_detected_fraction %||% 0,
    smooth_method = inputs$smooth_method %||% "none",
    loess_span = inputs$loess_span %||% 0.5,
    bootstrap_n = inputs$bootstrap_n %||% 0L,
    bootstrap_seed = inputs$bootstrap_seed %||% 1L,
    ci_level = inputs$ci_level %||% 0.95,
    class_min_amplitude = inputs$class_min_amplitude %||% 0
  )

  .wb_assert(is.list(raw) && is.list(raw$outputs),
             "trajectory_geneset_dynamics must return list(outputs=<list>, params=<list>).")
  raw
}

.wb_runner_trajectory_route_smooth <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  .wb_assert(!is.null(resolved$matrix), "trajectory_route_smooth runner: missing resolved$matrix.")
  .wb_assert(!is.null(resolved$pseudotime), "trajectory_route_smooth runner: missing resolved$pseudotime.")
  .wb_assert(!is.null(resolved$branch_membership), "trajectory_route_smooth runner: missing resolved$branch_membership.")

  raw <- wb_op_trajectory_route_smooth(
    bundle = bundle,
    matrix_id = as.character(resolved$matrix$matrix_id)[1],
    pseudotime = resolved$pseudotime,
    branch_membership = resolved$branch_membership,
    route_key = as.character(inputs$route_key %||% "")[1],
    cells = effective_cells,
    feature_set = inputs$feature_set %||% NULL,
    features = inputs$features %||% NULL,
    n_bins = inputs$n_bins %||% 50L,
    summary_fun = inputs$summary_fun %||% "mean",
    min_cells_per_bin = inputs$min_cells_per_bin %||% 5L,
    weight_mode = inputs$weight_mode %||% "probability",
    prob_min = inputs$prob_min %||% 0,
    chunk_size = inputs$chunk_size %||% 128L
  )

  .wb_assert(is.list(raw) && is.list(raw$outputs),
             "trajectory_route_smooth must return list(outputs=<list>, params=<list>).")
  raw
}

.wb_runner_trajectory_vector_smooth <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  .wb_assert(!is.null(resolved$signal), "trajectory_vector_smooth runner: missing resolved$signal.")
  .wb_assert(!is.null(resolved$model), "trajectory_vector_smooth runner: missing resolved$model.")

  raw <- wb_op_trajectory_vector_smooth(
    bundle = bundle,
    signal = resolved$signal,
    model = resolved$model,
    cells = as.character(effective_cells),
    lineage = inputs$lineage %||% NULL,
    signal_keys = inputs$signal_keys %||% NULL,
    n_bins = inputs$n_bins %||% 50L,
    summary_fun = inputs$summary_fun %||% "mean",
    min_cells_per_bin = inputs$min_cells_per_bin %||% 5L
  )

  .wb_assert(is.list(raw) && is.list(raw$outputs),
             "trajectory_vector_smooth must return list(outputs=<list>, params=<list>).")
  raw
}

.wb_runner_space_path_define <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  .wb_assert(!is.null(resolved$space), "space_path_define runner: missing resolved$space.")
  .wb_assert(!is.null(effective_cells) && length(effective_cells) > 0,
             "space_path_define runner: effective_cells is empty.")

  raw <- wb_op_space_path_define(
    bundle = bundle,
    space_id = as.character(resolved$space$space_id)[1],
    checkpoint_sets = as.character(inputs$checkpoint_sets %||% character(0)),
    cells = as.character(effective_cells),
    fit_mode = as.character(inputs$fit_mode %||% "linear")[1],
    checkpoint_summary = as.character(inputs$checkpoint_summary %||% "centroid")[1],
    n_path_points = inputs$n_path_points %||% NULL,
    smooth_k = inputs$smooth_k %||% 30L,
    smooth_n_iter = inputs$smooth_n_iter %||% 2L,
    smooth_weight = as.character(inputs$smooth_weight %||% "inverse_distance")[1],
    path_id_out = as.character(inputs$path_id_out %||% "space_path")[1]
  )

  .wb_assert(is.list(raw) && is.list(raw$outputs),
             "space_path_define must return list(outputs=<list>, params=<list>).")
  raw
}

.wb_runner_space_path_score <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  .wb_assert(!is.null(resolved$space), "space_path_score runner: missing resolved$space.")
  .wb_assert(!is.null(resolved$path), "space_path_score runner: missing resolved$path.")
  .wb_assert(!is.null(effective_cells) && length(effective_cells) > 0,
             "space_path_score runner: effective_cells is empty.")

  raw <- wb_op_space_path_score(
    bundle = bundle,
    space_id = as.character(resolved$space$space_id)[1],
    path = resolved$path,
    cells = as.character(effective_cells),
    score_mode = as.character(inputs$score_mode %||% "orthogonal_projection")[1],
    distance_metric = as.character(inputs$distance_metric %||% "euclidean")[1],
    score_prefix = inputs$score_prefix %||% NULL
  )

  .wb_assert(is.list(raw) && is.list(raw$outputs),
             "space_path_score must return list(outputs=<list>, params=<list>).")
  raw
}

.wb_runner_space_path_project_2d <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  .wb_assert(!is.null(resolved$path), "space_path_project_2d runner: missing resolved$path.")
  .wb_assert(!is.null(resolved$plot_space), "space_path_project_2d runner: missing resolved$plot_space.")

  raw <- wb_op_space_path_project_2d(
    bundle = bundle,
    path = resolved$path,
    plot_space_id = as.character(resolved$plot_space$space_id)[1],
    project_mode = as.character(inputs$project_mode %||% "local_interpolation")[1],
    approx_points = inputs$approx_points %||% NULL
  )

  .wb_assert(is.list(raw) && is.list(raw$outputs),
             "space_path_project_2d must return list(outputs=<list>, params=<list>).")
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
    ucell = list(
      op_name = "ucell",
      title = "UCell Signature Scoring",
      description = "Rank-based per-cell signature scoring using the UCell method.",
      intent = c("expression", "signature", "score"),
      requires = list(matrix = "matrix"),
      produces = list(
        signature_scores = "cell_vector_family",
        signature_summary = "obs_table"
      ),
      promotable = c("signature_scores", "signature_summary"),
      chunking = list(
        chunkable = TRUE,
        axis = "cells",
        chunk_size_param = "chunk_size",
        chunk_size_default = 2000L,
        merge = list(
          signature_scores = "row_bind_cell_vector_family",
          signature_summary = "recompute_summary"
        ),
        status = "planned"
      ),
      runner = .wb_runner_ucell,
      inputs = list(
        matrix = list(required = TRUE, kind = "matrix")
      ),
      params = list(
        list(name = "features", type = "string_vec_or_list", default = NULL,
             help = "Signature feature IDs: character vector or list of vectors."),
        list(name = "name", type = "string", default = "Signature",
             help = "Prefix for signature names when features are unnamed."),
        list(name = "max_rank", type = "int", default = 1500L, min = 1, max = 1000000,
             help = "Maximum rank considered by UCell."),
        list(name = "ncores", type = "int", default = 1L, min = 1, max = 1024,
             help = "Number of worker processes requested by UCell."),
        list(name = "parallel_backend", type = "choice", default = "auto",
             choices = c("auto", "serial"),
             help = "Execution backend for UCell. Use 'serial' to avoid socket-based parallel backends on constrained systems."),
        list(name = "chunk_size", type = "int", default = NULL, min = 8, max = 1000000,
             help = "Reserved chunk size hint for future engine-owned cell-axis chunking; currently ignored."),
        list(name = "missing_features_policy", type = "choice", default = "drop",
             choices = c("drop", "error"),
             help = "How to handle signature features missing from the matrix.")
      ),
      interface_produces = list(
        signature_scores = list(
          kind = "cell_vector_family",
          value_kind = "continuous",
          key = "signature",
          description = "Per-cell UCell scores for one or more signatures."
        ),
        signature_summary = list(
          kind = "obs_table",
          description = "Per-signature scoring summary and feature-match diagnostics."
        )
      )
    ),
    cell_vector_family_reduce = list(
      op_name = "cell_vector_family_reduce",
      title = "Reduce Cell Vector Family",
      description = "Compress a cell_vector_family into one categorical cell_vector using explicit reduction and abstention rules.",
      intent = c("label", "reduce", "signal"),
      requires = list(signal = "cell_vector_family"),
      produces = list(
        label = "cell_vector",
        top_score = "cell_vector",
        runner_up_score = "cell_vector",
        score_margin = "cell_vector",
        abstain_reason = "cell_vector",
        decision_table = "obs_table",
        label_summary = "obs_table"
      ),
      promotable = c("label", "top_score", "runner_up_score", "score_margin", "abstain_reason", "decision_table", "label_summary"),
      runner = .wb_runner_cell_vector_family_reduce,
      inputs = list(
        signal = list(required = TRUE, kind = "cell_vector_family")
      ),
      params = list(
        list(name = "signal_keys", type = "string_vec", default = NULL,
             help = "Optional signal-key subset within the cell_vector_family."),
        list(name = "rule", type = "choice", default = "argmax",
             choices = c("argmax"),
             help = "Reduction rule used to choose one label per cell."),
        list(name = "min_score", type = "dbl", default = NULL, min = -1e9, max = 1e9,
             help = "Optional minimum winning score required to emit a non-unknown label."),
        list(name = "min_margin", type = "dbl", default = NULL, min = 0, max = 1e9,
             help = "Optional minimum top-vs-second margin required to emit a non-unknown label."),
        list(name = "unknown_label", type = "string", default = "unknown",
             help = "Fallback label emitted when thresholds or ties abstain."),
        list(name = "ties", type = "choice", default = "unknown",
             choices = c("unknown", "first"),
             help = "How to handle tied top scores."),
        list(name = "tie_tol", type = "dbl", default = 1e-08, min = 0, max = 1,
             help = "Tolerance used when detecting ties.")
      ),
      interface_produces = list(
        label = list(
          kind = "cell_vector",
          value_kind = "categorical",
          description = "Per-cell categorical labels after reducing the signal family."
        ),
        top_score = list(
          kind = "cell_vector",
          value_kind = "continuous",
          description = "Winning score for each cell."
        ),
        runner_up_score = list(
          kind = "cell_vector",
          value_kind = "continuous",
          description = "Second-best score for each cell."
        ),
        score_margin = list(
          kind = "cell_vector",
          value_kind = "continuous",
          description = "Winning minus runner-up score for each cell."
        ),
        abstain_reason = list(
          kind = "cell_vector",
          value_kind = "categorical",
          description = "Per-cell abstention reason (`none`, `tie`, `min_score`, `min_margin`)."
        ),
        decision_table = list(
          kind = "obs_table",
          description = "Per-cell reduction diagnostics including label, scores, margin, and abstention reason."
        ),
        label_summary = list(
          kind = "obs_table",
          description = "Per-label counts and score summaries after reduction."
        )
      )
    ),
    cell_vector_family_calibrate = list(
      op_name = "cell_vector_family_calibrate",
      title = "Calibrate Cell Vector Family",
      description = "Normalize one keyed per-cell signal family within keys so cross-key comparisons become more meaningful.",
      intent = c("signal", "calibrate", "normalize"),
      requires = list(signal = "cell_vector_family"),
      produces = list(
        calibrated_signal = "cell_vector_family",
        calibration_summary = "obs_table"
      ),
      promotable = c("calibrated_signal", "calibration_summary"),
      runner = .wb_runner_cell_vector_family_calibrate,
      inputs = list(
        signal = list(required = TRUE, kind = "cell_vector_family")
      ),
      params = list(
        list(name = "signal_keys", type = "string_vec", default = NULL,
             help = "Optional signal-key subset within the cell_vector_family."),
        list(name = "method", type = "choice", default = "percentile",
             choices = c("percentile", "zscore", "robust_zscore"),
             help = "Calibration method applied independently within each key."),
        list(name = "center", type = "bool", default = TRUE,
             help = "For z-score calibration, subtract the fitted center."),
        list(name = "scale", type = "bool", default = TRUE,
             help = "For z-score calibration, divide by the fitted scale."),
        list(name = "ties_method", type = "choice", default = "average",
             choices = c("average", "first", "random", "max", "min"),
             help = "Rank tie handling for percentile calibration."),
        list(name = "na_rm", type = "bool", default = TRUE,
             help = "Ignore non-finite values when fitting calibration.")
      ),
      interface_produces = list(
        calibrated_signal = list(
          kind = "cell_vector_family",
          value_kind = "continuous",
          key = "signal_key",
          description = "Calibrated per-cell values for each key in the signal family."
        ),
        calibration_summary = list(
          kind = "obs_table",
          description = "Per-key calibration statistics for raw and calibrated values."
        )
      )
    ),
    cell_vector_family_qc = list(
      op_name = "cell_vector_family_qc",
      title = "QC Cell Vector Family",
      description = "Compute per-key and pairwise diagnostics for one keyed per-cell signal family.",
      intent = c("signal", "qc", "diagnostics"),
      requires = list(signal = "cell_vector_family"),
      optional_requires = list(grouping = "cell_vector"),
      produces = list(
        key_summary = "obs_table",
        pairwise_summary = "obs_table",
        group_summary = "obs_table"
      ),
      promotable = c("key_summary", "pairwise_summary", "group_summary"),
      runner = .wb_runner_cell_vector_family_qc,
      inputs = list(
        signal = list(required = TRUE, kind = "cell_vector_family"),
        grouping = list(required = FALSE, kind = "cell_vector")
      ),
      params = list(
        list(name = "signal_keys", type = "string_vec", default = NULL,
             help = "Optional signal-key subset within the cell_vector_family."),
        list(name = "correlation_methods", type = "string_vec", default = c("pearson", "spearman"),
             help = "Pairwise correlation methods to compute between keys."),
        list(name = "tie_tol", type = "dbl", default = 1e-08, min = 0, max = 1,
             help = "Tolerance used when counting tied top-key winners.")
      ),
      interface_produces = list(
        key_summary = list(
          kind = "obs_table",
          description = "Per-key QC summaries including score distribution, finite coverage, and winner frequencies."
        ),
        pairwise_summary = list(
          kind = "obs_table",
          description = "Pairwise key relationships including overlap counts and correlations."
        ),
        group_summary = list(
          kind = "obs_table",
          description = "Per-group per-key QC summaries when an optional grouping vector is supplied."
        )
      )
    ),
    chromvar = list(
      op_name = "chromvar",
      title = "chromVAR deviations",
      description = "Bias-corrected chromVAR deviations on a peak matrix using genome-backed GC bias and motif matching against a JASPAR PWM catalog.",
      intent = c("atac", "motif", "signature", "score"),
      requires = list(matrix = "matrix"),
      produces = list(
        deviation_z = "cell_vector_family",
        deviation_raw = "cell_vector_family",
        motif_summary = "obs_table"
      ),
      promotable = c("deviation_z", "deviation_raw", "motif_summary"),
      runner = .wb_runner_chromvar,
      inputs = list(
        matrix = list(required = TRUE, kind = "matrix")
      ),
      params = list(
        list(name = "motif_library", type = "string", default = NULL,
             help = "Canonical motif-library key from the motif registry."),
        list(name = "motifs", type = "string_vec", default = NULL,
             help = "Optional motif-key subset within motif_library."),
        list(name = "motif_match_set", type = "string", default = NULL,
             help = "Optional canonical motif-match-set key to reuse cached motif-to-peak matches."),
        list(name = "min_motif_peaks", type = "int", default = 10L, min = 1, max = 100000,
             help = "Minimum number of matched peaks per retained motif."),
        list(name = "max_motif_peaks", type = "int", default = NULL, min = 1, max = 1000000,
             help = "Optional maximum number of matched peaks per retained motif."),
        list(name = "motif_p_cutoff", type = "dbl", default = 5e-05, min = 0, max = 1,
             help = "Motifmatchr p-value cutoff."),
        list(name = "motif_w", type = "int", default = 7L, min = 1, max = 100,
             help = "Motifmatchr background window width."),
        list(name = "seqlevels_mode", type = "choice", default = "standard", choices = c("standard", "all"),
             help = "Seqlevel policy; standard chromosomes are the default."),
        list(name = "seqlevels_include", type = "string_vec", default = NULL,
             help = "Optional explicit seqlevels to keep after applying seqlevels_mode."),
        list(name = "seqlevels_exclude", type = "string_vec", default = NULL,
             help = "Optional explicit seqlevels to drop after applying seqlevels_mode."),
        list(name = "background_iterations", type = "int", default = 50L, min = 1, max = 1000,
             help = "Number of chromVAR background iterations."),
        list(name = "background_w", type = "dbl", default = 0.1, min = 0, max = 10,
             help = "Background peak matching window width."),
        list(name = "background_bs", type = "int", default = 50L, min = 2, max = 1000,
             help = "Background peak matching bin count.")
      ),
      interface_produces = list(
        deviation_z = list(
          kind = "cell_vector_family",
          value_kind = "continuous",
          key = "motif",
          description = "Per-cell chromVAR z-scores keyed by motif."
        ),
        deviation_raw = list(
          kind = "cell_vector_family",
          value_kind = "continuous",
          key = "motif",
          description = "Per-cell raw chromVAR deviations keyed by motif."
        ),
        motif_summary = list(
          kind = "obs_table",
          description = "Per-motif chromVAR summary statistics."
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
    pathway_enrich = list(
      op_name = "pathway_enrich",
      title = "Pathway Enrichment (Namespace)",
      description = "Hypergeometric enrichment against all feature sets in a namespace.",
      intent = c("pathway", "enrichment"),
      requires = list(matrix = "matrix", feature_table = "feature_table"),
      produces = list(pathways = "obs_table"),
      promotable = c("pathways"),
      runner = .wb_runner_pathway_enrich,
      inputs = list(
        matrix = list(required = TRUE, kind = "matrix"),
        feature_table = list(
          required = TRUE,
          kind = "feature_table",
          label = "Input feature table (e.g. DE/marker results)"
        )
      ),
      params = list(
        list(name = "namespace", type = "string", default = NULL,
             help = "Feature-set namespace from wb_feature_sets() (e.g. bcell_gsea)."),
        list(name = "feature_col", type = "string", default = "feature_id",
             help = "Column in input feature table containing feature IDs (usually feature_id)."),
        list(name = "p_adj_col", type = "string", default = "p_val_adj",
             help = "Adjusted p-value column used for query filtering."),
        list(name = "p_adj_max", type = "dbl", default = 0.05, min = 0, max = 1,
             help = "Maximum adjusted p-value for query features."),
        list(name = "lfc_col", type = "string", default = "avg_log1p_fc",
             help = "Effect-size column used for directional filtering."),
        list(name = "direction", type = "string", default = "any",
             help = "Directional filter: any|up|down."),
        list(name = "lfc_min_abs", type = "dbl", default = 0, min = 0,
             help = "Minimum |effect| when direction='any'."),
        list(name = "lfc_min", type = "dbl", default = 0.25, min = 0,
             help = "Minimum effect for direction='up'/'down'."),
        list(name = "min_set_size", type = "int", default = 5, min = 1,
             help = "Minimum pathway size to test."),
        list(name = "max_set_size", type = "int", default = 5000, min = 1,
             help = "Maximum pathway size to test."),
        list(name = "p_adjust_method", type = "string", default = "BH",
             help = "Method passed to p.adjust.")
      ),
      interface_produces = list(
        pathways = list(
          kind = "obs_table",
          description = "Pathway enrichment statistics for one namespace."
        )
      )
    ),
    cell_suffix_label = list(
      op_name = "cell_suffix_label",
      title = "Cell Labels From ID Suffix",
      description = "Build a categorical cell vector by parsing cell_id suffix tokens.",
      intent = c("annotation", "metadata"),
      requires = list(),
      produces = list(labels = "cell_vector", label_table = "obs_table"),
      promotable = c("labels", "label_table"),
      runner = .wb_runner_cell_suffix_label,
      inputs = list(),
      params = list(
        list(name = "sep", type = "string", default = "-",
             help = "Separator used in cell IDs before suffix token."),
        list(name = "mapping", type = "string_vec", default = NULL,
             help = "Optional named mapping suffix->label."),
        list(name = "default_label", type = "string", default = "UNKNOWN",
             help = "Fallback label for unmapped suffixes.")
      ),
      interface_produces = list(
        labels = list(
          kind = "cell_vector",
          value_kind = "categorical",
          description = "Categorical label per cell from suffix parsing."
        ),
        label_table = list(
          kind = "obs_table",
          description = "Per-cell suffix/label table."
        )
      )
    ),
    cell_vector_assoc = list(
      op_name = "cell_vector_assoc",
      title = "Cell Vector Association",
      description = "Test whether a continuous cell-level signal differs across groups defined by a categorical cell-level vector.",
      intent = c("statistics", "association", "confounding"),
      requires = list(vector_cont = "cell_vector", vector_group = "cell_vector"),
      produces = list(assoc_summary = "feature_table", group_stats = "obs_table"),
      promotable = c("assoc_summary", "group_stats"),
      runner = .wb_runner_cell_vector_assoc,
      inputs = list(
        vector_cont = list(
          required = TRUE,
          kind = "cell_vector",
          label = "Continuous vector (numeric per cell)",
          help = "Examples: pseudotime, module score, gene-program score."
        ),
        vector_group = list(
          required = TRUE,
          kind = "cell_vector",
          label = "Grouping vector (categorical per cell)",
          help = "Examples: cluster labels, cell type labels, condition labels."
        )
      ),
      params = list(
        list(name = "min_n_per_group", type = "int", default = 3, min = 1, max = 100000,
             help = "Minimum cells per group.")
      ),
      interface_produces = list(
        assoc_summary = list(
          kind = "feature_table",
          description = "Omnibus association test summary (Kruskal/ANOVA)."
        ),
        group_stats = list(
          kind = "obs_table",
          description = "Per-group descriptive statistics."
        )
      )
    ),
    cell_vector_compare = list(
      op_name = "cell_vector_compare",
      title = "Cell Vector Comparison",
      description = "Compare two cell-level signals on their shared cell universe in raw or rank space.",
      intent = c("statistics", "comparison", "signal"),
      requires = list(a = "cell_vector", b = "cell_vector"),
      produces = list(summary = "obs_table", comparison = "obs_table"),
      promotable = c("summary", "comparison"),
      runner = .wb_runner_cell_vector_compare,
      inputs = list(
        a = list(
          required = TRUE,
          kind = "cell_vector",
          label = "Signal A",
          help = "Continuous or rankable numeric signal per cell."
        ),
        b = list(
          required = TRUE,
          kind = "cell_vector",
          label = "Signal B",
          help = "Continuous or rankable numeric signal per cell."
        )
      ),
      params = list(
        list(name = "compare_space", type = "choice", default = "rank",
             choices = c("raw", "rank"),
             help = "Whether to compare original numeric values or cell ranks."),
        list(name = "ties_method", type = "choice", default = "average",
             choices = c("average", "first", "last", "random", "max", "min"),
             help = "Tie handling rule used when compare_space='rank'."),
        list(name = "signal_a", type = "string", default = "a",
             help = "Optional label recorded in the summary table for signal A."),
        list(name = "signal_b", type = "string", default = "b",
             help = "Optional label recorded in the summary table for signal B.")
      ),
      interface_produces = list(
        summary = list(
          kind = "obs_table",
          description = "One-row comparison summary with concordance and delta metrics."
        ),
        comparison = list(
          kind = "obs_table",
          description = "Per-cell comparison table with original values, compared values, and deltas."
        )
      )
    ),
    feature_trend_spearman = list(
      op_name = "feature_trend_spearman",
      title = "Feature Trends vs Continuous Vector",
      description = "Feature-level Spearman trend testing against continuous pseudotime-like vectors.",
      intent = c("trend", "statistics", "trajectory"),
      requires = list(matrix = "matrix", pseudotime = "cell_vector"),
      produces = list(trend_table = "feature_table"),
      promotable = c("trend_table"),
      chunking = list(
        chunkable = TRUE,
        axis = "features",
        chunk_size_param = "chunk_size",
        chunk_size_default = 128L,
        merge = list(
          trend_table = "row_bind_feature_table"
        ),
        status = "implemented_generic"
      ),
      runner = .wb_runner_feature_trend_spearman,
      inputs = list(
        matrix = list(required = TRUE, kind = "matrix"),
        pseudotime = list(required = TRUE, kind = "cell_vector")
      ),
      params = list(
        list(name = "features", type = "string_vec", default = NULL,
             help = "Optional feature subset."),
        list(name = "min_pct_nonzero", type = "dbl", default = 0, min = 0, max = 1,
             help = "Minimum non-zero fraction filter."),
        list(name = "min_sd", type = "dbl", default = 0, min = 0, max = 1e6,
             help = "Minimum per-feature standard deviation filter."),
        list(name = "p_adjust_method", type = "string", default = "BH",
             help = "Method passed to p.adjust."),
        list(name = "chunk_size", type = "int", default = 128, min = 8, max = 4096,
             help = "Chunk size for matrix slicing.")
      ),
      interface_produces = list(
        trend_table = list(
          kind = "feature_table",
          description = "Per-feature trend statistics (rho, p, adjusted p)."
        )
      )
    ),
    trajectory_de = list(
      op_name = "trajectory_de",
      title = "Trajectory DE",
      description = "Lineage-aware feature trend testing against trajectory pseudotime from model_ref.",
      intent = c("trajectory", "trend", "statistics"),
      requires = list(matrix = "matrix", model = "model_ref"),
      produces = list(
        de_table = "feature_table",
        fit_summary = "obs_table"
      ),
      promotable = c("de_table", "fit_summary"),
      chunking = list(
        chunkable = TRUE,
        axis = "features",
        chunk_size_param = "chunk_size",
        chunk_size_default = 128L,
        merge = list(
          de_table = "row_bind_feature_table",
          fit_summary = "row_bind_obs_table"
        ),
        status = "implemented_op_local"
      ),
      runner = .wb_runner_trajectory_de,
      inputs = list(
        matrix = list(required = TRUE, kind = "matrix"),
        model = list(required = TRUE, kind = "model_ref")
      ),
      params = list(
        list(name = "lineage", type = "string_vec", default = NULL,
             help = "Optional lineage key subset."),
        list(name = "feature_set", type = "string", default = NULL,
             help = "Optional feature set name from wb_feature_sets() for matrix."),
        list(name = "features", type = "string_vec", default = NULL,
             help = "Optional explicit feature subset (intersected with feature_set when both provided)."),
        list(name = "test", type = "choice", default = "spearman",
             choices = c("spearman"),
             help = "Statistical test. v1 supports spearman."),
        list(name = "min_pct_nonzero", type = "dbl", default = 0, min = 0, max = 1,
             help = "Minimum non-zero fraction filter."),
        list(name = "min_sd", type = "dbl", default = 0, min = 0, max = 1e6,
             help = "Minimum per-feature standard deviation filter."),
        list(name = "p_adjust_method", type = "string", default = "BH",
             help = "Method passed to p.adjust."),
        list(name = "chunk_size", type = "int", default = 128, min = 8, max = 4096,
             help = "Chunk size for matrix slicing.")
      ),
      interface_produces = list(
        de_table = list(
          kind = "feature_table",
          description = "Per-lineage feature trend statistics (rho, p, adjusted p)."
        ),
        fit_summary = list(
          kind = "obs_table",
          description = "Per-lineage input and filtering diagnostics."
        )
      )
    ),
    trajectory_smooth = list(
      op_name = "trajectory_smooth",
      title = "Trajectory Feature Smoothing",
      description = "Summarize per-feature expression along trajectory pseudotime into reusable trend tables.",
      intent = c("trajectory", "summary", "expression"),
      requires = list(matrix = "matrix", model = "model_ref"),
      produces = list(
        trend_table = "obs_table",
        fit_summary = "obs_table"
      ),
      promotable = c("trend_table", "fit_summary"),
      chunking = list(
        chunkable = TRUE,
        axis = "features",
        chunk_size_param = "chunk_size",
        chunk_size_default = 128L,
        merge = list(
          trend_table = "row_bind_obs_table",
          fit_summary = "row_bind_obs_table"
        ),
        status = "implemented_op_local"
      ),
      runner = .wb_runner_trajectory_smooth,
      inputs = list(
        matrix = list(required = TRUE, kind = "matrix"),
        model = list(required = TRUE, kind = "model_ref")
      ),
      params = list(
        list(name = "lineage", type = "string_vec", default = NULL,
             help = "Optional lineage key subset."),
        list(name = "feature_set", type = "string", default = NULL,
             help = "Optional feature set name from wb_feature_sets() for matrix."),
        list(name = "features", type = "string_vec", default = NULL,
             help = "Optional explicit feature subset (intersected with feature_set when both provided)."),
        list(name = "n_bins", type = "int", default = 50, min = 5, max = 1000,
             help = "Number of pseudotime bins."),
        list(name = "summary_fun", type = "choice", default = "mean",
             choices = c("mean", "median"),
             help = "Summary statistic across cells within each bin."),
        list(name = "min_cells_per_bin", type = "int", default = 5, min = 1, max = 100000,
             help = "Minimum cells required for an output bin."),
        list(name = "chunk_size", type = "int", default = 128, min = 8, max = 4096,
             help = "Chunk size for matrix slicing.")
      ),
      interface_produces = list(
        trend_table = list(
          kind = "obs_table",
          description = "Per-feature binned expression summaries along trajectory pseudotime."
        ),
        fit_summary = list(
          kind = "obs_table",
          description = "Per-lineage smoothing diagnostics."
        )
      )
    ),
    trajectory_branch_compare = list(
      op_name = "trajectory_branch_compare",
      title = "Trajectory Branch Compare",
      description = "Compare two trajectory branches feature-by-feature using explicit pseudotime and branch membership primitives.",
      intent = c("trajectory", "comparison", "statistics"),
      requires = list(
        matrix = "matrix",
        pseudotime = "cell_vector_family",
        branch_membership = "relation_family"
      ),
      produces = list(
        branch_de_table = "feature_table",
        branch_summary = "obs_table"
      ),
      promotable = c("branch_de_table", "branch_summary"),
      runner = .wb_runner_trajectory_branch_compare,
      inputs = list(
        matrix = list(required = TRUE, kind = "matrix"),
        pseudotime = list(required = TRUE, kind = "cell_vector_family"),
        branch_membership = list(required = TRUE, kind = "relation_family")
      ),
      params = list(
        list(name = "branch_a", type = "string", default = NULL,
             help = "Branch/lineage key A."),
        list(name = "branch_b", type = "string", default = NULL,
             help = "Branch/lineage key B."),
        list(name = "feature_set", type = "string", default = NULL,
             help = "Optional feature set name from wb_feature_sets() for matrix."),
        list(name = "features", type = "string_vec", default = NULL,
             help = "Optional explicit feature subset (intersected with feature_set when both provided)."),
        list(name = "min_pct", type = "dbl", default = 0, min = 0, max = 1,
             help = "Minimum detection fraction in either branch."),
        list(name = "p_adjust_method", type = "string", default = "BH",
             help = "Method passed to p.adjust.")
      ),
      interface_produces = list(
        branch_de_table = list(
          kind = "feature_table",
          description = "Per-feature branch comparison statistics and effect sizes."
        ),
        branch_summary = list(
          kind = "obs_table",
          description = "Branch-pair cell counts and pseudotime summary diagnostics."
        )
      )
    ),
    trajectory_signature_smooth = list(
      op_name = "trajectory_signature_smooth",
      title = "Trajectory Signature Smoothing",
      description = "Summarize feature-set signature scores along trajectory pseudotime into reusable trend tables.",
      intent = c("trajectory", "summary", "signature"),
      requires = list(matrix = "matrix", model = "model_ref"),
      produces = list(
        signature_table = "obs_table",
        fit_summary = "obs_table"
      ),
      promotable = c("signature_table", "fit_summary"),
      runner = .wb_runner_trajectory_signature_smooth,
      inputs = list(
        matrix = list(required = TRUE, kind = "matrix"),
        model = list(required = TRUE, kind = "model_ref")
      ),
      params = list(
        list(name = "feature_set", type = "string", default = NULL,
             help = "Required feature set name from wb_feature_sets() for matrix."),
        list(name = "lineage", type = "string_vec", default = NULL,
             help = "Optional lineage key subset."),
        list(name = "score_method", type = "choice", default = "mean",
             choices = c("mean", "sum"),
             help = "How to score the feature set within each cell."),
        list(name = "n_bins", type = "int", default = 50, min = 5, max = 1000,
             help = "Number of pseudotime bins."),
        list(name = "summary_fun", type = "choice", default = "mean",
             choices = c("mean", "median"),
             help = "Summary statistic across cells within each bin."),
        list(name = "min_cells_per_bin", type = "int", default = 5, min = 1, max = 100000,
             help = "Minimum cells required for an output bin.")
      ),
      interface_produces = list(
        signature_table = list(
          kind = "obs_table",
          description = "Per-signature binned summaries along trajectory pseudotime."
        ),
        fit_summary = list(
          kind = "obs_table",
          description = "Per-lineage signature smoothing diagnostics."
        )
      )
    ),
    trajectory_geneset_dynamics = list(
      op_name = "trajectory_geneset_dynamics",
      title = "Trajectory Gene-Set Dynamics",
      description = "Screen all feature sets in a namespace for dynamic behavior along trajectory pseudotime.",
      intent = c("trajectory", "pathway", "discovery", "signature"),
      requires = list(matrix = "matrix", model = "model_ref"),
      produces = list(
        signature_table = "obs_table",
        dynamics_table = "obs_table",
        top_sets = "obs_table",
        driver_table = "obs_table",
        driver_curve_table = "obs_table",
        fit_summary = "obs_table"
      ),
      promotable = c("signature_table", "dynamics_table", "top_sets", "driver_table", "driver_curve_table", "fit_summary"),
      runner = .wb_runner_trajectory_geneset_dynamics,
      inputs = list(
        matrix = list(required = TRUE, kind = "matrix"),
        model = list(required = TRUE, kind = "model_ref")
      ),
      params = list(
        list(name = "namespace", type = "string", default = NULL,
             help = "Feature-set namespace from wb_feature_sets() to screen."),
        list(name = "feature_sets", type = "string_vec", default = NULL,
             help = "Optional feature-set subset within the namespace."),
        list(name = "lineage", type = "string_vec", default = NULL,
             help = "Optional lineage key subset."),
        list(name = "score_method", type = "choice", default = "mean",
             choices = c("mean", "sum", "rank_mean"),
             help = "How to score each feature set within each cell."),
        list(name = "pseudotime_direction", type = "choice", default = "as_is",
             choices = c("as_is", "invert"),
             help = "Use pseudotime as provided or invert it before binning and classification."),
        list(name = "start_label", type = "string", default = NULL,
             help = "Optional biological start label recorded in output metadata."),
        list(name = "end_label", type = "string", default = NULL,
             help = "Optional biological end label recorded in output metadata."),
        list(name = "n_bins", type = "int", default = 50, min = 5, max = 1000,
             help = "Number of pseudotime bins."),
        list(name = "summary_fun", type = "choice", default = "mean",
             choices = c("mean", "median"),
             help = "Summary statistic across cells within each bin."),
        list(name = "min_cells_per_bin", type = "int", default = 5, min = 1, max = 100000,
             help = "Minimum cells required for an output bin."),
        list(name = "min_set_size", type = "int", default = 5, min = 1, max = 100000,
             help = "Minimum feature-set size after intersecting with the matrix."),
        list(name = "max_set_size", type = "int", default = 5000, min = 1, max = 1000000,
             help = "Maximum feature-set size after intersecting with the matrix."),
        list(name = "top_n", type = "int", default = 50, min = 1, max = 10000,
             help = "Number of top-ranked feature sets retained in top_sets."),
        list(name = "on_off_min_delta", type = "dbl", default = 0, min = 0,
             help = "Minimum absolute late-early delta for turns_on/turns_off classes."),
        list(name = "monotonic_min_abs_rho", type = "dbl", default = 0.5, min = 0, max = 1,
             help = "Minimum absolute Spearman rho for turns_on/turns_off classes."),
        list(name = "top_driver_genes", type = "int", default = 5, min = 0, max = 1000,
             help = "Number of top member genes retained as curve drivers per feature set."),
        list(name = "min_amplitude", type = "dbl", default = 0, min = 0,
             help = "Minimum curve amplitude required for passes_filters."),
        list(name = "min_bins_observed", type = "int", default = 5, min = 1, max = 1000,
             help = "Minimum retained bins required for passes_filters."),
        list(name = "min_features_detected", type = "int", default = 1, min = 0, max = 100000,
             help = "Minimum detected set members required for passes_filters."),
        list(name = "min_detected_fraction", type = "dbl", default = 0, min = 0, max = 1,
             help = "Minimum fraction of detected set members required for passes_filters."),
        list(name = "smooth_method", type = "choice", default = "none",
             choices = c("none", "loess", "spline"),
             help = "Optional smoothing method applied to binned curves before metrics/classes."),
        list(name = "loess_span", type = "dbl", default = 0.5, min = 0.01, max = 1,
             help = "Span used when smooth_method='loess'."),
        list(name = "bootstrap_n", type = "int", default = 0, min = 0, max = 10000,
             help = "Bootstrap replicates per bin for confidence bands; 0 disables CIs."),
        list(name = "bootstrap_seed", type = "int", default = 1, min = 1,
             help = "Random seed for bootstrap confidence bands."),
        list(name = "ci_level", type = "dbl", default = 0.95, min = 0.5, max = 0.999,
             help = "Confidence level for bootstrap bands."),
        list(name = "class_min_amplitude", type = "dbl", default = 0, min = 0,
             help = "Minimum amplitude required before assigning non-flat curve classes.")
      ),
      interface_produces = list(
        signature_table = list(
          kind = "obs_table",
          description = "Binned feature-set score curves along trajectory pseudotime."
        ),
        dynamics_table = list(
          kind = "obs_table",
          description = "Per-feature-set dynamic metrics and rank."
        ),
        top_sets = list(
          kind = "obs_table",
          description = "Top-ranked dynamic feature sets for report-first discovery."
        ),
        driver_table = list(
          kind = "obs_table",
          description = "Top dynamic member genes within each screened feature set."
        ),
        driver_curve_table = list(
          kind = "obs_table",
          description = "Binned curves for top driver genes within each screened feature set."
        ),
        fit_summary = list(
          kind = "obs_table",
          description = "Per-lineage screening diagnostics."
        )
      )
    ),
    trajectory_route_smooth = list(
      op_name = "trajectory_route_smooth",
      title = "Trajectory Route Smoothing",
      description = "Summarize per-feature expression along an explicit route using global pseudotime plus route membership weights.",
      intent = c("trajectory", "summary", "route"),
      requires = list(
        matrix = "matrix",
        pseudotime = "cell_vector",
        branch_membership = "relation_family"
      ),
      produces = list(
        trend_table = "obs_table",
        fit_summary = "obs_table"
      ),
      promotable = c("trend_table", "fit_summary"),
      runner = .wb_runner_trajectory_route_smooth,
      inputs = list(
        matrix = list(required = TRUE, kind = "matrix"),
        pseudotime = list(required = TRUE, kind = "cell_vector"),
        branch_membership = list(required = TRUE, kind = "relation_family")
      ),
      params = list(
        list(name = "route_key", type = "string", default = NULL,
             help = "Required route/branch key within branch_membership."),
        list(name = "feature_set", type = "string", default = NULL,
             help = "Optional feature set name from wb_feature_sets() for matrix."),
        list(name = "features", type = "string_vec", default = NULL,
             help = "Optional explicit feature subset (intersected with feature_set when both provided)."),
        list(name = "n_bins", type = "int", default = 50, min = 5, max = 1000,
             help = "Number of pseudotime bins."),
        list(name = "summary_fun", type = "choice", default = "mean",
             choices = c("mean", "median"),
             help = "Summary statistic across cells within each bin. Weighted routes currently support mean only."),
        list(name = "min_cells_per_bin", type = "int", default = 5, min = 1, max = 100000,
             help = "Minimum cells required for an output bin."),
        list(name = "weight_mode", type = "choice", default = "probability",
             choices = c("probability", "binary_threshold"),
             help = "Use route probabilities directly or threshold to a binary route membership."),
        list(name = "prob_min", type = "dbl", default = 0, min = 0, max = 1,
             help = "Minimum route probability required to include a cell."),
        list(name = "chunk_size", type = "int", default = 128, min = 1, max = 100000,
             help = "Feature chunk size for matrix slicing.")
      ),
      interface_produces = list(
        trend_table = list(
          kind = "obs_table",
          description = "Per-feature binned summaries along a selected route."
        ),
        fit_summary = list(
          kind = "obs_table",
          description = "Route smoothing diagnostics."
        )
      )
    ),
    trajectory_vector_smooth = list(
      op_name = "trajectory_vector_smooth",
      title = "Trajectory Signal Smoothing",
      description = "Summarize cell-level signal families along trajectory pseudotime into reusable trend tables.",
      intent = c("trajectory", "summary", "signal"),
      requires = list(signal = "cell_vector_family", model = "model_ref"),
      produces = list(
        signal_table = "obs_table",
        fit_summary = "obs_table"
      ),
      promotable = c("signal_table", "fit_summary"),
      runner = .wb_runner_trajectory_vector_smooth,
      inputs = list(
        signal = list(required = TRUE, kind = "cell_vector_family"),
        model = list(required = TRUE, kind = "model_ref")
      ),
      params = list(
        list(name = "signal_keys", type = "string_vec", default = NULL,
             help = "Optional signal-key subset within the cell_vector_family."),
        list(name = "lineage", type = "string_vec", default = NULL,
             help = "Optional lineage key subset."),
        list(name = "n_bins", type = "int", default = 50, min = 5, max = 1000,
             help = "Number of pseudotime bins."),
        list(name = "summary_fun", type = "choice", default = "mean",
             choices = c("mean", "median"),
             help = "Summary statistic across cells within each bin."),
        list(name = "min_cells_per_bin", type = "int", default = 5, min = 1, max = 100000,
             help = "Minimum cells required for an output bin.")
      ),
      interface_produces = list(
        signal_table = list(
          kind = "obs_table",
          description = "Per-signal binned summaries along trajectory pseudotime."
        ),
        fit_summary = list(
          kind = "obs_table",
          description = "Per-lineage signal smoothing diagnostics."
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
    ),
    slingshot_fit = list(
      op_name = "slingshot_fit",
      title = "Slingshot fit",
      description = "Fit Slingshot lineages/pseudotime in a chosen fit space (typically latent/PCA).",
      intent = c("trajectory"),
      requires = list(fit_space = "space", clusters = "cell_vector"),
      produces = list(
        pseudotime = "cell_vector_family",
        model = "model_ref"
      ),
      promotable = c("pseudotime", "model"),
      runner = .wb_runner_slingshot_fit,
      inputs = list(
        fit_space = list(required = TRUE, must_be_2d = FALSE, dims_min = 2),
        clusters = list(required = TRUE, kind = "cell_vector")
      ),
      params = list(
        list(name = "start.clus", type = "string", default = NULL,
             help = "Starting cluster id."),
        list(name = "end.clus", type = "string_vec", default = NULL,
             help = "Ending cluster id(s)."),
        list(name = "include_clusters", type = "string_vec", default = NULL,
             help = "Restrict fitting to these cluster id(s)."),
        list(name = "exclude_clusters", type = "string_vec", default = character(0),
             help = "Cluster id(s) to exclude before fitting."),
        list(name = "exclude_cells", type = "cell_ids", default = NULL,
             help = "Optional cell IDs to exclude before fitting."),
        list(name = "stretch", type = "dbl", default = 2, min = 0, max = 10,
             help = "Slingshot curve stretching."),
        list(name = "reweight", type = "bool", default = TRUE,
             help = "Whether to reweight assignments during fitting."),
        list(name = "shrink", type = "dbl", default = 1, min = 0, max = 1,
             help = "Curve shrinkage toward shared segments."),
        list(name = "maxit", type = "int", default = 10, min = 1, max = 200,
             help = "Maximum fitting iterations.")
      ),
      interface_produces = list(
        pseudotime = list(
          kind = "cell_vector_family",
          value_kind = "continuous",
          key = "lineage_id",
          description = "Lineage-specific pseudotime values per cell (fit space inference)."
        ),
        model = list(
          kind = "model_ref",
          description = "Session-chainable Slingshot fit model (engine='slingshot')."
        )
      )
    ),
    slingshot_project = list(
      op_name = "slingshot_project",
      title = "Slingshot project curves",
      description = "Project a fitted Slingshot model into a 2D display space (e.g. UMAP).",
      intent = c("trajectory"),
      requires = list(model = "model_ref", plot_space = "space_2d"),
      produces = list(curves = "path_2d_family"),
      promotable = c("curves"),
      runner = .wb_runner_slingshot_project,
      inputs = list(
        model = list(required = TRUE, kind = "model_ref"),
        plot_space = list(required = TRUE, must_be_2d = TRUE, dims_min = 2, dims_max = 2)
      ),
      params = list(
        list(name = "stretch", type = "dbl", default = NULL, min = 0, max = 10,
             help = "Optional override of stretch during embedding."),
        list(name = "shrink", type = "dbl", default = NULL, min = 0, max = 1,
             help = "Optional override of shrink during embedding."),
        list(name = "approx_points", type = "int", default = 200, min = 0, max = 5000,
             help = "Target max curve points per lineage for display (0/NULL = no compaction).")
      ),
      interface_produces = list(
        curves = list(
          kind = "path_2d_family",
          key = "lineage_id",
          description = "Projected Slingshot lineage curves in the chosen 2D display space."
        )
      )
    ),
    monocle3_fit = list(
      op_name = "monocle3_fit",
      title = "Monocle3 fit (hybrid space)",
      description = "Fit monocle3 graph/pseudotime using a scworkbench latent space injected into monocle3's UMAP slot.",
      intent = c("trajectory"),
      requires = list(fit_space = "space"),
      produces = list(
        pseudotime = "cell_vector",
        branch_membership = "relation_family",
        model = "model_ref"
      ),
      promotable = c("pseudotime", "branch_membership", "model"),
      runner = .wb_runner_monocle3_fit,
      inputs = list(
        fit_space = list(required = TRUE, must_be_2d = FALSE, dims_min = 2)
      ),
      params = list(
        list(name = "dims", type = "string_vec", default = NULL,
             help = "Optional fit-space dimensions to use (e.g. 1:20 as explicit integer vector)."),
        list(name = "root_cells", type = "cell_ids", default = NULL,
             help = "Root cell IDs (exactly one of root_cells or root_pr_nodes)."),
        list(name = "root_pr_nodes", type = "string_vec", default = NULL,
             help = "Principal graph root node IDs (advanced; exactly one of root_cells or root_pr_nodes)."),
        list(name = "k", type = "int", default = 20, min = 2, max = 500,
             help = "kNN size for monocle3 clustering."),
        list(name = "cluster_method", type = "choice", default = "leiden",
             choices = c("leiden", "louvain"),
             help = "Monocle3 clustering backend."),
        list(name = "num_iter", type = "int", default = 2, min = 1, max = 200,
             help = "Monocle3 clustering iterations."),
        list(name = "partition_qval", type = "dbl", default = 0.05, min = 0, max = 1,
             help = "Partition significance threshold."),
        list(name = "weight", type = "bool", default = FALSE,
             help = "Use weighted nearest-neighbor graph for monocle3 clustering."),
        list(name = "resolution", type = "dbl", default = NULL, min = 0, max = 100,
             help = "Optional clustering resolution (NULL lets monocle3 choose)."),
        list(name = "random_seed", type = "int", default = 42, min = 1, max = 999999,
             help = "Random seed for clustering."),
        list(name = "use_partition", type = "bool", default = FALSE,
             help = "Learn graph per partition. FALSE is recommended for v1 tree semantics."),
        list(name = "close_loop", type = "bool", default = FALSE,
             help = "Allow loop closure in graph learning. FALSE required for v1 tree-derived lineages."),
        list(name = "verbose", type = "bool", default = FALSE,
             help = "Verbose monocle3 output.")
      ),
      interface_produces = list(
        pseudotime = list(
          kind = "cell_vector",
          value_kind = "continuous",
          description = "Rooted global pseudotime per cell from monocle3."
        ),
        branch_membership = list(
          kind = "relation_family",
          key = "lineage_id",
          description = "Derived cell-to-lineage membership relations (tree root-to-leaf paths; binary weights in v1)."
        ),
        model = list(
          kind = "model_ref",
          description = "Session-chainable monocle3 CDS model (engine='monocle3')."
        )
      )
    ),
    monocle3_project = list(
      op_name = "monocle3_project",
      title = "Monocle3 project curves",
      description = "Project a fitted monocle3 trajectory graph into a 2D display space.",
      intent = c("trajectory"),
      requires = list(model = "model_ref", plot_space = "space_2d"),
      produces = list(curves = "path_2d_family"),
      promotable = c("curves"),
      runner = .wb_runner_monocle3_project,
      inputs = list(
        model = list(required = TRUE, kind = "model_ref"),
        plot_space = list(required = TRUE, must_be_2d = TRUE, dims_min = 2, dims_max = 2)
      ),
      params = list(
        list(name = "approx_points", type = "int", default = 200, min = 0, max = 5000,
             help = "Target max curve points per lineage for display (0/NULL = no compaction).")
      ),
      interface_produces = list(
        curves = list(
          kind = "path_2d_family",
          key = "lineage_id",
          description = "Projected monocle3 root-qualified lineage curves in the chosen 2D display space."
        )
      )
    ),
    peakvi_fit = list(
      op_name = "peakvi_fit",
      title = "PeakVI fit (pybench)",
      description = "Train a PeakVI model on a matrix via the pybench Python runtime and emit a latent space plus model reference.",
      intent = c("latent", "model", "python"),
      requires = list(matrix = "matrix"),
      produces = list(
        space = "space",
        model = "model_ref"
      ),
      promotable = c("model"),
      runner = .wb_runner_peakvi_fit,
      inputs = list(
        matrix = list(required = TRUE, kind = "matrix")
      ),
      params = list(
        list(name = "n_latent", type = "int", default = 20, min = 2, max = 1024,
             help = "Target latent dimensionality for the emitted PeakVI space."),
        list(name = "n_layers", type = "int", default = 2, min = 1, max = 32,
             help = "Number of hidden layers passed to the PeakVI model constructor."),
        list(name = "n_hidden", type = "int", default = 256, min = 1, max = 8192,
             help = "Hidden width passed to the PeakVI model constructor."),
        list(name = "dropout", type = "number", default = 0.2, min = 0, max = 1,
             help = "Dropout rate passed to the PeakVI model constructor."),
        list(name = "batch_key", type = "string", default = NULL,
             help = "Optional observation field used as the PeakVI batch covariate."),
        list(name = "max_epochs", type = "int", default = 500, min = 1, max = 100000,
             help = "Maximum training epochs passed through to scvi-tools."),
        list(name = "lr", type = "number", default = 1e-3, min = 0,
             help = "Optional learning rate passed through in train plan_kwargs."),
        list(name = "early_stopping", type = "bool", default = TRUE,
             help = "If TRUE, enable scvi-tools early stopping during PeakVI training."),
        list(name = "seed", type = "int", default = 1, min = 0, max = 999999,
             help = "Random seed for PeakVI training."),
        list(name = "use_gpu", type = "bool", default = FALSE,
             help = "If TRUE, request GPU-backed training in scvi-tools."),
        list(name = "space_id_out", type = "string", default = "peakvi_space",
             help = "Space id to write for the learned PeakVI latent embedding.")
      ),
      interface_produces = list(
        space = list(
          kind = "space",
          description = "PeakVI latent space written into the bundle spaces registry."
        ),
        model = list(
          kind = "model_ref",
          description = "Serialized PeakVI Python model payload (engine='peakvi')."
        )
      )
    ),
    peakvi_project = list(
      op_name = "peakvi_project",
      title = "PeakVI project (pybench)",
      description = "Project cells from an ATAC matrix through a saved PeakVI model and emit a latent space.",
      intent = c("projection", "latent", "python"),
      requires = list(matrix = "matrix", model = "model_ref"),
      produces = list(
        space = "space"
      ),
      promotable = character(0),
      runner = .wb_runner_peakvi_project,
      inputs = list(
        matrix = list(required = TRUE, kind = "matrix"),
        model = list(required = TRUE, kind = "model_ref")
      ),
      params = list(
        list(name = "batch_key", type = "string", default = NULL,
             help = "Optional observation field used as the PeakVI batch covariate during projection."),
        list(name = "use_gpu", type = "bool", default = FALSE,
             help = "If TRUE, request GPU-backed model loading/projection in scvi-tools."),
        list(name = "space_id_out", type = "string", default = "peakvi_project_space",
             help = "Space id to write for the projected PeakVI latent embedding.")
      ),
      interface_produces = list(
        space = list(
          kind = "space",
          description = "Projected PeakVI latent space written into the bundle spaces registry."
        )
      )
    ),
    space_path_define = list(
      op_name = "space_path_define",
      title = "Define analytical space path",
      description = "Contract scaffold for checkpoint-anchored path construction in a named analytical space.",
      intent = c("trajectory", "geometry", "path"),
      requires = list(space = "space"),
      produces = list(path = "space_path_family"),
      promotable = c("path"),
      runner = .wb_runner_space_path_define,
      inputs = list(
        space = list(required = TRUE, kind = "space")
      ),
      params = list(
        list(name = "checkpoint_sets", type = "string_vec", default = NULL,
             help = "Ordered checkpoint cell-set refs that anchor the path definition."),
        list(name = "fit_mode", type = "choice", default = "linear",
             choices = c("linear", "manifold_smooth"),
             help = "Path fitting mode. V1 supports linear and a first conservative manifold smoothing mode."),
        list(name = "checkpoint_summary", type = "choice", default = "centroid",
             choices = c("centroid"),
             help = "Checkpoint summarization rule used to derive anchors from checkpoint cells."),
        list(name = "n_path_points", type = "int", default = NULL, min = 2, max = 50000,
             help = "Optional explicit number of fitted path points."),
        list(name = "smooth_k", type = "int", default = 30, min = 2, max = 5000,
             help = "For fit_mode='manifold_smooth', number of nearest cells used per provisional path point."),
        list(name = "smooth_n_iter", type = "int", default = 2, min = 1, max = 50,
             help = "For fit_mode='manifold_smooth', number of refinement passes."),
        list(name = "smooth_weight", type = "choice", default = "inverse_distance",
             choices = c("inverse_distance", "gaussian"),
             help = "For fit_mode='manifold_smooth', distance-weighting rule for local cell pull."),
        list(name = "path_id_out", type = "string", default = "space_path",
             help = "Path id to record for the emitted analytical path.")
      ),
      interface_produces = list(
        path = list(
          kind = "space_path_family",
          key = "path_id",
          description = "Analytical path in the original latent space."
        )
      )
    ),
    space_path_score = list(
      op_name = "space_path_score",
      title = "Score cells against analytical path",
      description = "Contract scaffold for path-relative scoring in a named analytical space.",
      intent = c("trajectory", "geometry", "path"),
      requires = list(space = "space", path = "space_path_family"),
      produces = list(
        path_scores = "cell_vector_family",
        fit_summary = "obs_table"
      ),
      promotable = c("path_scores", "fit_summary"),
      runner = .wb_runner_space_path_score,
      inputs = list(
        space = list(required = TRUE, kind = "space"),
        path = list(required = TRUE, kind = "space_path_family")
      ),
      params = list(
        list(name = "score_mode", type = "choice", default = "orthogonal_projection",
             choices = c("orthogonal_projection"),
             help = "Scoring mode. V1 scaffolding standardizes on orthogonal projection semantics."),
        list(name = "distance_metric", type = "choice", default = "euclidean",
             choices = c("euclidean"),
             help = "Distance metric used for path-relative scoring."),
        list(name = "score_prefix", type = "string", default = NULL,
             help = "Optional prefix for emitted score-family keys.")
      ),
      interface_produces = list(
        path_scores = list(
          kind = "cell_vector_family",
          value_kind = "continuous",
          key = "score_name",
          description = "Per-cell path-relative scores such as progress and distance."
        ),
        fit_summary = list(
          kind = "obs_table",
          description = "Compact path-level scoring diagnostics."
        )
      )
    ),
    space_path_project_2d = list(
      op_name = "space_path_project_2d",
      title = "Project analytical path into 2D",
      description = "Contract scaffold for projecting an analytical path into a drawable 2D path family.",
      intent = c("trajectory", "geometry", "path", "display"),
      requires = list(path = "space_path_family", plot_space = "space_2d"),
      produces = list(curves = "path_2d_family"),
      promotable = c("curves"),
      runner = .wb_runner_space_path_project_2d,
      inputs = list(
        path = list(required = TRUE, kind = "space_path_family"),
        plot_space = list(required = TRUE, kind = "space_2d")
      ),
      params = list(
        list(name = "project_mode", type = "choice", default = "local_interpolation",
             choices = c("local_interpolation"),
             help = "Projection mode used to approximate the analytical path in a 2D plot space."),
        list(name = "approx_points", type = "int", default = NULL, min = 2, max = 50000,
             help = "Optional target point count for display compaction.")
      ),
      interface_produces = list(
        curves = list(
          kind = "path_2d_family",
          key = "path_id",
          description = "Approximate 2D rendering of the analytical path."
        )
      )
    ),
    palantir_fit = list(
      op_name = "palantir_fit",
      title = "Palantir fit (pybench)",
      description = "Run Palantir pseudotime/branch probabilities on a scworkbench latent space via the pybench Python runtime.",
      intent = c("trajectory"),
      requires = list(fit_space = "space"),
      produces = list(
        pseudotime = "cell_vector",
        branch_membership = "relation_family",
        branch_summary = "obs_table",
        entropy = "cell_vector",
        model = "model_ref"
      ),
      promotable = c("pseudotime", "branch_membership", "branch_summary", "entropy", "model"),
      runner = .wb_runner_palantir_fit,
      inputs = list(
        fit_space = list(required = TRUE, must_be_2d = FALSE, dims_min = 2)
      ),
      params = list(
        list(name = "root_cell", type = "string", default = NULL,
             help = "Single Palantir early/root cell ID (Palantir-native single-root semantics)."),
        list(name = "terminal_cells", type = "cell_ids", default = NULL,
             help = "Optional explicit terminal cell IDs passed to Palantir as terminal states (recommended for branch probabilities)."),
        list(name = "dims", type = "string_vec", default = NULL,
             help = "Optional fit-space dimensions to use (for example 1:20 as explicit integer vector)."),
        list(name = "knn", type = "int", default = 30, min = 2, max = 1000,
             help = "kNN size for Palantir diffusion graph and pseudotime."),
        list(name = "n_diffusion_components", type = "int", default = 10, min = 2, max = 200,
             help = "Number of diffusion components for Palantir."),
        list(name = "n_waypoints", type = "int", default = 300, min = 10, max = 10000,
             help = "Number of Palantir waypoints."),
        list(name = "use_early_cell_as_start", type = "bool", default = TRUE,
             help = "Pass through to Palantir; if TRUE, force the provided early/root cell to be used as trajectory start."),
        list(name = "seed", type = "int", default = 20, min = 0, max = 999999,
             help = "Random seed for Palantir stochastic steps.")
      ),
      interface_produces = list(
        pseudotime = list(
          kind = "cell_vector",
          value_kind = "continuous",
          description = "Palantir pseudotime (single-root, global)."
        ),
        branch_membership = list(
          kind = "relation_family",
          key = "branch_id",
          description = "Palantir branch probabilities as cell-to-branch relations (`branch:*` keys; weights are probabilities)."
        ),
        branch_summary = list(
          kind = "obs_table",
          entity_kind = "branch",
          description = "Palantir branch probability summary table."
        ),
        entropy = list(
          kind = "cell_vector",
          value_kind = "continuous",
          description = "Palantir entropy per cell."
        ),
        model = list(
          kind = "model_ref",
          description = "Palantir Python model payload (engine='palantir')."
        )
      )
    ),
    palantir_project = list(
      op_name = "palantir_project",
      title = "Palantir project trajectories",
      description = "Project Palantir branch trajectories into a 2D display space using Palantir-style mellon interpolation from the fitted Palantir model.",
      intent = c("trajectory"),
      requires = list(
        model = "model_ref",
        plot_space = "space_2d"
      ),
      produces = list(curves = "path_2d_family"),
      promotable = c("curves"),
      runner = .wb_runner_palantir_project,
      inputs = list(
        model = list(required = TRUE, kind = "model_ref"),
        plot_space = list(required = TRUE, must_be_2d = TRUE, dims_min = 2, dims_max = 2)
      ),
      params = list(
        list(name = "prob_min", type = "dbl", default = 0.05, min = 0, max = 1,
             help = "Minimum branch probability mask threshold for branch trajectory interpolation."),
        list(name = "smoothness", type = "dbl", default = 1.0, min = 0.05, max = 20,
             help = "Palantir-style mellon trajectory smoothing multiplier (higher = smoother)."),
        list(name = "min_cells_per_branch", type = "int", default = 50, min = 2, max = 1000000,
             help = "Minimum eligible cells required to derive a branch trajectory."),
        list(name = "approx_points", type = "int", default = 200, min = 0, max = 5000,
             help = "Number of trajectory sample points per branch (curve resolution).")
      ),
      interface_produces = list(
        curves = list(
          kind = "path_2d_family",
          key = "branch_id",
          description = "Palantir-style smoothed branch trajectories projected into the chosen 2D display space."
        )
      )
    )
  )
}
