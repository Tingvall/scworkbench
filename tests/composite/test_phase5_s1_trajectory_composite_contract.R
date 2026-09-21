test_phase5_s1_rna_representation_trajectory_composite_contract <- function() {
  contract_test_activate_rna_pack()
  contract_test_activate_representation_pack()
  contract_test_activate_trajectory_pack()
  root <- tempfile("scwb-phase5-s1-composite-")
  b <- wb_init_bundle(root, overwrite = TRUE)
  on.exit({try(wb_close_bundle(b), silent = TRUE)
    unlink(root, recursive = TRUE, force = TRUE)}, add = TRUE)
  cells <- paste0("c", sprintf("%02d", seq_len(24L)))
  features <- paste0("g", seq_len(8L))
  values <- outer(seq_along(features), seq_along(cells), function(i, j)
    as.integer(2L + (i * j) %% 11L))
  dimnames(values) <- list(features, cells)
  wb_define_cells(b, cells)
  wb_attach_matrix(b, "RNA", Matrix::Matrix(values, sparse = TRUE),
    feature_type = "gene")
  rna_qc <- wb_session_run_op(wb_session_new(), b,
    "scwbrna::rna_qc_metrics", inputs = list(matrix = "RNA",
      mitochondrial_pattern = "^g1$", ribosomal_pattern = "^g2$",
      chunk_size = 4L, min_cells = 1L))
  rna_qc_promotion <- wb_session_promote_current(b, rna_qc$session,
    outputs = names(rna_qc$run$outputs),
    created_by = "phase5-s1-composite")
  stopifnot(all(rna_qc_promotion$promoted$status == "ok"))
  pseudotime <- wb_prim_cell_vector(
    setNames(seq(0, 1, length.out = length(cells)), cells), "continuous")
  membership <- wb_prim_relation_family(rep("route", length(cells)), cells,
    seq(.2, 1, length.out = length(cells)))
  family <- wb_prim_cell_vector_family(rep(c("A", "B"), each = 24L),
    rep(cells, 2L), c(seq(0, 1, length.out = 24L),
      seq(1, 0, length.out = 24L)))
  branches <- wb_prim_relation_family(rep(c("A", "B"), each = 12L),
    c(cells[1:12], cells[13:24]), rep(1, 24L))
  normalized <- wb_session_run_op(wb_session_new(), b,
    "scwbrna::matrix_log_normalize", inputs = list(matrix = "RNA",
      output_matrix_id = "RNA_log_staged", scale_factor = 1000,
      chunk_size = 4L, overwrite = FALSE, min_cells = 1L))
  staged_compared <- wb_session_run_op(normalized$session, b,
    "scwbtrajectory::trajectory_branch_compare", inputs = list(
      matrix = "RNA_log_staged", pseudotime = family,
      branch_membership = branches, branch_a = "A", branch_b = "B",
      features = features[1:3], min_cells = 1L))
  stopifnot(nrow(staged_compared$run$outputs$branch_de_table$table) == 3L)
  compared <- wb_session_run_op(wb_session_new(), b,
    "scwbtrajectory::trajectory_branch_compare", inputs = list(
      matrix = "RNA",
      pseudotime = family, branch_membership = branches,
      branch_a = "A", branch_b = "B", features = features[1:3],
      min_cells = 1L))
  compared_promotion <- wb_session_promote_current(b, compared$session,
    outputs = names(compared$run$outputs),
    created_by = "phase5-s1-composite")
  stopifnot(all(compared_promotion$promoted$status == "ok"))
  smoothed <- wb_session_run_op(wb_session_new(), b,
    "scwbtrajectory::trajectory_route_smooth", inputs = list(
      matrix = "RNA", pseudotime = pseudotime,
      branch_membership = membership, route_key = "route",
      features = features[1:2], n_bins = 5L, min_cells_per_bin = 1L,
      min_cells = 1L))
  smoothed_promotion <- wb_session_promote_current(b, smoothed$session,
    outputs = names(smoothed$run$outputs),
    created_by = "phase5-s1-composite")
  stopifnot(all(smoothed_promotion$promoted$status == "ok"))
  pca <- wb_session_run_op(wb_session_new(), b,
    "scwbrepresentation::pca_fit", inputs = list(matrix = "RNA",
      feature_ids = features, n_components = 3L, center = TRUE,
      scale = FALSE, backend = "prcomp", seed = 1L,
      space_id_out = "pca", overwrite = FALSE, max_dense_gb = 1,
      chunk_size = 4L, min_cells = 1L))
  pca_promotion <- wb_session_promote_current(b, pca$session,
    outputs = "fit_summary", created_by = "phase5-s1-composite")
  stopifnot(all(pca_promotion$promoted$status %in% c("ok", "skipped")))
  pca_values <- wb_space(b, "pca")
  wb_add_space(b, "pca_plot", pca_values[, 1:2, drop = FALSE])
  wb_cell_set_replace(b, "set:start", cells[1:4], source = "phase5-s1")
  wb_cell_set_replace(b, "set:end", cells[21:24], source = "phase5-s1")
  path_run <- wb_session_run_op(wb_session_new(), b,
    "scwbtrajectory::space_path_define",
    inputs = list(space = "pca", checkpoint_sets = c("set:start",
      "set:end"), n_path_points = 6L, path_id_out = "pca_path",
      min_cells = 1L))
  path <- path_run$run$outputs$path
  scored <- wb_session_run_op(path_run$session, b,
    "scwbtrajectory::space_path_score", inputs = list(space = "pca",
      path = wb_ref_run(path_run$run$run_id, "path"), min_cells = 1L))
  projected <- wb_session_run_op(scored$session, b,
    "scwbtrajectory::space_path_project_2d", inputs = list(
      path = wb_ref_run(path_run$run$run_id, "path"),
      source_space = "pca", plot_space = "pca_plot", approx_points = 4L,
      min_cells = 1L))
  stopifnot(identical(unique(scored$run$outputs$path_scores$key),
      c("progress", "distance", "nearest_segment", "nearest_anchor")),
    length(unique(projected$run$outputs$curves$point)) == 4L,
    nrow(compared$run$outputs$branch_de_table$table) == 3L,
    nrow(smoothed$run$outputs$trend_table$table) > 0L,
    identical(path$meta$space_id, "pca"))
  geometry_promotion <- wb_session_promote_current(b, projected$session,
    outputs = "curves", created_by = "phase5-s1-composite")
  stopifnot(all(geometry_promotion$promoted$status %in% c("ok", "skipped")),
    any(geometry_promotion$promoted$op_name ==
      "scwbtrajectory::space_path_project_2d"))
  TRUE
}
