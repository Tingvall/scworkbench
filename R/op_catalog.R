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

.wb_runner_matrix_log_normalize <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  .wb_assert(!is.null(resolved$matrix), "matrix_log_normalize runner: missing resolved$matrix.")
  matrix_id <- as.character(resolved$matrix$matrix_id %||% "")[1]
  .wb_assert(nzchar(matrix_id), "matrix_log_normalize runner: resolved matrix primitive missing matrix_id.")

  all_cells <- wb_cells(bundle, cell_set = "all")
  .wb_assert(identical(as.character(effective_cells), as.character(all_cells)),
             "matrix_log_normalize currently writes full bundle matrices only; use cell_set='all'.")

  raw <- wb_op_matrix_log_normalize(
    bundle = bundle,
    matrix_id = matrix_id,
    output_matrix_id = inputs$output_matrix_id %||% NULL,
    scale_factor = inputs$scale_factor %||% 10000,
    overwrite = inputs$overwrite %||% FALSE
  )

  .wb_assert(is.list(raw) && is.list(raw$outputs),
             "matrix_log_normalize must return list(outputs=<list>, params=<list>).")
  raw
}

.wb_runner_hvg_select <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  .wb_assert(!is.null(resolved$matrix), "hvg_select runner: missing resolved$matrix.")
  matrix_id <- as.character(resolved$matrix$matrix_id %||% "")[1]
  .wb_assert(nzchar(matrix_id), "hvg_select runner: resolved matrix primitive missing matrix_id.")

  raw <- wb_op_hvg_select(
    bundle = bundle,
    matrix_id = matrix_id,
    cells = as.character(effective_cells),
    n_features = inputs$n_features %||% 2000L,
    method = inputs$method %||% "vst",
    min_mean = inputs$min_mean %||% NULL,
    max_mean = inputs$max_mean %||% NULL,
    min_dispersion = inputs$min_dispersion %||% NULL,
    batch_key = inputs$batch_key %||% NULL,
    exclude_features = inputs$exclude_features %||% NULL,
    feature_type = inputs$feature_type %||% NULL,
    seed = inputs$seed %||% 1L,
    chunk_size = inputs$chunk_size %||% 256L
  )

  .wb_assert(is.list(raw) && is.list(raw$outputs),
             "hvg_select must return list(outputs=<list>, params=<list>).")
  raw
}

.wb_runner_pca_fit <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  .wb_assert(!is.null(resolved$matrix), "pca_fit runner: missing resolved$matrix.")
  matrix_id <- as.character(resolved$matrix$matrix_id %||% "")[1]
  .wb_assert(nzchar(matrix_id), "pca_fit runner: resolved matrix primitive missing matrix_id.")

  raw <- wb_op_pca_fit(
    bundle = bundle,
    matrix_id = matrix_id,
    cells = as.character(effective_cells),
    feature_table = resolved$features %||% resolved$feature_table %||% NULL,
    feature_ids = inputs$feature_ids %||% NULL,
    n_components = inputs$n_components %||% 50L,
    center = inputs$center %||% TRUE,
    scale = inputs$scale %||% TRUE,
    backend = inputs$backend %||% "irlba",
    seed = inputs$seed %||% 1L,
    space_id_out = inputs$space_id_out %||% "rna.pca",
    overwrite = inputs$overwrite %||% FALSE,
    max_dense_gb = inputs$max_dense_gb %||% 8
  )

  .wb_assert(is.list(raw) && is.list(raw$outputs),
             "pca_fit must return list(outputs=<list>, params=<list>).")
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

.wb_runner_slingshot_lineage_weights <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  .wb_assert(!is.null(resolved$model), "slingshot_lineage_weights runner: missing resolved$model.")
  raw <- wb_op_slingshot_lineage_weights(model_ref = resolved$model)
  .wb_assert(is.list(raw) && is.list(raw$outputs),
             "slingshot_lineage_weights must return list(outputs=<list>, params=<list>).")
  raw
}

.wb_runner_trajectory_segment_join <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  raw <- wb_op_trajectory_segment_join(
    bundle = bundle,
    segments = inputs$segments,
    composite_id = inputs$composite_id %||% NULL,
    composite_key = inputs$composite_key %||% NULL,
    join_policy = inputs$join_policy %||% "exact_boundary_collapse",
    min_weight = inputs$min_weight %||% NULL,
    allow_legacy = inputs$allow_legacy %||% FALSE,
    runs = inputs$runs %||% NULL
  )
  .wb_assert(is.list(raw) && is.list(raw$outputs),
             "trajectory_segment_join must return list(outputs=<list>, params=<list>).")
  raw
}

.wb_runner_trajectory_segment_from_artifacts <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  .wb_assert(!is.null(resolved$pseudotime), "trajectory_segment_from_artifacts runner: missing resolved$pseudotime.")
  raw <- wb_op_trajectory_segment_from_artifacts(
    bundle = bundle,
    pseudotime = resolved$pseudotime,
    lineage = inputs$lineage,
    segment_id = inputs$segment_id,
    segment_order = inputs$segment_order %||% 1L,
    model = resolved$model %||% inputs$model %||% NULL,
    lineage_weights = resolved$lineage_weights %||% inputs$lineage_weights %||% NULL,
    membership = inputs$membership %||% NULL,
    confidence = resolved$confidence %||% inputs$confidence %||% NULL,
    confidence_key = inputs$confidence_key %||% NULL,
    path = resolved$path %||% inputs$path %||% NULL,
    source_engine = inputs$source_engine %||% NULL,
    start_label = inputs$start_label %||% NULL,
    end_label = inputs$end_label %||% NULL,
    composite_id = inputs$composite_id %||% NULL,
    runs = inputs$runs %||% NULL,
    allow_legacy = inputs$allow_legacy %||% FALSE
  )
  .wb_assert(is.list(raw) && is.list(raw$outputs),
             "trajectory_segment_from_artifacts must return list(outputs=<list>, params=<list>).")
  raw
}

.wb_runner_trajectory_segment_path_join <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  raw <- wb_op_trajectory_segment_path_join(
    bundle = bundle,
    paths = inputs$paths,
    composite_id = inputs$composite_id %||% NULL,
    composite_key = inputs$composite_key %||% NULL,
    display_space_id = inputs$display_space_id %||% NULL,
    endpoint_summary_method = inputs$endpoint_summary_method %||% "centroid",
    endpoint_max_distance = inputs$endpoint_max_distance %||% NULL,
    endpoint_qc_action = inputs$endpoint_qc_action %||% "fail",
    allow_legacy = inputs$allow_legacy %||% FALSE
  )
  .wb_assert(is.list(raw) && is.list(raw$outputs),
             "trajectory_segment_path_join must return list(outputs=<list>, params=<list>).")
  raw
}

.wb_runner_trajectory_space_path_segment <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  .wb_assert(!is.null(resolved$path_scores), "trajectory_space_path_segment runner: missing resolved$path_scores.")
  raw <- wb_op_trajectory_space_path_segment(
    bundle = bundle,
    path_scores = resolved$path_scores,
    segment_id = inputs$segment_id,
    segment_order = inputs$segment_order %||% 1L,
    score_prefix = inputs$score_prefix %||% NULL,
    candidate_cells = inputs$candidate_cells %||% NULL,
    distance_threshold = inputs$distance_threshold %||% NULL,
    distance_quantile = inputs$distance_quantile %||% NULL,
    start_label = inputs$start_label %||% NULL,
    end_label = inputs$end_label %||% NULL,
    path = inputs$path %||% NULL,
    display_path = resolved$display_path %||% inputs$display_path %||% NULL,
    display_lineage = inputs$display_lineage %||% NULL,
    display_space_id = inputs$display_space_id %||% NULL,
    start_endpoint = inputs$start_endpoint %||% NULL,
    end_endpoint = inputs$end_endpoint %||% NULL,
    start_cell_set = inputs$start_cell_set %||% NULL,
    end_cell_set = inputs$end_cell_set %||% NULL,
    endpoint_summary_method = inputs$endpoint_summary_method %||% "centroid",
    endpoint_max_distance = inputs$endpoint_max_distance %||% NULL,
    endpoint_qc_action = inputs$endpoint_qc_action %||% "fail",
    composite_id = inputs$composite_id %||% NULL,
    pseudotime_key = inputs$pseudotime_key %||% NULL,
    confidence_key = inputs$confidence_key %||% NULL,
    runs = inputs$runs %||% NULL
  )
  .wb_assert(is.list(raw) && is.list(raw$outputs),
             "trajectory_space_path_segment must return list(outputs=<list>, params=<list>).")
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

.wb_runner_scvi_train <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  .wb_assert(!is.null(resolved$matrix), "scvi_train runner: missing resolved$matrix.")
  .wb_assert(!is.null(effective_cells) && length(effective_cells) > 0,
             "scvi_train runner: effective_cells is empty.")

  matrix_id <- as.character(resolved$matrix$matrix_id %||% "")[1]
  .wb_assert(nzchar(matrix_id), "scvi_train runner: resolved matrix primitive missing matrix_id.")

  raw <- wb_op_scvi_train(
    bundle = bundle,
    matrix_id = matrix_id,
    cells = as.character(effective_cells),
    batch_key = inputs$batch_key %||% NULL,
    categorical_covariates = inputs$categorical_covariates %||% NULL,
    continuous_covariates = inputs$continuous_covariates %||% NULL,
    n_latent = inputs$n_latent %||% 30L,
    n_hidden = inputs$n_hidden %||% 128L,
    n_layers = inputs$n_layers %||% 2L,
    dropout = inputs$dropout %||% 0.1,
    max_epochs = inputs$max_epochs %||% NULL,
    early_stopping = inputs$early_stopping %||% TRUE,
    seed = inputs$seed %||% 1L,
    use_gpu = inputs$use_gpu %||% FALSE,
    output_space_id = inputs$output_space_id %||% inputs$space_id_out %||% "rna.scvi",
    model_artifact_id = inputs$model_artifact_id %||% NULL,
    overwrite = inputs$overwrite %||% FALSE,
    allow_non_counts = inputs$allow_non_counts %||% FALSE,
    cell_set = inputs$cell_set %||% "all"
  )

  .wb_assert(is.list(raw) && is.list(raw$outputs),
             "scvi_train must return list(outputs=<list>, params=<list>).")
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
  raw$outputs$fit_summary <- wb_prim_obs_table(data.frame(
    matrix_id=matrix_id, output_space_id=as.character(raw$params$space_id_out %||% inputs$space_id_out),
    n_cells=length(effective_cells), n_features=as.integer(raw$params$n_features %||% NA_integer_),
    batch_key=as.character(inputs$batch_key %||% NA_character_), use_gpu=isTRUE(inputs$use_gpu %||% FALSE), stringsAsFactors=FALSE),
    table_type="peakvi_project_summary")
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

  raw <- wb_op_ucell(
    bundle = bundle,
    matrix_id = matrix_id,
    features = inputs$features,
    cells = as.character(effective_cells),
    name = inputs$name %||% "Signature",
    max_rank = inputs$max_rank %||% 1500L,
    ncores = inputs$ncores %||% 1L,
    parallel_backend = inputs$parallel_backend %||% "auto",
    chunk_size = if ("chunk_size" %in% names(inputs)) inputs$chunk_size else 2000L,
    missing_features_policy = inputs$missing_features_policy %||% "drop"
  )

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

.wb_runner_feature_set_import <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  .wb_assert(!is.null(resolved$matrix), "feature_set_import runner: missing resolved$matrix.")
  .wb_assert(!is.null(inputs$namespace), "feature_set_import runner: inputs$namespace is required.")

  raw <- wb_op_feature_set_import(
    bundle = bundle,
    matrix_id = resolved$matrix$matrix_id,
    source_path = inputs$source_path %||% NULL,
    source_format = inputs$source_format %||% "auto",
    namespace = as.character(inputs$namespace)[1],
    collection = inputs$collection %||% NULL,
    subcollection = inputs$subcollection %||% NULL,
    species = inputs$species %||% NULL,
    organism = inputs$organism %||% NULL,
    gene_id_type = inputs$gene_id_type %||% NULL,
    set_id_col = inputs$set_id_col %||% "feature_set",
    set_name_col = inputs$set_name_col %||% NULL,
    gene_col = inputs$gene_col %||% "feature_id",
    description_col = inputs$description_col %||% "description",
    split_by_collection = inputs$split_by_collection %||% FALSE,
    overwrite = inputs$overwrite %||% TRUE,
    strict = inputs$strict %||% FALSE,
    created_by = inputs$created_by %||% NULL,
    source_id = inputs$source_id %||% NULL,
    source_version = inputs$source_version %||% NULL,
    origin = inputs$origin %||% "imported",
    is_readonly = inputs$is_readonly %||% TRUE
  )

  .wb_assert(is.list(raw) && is.list(raw$outputs),
             "feature_set_import must return list(outputs=<list>, params=<list>).")
  raw
}

.wb_runner_feature_set_overlap_qc <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  .wb_assert(!is.null(resolved$matrix), "feature_set_overlap_qc runner: missing resolved$matrix.")

  raw <- wb_op_feature_set_overlap_qc(
    bundle = bundle,
    matrix_id = resolved$matrix$matrix_id,
    namespaces = inputs$namespaces %||% NULL,
    namespace = inputs$namespace %||% NULL,
    feature_sets = inputs$feature_sets %||% NULL,
    min_set_size = inputs$min_set_size %||% 1L,
    max_set_size = inputs$max_set_size %||% Inf,
    min_detected_fraction = inputs$min_detected_fraction %||% 0,
    deduplicate_sets = inputs$deduplicate_sets %||% TRUE
  )

  .wb_assert(is.list(raw) && is.list(raw$outputs),
             "feature_set_overlap_qc must return list(outputs=<list>, params=<list>).")
  raw
}

.wb_runner_feature_set_namespace_transfer <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  .wb_assert(!is.null(resolved$source_matrix), "feature_set_namespace_transfer runner: missing resolved$source_matrix.")
  .wb_assert(!is.null(resolved$target_matrix), "feature_set_namespace_transfer runner: missing resolved$target_matrix.")

  raw <- wb_feature_set_namespace_transfer(
    bundle = bundle,
    source_matrix_id = resolved$source_matrix$matrix_id,
    target_matrix_id = resolved$target_matrix$matrix_id,
    namespace = inputs$namespace %||% NULL,
    namespaces = inputs$namespaces %||% NULL,
    feature_sets = inputs$feature_sets %||% NULL,
    mode = inputs$mode %||% "mirror",
    target_namespace = inputs$target_namespace %||% NULL,
    overwrite = inputs$overwrite %||% FALSE,
    strict = inputs$strict %||% TRUE,
    min_retained_features = inputs$min_retained_features %||% 1L,
    min_retained_fraction = inputs$min_retained_fraction %||% 0,
    created_by = inputs$created_by %||% NULL,
    notes = inputs$notes %||% NULL
  )

  .wb_assert(is.list(raw) && is.list(raw$outputs),
             "feature_set_namespace_transfer must return list(outputs=<list>, params=<list>).")
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

.wb_runner_cell_set_derive <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  target_cell_set <- as.character(inputs$target_cell_set %||% "")[1]
  .wb_assert(nzchar(target_cell_set), "cell_set_derive runner: target_cell_set is required.")
  .wb_assert(!is.null(effective_cells) && length(effective_cells) > 0,
             "cell_set_derive runner: effective_cells is empty.")

  raw <- wb_cell_set_derive(
    bundle = bundle,
    cell_set = target_cell_set,
    cells = as.character(effective_cells),
    role = inputs$role %||% "analysis_universe",
    status = inputs$status %||% "candidate",
    source = inputs$source %||% "selector_recipe",
    created_by = inputs$created_by %||% NULL,
    description = inputs$description %||% NULL,
    recipe = inputs$recipe %||% NULL,
    overwrite = inputs$overwrite %||% TRUE,
    promote_manifest = FALSE
  )

  .wb_assert(is.list(raw) && is.list(raw$outputs),
             "cell_set_derive must return list(outputs=<list>, params=<list>).")
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

.wb_runner_cell_vector_family_graph_smooth <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  .wb_assert(!is.null(resolved$signal), "cell_vector_family_graph_smooth runner: missing resolved$signal.")
  .wb_assert(!is.null(resolved$space), "cell_vector_family_graph_smooth runner: missing resolved$space.")

  source_signal_artifact_id <- inputs$source_signal_artifact_id %||% NULL
  if (is.null(source_signal_artifact_id) &&
      is.list(inputs$signal) &&
      identical(as.character(inputs$signal$ref_type %||% "")[1], "artifact")) {
    source_signal_artifact_id <- as.character(inputs$signal$artifact_id %||% NA_character_)[1]
  }

  source_run_id <- inputs$source_run_id %||% NULL
  source_snapshot_id <- inputs$source_snapshot_id %||% NULL
  if (!is.null(source_signal_artifact_id) && nzchar(as.character(source_signal_artifact_id)[1])) {
    art <- tryCatch(wb_art_list(bundle), error = function(e) NULL)
    if (is.data.frame(art) && nrow(art)) {
      hit <- art[as.character(art$artifact_id) == as.character(source_signal_artifact_id)[1], , drop = FALSE]
      if (nrow(hit)) {
        source_run_id <- source_run_id %||% if ("source_run_id" %in% names(hit)) hit$source_run_id[[1]] else NULL
        source_snapshot_id <- source_snapshot_id %||% if ("provenance_snapshot_id" %in% names(hit)) hit$provenance_snapshot_id[[1]] else NULL
      }
    }
  }

  raw <- wb_op_cell_vector_family_graph_smooth(
    bundle = bundle,
    signal = resolved$signal,
    space_id = resolved$space$space_id,
    cells = as.character(effective_cells),
    signal_keys = inputs$signal_keys %||% NULL,
    dims = inputs$dims %||% NULL,
    k = inputs$k %||% 30L,
    alpha = inputs$alpha %||% 0.5,
    distance_metric = inputs$distance_metric %||% "euclidean",
    query_chunk_size = inputs$query_chunk_size %||% 512L,
    include_self = inputs$include_self %||% FALSE,
    na_policy = inputs$na_policy %||% "ignore",
    cell_set = inputs$cell_set %||% NULL,
    source_signal_artifact_id = source_signal_artifact_id,
    source_run_id = source_run_id,
    source_snapshot_id = source_snapshot_id
  )

  .wb_assert(is.list(raw) && is.list(raw$outputs),
             "cell_vector_family_graph_smooth must return list(outputs=<list>, params=<list>).")
  raw
}

.wb_runner_cell_vector_winners <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  .wb_assert(!is.null(resolved$signal), "cell_vector_winners runner: missing resolved$signal.")

  sig <- resolved$signal
  keep <- intersect(as.character(sig$cell_id), as.character(effective_cells))
  ii <- as.character(sig$cell_id) %in% keep
  sig_use <- wb_prim_cell_vector_family(
    key = as.character(sig$key[ii]),
    cell_id = as.character(sig$cell_id[ii]),
    value = as.numeric(sig$value[ii]),
    value_type = as.character(sig$value_type %||% "continuous")[1]
  )

  raw <- wb_op_cell_vector_winners(
    signal = sig_use,
    signal_keys = inputs$signal_keys %||% NULL,
    min_winners = inputs$min_winners %||% 10L,
    tie_method = inputs$tie_method %||% "first",
    source_score_artifact_id = inputs$source_score_artifact_id %||% NULL,
    source_run_id = inputs$source_run_id %||% NULL,
    source_snapshot_id = inputs$source_snapshot_id %||% NULL
  )

  .wb_assert(is.list(raw) && is.list(raw$outputs),
             "cell_vector_winners must return list(outputs=<list>, params=<list>).")
  raw
}

.wb_runner_winner_cell_sets <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  .wb_assert(!is.null(resolved$winners), "winner_cell_sets runner: missing resolved$winners.")

  manifest <- wb_register_winner_cell_sets(
    bundle = bundle,
    winners = resolved$winners,
    source_winner_artifact_id = inputs$source_winner_artifact_id %||% NULL,
    cell_set_prefix = inputs$cell_set_prefix %||% "winner_",
    winner_col = inputs$winner_col %||% "winner",
    passes_col = inputs$passes_col %||% "passes_pruning",
    source = inputs$source %||% "cell_vector_winners",
    created_by = inputs$created_by %||% NULL,
    replace = inputs$replace %||% TRUE
  )

  list(
    outputs = list(manifest = manifest),
    params = list(
      cell_set_prefix = inputs$cell_set_prefix %||% "winner_",
      winner_col = inputs$winner_col %||% "winner",
      passes_col = inputs$passes_col %||% "passes_pruning",
      replace = inputs$replace %||% TRUE,
      n_cell_sets = nrow(manifest$table)
    )
  )
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

.wb_runner_resolve_optional_membership <- function(bundle, membership) {
  if (is.null(membership)) return(NULL)
  if (.wb_is_primitive(membership)) return(membership)
  aid <- .wb_ref_to_artifact_id(membership)
  if (!is.null(aid) && nzchar(as.character(aid)[1])) {
    return(wb_art_load(bundle, artifact_id = as.character(aid)[1], expected_kind = "cell_vector"))
  }
  if (is.character(membership) && length(membership) == 1L && startsWith(membership, "artifact:")) {
    return(wb_art_load(bundle, artifact_id = sub("^artifact:", "", membership), expected_kind = "cell_vector"))
  }
  membership
}

.wb_runner_trajectory_geneset_dynamics <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  .wb_assert(!is.null(resolved$matrix), "trajectory_geneset_dynamics runner: missing resolved$matrix.")
  explicit_pt <- !is.null(inputs$pseudotime) || !is.null(inputs$pseudotime_ref)
  explicit_model <- !is.null(inputs$model) || !is.null(inputs$model_ref)

  raw <- wb_op_trajectory_geneset_dynamics(
    bundle = bundle,
    matrix_id = resolved$matrix$matrix_id,
    model = if (isTRUE(explicit_pt) && !isTRUE(explicit_model)) NULL else resolved$model %||% NULL,
    pseudotime = resolved$pseudotime %||% NULL,
    pseudotime_key = inputs$pseudotime_key %||% NULL,
    membership = .wb_runner_resolve_optional_membership(bundle, inputs$membership %||% NULL),
    pseudotime_artifact_id = .wb_trajectory_input_artifact_id(inputs$pseudotime %||% inputs$pseudotime_ref %||% NULL),
    membership_artifact_id = .wb_trajectory_input_artifact_id(inputs$membership %||% NULL),
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
    min_mean_score = inputs$min_mean_score %||% 0,
    min_max_score = inputs$min_max_score %||% 0,
    min_signal_to_noise = inputs$min_signal_to_noise %||% 0,
    low_abundance_max_score = inputs$low_abundance_max_score %||% 0.1,
    smooth_method = inputs$smooth_method %||% "none",
    loess_span = inputs$loess_span %||% 0.5,
    bootstrap_n = inputs$bootstrap_n %||% 0L,
    bootstrap_seed = inputs$bootstrap_seed %||% 1L,
    ci_level = inputs$ci_level %||% 0.95,
    class_min_amplitude = inputs$class_min_amplitude %||% 0,
    n_permutations = inputs$n_permutations %||% 0L,
    permutation_seed = inputs$permutation_seed %||% 1L,
    p_adjust_method = inputs$p_adjust_method %||% "BH"
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

.wb_runner_trajectory_signal_dynamics <- function(bundle, resolved, effective_cells, inputs = list(), ...) {
  .wb_assert(!is.null(resolved$signal), "trajectory_signal_dynamics runner: missing resolved$signal.")
  explicit_pt <- !is.null(inputs$pseudotime) || !is.null(inputs$pseudotime_ref)
  explicit_model <- !is.null(inputs$model) || !is.null(inputs$model_ref)

  raw <- wb_op_trajectory_signal_dynamics(
    bundle = bundle,
    signal = resolved$signal,
    model = if (isTRUE(explicit_pt) && !isTRUE(explicit_model)) NULL else resolved$model %||% NULL,
    pseudotime = resolved$pseudotime %||% NULL,
    pseudotime_key = inputs$pseudotime_key %||% NULL,
    membership = .wb_runner_resolve_optional_membership(bundle, inputs$membership %||% NULL),
    pseudotime_artifact_id = .wb_trajectory_input_artifact_id(inputs$pseudotime %||% inputs$pseudotime_ref %||% NULL),
    membership_artifact_id = .wb_trajectory_input_artifact_id(inputs$membership %||% NULL),
    cells = as.character(effective_cells),
    lineage = inputs$lineage %||% NULL,
    signal_keys = inputs$signal_keys %||% NULL,
    n_bins = inputs$n_bins %||% 50L,
    summary_fun = inputs$summary_fun %||% "mean",
    min_cells_per_bin = inputs$min_cells_per_bin %||% 5L,
    top_n = inputs$top_n %||% 50L,
    on_off_min_delta = inputs$on_off_min_delta %||% 0,
    monotonic_min_abs_rho = inputs$monotonic_min_abs_rho %||% 0.5,
    pseudotime_direction = inputs$pseudotime_direction %||% "as_is",
    start_label = inputs$start_label %||% NULL,
    end_label = inputs$end_label %||% NULL,
    min_amplitude = inputs$min_amplitude %||% 0,
    min_bins_observed = inputs$min_bins_observed %||% 5L,
    smooth_method = inputs$smooth_method %||% "none",
    loess_span = inputs$loess_span %||% 0.5,
    bootstrap_n = inputs$bootstrap_n %||% 0L,
    bootstrap_seed = inputs$bootstrap_seed %||% 1L,
    ci_level = inputs$ci_level %||% 0.95,
    class_min_amplitude = inputs$class_min_amplitude %||% 0
  )

  .wb_assert(is.list(raw) && is.list(raw$outputs),
             "trajectory_signal_dynamics must return list(outputs=<list>, params=<list>).")
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
    matrix_log_normalize = list(
      op_name = "matrix_log_normalize",
      title = "Log-normalize count matrix",
      description = "Create a reusable log1p(counts / library_size * scale_factor) BPCells matrix in the bundle.",
      semantics = list(
        transform = "log1p(count / cell_library_size * scale_factor)",
        library_size = "sum of input counts across features for each cell",
        scale_factor = "per-cell target count before log1p"
      ),
      intent = c("matrix", "normalize", "rna", "transform"),
      requires = list(matrix = "matrix"),
      produces = list(
        matrix = "matrix",
        summary = "obs_table"
      ),
      promotable = c("summary"),
      runner = .wb_runner_matrix_log_normalize,
      inputs = list(
        matrix = list(required = TRUE, kind = "matrix")
      ),
      params = list(
        list(name = "output_matrix_id", type = "string", default = NULL,
             help = "Matrix id to create, for example RNA_log1p_cp10k. Defaults to <source>_log1p_cp<scale_factor>."),
        list(name = "scale_factor", type = "dbl", default = 10000, min = 1, max = 1e9,
             help = "Per-cell target count scale before log1p; 10000 is the common CP10K convention."),
        list(name = "overwrite", type = "bool", default = FALSE,
             help = "If TRUE, replace an existing output matrix with the same id."),
        list(name = "cell_set", type = "cell_set", default = "all",
             help = "Must be 'all' because the output matrix is registered as a full bundle matrix.")
      ),
      interface_produces = list(
        matrix = list(
          kind = "matrix",
          description = "Reference to the newly registered log-normalized matrix."
        ),
        summary = list(
          kind = "obs_table",
          table_type = "matrix_log_normalize_summary",
          description = "Transform parameters, source/output matrix ids, dimensions, library-size diagnostics, and storage path."
        )
      )
    ),
    hvg_select = list(
      op_name = "hvg_select",
      title = "Highly Variable Feature Selection",
      description = "Select highly variable features from a matrix using chunked feature-wise summaries.",
      intent = c("matrix", "feature_selection", "rna", "hvg"),
      requires = list(matrix = "matrix"),
      produces = list(
        selected_features = "feature_table",
        fit_summary = "obs_table"
      ),
      promotable = c("selected_features", "fit_summary"),
      chunking = list(
        chunkable = TRUE,
        axis = "features",
        chunk_size_param = "chunk_size",
        chunk_size_default = 256L,
        status = "implemented_op_internal"
      ),
      runner = .wb_runner_hvg_select,
      inputs = list(
        matrix = list(required = TRUE, kind = "matrix")
      ),
      params = list(
        list(name = "n_features", type = "int", default = 2000L, min = 1, max = 1000000,
             help = "Number of highly variable features to mark selected."),
        list(name = "method", type = "choice", default = "vst",
             choices = c("vst", "dispersion", "variance"),
             help = "Feature scoring method. 'vst' is a lightweight stabilized dispersion score log1p(variance / mean)."),
        list(name = "min_mean", type = "dbl", default = NULL, min = 0,
             help = "Optional minimum feature mean filter."),
        list(name = "max_mean", type = "dbl", default = NULL, min = 0,
             help = "Optional maximum feature mean filter."),
        list(name = "min_dispersion", type = "dbl", default = NULL, min = 0,
             help = "Optional minimum HVG score filter."),
        list(name = "batch_key", type = "string", default = NULL,
             help = "Reserved for future batch-aware HVG; currently unsupported if non-null."),
        list(name = "exclude_features", type = "string_vec", default = NULL,
             help = "Optional feature IDs to exclude before ranking."),
        list(name = "feature_type", type = "string", default = NULL,
             help = "Optional feature_type filter from the bundle feature registry."),
        list(name = "seed", type = "int", default = 1L,
             help = "Random seed reserved for deterministic future methods."),
        list(name = "chunk_size", type = "int", default = 256L, min = 1, max = 100000,
             help = "Feature chunk size for backed matrix reads.")
      ),
      interface_produces = list(
        selected_features = list(
          kind = "feature_table",
          table_type = "feature_selection_table",
          description = "Feature-wise mean, variance, dispersion, score, rank, and selected flag."
        ),
        fit_summary = list(
          kind = "obs_table",
          table_type = "hvg_select_summary",
          description = "Input matrix, method, filters, dimensions, and selection counts."
        )
      )
    ),
    pca_fit = list(
      op_name = "pca_fit",
      title = "PCA Fit",
      description = "Compute PCA from a matrix and selected features, then persist the cell coordinates as a bundle space.",
      intent = c("matrix", "pca", "space", "rna", "dimension_reduction"),
      requires = list(matrix = "matrix"),
      optional_requires = list(features = "feature_table"),
      produces = list(
        space = "space",
        loadings = "feature_table",
        variance = "obs_table",
        fit_summary = "obs_table"
      ),
      promotable = c("loadings", "variance", "fit_summary"),
      runner = .wb_runner_pca_fit,
      inputs = list(
        matrix = list(required = TRUE, kind = "matrix"),
        features = list(required = FALSE, kind = "feature_table")
      ),
      params = list(
        list(name = "feature_ids", type = "string_vec", default = NULL,
             help = "Optional explicit feature IDs when not passing features as a feature_table reference."),
        list(name = "n_components", type = "int", default = 50L, min = 2, max = 10000,
             help = "Number of principal components to compute."),
        list(name = "center", type = "bool", default = TRUE,
             help = "Center features before PCA."),
        list(name = "scale", type = "bool", default = TRUE,
             help = "Scale features before PCA."),
        list(name = "backend", type = "choice", default = "irlba",
             choices = c("irlba", "prcomp"),
             help = "PCA backend. 'irlba' is recommended for large sparse/backed matrices."),
        list(name = "seed", type = "int", default = 1L,
             help = "Random seed."),
        list(name = "space_id_out", type = "string", default = "rna.pca",
             help = "Bundle space id to create."),
        list(name = "overwrite", type = "bool", default = FALSE,
             help = "Replace an existing space_id_out if present."),
        list(name = "max_dense_gb", type = "dbl", default = 8, min = 0.1,
             help = "Approximate dense selected-block size guard for dense backends.")
      ),
      interface_produces = list(
        space = list(
          kind = "space",
          description = "Reference to the persisted PCA space."
        ),
        loadings = list(
          kind = "feature_table",
          table_type = "pca_loadings",
          description = "Feature loadings per principal component."
        ),
        variance = list(
          kind = "obs_table",
          table_type = "pca_variance_explained",
          description = "Per-PC standard deviation and variance explained."
        ),
        fit_summary = list(
          kind = "obs_table",
          table_type = "pca_fit_summary",
          description = "Input matrix, feature count, backend, component count, and output space id."
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
        list(name = "space_id_out", type = "string", default = NULL,
             help = "Output 2D space id. Defaults to umap.<source_space>."),
        list(name = "n_neighbors", type = "int", default = 30, min = 2, max = 100000,
             help = "UMAP neighborhood size."),
        list(name = "min_dist", type = "dbl", default = 0.3, min = 0, max = 1,
             help = "UMAP minimum distance."),
        list(name = "metric", type = "string", default = "euclidean",
             help = "Distance metric passed to uwot."),
        list(name = "nn_method", type = "choice", default = "nndescent",
             choices = c("nndescent", "annoy", "fnn"),
             help = "Nearest-neighbor backend. 'nndescent' requires rnndescent; 'fnn' requires FNN; 'annoy' uses uwot's Annoy backend."),
        list(name = "spread", type = "dbl", default = 1.0, min = 0,
             help = "UMAP spread parameter."),
        list(name = "seed", type = "int", default = 1,
             help = "Random seed.")
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
        status = "active"
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
        list(name = "chunk_size", type = "int", default = 2000L, min = 8, max = 1000000,
             help = "Cell-axis chunk size for engine-owned UCell execution. Use NULL to disable chunking."),
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
    cell_vector_family_graph_smooth = list(
      op_name = "cell_vector_family_graph_smooth",
      title = "Graph Smooth Cell Vector Family",
      description = "Smooth each key of a cell_vector_family over local nearest-neighbor geometry in a selected bundle space.",
      intent = c("signal", "smoothing", "geometry"),
      requires = list(signal = "cell_vector_family", space = "space"),
      produces = list(
        smoothed_signal = "cell_vector_family",
        smoothing_summary = "obs_table"
      ),
      promotable = c("smoothed_signal", "smoothing_summary"),
      runner = .wb_runner_cell_vector_family_graph_smooth,
      inputs = list(
        signal = list(required = TRUE, kind = "cell_vector_family"),
        space = list(required = TRUE, kind = "space")
      ),
      params = list(
        list(name = "signal_keys", type = "string_vec", default = NULL,
             help = "Optional key subset within the cell_vector_family."),
        list(name = "dims", type = "int_vec", default = NULL,
             help = "Optional dimensions of the selected space. NULL uses all dimensions."),
        list(name = "k", type = "int", default = 30L, min = 1, max = 100000,
             help = "Nearest-neighbor count per cell."),
        list(name = "alpha", type = "dbl", default = 0.5, min = 0, max = 1,
             help = "Blend weight for raw score in alpha * raw + (1 - alpha) * neighbor_mean."),
        list(name = "distance_metric", type = "choice", default = "euclidean",
             choices = c("euclidean"),
             help = "Distance metric used for nearest-neighbor search."),
        list(name = "query_chunk_size", type = "int", default = 512L, min = 1, max = 1000000,
             help = "Number of query cells processed per nearest-neighbor chunk."),
        list(name = "include_self", type = "bool", default = FALSE,
             help = "Include each cell itself in its neighbor mean."),
        list(name = "na_policy", type = "choice", default = "ignore",
             choices = c("ignore", "zero", "propagate"),
             help = "How missing signal values are handled during neighbor averaging."),
        list(name = "source_signal_artifact_id", type = "string", default = NULL,
             help = "Optional source cell_vector_family artifact ID copied into metadata."),
        list(name = "source_run_id", type = "string", default = NULL,
             help = "Optional source run ID copied into metadata."),
        list(name = "source_snapshot_id", type = "string", default = NULL,
             help = "Optional source provenance snapshot ID copied into metadata.")
      ),
      interface_produces = list(
        smoothed_signal = list(
          kind = "cell_vector_family",
          value_kind = "continuous",
          key = "signal_key",
          description = "Geometry-smoothed per-cell values for each selected key."
        ),
        smoothing_summary = list(
          kind = "obs_table",
          table_type = "cell_vector_family_graph_smooth_summary",
          entity_kind = "signal_key",
          description = "Per-key smoothing diagnostics and parameter echo."
        )
      )
    ),
    cell_vector_winners = list(
      op_name = "cell_vector_winners",
      title = "Cell Vector Winner Assignment",
      description = "Assign one winning key per cell from a cell_vector_family and report confidence and pruning metrics.",
      intent = c("signal", "labeling", "winner"),
      requires = list(signal = "cell_vector_family"),
      produces = list(winners = "obs_table"),
      promotable = c("winners"),
      runner = .wb_runner_cell_vector_winners,
      inputs = list(
        signal = list(required = TRUE, kind = "cell_vector_family")
      ),
      params = list(
        list(name = "signal_keys", type = "string_vec", default = NULL,
             help = "Optional key subset within the cell_vector_family."),
        list(name = "min_winners", type = "int", default = 10L, min = 0, max = 100000000,
             help = "Minimum raw winner count required for a winner label to pass pruning."),
        list(name = "tie_method", type = "choice", default = "first",
             choices = c("first", "last"),
             help = "Deterministic tie handling for top-score winners."),
        list(name = "source_score_artifact_id", type = "string", default = NULL,
             help = "Optional source cell_vector_family artifact ID copied into winner table metadata."),
        list(name = "source_run_id", type = "string", default = NULL,
             help = "Optional source run ID copied into winner table metadata."),
        list(name = "source_snapshot_id", type = "string", default = NULL,
             help = "Optional source provenance snapshot ID copied into winner table metadata.")
      ),
      interface_produces = list(
        winners = list(
          kind = "obs_table",
          table_type = "cell_vector_winners",
          entity_kind = "cell",
          description = "Per-cell winner, runner-up, confidence, and pruning table."
        )
      )
    ),
    winner_cell_sets = list(
      op_name = "winner_cell_sets",
      title = "Winner Cell-Set Registration",
      description = "Register bundle cell sets from a cell_vector_winners obs_table and return a manifest table.",
      intent = c("signal", "labeling", "cell_sets"),
      requires = list(winners = "obs_table"),
      produces = list(manifest = "obs_table"),
      promotable = c("manifest"),
      runner = .wb_runner_winner_cell_sets,
      inputs = list(
        winners = list(required = TRUE, kind = "obs_table")
      ),
      params = list(
        list(name = "source_winner_artifact_id", type = "string", default = NULL,
             help = "Optional source winner obs_table artifact ID copied into manifest metadata."),
        list(name = "cell_set_prefix", type = "string", default = "winner_",
             help = "Prefix used after set: when creating winner cell-set names."),
        list(name = "winner_col", type = "string", default = "winner",
             help = "Winner-label column in the winner table."),
        list(name = "passes_col", type = "string", default = "passes_pruning",
             help = "Logical pruning-pass column in the winner table."),
        list(name = "source", type = "string", default = "cell_vector_winners",
             help = "Source label stored on cell-set membership rows."),
        list(name = "created_by", type = "string", default = NULL,
             help = "Optional actor stored on cell-set membership rows."),
        list(name = "replace", type = "logical", default = TRUE,
             help = "If TRUE, replace existing winner cell-set memberships.")
      ),
      interface_produces = list(
        manifest = list(
          kind = "obs_table",
          table_type = "winner_cell_set_manifest",
          entity_kind = "cell_set",
          description = "One row per registered winner cell set."
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
    feature_set_import = list(
      op_name = "feature_set_import",
      title = "Feature-Set Library Import",
      description = "Import GMT/RDS/table feature-set libraries into the bundle feature-set registry and emit import provenance tables.",
      intent = c("feature_set", "import", "gene_set", "provenance", "library"),
      requires = list(matrix = "matrix"),
      produces = list(
        import_summary = "obs_table",
        import_manifest = "obs_table",
        rejected_sets = "obs_table"
      ),
      promotable = c("import_summary", "import_manifest", "rejected_sets"),
      runner = .wb_runner_feature_set_import,
      inputs = list(
        matrix = list(required = TRUE, kind = "matrix")
      ),
      params = list(
        list(name = "source_path", type = "path", default = NULL,
             help = "Path to GMT, RDS list/data.frame, or CSV-like table source."),
        list(name = "source_format", type = "choice", default = "auto",
             choices = c("auto", "gmt", "rds", "table"),
             help = "Input parser. auto infers from file extension."),
        list(name = "namespace", type = "string", default = NULL,
             help = "Target feature-set namespace base label."),
        list(name = "collection", type = "string", default = NULL,
             help = "Optional collection label recorded in import manifests."),
        list(name = "subcollection", type = "string", default = NULL,
             help = "Optional subcollection label; used for namespace splitting when requested."),
        list(name = "species", type = "string", default = NULL,
             help = "Species/organism label recorded in feature-set metadata."),
        list(name = "gene_id_type", type = "string", default = NULL,
             help = "Identifier type expected in source genes, for example gene_symbol."),
        list(name = "set_id_col", type = "string", default = "feature_set",
             help = "For table sources, column containing set identifiers."),
        list(name = "set_name_col", type = "string", default = NULL,
             help = "For table sources, optional human-readable set-name column."),
        list(name = "gene_col", type = "string", default = "feature_id",
             help = "For table sources, column containing gene/feature identifiers."),
        list(name = "description_col", type = "string", default = "description",
             help = "For table sources, optional set description column."),
        list(name = "split_by_collection", type = "bool", default = FALSE,
             help = "If TRUE, append detected/declared subcollection to the namespace base."),
        list(name = "overwrite", type = "bool", default = TRUE,
             help = "If FALSE, existing feature sets are skipped instead of replaced."),
        list(name = "strict", type = "bool", default = FALSE,
             help = "If TRUE, error on genes absent from the matrix; otherwise drop absent genes."),
        list(name = "source_id", type = "string", default = NULL,
             help = "Optional source/library identifier stored in feature-set metadata."),
        list(name = "source_version", type = "string", default = NULL,
             help = "Optional source/library version stored in feature-set metadata.")
      ),
      interface_produces = list(
        import_summary = list(
          kind = "obs_table",
          table_type = "feature_set_import_summary",
          description = "One-row summary of parsed/imported/skipped/rejected set counts."
        ),
        import_manifest = list(
          kind = "obs_table",
          table_type = "feature_set_import_manifest",
          description = "One row per parsed feature set with target namespace, overlap counts, and import status."
        ),
        rejected_sets = list(
          kind = "obs_table",
          table_type = "feature_set_import_rejected",
          description = "Feature sets rejected during import, typically because no genes mapped to the matrix."
        )
      )
    ),
    feature_set_overlap_qc = list(
      op_name = "feature_set_overlap_qc",
      title = "Feature-Set Matrix Overlap QC",
      description = "Screen imported feature-set namespaces against a matrix before pathway or trajectory discovery.",
      intent = c("feature_set", "qc", "gene_set", "screening", "trajectory"),
      requires = list(matrix = "matrix"),
      produces = list(
        overlap_qc = "obs_table",
        namespace_summary = "obs_table"
      ),
      promotable = c("overlap_qc", "namespace_summary"),
      runner = .wb_runner_feature_set_overlap_qc,
      inputs = list(
        matrix = list(required = TRUE, kind = "matrix")
      ),
      params = list(
        list(name = "namespace", type = "string", default = NULL,
             help = "Single feature-set namespace to QC."),
        list(name = "namespaces", type = "string_vec", default = NULL,
             help = "Optional multiple feature-set namespaces to QC."),
        list(name = "feature_sets", type = "string_vec", default = NULL,
             help = "Optional feature-set subset within selected namespaces."),
        list(name = "min_set_size", type = "int", default = 1, min = 0,
             help = "Minimum mapped/detected genes required to include a set."),
        list(name = "max_set_size", type = "dbl", default = Inf, min = 1,
             help = "Maximum mapped/detected genes allowed to include a set."),
        list(name = "min_detected_fraction", type = "dbl", default = 0, min = 0, max = 1,
             help = "Minimum fraction of source genes detected in the matrix."),
        list(name = "deduplicate_sets", type = "bool", default = TRUE,
             help = "If TRUE, duplicate mapped-gene signatures after the first are excluded.")
      ),
      interface_produces = list(
        overlap_qc = list(
          kind = "obs_table",
          table_type = "feature_set_overlap_qc",
          description = "One row per feature set with raw, mapped, detected counts and include/exclude status."
        ),
        namespace_summary = list(
          kind = "obs_table",
          table_type = "feature_set_overlap_qc_summary",
          description = "Namespace-level count and overlap summaries."
        )
      )
    ),
    feature_set_namespace_transfer = list(
      op_name = "feature_set_namespace_transfer",
      title = "Feature-Set Namespace Transfer",
      description = "Transfer matrix-scoped feature-set namespaces between comparable matrices using mirror or intersect semantics.",
      intent = c("feature_set", "transfer", "namespace", "matrix", "provenance"),
      requires = list(source_matrix = "matrix", target_matrix = "matrix"),
      produces = list(
        transfer_summary = "obs_table",
        transfer_manifest = "obs_table",
        transfer_rejected = "obs_table"
      ),
      promotable = c("transfer_summary", "transfer_manifest", "transfer_rejected"),
      runner = .wb_runner_feature_set_namespace_transfer,
      inputs = list(),
      params = list(
        list(name = "namespace", type = "string", default = NULL,
             help = "Single source namespace to transfer."),
        list(name = "namespaces", type = "string_vec", default = NULL,
             help = "Optional multiple source namespaces to transfer."),
        list(name = "feature_sets", type = "string_vec", default = NULL,
             help = "Optional feature-set subset within selected source namespaces."),
        list(name = "mode", type = "choice", default = "mirror",
             choices = c("mirror", "intersect"),
             help = "mirror requires identical feature universes; intersect retains only target-valid members and records loss."),
        list(name = "target_namespace", type = "string", default = NULL,
             help = "Optional target namespace override. Defaults to the source namespace."),
        list(name = "overwrite", type = "bool", default = FALSE,
             help = "If FALSE, existing target feature sets are skipped instead of replaced."),
        list(name = "strict", type = "bool", default = TRUE,
             help = "If TRUE, fail when intersect mode rejects any selected set by retention thresholds."),
        list(name = "min_retained_features", type = "int", default = 1, min = 0,
             help = "Minimum target-retained members required to transfer a set."),
        list(name = "min_retained_fraction", type = "dbl", default = 0, min = 0, max = 1,
             help = "Minimum fraction of source members retained on the target matrix."),
        list(name = "created_by", type = "string", default = NULL,
             help = "Optional created_by metadata for transferred registry rows."),
        list(name = "notes", type = "string", default = NULL,
             help = "Optional provenance note. This op is not for gene-to-peak, peak-to-gene, motif-to-TF, ortholog, or synonym mapping.")
      ),
      interface_produces = list(
        transfer_summary = list(
          kind = "obs_table",
          table_type = "feature_set_transfer_summary",
          description = "Namespace-level summary of transfer mode, matrix compatibility, and transferred/skipped/rejected set counts."
        ),
        transfer_manifest = list(
          kind = "obs_table",
          table_type = "feature_set_transfer_manifest",
          description = "One row per source feature set with source/target matrices, namespaces, retained members, status, and set IDs."
        ),
        transfer_rejected = list(
          kind = "obs_table",
          table_type = "feature_set_transfer_rejected",
          description = "Feature sets rejected during intersect transfer because retained members failed thresholds."
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
    cell_set_derive = list(
      op_name = "cell_set_derive",
      title = "Derived Cell Set",
      description = "Materialize a selector-derived or explicitly declared cell universe as a named cell set with lifecycle role/status and manifest tables.",
      intent = c("selection", "provenance", "registry"),
      requires = list(),
      produces = list(manifest = "obs_table", rule_table = "obs_table"),
      promotable = c("manifest", "rule_table"),
      runner = .wb_runner_cell_set_derive,
      inputs = list(),
      params = list(
        list(name = "target_cell_set", type = "string", default = NULL,
             help = "Name of the derived cell set to create, for example set:universe_b_l1_weight090."),
        list(name = "role", type = "choice", default = "analysis_universe",
             choices = c("core", "annotation", "analysis_universe", "exclusion_set", "endpoint_set", "diagnostic", "temporary"),
             help = "Lifecycle role of the derived set."),
        list(name = "status", type = "choice", default = "candidate",
             choices = c("active", "candidate", "accepted", "superseded", "rejected", "temporary"),
             help = "Lifecycle status controlling interpretation and default visibility."),
        list(name = "source", type = "string", default = "selector_recipe",
             help = "Source/provenance label stored on membership rows."),
        list(name = "created_by", type = "string", default = NULL,
             help = "Optional creator label."),
        list(name = "description", type = "string", default = NULL,
             help = "Human-readable derivation rationale."),
        list(name = "overwrite", type = "bool", default = TRUE,
             help = "If TRUE, replace existing membership for the target set; if FALSE, add cells to it.")
      ),
      interface_produces = list(
        manifest = list(
          kind = "obs_table",
          table_type = "derived_cell_set_manifest",
          entity_kind = "cell_set",
          description = "One-row lifecycle manifest for the named derived cell set, including counts, role, status, recipe availability, and source summary."
        ),
        rule_table = list(
          kind = "obs_table",
          table_type = "derived_cell_set_rules",
          entity_kind = "cell_set_rule",
          description = "Ordered per-rule derivation audit table with input/output/removal counts and source fields."
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
             help = "Statistical test. The current implementation supports spearman."),
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
      requires = list(matrix = "matrix"),
      optional_requires = list(model = "model_ref", pseudotime = "cell_vector_family"),
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
        model = list(required = FALSE, kind = "model_ref"),
        pseudotime = list(required = FALSE, kind = "cell_vector_family")
      ),
      params = list(
        list(name = "namespace", type = "string", default = NULL,
             help = "Feature-set namespace from wb_feature_sets() to screen."),
        list(name = "feature_sets", type = "string_vec", default = NULL,
             help = "Optional feature-set subset within the namespace."),
        list(name = "lineage", type = "string_vec", default = NULL,
             help = "Optional lineage key subset."),
        list(name = "pseudotime_key", type = "string", default = NULL,
             help = "Required key for explicit cell_vector_family pseudotime when multiple keys are present."),
        list(name = "membership", type = "cell_ids_or_set", default = NULL,
             help = "Optional cell_vector artifact, cell set, or cell IDs intersected with finite pseudotime cells."),
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
        list(name = "min_mean_score", type = "dbl", default = 0, min = 0,
             help = "Optional minimum mean smoothed score required for passes_filters; use to suppress very low-abundance dynamics."),
        list(name = "min_max_score", type = "dbl", default = 0, min = 0,
             help = "Optional minimum maximum smoothed score required for passes_filters; use to suppress near-zero curves."),
        list(name = "min_signal_to_noise", type = "dbl", default = 0, min = 0,
             help = "Optional minimum amplitude divided by mean bootstrap SE required for passes_filters."),
        list(name = "low_abundance_max_score", type = "dbl", default = 0.1, min = 0,
             help = "Curves with max_score below this value are flagged low_abundance_flag but not filtered unless min_max_score is set."),
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
             help = "Minimum amplitude required before assigning non-flat curve classes."),
        list(name = "n_permutations", type = "int", default = 0, min = 0, max = 100000,
             help = "Number of empirical permutations for dynamic-score p-values; 0 disables permutation testing."),
        list(name = "permutation_seed", type = "int", default = 1, min = 1,
             help = "Random seed for empirical dynamic-score permutations."),
        list(name = "p_adjust_method", type = "choice", default = "BH",
             choices = stats::p.adjust.methods,
             help = "Multiple-testing correction method for q_dynamic.")
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
    trajectory_signal_dynamics = list(
      op_name = "trajectory_signal_dynamics",
      title = "Trajectory Signal Dynamics",
      description = "Rank precomputed cell-level signal families by dynamic behavior along trajectory pseudotime.",
      intent = c("trajectory", "signal", "discovery", "dynamics"),
      requires = list(signal = "cell_vector_family"),
      optional_requires = list(model = "model_ref", pseudotime = "cell_vector_family"),
      produces = list(
        signal_table = "obs_table",
        dynamics_table = "obs_table",
        top_signals = "obs_table",
        fit_summary = "obs_table"
      ),
      promotable = c("signal_table", "dynamics_table", "top_signals", "fit_summary"),
      runner = .wb_runner_trajectory_signal_dynamics,
      inputs = list(
        signal = list(required = TRUE, kind = "cell_vector_family"),
        model = list(required = FALSE, kind = "model_ref"),
        pseudotime = list(required = FALSE, kind = "cell_vector_family")
      ),
      params = list(
        list(name = "signal_keys", type = "string_vec", default = NULL,
             help = "Optional signal-key subset within the cell_vector_family."),
        list(name = "lineage", type = "string_vec", default = NULL,
             help = "Optional lineage key subset."),
        list(name = "pseudotime_key", type = "string", default = NULL,
             help = "Required key for explicit cell_vector_family pseudotime when multiple keys are present."),
        list(name = "membership", type = "cell_ids_or_set", default = NULL,
             help = "Optional cell_vector artifact, cell set, or cell IDs intersected with finite pseudotime cells."),
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
        list(name = "top_n", type = "int", default = 50, min = 1, max = 10000,
             help = "Number of top-ranked signals retained in top_signals."),
        list(name = "on_off_min_delta", type = "dbl", default = 0, min = 0,
             help = "Minimum absolute late-early delta for turns_on/turns_off classes."),
        list(name = "monotonic_min_abs_rho", type = "dbl", default = 0.5, min = 0, max = 1,
             help = "Minimum absolute Spearman rho for turns_on/turns_off classes."),
        list(name = "min_amplitude", type = "dbl", default = 0, min = 0,
             help = "Minimum curve amplitude required for passes_filters."),
        list(name = "min_bins_observed", type = "int", default = 5, min = 1, max = 1000,
             help = "Minimum retained bins required for passes_filters."),
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
        signal_table = list(
          kind = "obs_table",
          description = "Binned signal-score curves along trajectory pseudotime."
        ),
        dynamics_table = list(
          kind = "obs_table",
          description = "Per-signal dynamic metrics and rank."
        ),
        top_signals = list(
          kind = "obs_table",
          description = "Top-ranked dynamic signals for report-first discovery."
        ),
        fit_summary = list(
          kind = "obs_table",
          description = "Per-lineage signal dynamics diagnostics."
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
        lineage_weights = "cell_vector_family",
        model = "model_ref"
      ),
      promotable = c("pseudotime", "lineage_weights", "model"),
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
        lineage_weights = list(
          kind = "cell_vector_family",
          value_kind = "continuous",
          key = "lineage_id",
          family_kind = "trajectory_membership_weight",
          engine = "slingshot",
          range = c(0, 1),
          description = "Slingshot lineage membership weights per cell and lineage. These are trajectory membership weights, not pseudotime."
        ),
        model = list(
          kind = "model_ref",
          description = "Session-chainable Slingshot fit model (engine='slingshot')."
        )
      )
    ),
    slingshot_lineage_weights = list(
      op_name = "slingshot_lineage_weights",
      title = "Slingshot lineage weights",
      description = "Extract Slingshot lineage membership weights from an existing model_ref without refitting, preserving trajectory_fit_id and lineage mapping.",
      intent = c("trajectory", "provenance", "backfill"),
      requires = list(model = "model_ref"),
      produces = list(lineage_weights = "cell_vector_family"),
      promotable = c("lineage_weights"),
      runner = .wb_runner_slingshot_lineage_weights,
      inputs = list(
        model = list(required = TRUE, kind = "model_ref")
      ),
      params = list(),
      interface_produces = list(
        lineage_weights = list(
          kind = "cell_vector_family",
          value_kind = "continuous",
          key = "lineage_id",
          family_kind = "trajectory_membership_weight",
          engine = "slingshot",
          range = c(0, 1),
          description = "Slingshot lineage membership weights extracted from an existing model_ref; no trajectory refit is performed."
        )
      )
    ),
    trajectory_segment_join = list(
      op_name = "trajectory_segment_join",
      title = "Trajectory segment join",
      description = "Join ordered generic trajectory segments into an auditable composite pseudotime without merging parent trajectory models.",
      intent = c("trajectory", "provenance", "composition"),
      requires = list(),
      produces = list(
        composite_pseudotime_unit_segment = "cell_vector_family",
        composite_pseudotime_cell_weighted_0_1 = "cell_vector_family",
        segment_local_table = "obs_table",
        composite_manifest = "obs_table",
        composite_membership = "cell_vector"
      ),
      promotable = c("composite_pseudotime_unit_segment", "composite_pseudotime_cell_weighted_0_1", "segment_local_table", "composite_manifest", "composite_membership"),
      runner = .wb_runner_trajectory_segment_join,
      inputs = list(),
      params = list(
        list(name = "segments", type = "list", default = NULL,
             help = "Ordered segment specs with source_kind/source_engine, pseudotime ref, lineage key, optional membership/weights/confidence/path refs, labels, and order."),
        list(name = "composite_id", type = "string", default = NULL,
             help = "Optional stable trajectory_composite_id. Generated when omitted."),
        list(name = "composite_key", type = "string", default = "composite_L1",
             help = "Key used in the output composite pseudotime cell_vector_family objects."),
        list(name = "join_policy", type = "string", default = "exact_boundary_collapse",
             help = "Overlap policy. The current implementation supports exact_boundary_collapse."),
        list(name = "min_weight", type = "dbl", default = NULL,
             help = "Optional minimum lineage weight required for segment-local membership when weights are supplied."),
        list(name = "allow_legacy", type = "bool", default = FALSE,
             help = "Allow missing trajectory_fit_id within a segment with warning. Default rejects legacy ambiguity.")
      ),
      interface_produces = list(
        composite_pseudotime_unit_segment = list(
          kind = "cell_vector_family",
          value_kind = "continuous",
          key = "composite_key",
          family_kind = "trajectory_composite_pseudotime",
          description = "Canonical one-row-per-cell composite pseudotime with exact integer segment boundaries."
        ),
        composite_pseudotime_cell_weighted_0_1 = list(
          kind = "cell_vector_family",
          value_kind = "continuous",
          key = "composite_key",
          family_kind = "trajectory_composite_pseudotime",
          description = "One-row-per-cell composite pseudotime normalized to [0,1] with segment lengths weighted by segment-local cell counts."
        ),
        segment_local_table = list(
          kind = "obs_table",
          table_type = "trajectory_segment_local_membership",
          description = "One row per cell per parent segment preserving source kind, raw pseudotime, normalized pseudotime, confidence, weight, and segment role."
        ),
        composite_manifest = list(
          kind = "obs_table",
          table_type = "trajectory_segment_join_manifest",
          description = "Audit manifest recording parent segment sources, artifacts, fit IDs where available, labels, join policy, overlap counts, and caveats."
        ),
        composite_membership = list(
          kind = "cell_vector",
          value_kind = "categorical",
          description = "One-cell assignment to a unique segment or waypoint overlap."
        )
      )
    ),
    trajectory_segment_from_artifacts = list(
      op_name = "trajectory_segment_from_artifacts",
      title = "Trajectory fitted-artifact segment",
      description = "Materialize the generic trajectory segment contract from fitted-model trajectory artifacts with fit-family validation.",
      intent = c("trajectory", "adapter", "composition", "provenance"),
      requires = list(pseudotime = "cell_vector_family"),
      optional_requires = list(
        model = "model_ref",
        lineage_weights = "cell_vector_family",
        confidence = "cell_vector_family",
        path = "path_2d_family"
      ),
      produces = list(
        pseudotime = "cell_vector_family",
        membership = "cell_vector",
        confidence = "cell_vector_family",
        segment_manifest = "obs_table"
      ),
      promotable = c("pseudotime", "membership", "confidence", "segment_manifest"),
      runner = .wb_runner_trajectory_segment_from_artifacts,
      inputs = list(
        pseudotime = list(required = TRUE, kind = "cell_vector_family"),
        model = list(required = FALSE, kind = "model_ref"),
        lineage_weights = list(required = FALSE, kind = "cell_vector_family"),
        confidence = list(required = FALSE, kind = "cell_vector_family"),
        path = list(required = FALSE, kind = "path_2d_family")
      ),
      params = list(
        list(name = "segment_id", type = "string", default = NULL,
             help = "Stable segment identifier."),
        list(name = "segment_order", type = "dbl", default = 1,
             help = "Order of this fitted segment in a future composite."),
        list(name = "lineage", type = "string", default = NULL,
             help = "Lineage/key to extract from fitted pseudotime and optional weights."),
        list(name = "membership", type = "cell_ids_or_set", default = NULL,
             help = "Optional cell_vector artifact, cell set, or cell IDs intersected with finite pseudotime cells."),
        list(name = "confidence_key", type = "string", default = NULL,
             help = "Optional key for confidence cell_vector_family. Defaults to lineage."),
        list(name = "source_engine", type = "string", default = NULL,
             help = "Fitted trajectory engine, usually slingshot, monocle3, or palantir."),
        list(name = "start_label", type = "string", default = NULL,
             help = "Biological start label."),
        list(name = "end_label", type = "string", default = NULL,
             help = "Biological end label."),
        list(name = "allow_legacy", type = "bool", default = FALSE,
             help = "Allow missing trajectory_fit_id with warning. Default rejects legacy ambiguity.")
      ),
      interface_produces = list(
        pseudotime = list(
          kind = "cell_vector_family",
          value_kind = "continuous",
          source_kind = "fitted_model",
          description = "Fitted-model segment pseudotime for the selected lineage/key."
        ),
        membership = list(
          kind = "cell_vector",
          value_kind = "categorical",
          description = "Cells included in the fitted-model segment."
        ),
        confidence = list(
          kind = "cell_vector_family",
          value_kind = "continuous",
          description = "Segment confidence, derived from supplied confidence/lineage weights or defaulting to 1."
        ),
        segment_manifest = list(
          kind = "obs_table",
          table_type = "trajectory_segment_manifest",
          description = "Audit manifest for the fitted-model segment."
        )
      )
    ),
    trajectory_space_path_segment = list(
      op_name = "trajectory_space_path_segment",
      title = "Trajectory space-path segment",
      description = "Convert space_path_score output into a generic trajectory segment using path-progress pseudotime and transparent distance-based membership.",
      intent = c("trajectory", "bridge", "composition", "geometry"),
      requires = list(path_scores = "cell_vector_family"),
      optional_requires = list(display_path = "path_2d_family"),
      produces = list(
        pseudotime = "cell_vector_family",
        membership = "cell_vector",
        confidence = "cell_vector_family",
        segment_manifest = "obs_table",
        display_endpoint_qc = "obs_table"
      ),
      promotable = c("pseudotime", "membership", "confidence", "segment_manifest", "display_endpoint_qc"),
      runner = .wb_runner_trajectory_space_path_segment,
      inputs = list(
        path_scores = list(required = TRUE, kind = "cell_vector_family"),
        display_path = list(required = FALSE, kind = "path_2d_family")
      ),
      params = list(
        list(name = "segment_id", type = "string", default = NULL,
             help = "Stable segment identifier."),
        list(name = "segment_order", type = "dbl", default = 1,
             help = "Order of this bridge segment in a future composite."),
        list(name = "score_prefix", type = "string", default = NULL,
             help = "Optional prefix used by space_path_score keys."),
        list(name = "candidate_cells", type = "cell_ids_or_set", default = NULL,
             help = "Optional candidate universe before distance thresholding."),
        list(name = "distance_threshold", type = "dbl", default = NULL,
             help = "Include cells with distance_to_path <= threshold."),
        list(name = "distance_quantile", type = "dbl", default = NULL,
             help = "Alternative threshold: include cells up to this distance quantile."),
        list(name = "start_label", type = "string", default = NULL,
             help = "Biological start label."),
        list(name = "end_label", type = "string", default = NULL,
             help = "Biological end label."),
        list(name = "display_lineage", type = "string", default = NULL,
             help = "Optional key/lineage to validate in display_path. Defaults to the only key if display_path has one."),
        list(name = "display_space_id", type = "string", default = NULL,
             help = "2D display space used for endpoint cell-set coordinate QC."),
        list(name = "start_endpoint", type = "list_or_cell_set", default = NULL,
             help = "Optional start endpoint descriptor with cell_set/cells or explicit x/y coordinates for display-path QC."),
        list(name = "end_endpoint", type = "list_or_cell_set", default = NULL,
             help = "Optional end endpoint descriptor with cell_set/cells or explicit x/y coordinates for display-path QC."),
        list(name = "start_cell_set", type = "cell_set", default = NULL,
             help = "Convenience start endpoint cell set for display-path QC."),
        list(name = "end_cell_set", type = "cell_set", default = NULL,
             help = "Convenience end endpoint cell set for display-path QC."),
        list(name = "endpoint_summary_method", type = "choice", default = "centroid",
             choices = c("centroid", "medoid"),
             help = "How endpoint cell sets are summarized in display space for QC."),
        list(name = "endpoint_max_distance", type = "dbl", default = NULL,
             help = "Optional absolute maximum endpoint distance before QC fails."),
        list(name = "endpoint_qc_action", type = "choice", default = "fail",
             choices = c("fail", "warn", "none"),
             help = "Action when display-path endpoint QC detects a large mismatch."),
        list(name = "pseudotime_key", type = "string", default = NULL,
             help = "Key for emitted bridge pseudotime. Defaults to segment_id."),
        list(name = "confidence_key", type = "string", default = NULL,
             help = "Key for emitted bridge confidence. Defaults to segment_id.")
      ),
      interface_produces = list(
        pseudotime = list(
          kind = "cell_vector_family",
          value_kind = "continuous",
          key = "pseudotime_key",
          source_kind = "space_path_bridge",
          description = "Bridge pseudotime from path arclength progress in [0,1]."
        ),
        membership = list(
          kind = "cell_vector",
          value_kind = "categorical",
          description = "Cells passing the transparent distance-to-path bridge membership rule."
        ),
        confidence = list(
          kind = "cell_vector_family",
          value_kind = "continuous",
          description = "Distance-derived confidence for included bridge cells."
        ),
        segment_manifest = list(
          kind = "obs_table",
          table_type = "trajectory_segment_manifest",
          description = "Audit manifest for the space-path bridge segment."
        ),
        display_endpoint_qc = list(
          kind = "obs_table",
          table_type = "trajectory_segment_display_path_endpoint_qc",
          description = "Endpoint-distance QC for an optional display_path against declared start/end endpoint descriptors."
        )
      )
    ),
    trajectory_segment_path_join = list(
      op_name = "trajectory_segment_path_join",
      title = "Trajectory segment path join",
      description = "Join ordered parent path_2d_family segments into a derived composite display curve without merging parent trajectory models.",
      intent = c("trajectory", "visualization", "provenance", "composition"),
      requires = list(),
      produces = list(
        curves = "path_2d_family",
        path_manifest = "obs_table",
        endpoint_qc = "obs_table"
      ),
      promotable = c("curves", "path_manifest", "endpoint_qc"),
      runner = .wb_runner_trajectory_segment_path_join,
      inputs = list(),
      params = list(
        list(name = "paths", type = "list", default = NULL,
             help = "Ordered path segment specs with path ref, lineage key, segment ID, labels, and order."),
        list(name = "composite_id", type = "string", default = NULL,
             help = "Optional trajectory_composite_id shared with a segmented pseudotime join."),
        list(name = "composite_key", type = "string", default = "composite_path",
             help = "Key used in the output composite path_2d_family."),
        list(name = "display_space_id", type = "string", default = NULL,
             help = "2D display space used for endpoint cell-set coordinate QC when path segment specs declare endpoint cell sets."),
        list(name = "endpoint_summary_method", type = "choice", default = "centroid",
             choices = c("centroid", "medoid"),
             help = "How endpoint cell sets are summarized in display space for QC."),
        list(name = "endpoint_max_distance", type = "dbl", default = NULL,
             help = "Optional absolute maximum endpoint distance before QC fails."),
        list(name = "endpoint_qc_action", type = "choice", default = "fail",
             choices = c("fail", "warn", "none"),
             help = "Action when display-path endpoint QC detects a large mismatch."),
        list(name = "allow_legacy", type = "bool", default = FALSE,
             help = "Allow missing trajectory_fit_id on parent paths with warning.")
      ),
      interface_produces = list(
        curves = list(
          kind = "path_2d_family",
          key = "composite_key",
          family_kind = "trajectory_composite_display_path",
          description = "Derived display-only composite path suitable for UMAP overlay; not a merged fitted trajectory model."
        ),
        path_manifest = list(
          kind = "obs_table",
          table_type = "trajectory_segment_path_join_manifest",
          description = "Audit manifest recording parent path artifacts, segment order, point boundaries, and caveats."
        ),
        endpoint_qc = list(
          kind = "obs_table",
          table_type = "trajectory_segment_display_path_endpoint_qc",
          description = "Endpoint-distance QC for joined display paths with declared endpoint descriptors."
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
             help = "Learn graph per partition. FALSE is recommended for current tree semantics."),
        list(name = "close_loop", type = "bool", default = FALSE,
             help = "Allow loop closure in graph learning. FALSE is required for tree-derived lineages."),
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
          description = "Derived cell-to-lineage membership relations (tree root-to-leaf paths; binary weights in the current implementation)."
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
    scvi_train = list(
      op_name = "scvi_train",
      title = "scVI train (pybench)",
      description = "Train an RNA scVI model on a raw/count-like matrix via the pybench Python runtime and emit a latent space, model reference, and fit summary.",
      intent = c("latent", "model", "python", "rna", "counts"),
      requires = list(matrix = "matrix"),
      produces = list(
        space = "space",
        model = "model_ref",
        fit_summary = "obs_table"
      ),
      promotable = c("model", "fit_summary"),
      runner = .wb_runner_scvi_train,
      inputs = list(
        matrix = list(required = TRUE, kind = "matrix")
      ),
      params = list(
        list(name = "n_latent", type = "int", default = 30, min = 2, max = 1024,
             help = "Target latent dimensionality for the emitted scVI space."),
        list(name = "n_hidden", type = "int", default = 128, min = 1, max = 8192,
             help = "Hidden width passed to the scVI model constructor."),
        list(name = "n_layers", type = "int", default = 2, min = 1, max = 32,
             help = "Number of hidden layers passed to the scVI model constructor."),
        list(name = "dropout", type = "number", default = 0.1, min = 0, max = 1,
             help = "Dropout rate passed to the scVI model constructor."),
        list(name = "batch_key", type = "string", default = NULL,
             help = "Optional cell metadata field used as the scVI batch covariate."),
        list(name = "categorical_covariates", type = "string_array", default = NULL,
             help = "Optional categorical cell metadata covariates passed to scVI setup_anndata."),
        list(name = "continuous_covariates", type = "string_array", default = NULL,
             help = "Optional continuous cell metadata covariates passed to scVI setup_anndata."),
        list(name = "max_epochs", type = "int", default = NULL, min = 1, max = 100000,
             help = "Optional maximum training epochs passed through to scvi-tools."),
        list(name = "early_stopping", type = "bool", default = TRUE,
             help = "If TRUE, enable scvi-tools early stopping during scVI training."),
        list(name = "seed", type = "int", default = 1, min = 0, max = 999999,
             help = "Random seed for scVI training."),
        list(name = "use_gpu", type = "bool", default = FALSE,
             help = "If TRUE, request GPU-backed training in scvi-tools."),
        list(name = "output_space_id", type = "string", default = "rna.scvi",
             help = "Space id to write for the learned scVI latent embedding."),
        list(name = "model_artifact_id", type = "string", default = NULL,
             help = "Optional preregistered model artifact id. NULL lets scworkbench assign one."),
        list(name = "overwrite", type = "bool", default = FALSE,
             help = "If TRUE, allow replacing an existing output_space_id."),
        list(name = "allow_non_counts", type = "bool", default = FALSE,
             help = "If TRUE, bypass raw/count-like matrix checks. Use only for intentional expert overrides.")
      ),
      interface_produces = list(
        space = list(
          kind = "space",
          description = "scVI latent space written into the bundle spaces registry."
        ),
        model = list(
          kind = "model_ref",
          description = "Serialized scVI Python model payload (engine='scvi')."
        ),
        fit_summary = list(
          kind = "obs_table",
          description = "Training summary, parameter, runtime, and metric table emitted by pybench."
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
        space = "space", fit_summary = "obs_table"
      ),
      promotable = c("fit_summary"),
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
        ),
        fit_summary = list(kind="obs_table", description="Projection receipt and output-space summary.")
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
             help = "Path fitting mode. The current implementation supports linear and a conservative manifold smoothing mode."),
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
             help = "Scoring mode. The current implementation standardizes on orthogonal projection semantics."),
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
