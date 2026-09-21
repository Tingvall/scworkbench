.make_composite_test_artifacts <- function(bundle, cells, key = "composite_test") {
  make_segment <- function(segment_id, selected, fit_id, order) list(
    segment_id = segment_id, order = order, source_kind = "fitted_model",
    source_engine = "slingshot", lineage = "L1",
    pseudotime = wb_prim_cell_vector_family(rep("L1", length(selected)),
      selected, seq(0, 1, length.out = length(selected)), "continuous",
      meta = list(trajectory_fit_id = fit_id, engine = "slingshot")))
  method <- getFromNamespace(".trajectory_segment_join", "scwbTrajectory")
  result <- method(segments = list(
    make_segment("segment_1", cells[1:6], "fit_1", 1L),
    make_segment("segment_2", cells[6:12], "fit_2", 2L)),
    composite_id = "comp_test", composite_key = key)

  run <- wb_new_run(
    op_name = "scwbtrajectory::trajectory_segment_join",
    inputs = list(cell_set = "all", user_inputs = list(composite_key = key)),
    params = result$params,
    outputs = result$outputs,
    notes = "synthetic composite pseudotime fixture"
  )
  prom <- wb_promote_analysis(
    bundle = bundle,
    runs = setNames(list(run), run$run_id),
    head_run_id = run$run_id,
    name_prefix = "composite pseudotime fixture",
    created_by = "test",
    fail_fast = TRUE
  )
  output_col <- if ("output_name" %in% names(prom$promoted)) "output_name" else "output"
  stats::setNames(as.character(prom$promoted$artifact_id), as.character(prom$promoted[[output_col]]))
}

.make_path_join_test_artifact <- function(bundle, fit_id, segment_id, x, y) {
  path <- wb_prim_path_2d_family(
    key = rep("L1", length(x)),
    point = seq_along(x),
    x = x,
    y = y,
    meta = list(
      trajectory_fit_id = fit_id,
      engine = "synthetic",
      n_lineages = 1L,
      family_kind = "trajectory_curve_2d"
    )
  )
  run <- wb_new_run(
    op_name = "slingshot_project",
    inputs = list(cell_set = "all", user_inputs = list(segment_id = segment_id)),
    params = list(
      trajectory_fit_id = fit_id,
      trajectory_engine = "synthetic",
      engine = "synthetic",
      n_lineages = 1L,
      plot_space_id = "umap_test"
    ),
    outputs = list(curves = path),
    notes = paste0("synthetic path fixture ", segment_id)
  )
  prom <- wb_promote_analysis(
    bundle = bundle,
    runs = setNames(list(run), run$run_id),
    head_run_id = run$run_id,
    name_prefix = paste0("path ", segment_id),
    created_by = "test",
    fail_fast = TRUE
  )
  output_col <- if ("output_name" %in% names(prom$promoted)) "output_name" else "output"
  as.character(prom$promoted$artifact_id[as.character(prom$promoted[[output_col]]) == "curves"])[1]
}

test_composite_pseudotime_dynamics_contract <- function() {
  if (!requireNamespace("BPCells", quietly = TRUE)) {
    return(contract_test_skip("BPCells is not installed."))
  }
  contract_test_activate_trajectory_pack()

  tmp <- tempfile("scwb_composite_dynamics_")
  b <- wb_init_bundle(tmp, overwrite = TRUE)
  on.exit({
    try(wb_close_bundle(b), silent = TRUE)
    unlink(tmp, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  cells <- paste0("c", seq_len(12))
  wb_define_cells(b, cells)
  mat <- matrix(
    c(
      seq(1, 12),
      rev(seq(1, 12)),
      rep(c(1, 3, 5), length.out = 12)
    ),
    nrow = 3,
    byrow = TRUE,
    dimnames = list(c("g1", "g2", "g3"), cells)
  )
  wb_attach_matrix(b, matrix_id = "RNA_counts", mat = mat, feature_type = "gene")
  wb_feature_set_replace(
    b,
    feature_set = "SET_ON",
    matrix_id = "RNA_counts",
    feature_ids = c("g1", "g3"),
    namespace = "test_sets",
    created_by = "test",
    strict = TRUE
  )
  wb_feature_set_replace(
    b,
    feature_set = "SET_OFF",
    matrix_id = "RNA_counts",
    feature_ids = c("g2"),
    namespace = "test_sets",
    created_by = "test",
    strict = TRUE
  )

  ids <- .make_composite_test_artifacts(b, cells, key = "joined_L1")
  pt_art <- ids[["composite_pseudotime_unit_segment"]]
  mem_art <- ids[["composite_membership"]]
  stopifnot(nzchar(pt_art), nzchar(mem_art))

  # Existing model-backed mode remains valid.
  model <- wb_prim_model_ref(model_space_id = "synthetic", in_space_id = "synthetic", engine = "synthetic")
  model$pseudotime_table <- data.frame(
    lineage_id = "joined_L1",
    cell_id = cells,
    pseudotime = seq(0, 1, length.out = length(cells)),
    stringsAsFactors = FALSE
  )
  model_gs <- wb_op_trajectory_geneset_dynamics(
    bundle = b,
    matrix_id = "RNA_counts",
    model = model,
    namespace = "test_sets",
    lineage = "joined_L1",
    n_bins = 5L,
    min_cells_per_bin = 1L,
    min_set_size = 1L,
    top_driver_genes = 1L
  )
  stopifnot(identical(as.character(model_gs$outputs$fit_summary$table$pseudotime_source_kind[1]), "model_ref"))

  s <- wb_session_new()
  gs <- wb_session_run_op(
    session = s,
    bundle = b,
    op_name = "trajectory_geneset_dynamics",
    inputs = list(
      cell_set = "all",
      min_cells = 1L,
      matrix = "RNA_counts",
      pseudotime = wb_ref_artifact(pt_art, "composite_pseudotime_unit_segment"),
      pseudotime_key = "joined_L1",
      membership = wb_ref_artifact(mem_art, "composite_membership"),
      namespace = "test_sets",
      n_bins = 5L,
      min_cells_per_bin = 1L,
      min_set_size = 1L,
      top_driver_genes = 1L
    )
  )
  sm <- gs$run$outputs$fit_summary$table
  stopifnot(identical(as.character(sm$pseudotime_source_kind[1]), "cell_vector_family"))
  stopifnot(identical(as.character(sm$pseudotime_artifact_id[1]), pt_art))
  stopifnot(identical(as.character(sm$pseudotime_key[1]), "joined_L1"))
  stopifnot(identical(as.character(sm$membership_artifact_id[1]), mem_art))
  stopifnot(identical(as.integer(sm$n_pseudotime_cells[1]), 12L))
  stopifnot(identical(as.integer(sm$n_membership_cells[1]), 12L))
  stopifnot(identical(as.integer(sm$n_cells_used[1]), 12L))

  bad_key <- try(
    wb_session_run_op(
      session = s,
      bundle = b,
      op_name = "trajectory_geneset_dynamics",
      inputs = list(
        cell_set = "all",
        min_cells = 1L,
        matrix = "RNA_counts",
        pseudotime = wb_ref_artifact(pt_art, "composite_pseudotime_unit_segment"),
        pseudotime_key = "missing_key",
        namespace = "test_sets",
        n_bins = 5L,
        min_cells_per_bin = 1L,
        min_set_size = 1L
      )
    ),
    silent = TRUE
  )
  stopifnot(inherits(bad_key, "try-error"))
  stopifnot(grepl("explicit pseudotime key", as.character(bad_key), fixed = TRUE))

  sig <- wb_prim_cell_vector_family(
    key = rep(c("sig_on", "sig_off"), each = length(cells)),
    cell_id = rep(cells, times = 2L),
    value = c(seq(0, 1, length.out = length(cells)), rev(seq(0, 1, length.out = length(cells)))),
    value_type = "continuous"
  )
  sig_dyn <- wb_session_run_op(
    session = gs$session,
    bundle = b,
    op_name = "trajectory_signal_dynamics",
    inputs = list(
      cell_set = "all",
      min_cells = 1L,
      signal = sig,
      pseudotime = wb_ref_artifact(pt_art, "composite_pseudotime_unit_segment"),
      pseudotime_key = "joined_L1",
      membership = wb_ref_artifact(mem_art, "composite_membership"),
      n_bins = 5L,
      min_cells_per_bin = 1L
    )
  )
  sig_sm <- sig_dyn$run$outputs$fit_summary$table
  stopifnot(identical(as.character(sig_sm$pseudotime_source_kind[1]), "cell_vector_family"))
  stopifnot(identical(as.character(sig_sm$pseudotime_artifact_id[1]), pt_art))

  path1 <- .make_path_join_test_artifact(b, "fit_path_1", "seg1", x = c(0, 1, 2), y = c(0, 0.5, 1))
  path2 <- .make_path_join_test_artifact(b, "fit_path_2", "seg2", x = c(2, 3, 4), y = c(1, 1.2, 1.5))
  pj <- wb_session_run_op(
    session = wb_session_new(),
    bundle = b,
    op_name = "scwbtrajectory::trajectory_segment_path_join",
    inputs = list(
      cell_set = "all",
      min_cells = 1L,
      paths = list(
        list(segment_id = "seg1", path = wb_ref_artifact(path1, "curves"), lineage = "L1", order = 1, start_label = "root", end_label = "DN3"),
        list(segment_id = "seg2", path = wb_ref_artifact(path2, "curves"), lineage = "L1", order = 2, start_label = "DN3", end_label = "CD4")
      ),
      composite_id = "comp_test",
      composite_key = "joined_path"
    )
  )
  curves <- pj$run$outputs$curves
  manifest <- pj$run$outputs$path_manifest
  stopifnot(identical(as.character(curves$kind), "path_2d_family"))
  stopifnot(identical(unique(as.character(curves$key)), "joined_path"))
  stopifnot(identical(length(curves$point), 6L))
  stopifnot(identical(as.character(manifest$table_type), "trajectory_segment_path_join_manifest"))
  stopifnot(identical(as.integer(manifest$table$composite_point_end[1]), 3L))
  stopifnot(identical(as.integer(manifest$table$composite_point_start[2]), 4L))

  prom <- wb_session_promote_current(
    bundle = b,
    session = pj$session,
    name_prefix = "composite path join",
    created_by = "test",
    fail_fast = TRUE,
    outputs = c("curves", "path_manifest")
  )
  output_col <- if ("output_name" %in% names(prom$promoted)) "output_name" else "output"
  promoted <- stats::setNames(as.character(prom$promoted$artifact_id), as.character(prom$promoted[[output_col]]))
  loaded_curves <- wb_art_load(b, promoted[["curves"]], expected_kind = "path_2d_family")
  loaded_manifest <- wb_art_load(b, promoted[["path_manifest"]], expected_kind = "obs_table")
  stopifnot(identical(as.character(loaded_curves$kind), "path_2d_family"))
  stopifnot(identical(as.character(loaded_manifest$table_type), "trajectory_segment_path_join_manifest"))

  TRUE
}
