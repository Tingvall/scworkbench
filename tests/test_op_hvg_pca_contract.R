test_op_hvg_pca_contract <- function() {
  if (!requireNamespace("BPCells", quietly = TRUE)) {
    return(contract_test_skip("BPCells is not installed."))
  }
  if (!requireNamespace("irlba", quietly = TRUE)) {
    return(contract_test_skip("irlba is not installed."))
  }

  tmp <- tempfile("scwb_hvg_pca_")
  b <- wb_init_bundle(tmp, overwrite = TRUE)
  on.exit({
    wb_close_bundle(b)
    unlink(tmp, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  cells <- paste0("cell_", letters[seq_len(8)])
  wb_define_cells(b, cells)

  mat <- Matrix::Matrix(
    matrix(
      c(
        10,  9, 11,  8,  1,  0,  1,  0,
         0,  1,  0,  1, 10, 11,  9, 12,
         5,  5,  4,  6,  5,  4,  6,  5,
         0,  0,  0,  1,  0,  0,  0,  1,
         2,  3,  2,  3,  8,  7,  9,  8,
         7,  6,  8,  7,  2,  1,  2,  1
      ),
      nrow = 6,
      byrow = TRUE,
      dimnames = list(paste0("g", seq_len(6)), cells)
    ),
    sparse = TRUE
  )
  wb_attach_matrix(b, matrix_id = "RNA_counts", mat = mat, feature_type = "gene")

  rr_norm <- wb_session_run_op(
    wb_session_new(),
    b,
    "matrix_log_normalize",
    inputs = list(
      matrix = "RNA_counts",
      cell_set = "all",
      min_cells = 1L,
      output_matrix_id = "RNA_log_norm",
      overwrite = TRUE
    )
  )

  rr_hvg <- wb_session_run_op(
    rr_norm$session,
    b,
    "hvg_select",
    inputs = list(
      matrix = "RNA_log_norm",
      cell_set = "all",
      min_cells = 1L,
      n_features = 4L,
      method = "vst",
      chunk_size = 2L
    )
  )
  hvg <- rr_hvg$run$outputs$selected_features
  stopifnot(identical(as.character(hvg$kind), "feature_table"))
  stopifnot(identical(as.character(hvg$table_type), "feature_selection_table"))
  stopifnot(all(c("feature_id", "rank", "mean", "variance", "dispersion", "score", "selected") %in% names(hvg$table)))
  stopifnot(sum(as.logical(hvg$table$selected)) == 4L)

  prom <- wb_session_promote_current(
    bundle = b,
    session = rr_hvg$session,
    name_prefix = "hvg_pca_test",
    created_by = "test",
    outputs = "selected_features"
  )
  hvg_art <- as.character(prom$promoted$artifact_id[as.character(prom$promoted$output) == "selected_features"][1])
  stopifnot(nzchar(hvg_art))
  norm_identity <- DBI::dbGetQuery(
    b$con,
    "SELECT content_sha256, verification_level, verification_status FROM prov_run_outputs WHERE snapshot_id = ? AND run_id = ? AND output_name = 'matrix';",
    params = list(prom$provenance_snapshot_id, rr_norm$run$run_id)
  )
  stopifnot(nrow(norm_identity) == 1L, identical(as.character(norm_identity$verification_level[1]), "content"),
            identical(as.character(norm_identity$verification_status[1]), "content_verified"),
            grepl("^[0-9a-f]{64}$", as.character(norm_identity$content_sha256[1])))

  rr_pca <- wb_session_run_op(
    rr_hvg$session,
    b,
    "pca_fit",
    inputs = list(
      matrix = "RNA_log_norm",
      features = wb_ref_artifact(hvg_art, "selected_features"),
      cell_set = "all",
      min_cells = 1L,
      n_components = 2L,
      center = TRUE,
      scale = TRUE,
      backend = "irlba",
      seed = 1L,
      space_id_out = "rna.pca",
      overwrite = TRUE,
      max_dense_gb = 1
    )
  )

  stopifnot(identical(as.character(rr_pca$run$outputs$space$kind), "space"))
  stopifnot(identical(rr_pca$run$inputs$coverage$per_input$matrix$available_n, length(cells)),
            identical(rr_pca$run$inputs$coverage$effective_n, length(cells)))
  stopifnot(identical(as.character(rr_pca$run$outputs$space$space_id), "rna.pca"))
  stopifnot(!"rna.pca" %in% as.character(wb_spaces(b)$space_id))
  coords <- wb_space(wb_session_view(rr_pca$session), "rna.pca")
  stopifnot(is.data.frame(coords), nrow(coords) == 8L)
  stopifnot(all(c("cell_id", "x", "y") %in% names(coords)))
  stopifnot(all(is.finite(coords$x)), all(is.finite(coords$y)),
            identical(as.character(coords$cell_id), cells),
            identical(rownames(coords), cells))

  loadings <- rr_pca$run$outputs$loadings
  variance <- rr_pca$run$outputs$variance
  fit_summary <- rr_pca$run$outputs$fit_summary
  stopifnot(identical(as.character(loadings$kind), "feature_table"))
  stopifnot(identical(as.character(loadings$table_type), "pca_loadings"))
  stopifnot(all(c("feature_id", "PC", "loading") %in% names(loadings$table)))
  stopifnot(identical(as.character(variance$table_type), "pca_variance_explained"))
  stopifnot(identical(as.character(fit_summary$table_type), "pca_fit_summary"))
  stopifnot(identical(as.character(fit_summary$table$space_id[1]), "rna.pca"))

  pca_prom <- wb_session_promote_current(
    bundle = b,
    session = rr_pca$session,
    name_prefix = "hvg_pca_promotion",
    created_by = "test",
    outputs = c("loadings", "variance", "fit_summary")
  )
  pca_ok <- pca_prom$promoted[pca_prom$promoted$status == "ok", , drop = FALSE]
  stopifnot(setequal(as.character(pca_ok$output), c("loadings", "variance", "fit_summary")))
  pca_space_identity <- DBI::dbGetQuery(
    b$con,
    "SELECT content_sha256, verification_level, verification_status FROM prov_run_outputs WHERE snapshot_id = ? AND run_id = ? AND output_name = 'space';",
    params = list(pca_prom$provenance_snapshot_id, rr_pca$run$run_id)
  )
  stopifnot(nrow(pca_space_identity) == 1L, identical(as.character(pca_space_identity$verification_level[1]), "content"),
            identical(as.character(pca_space_identity$verification_status[1]), "content_verified"),
            grepl("^[0-9a-f]{64}$", as.character(pca_space_identity$content_sha256[1])))
  wb_close_bundle(b); b <- wb_open_bundle(tmp)
  stopifnot("rna.pca" %in% as.character(wb_spaces(b)$space_id))
  persisted_pca_ids <- DBI::dbGetQuery(
    b$con, "SELECT cell_id FROM space_2d WHERE space_id = ? ORDER BY rowid;",
    params = list("rna.pca")
  )$cell_id
  durable_pca <- wb_space(b, "rna.pca")
  stopifnot(nrow(durable_pca) == length(cells),
            identical(as.character(persisted_pca_ids), cells),
            identical(as.character(durable_pca$cell_id), cells),
            identical(rownames(durable_pca), cells))
  for (output in c("loadings", "variance", "fit_summary")) {
    aid <- as.character(pca_ok$artifact_id[as.character(pca_ok$output) == output][1])
    stopifnot(nzchar(aid), inherits(wb_art_load(b, aid), "wb_primitive"))
  }
  stopifnot(all(as.character(pca_ok$lineage_status) == "complete"))
  wb_finalize_recipient_bundle(b)
  stopifnot(isTRUE(wb_validate_bundle(tmp)))

  # PCA with two components uses the generic wb_add_space() wide writer.  A
  # separate promoted UMAP session must consume its exact canonical IDs and
  # retain them through the direct UMAP space_2d writer after reopen.
  if (requireNamespace("uwot", quietly = TRUE)) {
    rr_umap <- wb_session_run_op(
      wb_session_new(), b, "umap_fit",
      inputs = list(space = "rna.pca", cell_set = "all", min_cells = 1L,
                    dims = 1:2, space_id_out = "rna.umap", n_neighbors = 3L,
                    min_dist = 0.1, metric = "euclidean", nn_method = "annoy", seed = 1L)
    )
    stopifnot(identical(rr_umap$run$inputs$coverage$per_input$space$source_id, "rna.pca"),
              identical(rr_umap$run$inputs$coverage$effective_n, length(cells)))
    wb_session_promote_current(b, rr_umap$session, outputs = c("model", "space_2d"))
    wb_close_bundle(b); b <- wb_open_bundle(tmp)
    durable_umap <- wb_space(b, "rna.umap", cells = cells)
    stopifnot(identical(as.character(durable_umap$cell_id), cells),
              identical(rownames(durable_umap), cells),
              isTRUE(wb_validate_bundle(tmp)))
  }

  # A durable ancestor may be reused, but a different run must not replace its
  # committed matrix merely because the session overlay permits overwrite.
  rr_norm_collision <- try(wb_session_run_op(
    wb_session_new(), b, "matrix_log_normalize",
    inputs = list(matrix = "RNA_counts", cell_set = "all", min_cells = 1L,
                  output_matrix_id = "RNA_log_norm", overwrite = TRUE)
  ), silent = TRUE)
  stopifnot(inherits(rr_norm_collision, "try-error"))
  stopifnot(grepl("provenance-bound matrix 'RNA_log_norm'", as.character(rr_norm_collision), fixed = TRUE))
  stopifnot(isTRUE(wb_validate_bundle(tmp)))

  # Publication failure must leave the staged PCA closure entirely invisible.
  rr_pca_fail <- wb_session_run_op(
    rr_hvg$session, b, "pca_fit",
    inputs = list(matrix = "RNA_log_norm", features = wb_ref_artifact(hvg_art, "selected_features"),
                  cell_set = "all", min_cells = 1L, n_components = 2L, center = TRUE,
                  scale = TRUE, backend = "irlba", seed = 1L, space_id_out = "rna.pca.failure",
                  overwrite = FALSE, max_dense_gb = 1)
  )
  hook_calls <- 0L
  old_hook <- getOption("scworkbench.promotion_workspace_publish_hook")
  options(scworkbench.promotion_workspace_publish_hook = function(workspace, final_rel) {
    hook_calls <<- hook_calls + 1L
    if (hook_calls == 2L) stop("forced PCA publication failure", call. = FALSE)
  })
  on.exit(options(scworkbench.promotion_workspace_publish_hook = old_hook), add = TRUE)
  failed <- try(wb_session_promote_current(
    b, rr_pca_fail$session, name_prefix = "hvg_pca_failure", created_by = "test",
    outputs = c("loadings", "variance", "fit_summary")
  ), silent = TRUE)
  stopifnot(inherits(failed, "try-error"))
  wb_close_bundle(b); b <- wb_open_bundle(tmp)
  stopifnot(!"rna.pca.failure" %in% as.character(wb_spaces(b)$space_id))
  pca_arts <- wb_art_list(b)
  stopifnot(!any(as.character(pca_arts$source_op %||% "") == "pca_fit" &
                    grepl("hvg_pca_failure", as.character(pca_arts$name %||% ""), fixed = TRUE)))
  stopifnot(!any(as.character(DBI::dbGetQuery(b$con, "SELECT op_name FROM prov_runs;")$op_name) == "pca_fit" &
                    grepl("rna.pca.failure", as.character(DBI::dbGetQuery(b$con, "SELECT inputs_json FROM prov_runs;")$inputs_json), fixed = TRUE)))
  stopifnot(isTRUE(wb_validate_bundle(tmp)))

  iface_hvg <- wb_op_interface("hvg_select")
  iface_pca <- wb_op_interface("pca_fit")
  stopifnot(identical(as.character(iface_hvg$produces$selected_features$kind), "feature_table"))
  stopifnot(identical(as.character(iface_pca$produces$space$kind), "space"))
  stopifnot("hvg_select" %in% wb_list_ops())
  stopifnot("pca_fit" %in% wb_list_ops())

  err_batch <- try(
    wb_session_run_op(
      rr_norm$session,
      b,
      "hvg_select",
      inputs = list(matrix = "RNA_log_norm", cell_set = "all", min_cells = 1L, batch_key = "sample")
    ),
    silent = TRUE
  )
  stopifnot(inherits(err_batch, "try-error"))

  TRUE
}
