# PeakVI sparse chunk staging bridge. The public PeakVI operation is registered
# through the operation catalog; this helper is not a public API.
.wb_peakvi_stage_sparse_chunks <- function(bundle,
                                           matrix_id,
                                           feature_ids,
                                           cell_ids,
                                           chunk_cells = as.integer(Sys.getenv("SCWORKBENCH_PEAKVI_STAGE_CHUNK_CELLS", "256"))) {
  .wb_assert(length(feature_ids) > 0L, "peakvi_fit staging requires feature_ids.")
  .wb_assert(length(cell_ids) > 0L, "peakvi_fit staging requires cell_ids.")
  chunk_cells <- as.integer(chunk_cells)[1]
  .wb_assert(!is.na(chunk_cells) && chunk_cells >= 1L,
             "SCWORKBENCH_PEAKVI_STAGE_CHUNK_CELLS must be >= 1.")

  .wb_require_pkg("Matrix", "peakvi chunk staging")

  stage_dir <- tempfile("peakvi_stage_")
  dir.create(stage_dir, recursive = TRUE, showWarnings = FALSE)

  writeLines(as.character(feature_ids), con = file.path(stage_dir, "feature_ids.txt"), useBytes = TRUE)

  manifest <- vector("list", length = 0L)
  starts <- seq.int(1L, length(cell_ids), by = chunk_cells)
  for (i in seq_along(starts)) {
    start <- starts[[i]]
    stop <- min(length(cell_ids), start + chunk_cells - 1L)
    chunk_ids <- as.character(cell_ids[start:stop])
    chunk <- wb_slice(bundle, matrix_id = matrix_id, features = feature_ids, cells = chunk_ids)
    chunk <- .wb_as_sparse(chunk)

    stem <- sprintf("chunk_%05d", i)
    mtx_rel <- paste0(stem, ".mtx")
    cells_rel <- paste0(stem, "_cells.txt")
    Matrix::writeMM(chunk, file.path(stage_dir, mtx_rel))
    writeLines(chunk_ids, con = file.path(stage_dir, cells_rel), useBytes = TRUE)

    manifest[[i]] <- list(
      mtx = mtx_rel,
      cells = cells_rel,
      n_cells = length(chunk_ids)
    )
  }

  jsonlite::write_json(
    list(
      matrix_id = as.character(matrix_id)[1],
      n_features = length(feature_ids),
      n_cells = length(cell_ids),
      chunks = manifest
    ),
    file.path(stage_dir, "manifest.json"),
    auto_unbox = TRUE,
    pretty = TRUE,
    null = "null"
  )

  stage_dir
}

wb_op_peakvi_fit <- function(bundle,
                             matrix_id,
                             cells,
                             n_latent = 20L,
                             n_layers = 2L,
                             n_hidden = 256L,
                             dropout = 0.2,
                             batch_key = NULL,
                             max_epochs = 500L,
                             lr = 1e-3,
                             early_stopping = TRUE,
                             seed = 1L,
                             use_gpu = FALSE,
                             space_id_out = "peakvi_space",
                             cell_set = "all",
                             python_bin = .wb_pybench_default_python()) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert_operation_execution(bundle, "peakvi_fit")
  .wb_assert(is.character(matrix_id) && length(matrix_id) == 1L && nzchar(matrix_id),
             "peakvi_fit requires matrix_id.")

  cells <- unique(as.character(cells %||% character(0)))
  .wb_assert(length(cells) >= 10L, "peakvi_fit requires at least 10 cells.")

  n_latent <- as.integer(n_latent %||% 20L)[1]
  .wb_assert(!is.na(n_latent) && n_latent >= 2L, "peakvi_fit n_latent must be >= 2.")
  n_layers <- as.integer(n_layers %||% 2L)[1]
  .wb_assert(!is.na(n_layers) && n_layers >= 1L, "peakvi_fit n_layers must be >= 1.")
  n_hidden <- as.integer(n_hidden %||% 256L)[1]
  .wb_assert(!is.na(n_hidden) && n_hidden >= 1L, "peakvi_fit n_hidden must be >= 1.")
  dropout <- as.numeric(dropout %||% 0.2)[1]
  .wb_assert(!is.na(dropout) && dropout >= 0 && dropout <= 1,
             "peakvi_fit dropout must be between 0 and 1.")
  if (!is.null(max_epochs)) {
    max_epochs <- as.integer(max_epochs)[1]
    .wb_assert(!is.na(max_epochs) && max_epochs >= 1L, "peakvi_fit max_epochs must be >= 1.")
  }
  if (!is.null(lr)) {
    lr <- as.numeric(lr)[1]
    .wb_assert(!is.na(lr) && is.finite(lr) && lr > 0, "peakvi_fit lr must be > 0 or NULL.")
  }
  early_stopping <- isTRUE(early_stopping)
  if (!is.null(seed)) {
    seed <- as.integer(seed)[1]
    .wb_assert(!is.na(seed), "peakvi_fit seed must be integer-like or NULL.")
  }
  batch_key <- as.character(batch_key %||% "")[1]
  if (!nzchar(batch_key)) batch_key <- NULL
  space_id_out <- as.character(space_id_out %||% "peakvi_space")[1]
  .wb_assert(nzchar(space_id_out), "peakvi_fit requires non-empty space_id_out.")

  feats <- as.character(wb_feature_ids(bundle, matrix_id = matrix_id))
  .wb_assert(length(feats) > 0L, paste0("peakvi_fit: no features found for matrix_id='", matrix_id, "'."))
  stage_dir <- .wb_peakvi_stage_sparse_chunks(
    bundle = bundle,
    matrix_id = matrix_id,
    feature_ids = feats,
    cell_ids = cells
  )
  on.exit(unlink(stage_dir, recursive = TRUE, force = TRUE), add = TRUE)

  run_tmp <- wb_new_run(
    op_name = "peakvi_fit",
    inputs = list(
      cell_set = as.character(cell_set %||% "all")[1],
      user_inputs = list(
        matrix = matrix_id,
        cell_ids = cells
      )
    ),
    params = list(
      matrix_id = matrix_id,
      space_id_out = space_id_out
    ),
    outputs = list(),
    notes = "pybench staging preregistration"
  )
  outs_spec <- list(
    model = list(type = "model_ref", name = "PeakVI model")
  )
  prereg <- .wb_pybench_preregister_outputs(bundle = bundle, run = run_tmp, outputs_spec = outs_spec)
  staging_ids <- vapply(prereg, function(x) as.character(x$artifact_id), character(1))
  on.exit(.wb_palantir_cleanup_staging_artifacts(bundle, staging_ids, keep_model_files = FALSE), add = TRUE)

  req <- .wb_pybench_build_request(
    bundle = bundle,
    op_name = "peakvi_fit",
    run_id = as.character(run_tmp$run_id),
    inputs = list(
      matrix = matrix_id,
      cell_set = as.character(cell_set %||% "all")[1],
      cell_ids = cells,
      matrix_chunks_dir = stage_dir
    ),
    params = list(
      matrix_id = matrix_id,
      n_latent = n_latent,
      n_layers = n_layers,
      n_hidden = n_hidden,
      dropout = dropout,
      batch_key = batch_key,
      max_epochs = max_epochs,
      lr = lr,
      early_stopping = early_stopping,
      seed = seed,
      use_gpu = isTRUE(use_gpu),
      space_id_out = space_id_out
    ),
    outputs = prereg
  )
  bridge <- .wb_palantir_bridge_run_or_stop(
    module = "pybench.ops.peakvi_fit",
    request = req,
    python_bin = python_bin
  )
  rec <- bridge$receipt

  sp <- wb_space(bundle, space_id = space_id_out, cells = cells)
  X <- if (is.data.frame(sp)) .wb_as_coord_matrix(sp) else sp
  .wb_assert(is.matrix(X), "peakvi_fit: emitted space could not be resolved as a matrix.")
  .wb_assert(nrow(X) == length(cells), "peakvi_fit: latent space cell count mismatch.")
  .wb_assert(ncol(X) == n_latent, "peakvi_fit: latent space dimensionality mismatch.")

  model_prim <- wb_art_load(bundle, prereg$model$artifact_id, expected_kind = "model_ref")

  list(
    outputs = list(
      space = wb_prim_space(space_id_out),
      model = model_prim
    ),
    params = list(
      matrix_id = matrix_id,
      n_cells = length(cells),
      n_features = length(feats),
      n_latent = n_latent,
      n_layers = n_layers,
      n_hidden = n_hidden,
      dropout = dropout,
      batch_key = batch_key,
      max_epochs = max_epochs,
      lr = lr,
      early_stopping = early_stopping,
      seed = seed,
      use_gpu = isTRUE(use_gpu),
      space_id_out = space_id_out,
      pybench_runtime = list(
        protocol_version = as.character(rec$protocol_version %||% .wb_pyproto_version())[1],
        pybench_version = as.character(rec$pybench$version %||% NA_character_)[1],
        timings = rec$timings %||% list()
      )
    )
  )
}

#' Project New Cells Through A Saved PeakVI Model
#'
#' Uses the stable R-side matrix staging bridge to hand query ATAC chunks to the
#' pybench Python runtime, which loads a saved PeakVI model and emits a new
#' latent space without refitting.
#'
#' @export
wb_op_peakvi_project <- function(bundle,
                                 peakvi_model,
                                 matrix_id,
                                 cells,
                                 batch_key = NULL,
                                 use_gpu = FALSE,
                                 space_id_out = "peakvi_project_space",
                                 python_bin = .wb_pybench_default_python()) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert_operation_execution(bundle, "peakvi_project")
  .wb_assert_kind(peakvi_model, "model_ref")
  .wb_assert(identical(as.character(peakvi_model$engine %||% "")[1], "peakvi"),
             "peakvi_project requires model_ref(engine='peakvi').")
  model_path <- as.character(peakvi_model$model_path %||% "")[1]
  .wb_assert(nzchar(model_path) && file.exists(model_path),
             "peakvi_project requires readable model_ref$model_path.")
  .wb_assert(is.character(matrix_id) && length(matrix_id) == 1L && nzchar(matrix_id),
             "peakvi_project requires matrix_id.")

  cells <- unique(as.character(cells %||% character(0)))
  .wb_assert(length(cells) >= 1L, "peakvi_project requires at least one cell.")
  batch_key <- as.character(batch_key %||% "")[1]
  if (!nzchar(batch_key)) batch_key <- NULL
  space_id_out <- as.character(space_id_out %||% "peakvi_project_space")[1]
  .wb_assert(nzchar(space_id_out), "peakvi_project requires non-empty space_id_out.")

  feats <- as.character(wb_feature_ids(bundle, matrix_id = matrix_id))
  .wb_assert(length(feats) > 0L, paste0("peakvi_project: no features found for matrix_id='", matrix_id, "'."))
  stage_dir <- .wb_peakvi_stage_sparse_chunks(
    bundle = bundle,
    matrix_id = matrix_id,
    feature_ids = feats,
    cell_ids = cells
  )
  on.exit(unlink(stage_dir, recursive = TRUE, force = TRUE), add = TRUE)

  req <- .wb_pybench_build_request(
    bundle = bundle,
    op_name = "peakvi_project",
    run_id = paste0("peakvi_project_", format(Sys.time(), "%Y%m%d_%H%M%S")),
    inputs = list(
      matrix = matrix_id,
      cell_ids = cells,
      matrix_chunks_dir = stage_dir,
      model_path = model_path
    ),
    params = list(
      matrix_id = matrix_id,
      batch_key = batch_key,
      use_gpu = isTRUE(use_gpu),
      space_id_out = space_id_out
    ),
    outputs = list()
  )

  bridge <- .wb_palantir_bridge_run_or_stop(
    module = "pybench.ops.peakvi_project",
    request = req,
    python_bin = python_bin
  )
  rec <- bridge$receipt

  sp <- wb_space(bundle, space_id = space_id_out, cells = cells)
  X <- if (is.data.frame(sp)) .wb_as_coord_matrix(sp) else sp
  .wb_assert(is.matrix(X), "peakvi_project: emitted space could not be resolved as a matrix.")
  .wb_assert(nrow(X) == length(cells), "peakvi_project: latent space cell count mismatch.")

  list(
    outputs = list(
      space = wb_prim_space(space_id_out)
    ),
    params = list(
      matrix_id = matrix_id,
      n_cells = length(cells),
      n_features = length(feats),
      model_space_id = as.character(peakvi_model$model_space_id %||% "")[1],
      space_id_out = space_id_out,
      use_gpu = isTRUE(use_gpu),
      pybench_runtime = list(
        protocol_version = as.character(rec$protocol_version %||% .wb_pyproto_version())[1],
        pybench_version = as.character(rec$pybench$version %||% NA_character_)[1],
        timings = rec$timings %||% list()
      )
    )
  )
}
