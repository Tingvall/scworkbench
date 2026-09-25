test_phase5_s3_representation_slingshot_composite_contract <- function() {
  contract_test_activate_representation_pack()
  contract_test_activate_trajectory_pack()
  root <- tempfile("scwb-phase5-s3-composite-")
  bundle <- wb_init_bundle(root, overwrite = TRUE)
  on.exit({
    try(wb_close_bundle(bundle), silent = TRUE)
    unlink(root, recursive = TRUE, force = TRUE)
  }, add = TRUE)
  cells <- paste0("cell_", seq_len(120L))
  features <- paste0("gene_", seq_len(12L))
  group <- rep(c("root", "left", "right"), each = 40L)
  branch_x <- rep(c(0, -5, 5), each = 40L) +
    rep(seq(-.5, .5, length.out = 40L), 3L)
  branch_y <- rep(c(0, 5, 5), each = 40L) +
    sin(seq_len(120L) * .31) * .4
  branch_z <- sin(seq_len(120L) * .17) * .7
  counts <- outer(seq_len(12L), seq_len(120L), function(i, j)
    as.integer(round(100 + (i - 6) * branch_x[j] +
      ((i * 3L) %% 7L - 3L) * branch_y[j] +
      ((i * 5L) %% 11L - 5L) * branch_z[j] +
      ((i * j) %% 5L))))
  dimnames(counts) <- list(features, cells)
  wb_define_cells(bundle, cells)
  wb_attach_matrix(bundle, "RNA", Matrix::Matrix(counts, sparse = TRUE),
    feature_type = "gene")
  pca <- wb_session_run_op(wb_session_new(), bundle,
    "scwbrepresentation::pca_fit", inputs = list(matrix = "RNA",
      feature_ids = features, n_components = 3L, center = TRUE,
      scale = FALSE, backend = "prcomp", seed = 1L,
      space_id_out = "pca_s3", overwrite = FALSE, max_dense_gb = 1,
      chunk_size = 20L, min_cells = 1L))
  pca_publication <- wb_session_promote_current(bundle, pca$session,
    outputs = "fit_summary", created_by = "phase5-s3-composite")
  stopifnot(all(pca_publication$promoted$status %in% c("ok", "skipped")))
  coords <- wb_space(bundle, "pca_s3")
  plot <- coords[, 1:2, drop = FALSE]
  colnames(plot) <- c("x", "y")
  wb_add_space(bundle, "pca_s3_plot", plot)
  clusters <- wb_prim_cell_vector(stats::setNames(group, cells),
    value_type = "categorical")
  fit <- wb_session_run_op(wb_session_new(), bundle,
    "scwbtrajectory::slingshot_fit", inputs = list(fit_space = "pca_s3",
      clusters = clusters, start.clus = "root",
      end.clus = c("left", "right"), min_cells = 1L))
  stopifnot(identical(sort(names(fit$run$outputs)),
    c("lineage_weights", "model", "pseudotime")))
  promoted <- wb_session_promote_current(bundle, fit$session,
    outputs = names(fit$run$outputs), created_by = "phase5-s3-composite")
  stopifnot(nrow(promoted$promoted) == 3L,
    all(promoted$promoted$status == "ok"))
  model_id <- promoted$promoted$artifact_id[
    promoted$promoted$output == "model"][[1L]]
  reference <- wb_ref_artifact(model_id, "model")
  weights <- wb_session_run_op(wb_session_new(), bundle,
    "scwbtrajectory::slingshot_lineage_weights",
    inputs = list(model = reference, min_cells = 1L))
  project <- wb_session_run_op(wb_session_new(), bundle,
    "scwbtrajectory::slingshot_project",
    inputs = list(model = reference, plot_space = "pca_s3_plot",
      approx_points = 20L, min_cells = 1L))
  stopifnot(identical(unique(weights$run$outputs$lineage_weights$key),
    unique(fit$run$outputs$lineage_weights$key)),
    identical(unique(project$run$outputs$curves$key),
      unique(fit$run$outputs$pseudotime$key)),
    isTRUE(wb_finalize_recipient_bundle(bundle)$ready))
  wb_session_discard(fit$session)
  wb_session_discard(weights$session)
  wb_session_discard(project$session)
  TRUE
}
