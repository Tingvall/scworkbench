test_op_scvi_train_contract <- function(bundle_dir = NULL) {
  iface <- wb_op_interface("scvi_train")
  stopifnot(is.list(iface))
  stopifnot(identical(as.character(iface$produces$space$kind), "space"))
  stopifnot(identical(as.character(iface$produces$model$kind), "model_ref"))
  stopifnot(identical(as.character(iface$produces$fit_summary$kind), "obs_table"))
  params <- setNames(
    iface$params,
    vapply(iface$params, function(x) as.character(x$name %||% ""), character(1))
  )
  stopifnot(all(c(
    "n_latent", "n_hidden", "n_layers", "batch_key",
    "categorical_covariates", "continuous_covariates",
    "output_space_id", "overwrite", "allow_non_counts"
  ) %in% names(params)))
  stopifnot(identical(as.integer(params$n_latent$default), 30L))
  stopifnot(identical(as.integer(params$n_hidden$default), 128L))
  stopifnot(identical(as.integer(params$n_layers$default), 2L))

  required <- c("BPCells", "Matrix")
  missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing)) {
    return(contract_test_skip(paste("Missing runtime dependencies:", paste(missing, collapse = ", "))))
  }

  tmp <- tempfile("scwb_scvi_contract_")
  b <- wb_init_bundle(tmp, overwrite = TRUE)
  on.exit(wb_close_bundle(b), add = TRUE)

  cells <- paste0("cell", seq_len(6))
  meta <- data.frame(
    cell_id = cells,
    sample_id = c("s1", "s1", "s2", "s2", "s3", "s3"),
    replicate_score = c(0, 0.1, 0.2, 0.3, 0.4, 0.5),
    stringsAsFactors = FALSE
  )
  wb_define_cells(b, cells, metadata = meta, dataset_id = meta$sample_id)

  counts <- Matrix::Matrix(
    c(
      1, 0, 3, 0, 5, 1,
      0, 2, 0, 4, 0, 2,
      5, 0, 1, 0, 2, 0,
      0, 1, 0, 1, 0, 1
    ),
    nrow = 4,
    ncol = 6,
    sparse = TRUE
  )
  rownames(counts) <- paste0("gene", seq_len(4))
  colnames(counts) <- cells
  wb_attach_matrix(b, matrix_id = "RNA_counts", mat = counts, layer = "counts", feature_type = "gene")

  feats <- wb_feature_ids(b, "RNA_counts")
  .wb_scvi_check_covariates(
    b,
    cells = cells,
    batch_key = "sample_id",
    continuous_covariates = "replicate_score"
  )
  missing_cov <- try(.wb_scvi_check_covariates(b, cells = cells, batch_key = "missing_key"), silent = TRUE)
  stopifnot(inherits(missing_cov, "try-error"))

  .wb_scvi_check_count_matrix(b, "RNA_counts", cells = cells, feature_ids = feats)
  stage <- .wb_scvi_stage_sparse_chunks(
    b,
    matrix_id = "RNA_counts",
    feature_ids = feats,
    cell_ids = cells,
    batch_key = "sample_id",
    continuous_covariates = "replicate_score",
    chunk_cells = 2L
  )
  on.exit(unlink(stage, recursive = TRUE, force = TRUE), add = TRUE)
  man <- jsonlite::read_json(file.path(stage, "manifest.json"), simplifyVector = TRUE)
  stopifnot(identical(as.character(man$protocol), "scworkbench_sparse_matrix_chunks_v1"))
  stopifnot(identical(as.character(man$orientation), "features_by_cells"))
  stopifnot(identical(as.character(man$matrix_id), "RNA_counts"))
  stopifnot(identical(as.integer(man$n_features), 4L))
  stopifnot(identical(as.integer(man$n_cells), 6L))
  stopifnot(nrow(as.data.frame(man$chunks)) == 3L)
  stopifnot(file.exists(file.path(stage, "feature_ids.txt")))
  stopifnot(file.exists(file.path(stage, "cell_metadata.tsv")))
  md <- utils::read.delim(file.path(stage, "cell_metadata.tsv"), stringsAsFactors = FALSE)
  stopifnot(all(c("cell_id", "sample_id", "replicate_score") %in% names(md)))
  stopifnot(identical(as.character(md$cell_id), cells))

  log_mat <- counts
  log_mat@x <- log1p(log_mat@x)
  wb_attach_matrix(b, matrix_id = "RNA_log_norm", mat = log_mat, layer = "lognorm", feature_type = "gene")
  bad_counts <- try(.wb_scvi_check_count_matrix(b, "RNA_log_norm", cells = cells, feature_ids = feats), silent = TRUE)
  stopifnot(inherits(bad_counts, "try-error"))

  latent <- matrix(seq_len(18) / 10, nrow = 6, ncol = 3)
  rownames(latent) <- cells
  wb_add_space(b, space_id = "rna.scvi.synthetic", coords = latent, source = "test")
  X <- .wb_scvi_space_matrix(b, "rna.scvi.synthetic", cells)
  stopifnot(is.matrix(X), nrow(X) == 6L, ncol(X) == 3L)

  model_dir <- file.path(b$dir, "artifact_models", "scvi_synthetic_model")
  dir.create(model_dir, recursive = TRUE, showWarnings = FALSE)
  writeLines("synthetic scvi model", file.path(model_dir, "model.txt"), useBytes = TRUE)
  run <- wb_new_run(
    op_name = "scvi_train",
    inputs = list(cell_set = "core", user_inputs = list(matrix = "RNA_counts")),
    params = list(output_space_id = "rna.scvi.synthetic"),
    outputs = list(),
    notes = "synthetic scvi model_ref contract"
  )
  model_prim <- structure(
    list(
      kind = "model_ref",
      engine = "scvi",
      model_space_id = "rna.scvi.synthetic",
      in_space_id = "rna.scvi.synthetic",
      model_type = "scvi_train",
      model_path = model_dir
    ),
    class = "wb_primitive"
  )
  model_artifact <- .wb_promote_model_ref(
    bundle = b,
    run = run,
    out_name = "model",
    prim = model_prim,
    name = "synthetic scVI model"
  )
  loaded <- wb_art_load(b, model_artifact, expected_kind = "model_ref")
  stopifnot(identical(as.character(loaded$engine), "scvi"))
  stopifnot(identical(as.character(loaded$model_space_id), "rna.scvi.synthetic"))
  stopifnot(dir.exists(loaded$model_path))

  TRUE
}
