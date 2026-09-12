test_op_slingshot_adopt_contract <- function() {
  required <- c("BPCells", "slingshot", "SingleCellExperiment", "S4Vectors")
  missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing)) {
    return(contract_test_skip(paste("Missing runtime dependencies:", paste(missing, collapse = ", "))))
  }

  root <- tempfile("scwb_slingshot_adopt_")
  source_path <- tempfile("published_seurat_fixture_", fileext = ".rds")
  b <- wb_init_bundle(root, overwrite = TRUE)
  on.exit({
    try(wb_close_bundle(b), silent = TRUE)
    unlink(c(root, source_path), recursive = TRUE, force = TRUE)
  }, add = TRUE)

  n <- 120L
  cells <- paste0("bdev_", seq_len(n))
  trajectory_position <- seq(0, 1, length.out = n)
  clusters <- factor(rep(c("early", "middle", "late"), each = n / 3L))
  coordinates <- cbind(
    UMAP_1 = trajectory_position * 8,
    UMAP_2 = sin(trajectory_position * pi)
  )
  rownames(coordinates) <- cells

  wb_define_cells(b, cells, metadata = data.frame(
    cell_id = cells,
    published_cluster = as.character(clusters),
    stringsAsFactors = FALSE
  ))
  wb_attach_space(b, "published_umap", data.frame(
    cell_id = cells,
    x = coordinates[, 1],
    y = coordinates[, 2],
    stringsAsFactors = FALSE
  ), source = "published Seurat fixture", created_by = "contract test")
  expression <- rbind(
    cytokine_a = round(10 * trajectory_position),
    cytokine_b = round(10 * (1 - trajectory_position)),
    background_a = rep(2, n),
    background_b = rep(3, n)
  )
  colnames(expression) <- cells
  wb_attach_matrix(
    b, "published_rna", Matrix::Matrix(expression, sparse = TRUE),
    feature_type = "gene", source = "published Seurat fixture",
    created_by = "contract test"
  )
  feature_set_name <- "published_cytokine_signature"
  wb_feature_set_import_list(
    b, matrix_id = "published_rna",
    sets = stats::setNames(list(c("cytokine_a", "cytokine_b")), feature_set_name),
    namespace = "contract", created_by = "contract test", strict = TRUE,
    origin = "imported", is_readonly = FALSE
  )

  fitted_sce <- scworkbench:::.wb_slingshot_run_fit(
    X_fit = coordinates,
    cells_fit = cells,
    cluster_labels = clusters,
    start.clus = "early",
    end.clus = "late"
  )
  sds <- slingshot::SlingshotDataSet(fitted_sce)
  saveRDS(list(misc = list(published_slingshot = sds)), source_path, version = 3)
  source_sha256 <- wb_source_sha256(source_path)
  source_id <- "published_bdev_seurat_fixture"
  source_input <- wb_source_input(
    path = source_path,
    source_id = source_id,
    accession = "fixture",
    role = "published_seurat_object",
    format = "rds",
    scope = "external_file"
  )
  scworkbench:::.wb_record_declared_ingestion(
    b,
    transaction_name = "published_bdev_seurat_fixture_import",
    source = "published Seurat fixture",
    source_identity = list(
      source_type = "published_seurat_object",
      inputs = list(source_input)
    )
  )

  model <- wb_slingshot_adoption_model(
    bundle = b,
    sds = readRDS(source_path)$misc$published_slingshot,
    fit_space_id = "published_umap",
    source_sha256 = source_sha256
  )
  stopifnot(
    identical(model$engine, "slingshot"),
    isTRUE(model$source_derived),
    identical(model$source_sha256, source_sha256),
    identical(model$coordinate_match_max_abs_difference, 0)
  )

  adopted <- wb_session_run_op(
    wb_session_new(), b, "slingshot_adopt",
    inputs = list(
      model = model,
      source = wb_ref_entity("external_source", source_id),
      cell_set = "all",
      min_cells = 1L
    ),
    notes = "Adopt explicitly selected published Slingshot fit without refitting"
  )
  outputs <- adopted$run$outputs
  stopifnot(
    identical(sort(names(outputs)), sort(c("pseudotime", "lineage_weights", "curves", "model", "adoption_summary"))),
    identical(outputs$pseudotime$kind, "cell_vector_family"),
    identical(outputs$lineage_weights$kind, "cell_vector_family"),
    identical(outputs$curves$kind, "path_2d_family"),
    identical(outputs$model$kind, "model_ref"),
    identical(outputs$adoption_summary$kind, "obs_table"),
    identical(outputs$pseudotime$meta$trajectory_fit_id, outputs$model$trajectory_fit_id),
    identical(outputs$lineage_weights$meta$trajectory_fit_id, outputs$model$trajectory_fit_id),
    identical(outputs$curves$meta$trajectory_fit_id, outputs$model$trajectory_fit_id),
    isFALSE(outputs$adoption_summary$table$scworkbench_refit_performed[[1]]),
    identical(outputs$adoption_summary$table$upstream_execution[[1]], "external")
  )

  lineage <- as.character(unique(outputs$pseudotime$key))[1]
  downstream <- wb_session_run_op(
    adopted$session, b, "trajectory_signature_smooth",
    inputs = list(
      matrix = "published_rna",
      model = wb_ref_run(adopted$run$run_id, "model"),
      feature_set = feature_set_name,
      lineage = lineage,
      cell_set = "all",
      min_cells = 10L,
      n_bins = 10L,
      min_cells_per_bin = 2L
    ),
    notes = "Use the adopted trajectory for downstream signature smoothing without refitting"
  )
  stopifnot(
    identical(downstream$run$outputs$signature_table$kind, "obs_table"),
    nrow(downstream$run$outputs$signature_table$table) > 0L,
    all(downstream$run$outputs$signature_table$table$lineage_id == lineage)
  )

  promoted <- wb_session_promote_current(
    b, adopted$session,
    outputs = names(outputs),
    name_prefix = "published_slingshot",
    created_by = "contract test"
  )
  stopifnot(all(promoted$promoted$status == "ok"))
  artifact_ids <- stats::setNames(
    as.character(promoted$promoted$artifact_id),
    as.character(promoted$promoted$output)
  )
  identities_before <- lapply(
    outputs[c("pseudotime", "lineage_weights", "curves")],
    function(x) scworkbench:::.wb_prov_payload_identity(b, x)$content_sha256
  )

  source_edges <- DBI::dbGetQuery(
    b$con,
    "SELECT entity_kind, entity_id, relationship_type, run_id FROM prov_run_entity_bindings WHERE entity_kind = 'external_source' AND entity_id = ?;",
    params = list(source_id)
  )
  stopifnot(
    nrow(source_edges) >= 1L,
    any(source_edges$relationship_type == "CONSUMES" & source_edges$run_id == adopted$run$run_id)
  )

  wb_close_bundle(b)
  b <- wb_open_bundle(root)
  loaded <- lapply(artifact_ids, function(id) wb_art_load(b, id, allow_untrusted_deserialization = TRUE))
  identities_after <- lapply(
    loaded[c("pseudotime", "lineage_weights", "curves")],
    function(x) scworkbench:::.wb_prov_payload_identity(b, x)$content_sha256
  )
  stopifnot(
    inherits(loaded$model$model_obj, "SlingshotDataSet"),
    identical(loaded$model$trajectory_fit_id, model$trajectory_fit_id),
    identical(unclass(loaded$pseudotime), unclass(outputs$pseudotime)),
    identical(unclass(loaded$lineage_weights), unclass(outputs$lineage_weights)),
    identical(unclass(loaded$curves), unclass(outputs$curves)),
    identical(loaded$pseudotime$meta$trajectory_fit_id, model$trajectory_fit_id),
    identical(loaded$lineage_weights$meta$trajectory_fit_id, model$trajectory_fit_id),
    identical(loaded$curves$meta$trajectory_fit_id, model$trajectory_fit_id),
    identical(identities_after, identities_before)
  )
  stopifnot(isTRUE(wb_validate_bundle(root)))

  coordinate_mismatch <- coordinates
  coordinate_mismatch[1, 1] <- coordinate_mismatch[1, 1] + 0.25
  bad_sce <- scworkbench:::.wb_slingshot_run_fit(
    X_fit = coordinate_mismatch,
    cells_fit = cells,
    cluster_labels = clusters,
    start.clus = "early",
    end.clus = "late"
  )
  bad_sds <- slingshot::SlingshotDataSet(bad_sce)
  mismatch_error <- try(wb_slingshot_adoption_model(
    b, bad_sds, "published_umap", source_sha256
  ), silent = TRUE)
  stopifnot(inherits(mismatch_error, "try-error"))

  wrong_source_error <- try(wb_session_run_op(
    wb_session_new(), b, "slingshot_adopt",
    inputs = list(
      model = model,
      source = wb_ref_entity("external_source", "not_the_published_source"),
      cell_set = "all",
      min_cells = 1L
    )
  ), silent = TRUE)
  stopifnot(inherits(wrong_source_error, "try-error"))

  incomplete_error <- try(wb_session_run_op(
    wb_session_new(), b, "slingshot_adopt",
    inputs = list(
      model = model,
      source = wb_ref_entity("external_source", source_id),
      cell_set = "all",
      cell_ids = cells[-1],
      min_cells = 1L
    )
  ), silent = TRUE)
  stopifnot(inherits(incomplete_error, "try-error"))

  # Legacy trajectory payloads did not retain identity-bearing primitive
  # metadata. Their loader path still backfills the fit-family contract from
  # provenance, while modern payloads above remain byte-for-byte identical.
  legacy_provenance <- jsonlite::fromJSON(
    DBI::dbGetQuery(
      b$con, "SELECT provenance_json FROM artifacts WHERE artifact_id = ?;",
      params = list(artifact_ids[["pseudotime"]])
    )$provenance_json[[1L]],
    simplifyVector = FALSE
  )
  legacy_provenance$primitive_payload <- NULL
  DBI::dbExecute(
    b$con, "UPDATE artifacts SET provenance_json = ? WHERE artifact_id = ?;",
    params = list(
      jsonlite::toJSON(legacy_provenance, auto_unbox = TRUE, null = "null"),
      artifact_ids[["pseudotime"]]
    )
  )
  legacy_loaded <- wb_art_load(b, artifact_ids[["pseudotime"]])
  stopifnot(
    identical(legacy_loaded$meta$trajectory_fit_id, model$trajectory_fit_id),
    identical(legacy_loaded$meta$engine, "slingshot"),
    identical(legacy_loaded$meta$family_kind, "trajectory_pseudotime")
  )

  TRUE
}
