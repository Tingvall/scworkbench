test_op_hvg_pca_contract <- function() {
  if (!requireNamespace("BPCells", quietly = TRUE)) {
    message("Skipping hvg/pca contract test: BPCells not installed.")
    return(TRUE)
  }
  if (!requireNamespace("irlba", quietly = TRUE)) {
    message("Skipping hvg/pca contract test: irlba not installed.")
    return(TRUE)
  }

  tmp <- tempfile("scwb_hvg_pca_")
  b <- wb_init_bundle(tmp, overwrite = TRUE)
  on.exit({
    wb_close_bundle(b)
    unlink(tmp, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  cells <- paste0("c", seq_len(8))
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
  stopifnot(identical(as.character(rr_pca$run$outputs$space$space_id), "rna.pca"))
  stopifnot(!"rna.pca" %in% as.character(wb_spaces(b)$space_id))
  coords <- wb_space(wb_session_view(rr_pca$session), "rna.pca")
  stopifnot(is.data.frame(coords), nrow(coords) == 8L)
  stopifnot(all(c("cell_id", "x", "y") %in% names(coords)))
  stopifnot(all(is.finite(coords$x)), all(is.finite(coords$y)))

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
  wb_close_bundle(b); b <- wb_open_bundle(tmp)
  stopifnot("rna.pca" %in% as.character(wb_spaces(b)$space_id))
  stopifnot(nrow(wb_space(b, "rna.pca")) == length(cells))
  for (output in c("loadings", "variance", "fit_summary")) {
    aid <- as.character(pca_ok$artifact_id[as.character(pca_ok$output) == output][1])
    stopifnot(nzchar(aid), inherits(wb_art_load(b, aid), "wb_primitive"))
  }
  stopifnot(all(as.character(pca_ok$lineage_status) == "complete"))
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
