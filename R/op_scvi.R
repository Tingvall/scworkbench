# RNA scVI bridge op. The R side owns typed validation, matrix staging,
# artifact preregistration, and post-run bundle-space/model checks.

.wb_scvi_stage_sparse_chunks <- function(bundle,
                                         matrix_id,
                                         feature_ids,
                                         cell_ids,
                                         batch_key = NULL,
                                         categorical_covariates = NULL,
                                         continuous_covariates = NULL,
                                         chunk_cells = as.integer(Sys.getenv("SCWORKBENCH_SCVI_STAGE_CHUNK_CELLS", "256"))) {
  .wb_assert(length(feature_ids) > 0L, "scvi_train staging requires feature_ids.")
  .wb_assert(length(cell_ids) > 0L, "scvi_train staging requires cell_ids.")
  chunk_cells <- as.integer(chunk_cells)[1]
  .wb_assert(!is.na(chunk_cells) && chunk_cells >= 1L,
             "SCWORKBENCH_SCVI_STAGE_CHUNK_CELLS must be >= 1.")
  .wb_require_pkg("Matrix", "scvi chunk staging")
  .wb_require_pkg("jsonlite", "scvi chunk staging")

  covariates <- unique(as.character(c(batch_key, categorical_covariates, continuous_covariates) %||% character(0)))
  covariates <- covariates[nzchar(covariates)]
  meta_cols <- unique(c("cell_id", covariates))
  meta <- wb_meta(bundle, cells = cell_ids, cols = meta_cols)

  stage_dir <- tempfile("scvi_stage_")
  dir.create(stage_dir, recursive = TRUE, showWarnings = FALSE)

  writeLines(as.character(feature_ids), con = file.path(stage_dir, "feature_ids.txt"), useBytes = TRUE)
  utils::write.table(
    meta,
    file = file.path(stage_dir, "cell_metadata.tsv"),
    sep = "\t",
    quote = FALSE,
    row.names = FALSE,
    col.names = TRUE,
    na = ""
  )

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
      index = i,
      mtx = mtx_rel,
      cells = cells_rel,
      n_features = length(feature_ids),
      n_cells = length(chunk_ids)
    )
  }

  jsonlite::write_json(
    list(
      protocol = "scworkbench_sparse_matrix_chunks_v1",
      matrix_id = as.character(matrix_id)[1],
      value_type = "counts",
      orientation = "features_by_cells",
      feature_ids_file = "feature_ids.txt",
      cell_metadata_file = "cell_metadata.tsv",
      n_features = length(feature_ids),
      n_cells = length(cell_ids),
      batch_key = batch_key %||% NULL,
      categorical_covariates = as.character(categorical_covariates %||% character(0)),
      continuous_covariates = as.character(continuous_covariates %||% character(0)),
      chunk_cells = chunk_cells,
      chunks = manifest
    ),
    file.path(stage_dir, "manifest.json"),
    auto_unbox = TRUE,
    pretty = TRUE,
    null = "null"
  )

  stage_dir
}

.wb_scvi_check_covariates <- function(bundle,
                                      cells,
                                      batch_key = NULL,
                                      categorical_covariates = NULL,
                                      continuous_covariates = NULL) {
  covariates <- unique(as.character(c(batch_key, categorical_covariates, continuous_covariates) %||% character(0)))
  covariates <- covariates[nzchar(covariates)]
  if (!length(covariates)) return(invisible(TRUE))

  available <- names(wb_meta(bundle, cells = head(as.character(cells), 1), cols = NULL))
  missing <- setdiff(covariates, available)
  .wb_assert(!length(missing),
             paste0("scvi_train covariate(s) not found in cell metadata: ", paste(missing, collapse = ", ")))
  invisible(TRUE)
}

.wb_scvi_check_count_matrix <- function(bundle,
                                        matrix_id,
                                        cells,
                                        feature_ids,
                                        allow_non_counts = FALSE,
                                        sample_cells = 64L,
                                        sample_features = 128L) {
  if (isTRUE(allow_non_counts)) return(invisible(TRUE))

  info <- wb_matrices(bundle)
  row <- info[as.character(info$matrix_id) == as.character(matrix_id), , drop = FALSE]
  .wb_assert(nrow(row) == 1L, paste0("scvi_train: unknown matrix_id: ", matrix_id))
  layer <- tolower(as.character(row$layer[[1]] %||% ""))
  id <- tolower(as.character(matrix_id)[1])
  suspicious <- c("log", "log1p", "norm", "normalized", "scale", "scaled", "cp10k", "tfidf")
  if (any(vapply(suspicious, function(tok) grepl(tok, layer, fixed = TRUE) || grepl(tok, id, fixed = TRUE), logical(1)))) {
    stop("scvi_train requires raw/count-like matrix input; matrix_id/layer looks normalized. Set allow_non_counts=TRUE only for an intentional override.", call. = FALSE)
  }

  cells_s <- head(as.character(cells), as.integer(sample_cells)[1])
  feats_s <- head(as.character(feature_ids), as.integer(sample_features)[1])
  x <- wb_slice(bundle, matrix_id = matrix_id, features = feats_s, cells = cells_s)
  vals <- as.numeric(x)
  vals <- vals[is.finite(vals) & vals != 0]
  .wb_assert(!any(vals < 0), "scvi_train requires non-negative count-like values.")
  if (length(vals)) {
    delta <- abs(vals - round(vals))
    .wb_assert(all(delta < 1e-8),
               "scvi_train requires integer/count-like values. Set allow_non_counts=TRUE only for an intentional override.")
  }
  invisible(TRUE)
}

.wb_scvi_space_matrix <- function(bundle, space_id, cells) {
  sp <- wb_space(bundle, space_id = space_id, cells = cells)
  if (is.data.frame(sp)) .wb_as_coord_matrix(sp) else sp
}

wb_op_scvi_train <- function(bundle,
                             matrix_id,
                             cells,
                             batch_key = NULL,
                             categorical_covariates = NULL,
                             continuous_covariates = NULL,
                             n_latent = 30L,
                             n_hidden = 128L,
                             n_layers = 2L,
                             dropout = 0.1,
                             max_epochs = NULL,
                             early_stopping = TRUE,
                             seed = 1L,
                             use_gpu = FALSE,
                             output_space_id = "rna.scvi",
                             model_artifact_id = NULL,
                             overwrite = FALSE,
                             allow_non_counts = FALSE,
                             cell_set = "all",
                             python_bin = .wb_pybench_default_python()) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert_operation_execution(bundle, "scvi_train")
  .wb_assert(is.character(matrix_id) && length(matrix_id) == 1L && nzchar(matrix_id),
             "scvi_train requires matrix_id.")

  cells <- unique(as.character(cells %||% character(0)))
  .wb_assert(length(cells) >= 2L, "scvi_train requires at least 2 cells.")

  n_latent <- as.integer(n_latent %||% 30L)[1]
  .wb_assert(!is.na(n_latent) && n_latent >= 2L, "scvi_train n_latent must be >= 2.")
  n_layers <- as.integer(n_layers %||% 2L)[1]
  .wb_assert(!is.na(n_layers) && n_layers >= 1L, "scvi_train n_layers must be >= 1.")
  n_hidden <- as.integer(n_hidden %||% 128L)[1]
  .wb_assert(!is.na(n_hidden) && n_hidden >= 1L, "scvi_train n_hidden must be >= 1.")
  dropout <- as.numeric(dropout %||% 0.1)[1]
  .wb_assert(!is.na(dropout) && dropout >= 0 && dropout <= 1,
             "scvi_train dropout must be between 0 and 1.")
  if (!is.null(max_epochs)) {
    max_epochs <- as.integer(max_epochs)[1]
    .wb_assert(!is.na(max_epochs) && max_epochs >= 1L, "scvi_train max_epochs must be >= 1.")
  }
  if (!is.null(seed)) {
    seed <- as.integer(seed)[1]
    .wb_assert(!is.na(seed), "scvi_train seed must be integer-like or NULL.")
  }
  batch_key <- as.character(batch_key %||% "")[1]
  if (!nzchar(batch_key)) batch_key <- NULL
  categorical_covariates <- unique(as.character(categorical_covariates %||% character(0)))
  categorical_covariates <- categorical_covariates[nzchar(categorical_covariates)]
  continuous_covariates <- unique(as.character(continuous_covariates %||% character(0)))
  continuous_covariates <- continuous_covariates[nzchar(continuous_covariates)]

  output_space_id <- as.character(output_space_id %||% "rna.scvi")[1]
  .wb_assert(nzchar(output_space_id), "scvi_train requires non-empty output_space_id.")
  model_artifact_id <- as.character(model_artifact_id %||% "")[1]
  if (!nzchar(model_artifact_id)) model_artifact_id <- NULL

  existing_spaces <- tryCatch(wb_spaces(bundle)$space_id, error = function(e) character(0))
  if (!isTRUE(overwrite) && output_space_id %in% as.character(existing_spaces)) {
    stop("scvi_train output_space_id already exists: ", output_space_id, " (set overwrite=TRUE)", call. = FALSE)
  }
  if (isTRUE(overwrite) && output_space_id %in% as.character(existing_spaces)) {
    .wb_entity_assert_replaceable(bundle, "space", output_space_id, action = "overwrite")
    .wb_entity_assert_replaceable(bundle, "model", output_space_id, action = "overwrite")
  }

  feats <- as.character(wb_feature_ids(bundle, matrix_id = matrix_id))
  .wb_assert(length(feats) > 0L, paste0("scvi_train: no features found for matrix_id='", matrix_id, "'."))
  .wb_scvi_check_covariates(
    bundle = bundle,
    cells = cells,
    batch_key = batch_key,
    categorical_covariates = categorical_covariates,
    continuous_covariates = continuous_covariates
  )
  .wb_scvi_check_count_matrix(
    bundle = bundle,
    matrix_id = matrix_id,
    cells = cells,
    feature_ids = feats,
    allow_non_counts = allow_non_counts
  )

  stage_dir <- .wb_scvi_stage_sparse_chunks(
    bundle = bundle,
    matrix_id = matrix_id,
    feature_ids = feats,
    cell_ids = cells,
    batch_key = batch_key,
    categorical_covariates = categorical_covariates,
    continuous_covariates = continuous_covariates
  )
  on.exit(unlink(stage_dir, recursive = TRUE, force = TRUE), add = TRUE)

  run_tmp <- wb_new_run(
    op_name = "scvi_train",
    inputs = list(
      cell_set = as.character(cell_set %||% "all")[1],
      user_inputs = list(matrix = matrix_id, cell_ids = cells)
    ),
    params = list(matrix_id = matrix_id, output_space_id = output_space_id),
    outputs = list(),
    notes = "pybench staging preregistration"
  )
  outs_spec <- list(
    model = list(type = "model_ref", name = "scVI model", artifact_id = model_artifact_id),
    fit_summary = list(type = "obs_table", name = "scVI fit summary")
  )
  prereg <- .wb_pybench_preregister_outputs(bundle = bundle, run = run_tmp, outputs_spec = outs_spec)
  staging_ids <- vapply(prereg, function(x) as.character(x$artifact_id), character(1))
  pybench_success <- FALSE
  on.exit({
    if (!isTRUE(pybench_success)) {
      .wb_palantir_cleanup_staging_artifacts(bundle, staging_ids, keep_model_files = FALSE)
    }
  }, add = TRUE)

  req <- .wb_pybench_build_request(
    bundle = bundle,
    op_name = "scvi_train",
    run_id = .wb_pybench_current_run_id(bundle),
    inputs = list(
      matrix = matrix_id,
      cell_set = as.character(cell_set %||% "all")[1],
      cell_ids = cells,
      matrix_chunks_dir = stage_dir,
      cell_metadata_path = file.path(stage_dir, "cell_metadata.tsv")
    ),
    params = list(
      matrix_id = matrix_id,
      n_latent = n_latent,
      n_hidden = n_hidden,
      n_layers = n_layers,
      dropout = dropout,
      batch_key = batch_key,
      categorical_covariates = categorical_covariates,
      continuous_covariates = continuous_covariates,
      max_epochs = max_epochs,
      early_stopping = isTRUE(early_stopping),
      seed = seed,
      use_gpu = isTRUE(use_gpu),
      output_space_id = output_space_id,
      space_id_out = output_space_id,
      overwrite = isTRUE(overwrite),
      allow_non_counts = isTRUE(allow_non_counts)
    ),
    outputs = prereg
  )

  bridge <- .wb_palantir_bridge_run_or_stop(
    bundle = bundle,
    module = "pybench.ops.scvi_train",
    request = req,
    python_bin = python_bin
  )
  rec <- bridge$receipt

  X <- .wb_scvi_space_matrix(bundle, output_space_id, cells)
  .wb_assert(is.matrix(X), "scvi_train: emitted space could not be resolved as a matrix.")
  .wb_assert(nrow(X) == length(cells), "scvi_train: latent space cell count mismatch.")
  .wb_assert(ncol(X) == n_latent, "scvi_train: latent space dimensionality mismatch.")

  model_prim <- wb_art_load(bundle, prereg$model$artifact_id, expected_kind = "model_ref")
  fit_summary <- wb_art_load(bundle, prereg$fit_summary$artifact_id, expected_kind = "obs_table")
  pybench_success <- TRUE

  list(
    outputs = list(
      space = wb_prim_space(output_space_id),
      model = model_prim,
      fit_summary = fit_summary
    ),
    params = list(
      matrix_id = matrix_id,
      cell_set = as.character(cell_set %||% "all")[1],
      n_cells = length(cells),
      n_features = length(feats),
      n_latent = n_latent,
      n_hidden = n_hidden,
      n_layers = n_layers,
      dropout = dropout,
      batch_key = batch_key,
      categorical_covariates = categorical_covariates,
      continuous_covariates = continuous_covariates,
      max_epochs = max_epochs,
      early_stopping = isTRUE(early_stopping),
      seed = seed,
      use_gpu = isTRUE(use_gpu),
      output_space_id = output_space_id,
      model_artifact_id = prereg$model$artifact_id,
      fit_summary_artifact_id = prereg$fit_summary$artifact_id,
      pybench_runtime = list(
        protocol_version = as.character(rec$protocol_version %||% .wb_pyproto_version())[1],
        pybench_version = as.character(rec$pybench$version %||% NA_character_)[1],
        timings = rec$timings %||% list()
      )
    )
  )
}
