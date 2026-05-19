test_op_trajectory_smooth_contract <- function(bundle_dir) {
  if (!requireNamespace("slingshot", quietly = TRUE)) {
    message("Skipping trajectory_smooth contract test: slingshot not installed.")
    return(TRUE)
  }

  b <- wb_open_bundle(bundle_dir)
  on.exit(wb_close_bundle(b), add = TRUE)

  iface <- wb_op_interface("trajectory_smooth", bundle = b)
  stopifnot(is.list(iface))
  stopifnot(identical(as.character(iface$produces$trend_table$kind), "obs_table"))
  stopifnot(identical(as.character(iface$produces$fit_summary$kind), "obs_table"))
  stopifnot("trajectory_smooth" %in% wb_list_ops())

  mats <- wb_matrices(b)
  stopifnot(is.data.frame(mats), nrow(mats) >= 1L)
  matrix_id <- as.character(mats$matrix_id[1])
  feats <- as.character(head(wb_feature_ids(b, matrix_id = matrix_id), 200))
  stopifnot(length(feats) >= 50L)

  cells <- tryCatch(wb_cells(b, cell_set = "core"), error = function(e) character(0))
  if (length(cells) < 300L) cells <- wb_cells(b, cell_set = "all")
  stopifnot(length(cells) >= 300L)
  cells <- as.character(head(cells, 600))

  sp_tbl <- wb_spaces(b)
  fit_space_id <- NA_character_
  for (sid in as.character(sp_tbl$space_id)) {
    sp <- tryCatch(wb_space(b, space_id = sid, cells = head(cells, 40)), error = function(e) NULL)
    if (is.null(sp)) next
    if (is.matrix(sp) && ncol(sp) >= 2L) {
      fit_space_id <- sid
      break
    }
    if (is.data.frame(sp) && all(c("x", "y") %in% colnames(sp))) {
      fit_space_id <- sid
      break
    }
  }
  stopifnot(nzchar(fit_space_id))

  s <- wb_session_new()
  r1 <- wb_session_run_op(
    session = s,
    bundle = b,
    op_name = "leiden",
    inputs = list(
      cell_set = "all",
      cell_ids = cells,
      space = wb_prim_space(fit_space_id),
      k = 20,
      resolution = 0.3
    ),
    notes = "test trajectory_smooth: leiden"
  )
  s <- r1$session
  r2 <- wb_session_run_op(
    session = s,
    bundle = b,
    op_name = "slingshot_fit",
    inputs = list(
      cell_set = "all",
      cell_ids = cells,
      fit_space = wb_prim_space(fit_space_id),
      clusters = wb_ref_run(r1$run$run_id, "clusters")
    ),
    notes = "test trajectory_smooth: slingshot fit"
  )

  pt <- r2$run$outputs$pseudotime
  stopifnot(inherits(pt, "wb_primitive"), identical(as.character(pt$kind), "cell_vector_family"))
  lineage <- as.character(unique(pt$key))[1]
  stopifnot(nzchar(lineage))

  r3 <- wb_session_run_op(
    session = r2$session,
    bundle = b,
    op_name = "trajectory_smooth",
    inputs = list(
      cell_set = "all",
      cell_ids = cells,
      matrix = wb_prim_matrix(matrix_id),
      model = wb_ref_run(r2$run$run_id, "model"),
      lineage = lineage,
      features = feats[1:4],
      n_bins = 20L,
      summary_fun = "mean",
      min_cells_per_bin = 5L
    ),
    notes = "test trajectory_smooth: run"
  )

  trend <- r3$run$outputs$trend_table
  sm <- r3$run$outputs$fit_summary
  stopifnot(inherits(trend, "wb_primitive"), identical(as.character(trend$kind), "obs_table"))
  stopifnot(inherits(sm, "wb_primitive"), identical(as.character(sm$kind), "obs_table"))
  stopifnot(identical(as.character(trend$table_type), "trajectory_smooth"))

  trend_tbl <- trend$table
  sm_tbl <- sm$table
  stopifnot(is.data.frame(trend_tbl), nrow(trend_tbl) > 0L)
  stopifnot(all(c("feature_id", "lineage_id", "bin", "pseudotime", "expr", "n_cells") %in% colnames(trend_tbl)))
  stopifnot(all(as.character(trend_tbl$lineage_id) == lineage))
  stopifnot(setequal(unique(as.character(trend_tbl$feature_id)), feats[1:4]))
  stopifnot(is.data.frame(sm_tbl), nrow(sm_tbl) >= 1L)
  stopifnot(all(c("lineage_id", "n_cells_used", "n_features_with_rows", "n_bins") %in% colnames(sm_tbl)))

  TRUE
}

test_op_trajectory_signature_smooth_contract <- function(bundle_dir) {
  if (!requireNamespace("slingshot", quietly = TRUE)) {
    message("Skipping trajectory_signature_smooth contract test: slingshot not installed.")
    return(TRUE)
  }

  b <- wb_open_bundle(bundle_dir)
  on.exit(wb_close_bundle(b), add = TRUE)

  iface <- wb_op_interface("trajectory_signature_smooth", bundle = b)
  stopifnot(is.list(iface))
  stopifnot(identical(as.character(iface$produces$signature_table$kind), "obs_table"))
  stopifnot(identical(as.character(iface$produces$fit_summary$kind), "obs_table"))
  stopifnot("trajectory_signature_smooth" %in% wb_list_ops())

  mats <- wb_matrices(b)
  stopifnot(is.data.frame(mats), nrow(mats) >= 1L)
  matrix_id <- as.character(mats$matrix_id[1])
  feats <- as.character(head(wb_feature_ids(b, matrix_id = matrix_id), 10))
  stopifnot(length(feats) >= 6L)

  fs_name <- paste0(".__test_trajectory_signature_smooth_feature_set__.", as.integer(Sys.time()))
  wb_feature_set_replace(
    bundle = b,
    feature_set = fs_name,
    matrix_id = matrix_id,
    feature_ids = feats[1:6],
    created_by = "test",
    description = "trajectory_signature_smooth contract test feature set",
    strict = TRUE
  )

  cells <- tryCatch(wb_cells(b, cell_set = "core"), error = function(e) character(0))
  if (length(cells) < 300L) cells <- wb_cells(b, cell_set = "all")
  stopifnot(length(cells) >= 300L)
  cells <- as.character(head(cells, 600))

  sp_tbl <- wb_spaces(b)
  fit_space_id <- NA_character_
  for (sid in as.character(sp_tbl$space_id)) {
    sp <- tryCatch(wb_space(b, space_id = sid, cells = head(cells, 40)), error = function(e) NULL)
    if (is.null(sp)) next
    if (is.matrix(sp) && ncol(sp) >= 2L) {
      fit_space_id <- sid
      break
    }
    if (is.data.frame(sp) && all(c("x", "y") %in% colnames(sp))) {
      fit_space_id <- sid
      break
    }
  }
  stopifnot(nzchar(fit_space_id))

  s <- wb_session_new()
  r1 <- wb_session_run_op(
    session = s,
    bundle = b,
    op_name = "leiden",
    inputs = list(
      cell_set = "all",
      cell_ids = cells,
      space = wb_prim_space(fit_space_id),
      k = 20,
      resolution = 0.3
    ),
    notes = "test trajectory_signature_smooth: leiden"
  )
  s <- r1$session
  r2 <- wb_session_run_op(
    session = s,
    bundle = b,
    op_name = "slingshot_fit",
    inputs = list(
      cell_set = "all",
      cell_ids = cells,
      fit_space = wb_prim_space(fit_space_id),
      clusters = wb_ref_run(r1$run$run_id, "clusters")
    ),
    notes = "test trajectory_signature_smooth: slingshot fit"
  )

  pt <- r2$run$outputs$pseudotime
  lineage <- as.character(unique(pt$key))[1]
  stopifnot(nzchar(lineage))

  r3 <- wb_session_run_op(
    session = r2$session,
    bundle = b,
    op_name = "trajectory_signature_smooth",
    inputs = list(
      cell_set = "all",
      cell_ids = cells,
      matrix = wb_prim_matrix(matrix_id),
      model = wb_ref_run(r2$run$run_id, "model"),
      feature_set = fs_name,
      lineage = lineage,
      score_method = "mean",
      n_bins = 20L,
      summary_fun = "mean",
      min_cells_per_bin = 5L
    ),
    notes = "test trajectory_signature_smooth: run"
  )

  sig <- r3$run$outputs$signature_table
  sm <- r3$run$outputs$fit_summary
  stopifnot(inherits(sig, "wb_primitive"), identical(as.character(sig$kind), "obs_table"))
  stopifnot(inherits(sm, "wb_primitive"), identical(as.character(sm$kind), "obs_table"))
  stopifnot(identical(as.character(sig$table_type), "trajectory_signature_smooth"))

  sig_tbl <- sig$table
  stopifnot(is.data.frame(sig_tbl), nrow(sig_tbl) > 0L)
  stopifnot(all(c("feature_set", "lineage_id", "bin", "pseudotime", "value", "n_cells") %in% colnames(sig_tbl)))
  stopifnot(all(as.character(sig_tbl$feature_set) == fs_name))
  stopifnot(all(as.character(sig_tbl$lineage_id) == lineage))

  TRUE
}

test_op_trajectory_vector_smooth_contract <- function(bundle_dir) {
  if (!requireNamespace("slingshot", quietly = TRUE)) {
    message("Skipping trajectory_vector_smooth contract test: slingshot not installed.")
    return(TRUE)
  }

  b <- wb_open_bundle(bundle_dir)
  on.exit(wb_close_bundle(b), add = TRUE)

  iface <- wb_op_interface("trajectory_vector_smooth", bundle = b)
  stopifnot(is.list(iface))
  stopifnot(identical(as.character(iface$produces$signal_table$kind), "obs_table"))
  stopifnot(identical(as.character(iface$produces$fit_summary$kind), "obs_table"))
  stopifnot("trajectory_vector_smooth" %in% wb_list_ops())

  mats <- wb_matrices(b)
  stopifnot(is.data.frame(mats), nrow(mats) >= 1L)
  matrix_id <- as.character(mats$matrix_id[1])
  feats <- as.character(head(wb_feature_ids(b, matrix_id = matrix_id), 12))
  stopifnot(length(feats) >= 6L)

  cells <- tryCatch(wb_cells(b, cell_set = "core"), error = function(e) character(0))
  if (length(cells) < 300L) cells <- wb_cells(b, cell_set = "all")
  stopifnot(length(cells) >= 300L)
  cells <- as.character(head(cells, 600))

  sp_tbl <- wb_spaces(b)
  fit_space_id <- NA_character_
  for (sid in as.character(sp_tbl$space_id)) {
    sp <- tryCatch(wb_space(b, space_id = sid, cells = head(cells, 40)), error = function(e) NULL)
    if (is.null(sp)) next
    if (is.matrix(sp) && ncol(sp) >= 2L) {
      fit_space_id <- sid
      break
    }
    if (is.data.frame(sp) && all(c("x", "y") %in% colnames(sp))) {
      fit_space_id <- sid
      break
    }
  }
  stopifnot(nzchar(fit_space_id))

  s <- wb_session_new()
  r1 <- wb_session_run_op(
    session = s,
    bundle = b,
    op_name = "leiden",
    inputs = list(
      cell_set = "all",
      cell_ids = cells,
      space = wb_prim_space(fit_space_id),
      k = 20,
      resolution = 0.3
    ),
    notes = "test trajectory_vector_smooth: leiden"
  )
  s <- r1$session
  r2 <- wb_session_run_op(
    session = s,
    bundle = b,
    op_name = "slingshot_fit",
    inputs = list(
      cell_set = "all",
      cell_ids = cells,
      fit_space = wb_prim_space(fit_space_id),
      clusters = wb_ref_run(r1$run$run_id, "clusters")
    ),
    notes = "test trajectory_vector_smooth: slingshot fit"
  )
  s <- r2$session
  r3 <- wb_session_run_op(
    session = s,
    bundle = b,
    op_name = "addmodulescore",
    inputs = list(
      cell_set = "all",
      cell_ids = cells,
      matrix = wb_prim_matrix(matrix_id),
      features = list(sig_a = feats[1:3], sig_b = feats[4:6]),
      nbin = 12L,
      ctrl = 10L,
      seed = 1L
    ),
    notes = "test trajectory_vector_smooth: module scores"
  )

  pt <- r2$run$outputs$pseudotime
  lineage <- as.character(unique(pt$key))[1]
  stopifnot(nzchar(lineage))

  r4 <- wb_session_run_op(
    session = r3$session,
    bundle = b,
    op_name = "trajectory_vector_smooth",
    inputs = list(
      cell_set = "all",
      cell_ids = cells,
      signal = wb_ref_run(r3$run$run_id, "module_scores"),
      model = wb_ref_run(r2$run$run_id, "model"),
      lineage = lineage,
      signal_keys = c("sig_a", "sig_b"),
      n_bins = 20L,
      summary_fun = "mean",
      min_cells_per_bin = 5L
    ),
    notes = "test trajectory_vector_smooth: run"
  )

  sig <- r4$run$outputs$signal_table
  sm <- r4$run$outputs$fit_summary
  stopifnot(inherits(sig, "wb_primitive"), identical(as.character(sig$kind), "obs_table"))
  stopifnot(inherits(sm, "wb_primitive"), identical(as.character(sm$kind), "obs_table"))
  stopifnot(identical(as.character(sig$table_type), "trajectory_vector_smooth"))

  sig_tbl <- sig$table
  sm_tbl <- sm$table
  stopifnot(is.data.frame(sig_tbl), nrow(sig_tbl) > 0L)
  stopifnot(all(c("signal_key", "lineage_id", "bin", "pseudotime", "value", "n_cells") %in% colnames(sig_tbl)))
  stopifnot(all(as.character(sig_tbl$lineage_id) == lineage))
  stopifnot(setequal(unique(as.character(sig_tbl$signal_key)), c("sig_a", "sig_b")))
  stopifnot(is.data.frame(sm_tbl), nrow(sm_tbl) >= 1L)
  stopifnot(all(c("lineage_id", "n_cells_used", "n_signal_keys_with_rows", "n_bins") %in% colnames(sm_tbl)))

  TRUE
}

test_op_trajectory_signal_dynamics_contract <- function(bundle_dir) {
  if (!requireNamespace("slingshot", quietly = TRUE)) {
    message("Skipping trajectory_signal_dynamics contract test: slingshot not installed.")
    return(TRUE)
  }

  b <- wb_open_bundle(bundle_dir)
  on.exit(wb_close_bundle(b), add = TRUE)

  iface <- wb_op_interface("trajectory_signal_dynamics", bundle = b)
  stopifnot(is.list(iface))
  stopifnot(identical(as.character(iface$produces$signal_table$kind), "obs_table"))
  stopifnot(identical(as.character(iface$produces$dynamics_table$kind), "obs_table"))
  stopifnot(identical(as.character(iface$produces$top_signals$kind), "obs_table"))
  stopifnot(identical(as.character(iface$produces$fit_summary$kind), "obs_table"))
  stopifnot("trajectory_signal_dynamics" %in% wb_list_ops())

  mats <- wb_matrices(b)
  stopifnot(is.data.frame(mats), nrow(mats) >= 1L)
  matrix_id <- as.character(mats$matrix_id[1])
  feats <- as.character(head(wb_feature_ids(b, matrix_id = matrix_id), 12))
  stopifnot(length(feats) >= 6L)

  cells <- tryCatch(wb_cells(b, cell_set = "core"), error = function(e) character(0))
  if (length(cells) < 300L) cells <- wb_cells(b, cell_set = "all")
  stopifnot(length(cells) >= 300L)
  cells <- as.character(head(cells, 600))

  sp_tbl <- wb_spaces(b)
  fit_space_id <- NA_character_
  for (sid in as.character(sp_tbl$space_id)) {
    sp <- tryCatch(wb_space(b, space_id = sid, cells = head(cells, 40)), error = function(e) NULL)
    if (is.null(sp)) next
    if (is.matrix(sp) && ncol(sp) >= 2L) {
      fit_space_id <- sid
      break
    }
    if (is.data.frame(sp) && all(c("x", "y") %in% colnames(sp))) {
      fit_space_id <- sid
      break
    }
  }
  stopifnot(nzchar(fit_space_id))

  s <- wb_session_new()
  r1 <- wb_session_run_op(
    session = s,
    bundle = b,
    op_name = "leiden",
    inputs = list(
      cell_set = "all",
      cell_ids = cells,
      space = wb_prim_space(fit_space_id),
      k = 20,
      resolution = 0.3
    ),
    notes = "test trajectory_signal_dynamics: leiden"
  )
  r2 <- wb_session_run_op(
    session = r1$session,
    bundle = b,
    op_name = "slingshot_fit",
    inputs = list(
      cell_set = "all",
      cell_ids = cells,
      fit_space = wb_prim_space(fit_space_id),
      clusters = wb_ref_run(r1$run$run_id, "clusters")
    ),
    notes = "test trajectory_signal_dynamics: slingshot fit"
  )
  r3 <- wb_session_run_op(
    session = r2$session,
    bundle = b,
    op_name = "addmodulescore",
    inputs = list(
      cell_set = "all",
      cell_ids = cells,
      matrix = wb_prim_matrix(matrix_id),
      features = list(sig_a = feats[1:3], sig_b = feats[4:6]),
      nbin = 12L,
      ctrl = 10L,
      seed = 1L
    ),
    notes = "test trajectory_signal_dynamics: module scores"
  )

  pt <- r2$run$outputs$pseudotime
  lineage <- as.character(unique(pt$key))[1]
  stopifnot(nzchar(lineage))

  r4 <- wb_session_run_op(
    session = r3$session,
    bundle = b,
    op_name = "trajectory_signal_dynamics",
    inputs = list(
      cell_set = "all",
      cell_ids = cells,
      signal = wb_ref_run(r3$run$run_id, "module_scores"),
      model = wb_ref_run(r2$run$run_id, "model"),
      lineage = lineage,
      signal_keys = c("sig_a", "sig_b"),
      n_bins = 20L,
      summary_fun = "mean",
      min_cells_per_bin = 5L,
      top_n = 2L,
      smooth_method = "loess",
      bootstrap_n = 3L
    ),
    notes = "test trajectory_signal_dynamics: run"
  )

  sig <- r4$run$outputs$signal_table
  dyn <- r4$run$outputs$dynamics_table
  top <- r4$run$outputs$top_signals
  sm <- r4$run$outputs$fit_summary
  stopifnot(inherits(sig, "wb_primitive"), identical(as.character(sig$kind), "obs_table"))
  stopifnot(inherits(dyn, "wb_primitive"), identical(as.character(dyn$kind), "obs_table"))
  stopifnot(inherits(top, "wb_primitive"), identical(as.character(top$kind), "obs_table"))
  stopifnot(inherits(sm, "wb_primitive"), identical(as.character(sm$kind), "obs_table"))
  stopifnot(identical(as.character(sig$table_type), "trajectory_signal_dynamics_curve"))
  stopifnot(identical(as.character(dyn$table_type), "trajectory_signal_dynamics"))
  stopifnot(identical(as.character(top$table_type), "trajectory_signal_dynamics_top"))

  sig_tbl <- sig$table
  dyn_tbl <- dyn$table
  top_tbl <- top$table
  sm_tbl <- sm$table
  stopifnot(is.data.frame(sig_tbl), nrow(sig_tbl) > 0L)
  stopifnot(all(c("signal_key", "feature_set", "lineage_id", "bin", "pseudotime", "value", "value_raw", "value_smooth", "value_ci_low", "value_ci_high", "n_cells") %in% colnames(sig_tbl)))
  stopifnot(is.data.frame(dyn_tbl), nrow(dyn_tbl) == 2L)
  stopifnot(all(c("signal_key", "curve_class", "passes_filters", "dynamic_score", "amplitude", "late_minus_early", "spearman_rho", "rank") %in% colnames(dyn_tbl)))
  stopifnot(is.data.frame(top_tbl), nrow(top_tbl) <= 2L)
  stopifnot(setequal(unique(as.character(dyn_tbl$signal_key)), c("sig_a", "sig_b")))
  stopifnot(is.data.frame(sm_tbl), nrow(sm_tbl) >= 1L)
  stopifnot(all(c("lineage_id", "n_signal_keys_input", "n_signal_keys_with_rows", "n_bins") %in% colnames(sm_tbl)))

  ds <- wb_wrangle_plot_dataset(
    plot_type = "pseudotime_signature_line",
    inputs = list(table = sig),
    bundle = b
  )
  stopifnot(is.data.frame(ds$table), nrow(ds$table) > 0L)
  stopifnot(identical(as.character(ds$dataset_type), "trajectory_signal_dynamics_curve"))
  wb_plot_validate_dataset("pseudotime_signature_line", ds)

  TRUE
}

test_op_trajectory_signal_dynamics_promoted_contract <- function(bundle_dir) {
  if (!requireNamespace("slingshot", quietly = TRUE)) {
    message("Skipping trajectory_signal_dynamics promoted contract test: slingshot not installed.")
    return(TRUE)
  }

  b <- wb_open_bundle(bundle_dir)
  cleanup_artifacts <- character(0)
  on.exit({
    for (artifact_id in cleanup_artifacts) {
      try(wb_art_delete(b, artifact_id = artifact_id, recursive = TRUE, force = TRUE), silent = TRUE)
    }
    try(wb_close_bundle(b), silent = TRUE)
  }, add = TRUE)

  mats <- wb_matrices(b)
  stopifnot(is.data.frame(mats), nrow(mats) >= 1L)
  matrix_id <- as.character(mats$matrix_id[1])
  feats <- as.character(head(wb_feature_ids(b, matrix_id = matrix_id), 12))
  stopifnot(length(feats) >= 6L)

  cells <- tryCatch(wb_cells(b, cell_set = "core"), error = function(e) character(0))
  if (length(cells) < 300L) cells <- wb_cells(b, cell_set = "all")
  stopifnot(length(cells) >= 300L)
  cells <- as.character(head(cells, 600))

  sp_tbl <- wb_spaces(b)
  fit_space_id <- NA_character_
  for (sid in as.character(sp_tbl$space_id)) {
    sp <- tryCatch(wb_space(b, space_id = sid, cells = head(cells, 40)), error = function(e) NULL)
    if (is.null(sp)) next
    if (is.matrix(sp) && ncol(sp) >= 2L) {
      fit_space_id <- sid
      break
    }
    if (is.data.frame(sp) && all(c("x", "y") %in% colnames(sp))) {
      fit_space_id <- sid
      break
    }
  }
  stopifnot(nzchar(fit_space_id))

  prom_name <- paste0(".__test_trajectory_signal_promoted__.", as.integer(Sys.time()))
  s <- wb_session_new()
  r1 <- wb_session_run_op(
    session = s,
    bundle = b,
    op_name = "leiden",
    inputs = list(
      cell_set = "all",
      cell_ids = cells,
      space = wb_prim_space(fit_space_id),
      k = 20,
      resolution = 0.3
    ),
    notes = "test promoted trajectory_signal_dynamics: leiden"
  )
  r2 <- wb_session_run_op(
    session = r1$session,
    bundle = b,
    op_name = "slingshot_fit",
    inputs = list(
      cell_set = "all",
      cell_ids = cells,
      fit_space = wb_prim_space(fit_space_id),
      clusters = wb_ref_run(r1$run$run_id, "clusters")
    ),
    notes = "test promoted trajectory_signal_dynamics: slingshot fit"
  )
  r3 <- wb_session_run_op(
    session = r2$session,
    bundle = b,
    op_name = "addmodulescore",
    inputs = list(
      cell_set = "all",
      cell_ids = cells,
      matrix = wb_prim_matrix(matrix_id),
      features = list(sig_a = feats[1:3], sig_b = feats[4:6]),
      nbin = 12L,
      ctrl = 10L,
      seed = 1L
    ),
    notes = "test promoted trajectory_signal_dynamics: module scores"
  )
  pt <- r2$run$outputs$pseudotime
  lineage <- as.character(unique(pt$key))[1]
  stopifnot(nzchar(lineage))

  r4 <- wb_session_run_op(
    session = r3$session,
    bundle = b,
    op_name = "trajectory_signal_dynamics",
    inputs = list(
      cell_set = "all",
      cell_ids = cells,
      signal = wb_ref_run(r3$run$run_id, "module_scores"),
      model = wb_ref_run(r2$run$run_id, "model"),
      lineage = lineage,
      signal_keys = c("sig_a", "sig_b"),
      n_bins = 20L,
      min_cells_per_bin = 5L,
      top_n = 2L,
      smooth_method = "loess",
      min_bins_observed = 5L
    ),
    notes = "test promoted trajectory_signal_dynamics: run"
  )

  prom <- wb_promote_analysis(
    bundle = b,
    runs = r4$session$runs,
    head_run_id = r4$run$run_id,
    name_prefix = prom_name,
    created_by = "test",
    fail_fast = TRUE
  )
  stopifnot(is.data.frame(prom$promoted), nrow(prom$promoted) >= 4L)
  if ("artifact_id" %in% colnames(prom$promoted)) {
    cleanup_artifacts <- unique(stats::na.omit(as.character(prom$promoted$artifact_id)))
  }

  arts <- wb_art_list(b)
  tt <- DBI::dbGetQuery(
    b$con,
    "SELECT artifact_id, table_type FROM artifact_tables WHERE artifact_id IN (SELECT artifact_id FROM artifacts WHERE type = 'obs_table');"
  )
  arts <- merge(arts, tt, by = "artifact_id", all.x = TRUE, sort = FALSE)
  arts <- arts[as.character(arts$artifact_id) %in% cleanup_artifacts | as.character(arts$name) == prom_name, , drop = FALSE]
  curve_id <- as.character(arts$artifact_id[as.character(arts$table_type) == "trajectory_signal_dynamics_curve"][1])
  dyn_id <- as.character(arts$artifact_id[as.character(arts$table_type) == "trajectory_signal_dynamics"][1])
  top_id <- as.character(arts$artifact_id[as.character(arts$table_type) == "trajectory_signal_dynamics_top"][1])
  stopifnot(nzchar(curve_id), nzchar(dyn_id), nzchar(top_id))

  ds_curve <- wb_wrangle_plot_dataset(
    plot_type = "pseudotime_signature_line",
    inputs = list(table = paste0("artifact:", curve_id), top_n = 2L),
    bundle = b
  )
  stopifnot(is.data.frame(ds_curve$table), nrow(ds_curve$table) > 0L)
  stopifnot(identical(as.character(ds_curve$dataset_type), "trajectory_signal_dynamics_curve"))
  stopifnot("signal_key" %in% colnames(ds_curve$table))
  wb_plot_validate_dataset("pseudotime_signature_line", ds_curve)

  ds_dyn <- wb_wrangle_plot_dataset(
    plot_type = "ranked_lollipop",
    inputs = list(table = paste0("artifact:", dyn_id), score_col = "dynamic_score"),
    bundle = b
  )
  stopifnot(is.data.frame(ds_dyn$table), nrow(ds_dyn$table) > 0L)
  wb_plot_validate_dataset("ranked_lollipop", ds_dyn)

  nav_signals <- wb_nav_entities(dyn_id, b, entity_kind = "feature_set", lineage_id = lineage, limit = 3L)
  stopifnot(is.data.frame(nav_signals), nrow(nav_signals) >= 1L)
  nav_targets <- wb_nav_targets(dyn_id, b, entity = nav_signals[1, , drop = FALSE], lineage_id = lineage)
  stopifnot(any(as.character(nav_targets$action) == "open_signal_curve"))
  nav_curve <- wb_nav_handoff(dyn_id, "open_signal_curve", b, entity = nav_signals[1, , drop = FALSE], lineage_id = lineage)
  stopifnot(identical(as.character(nav_curve$plot_type), "pseudotime_signature_line"))
  stopifnot(identical(as.character(nav_curve$params$signal_key), as.character(nav_signals$entity_id[1])))

  nav_top <- wb_nav_entities(top_id, b, entity_kind = "feature_set", lineage_id = lineage, limit = 3L)
  stopifnot(is.data.frame(nav_top), nrow(nav_top) >= 1L)

  TRUE
}

test_op_trajectory_geneset_dynamics_contract <- function(bundle_dir) {
  if (!requireNamespace("slingshot", quietly = TRUE)) {
    message("Skipping trajectory_geneset_dynamics contract test: slingshot not installed.")
    return(TRUE)
  }

  b <- wb_open_bundle(bundle_dir)
  cleanup_feature_sets <- character(0)
  cleanup_matrix_id <- NULL
  cleanup_artifacts <- character(0)
  on.exit({
    for (artifact_id in cleanup_artifacts) {
      try(wb_art_delete(b, artifact_id = artifact_id, recursive = TRUE, force = TRUE), silent = TRUE)
    }
    for (fs_name in cleanup_feature_sets) {
      try(wb_feature_set_delete(b, feature_set = fs_name, matrix_id = cleanup_matrix_id), silent = TRUE)
    }
    try(wb_close_bundle(b), silent = TRUE)
  }, add = TRUE)

  iface <- wb_op_interface("trajectory_geneset_dynamics", bundle = b)
  stopifnot(is.list(iface))
  stopifnot(identical(as.character(iface$produces$signature_table$kind), "obs_table"))
  stopifnot(identical(as.character(iface$produces$dynamics_table$kind), "obs_table"))
  stopifnot(identical(as.character(iface$produces$top_sets$kind), "obs_table"))
  stopifnot(identical(as.character(iface$produces$driver_table$kind), "obs_table"))
  stopifnot(identical(as.character(iface$produces$driver_curve_table$kind), "obs_table"))
  stopifnot(identical(as.character(iface$produces$fit_summary$kind), "obs_table"))
  stopifnot("trajectory_geneset_dynamics" %in% wb_list_ops())

  mats <- wb_matrices(b)
  stopifnot(is.data.frame(mats), nrow(mats) >= 1L)
  matrix_id <- as.character(mats$matrix_id[1])
  feats <- as.character(head(wb_feature_ids(b, matrix_id = matrix_id), 40))
  stopifnot(length(feats) >= 24L)

  ns <- paste0(".__test_trajectory_geneset_dynamics_ns__.", as.integer(Sys.time()))
  fs_a <- paste0(ns, ".a")
  fs_b <- paste0(ns, ".b")
  fs_c <- paste0(ns, ".c")
  cleanup_feature_sets <- c(fs_a, fs_b, fs_c)
  cleanup_matrix_id <- matrix_id
  wb_feature_set_replace(
    bundle = b,
    feature_set = fs_a,
    matrix_id = matrix_id,
    feature_ids = feats[1:8],
    created_by = "test",
    namespace = ns,
    origin = "test",
    strict = TRUE
  )
  wb_feature_set_replace(
    bundle = b,
    feature_set = fs_b,
    matrix_id = matrix_id,
    feature_ids = feats[9:16],
    created_by = "test",
    namespace = ns,
    origin = "test",
    strict = TRUE
  )
  wb_feature_set_replace(
    bundle = b,
    feature_set = fs_c,
    matrix_id = matrix_id,
    feature_ids = feats[17:24],
    created_by = "test",
    namespace = ns,
    origin = "test",
    strict = TRUE
  )

  cells <- tryCatch(wb_cells(b, cell_set = "core"), error = function(e) character(0))
  if (length(cells) < 300L) cells <- wb_cells(b, cell_set = "all")
  stopifnot(length(cells) >= 300L)
  cells <- as.character(head(cells, 600))

  sp_tbl <- wb_spaces(b)
  fit_space_id <- NA_character_
  for (sid in as.character(sp_tbl$space_id)) {
    sp <- tryCatch(wb_space(b, space_id = sid, cells = head(cells, 40)), error = function(e) NULL)
    if (is.null(sp)) next
    if (is.matrix(sp) && ncol(sp) >= 2L) {
      fit_space_id <- sid
      break
    }
    if (is.data.frame(sp) && all(c("x", "y") %in% colnames(sp))) {
      fit_space_id <- sid
      break
    }
  }
  stopifnot(nzchar(fit_space_id))

  s <- wb_session_new()
  r1 <- wb_session_run_op(
    session = s,
    bundle = b,
    op_name = "leiden",
    inputs = list(
      cell_set = "all",
      cell_ids = cells,
      space = wb_prim_space(fit_space_id),
      k = 20,
      resolution = 0.3
    ),
    notes = "test trajectory_geneset_dynamics: leiden"
  )
  r2 <- wb_session_run_op(
    session = r1$session,
    bundle = b,
    op_name = "slingshot_fit",
    inputs = list(
      cell_set = "all",
      cell_ids = cells,
      fit_space = wb_prim_space(fit_space_id),
      clusters = wb_ref_run(r1$run$run_id, "clusters")
    ),
    notes = "test trajectory_geneset_dynamics: slingshot fit"
  )

  pt <- r2$run$outputs$pseudotime
  lineage <- as.character(unique(pt$key))[1]
  stopifnot(nzchar(lineage))

  r3 <- wb_session_run_op(
    session = r2$session,
    bundle = b,
    op_name = "trajectory_geneset_dynamics",
    inputs = list(
      cell_set = "all",
      cell_ids = cells,
      matrix = wb_prim_matrix(matrix_id),
      model = wb_ref_run(r2$run$run_id, "model"),
      namespace = ns,
      lineage = lineage,
      n_bins = 20L,
      min_cells_per_bin = 5L,
      min_set_size = 3L,
      top_n = 2L,
      top_driver_genes = 3L,
      smooth_method = "loess",
      bootstrap_n = 5L,
      min_bins_observed = 5L
    ),
    notes = "test trajectory_geneset_dynamics: run"
  )

  curve <- r3$run$outputs$signature_table
  dyn <- r3$run$outputs$dynamics_table
  top <- r3$run$outputs$top_sets
  drivers <- r3$run$outputs$driver_table
  driver_curve <- r3$run$outputs$driver_curve_table
  sm <- r3$run$outputs$fit_summary
  stopifnot(inherits(curve, "wb_primitive"), identical(as.character(curve$kind), "obs_table"))
  stopifnot(inherits(dyn, "wb_primitive"), identical(as.character(dyn$kind), "obs_table"))
  stopifnot(inherits(top, "wb_primitive"), identical(as.character(top$kind), "obs_table"))
  stopifnot(inherits(drivers, "wb_primitive"), identical(as.character(drivers$kind), "obs_table"))
  stopifnot(inherits(driver_curve, "wb_primitive"), identical(as.character(driver_curve$kind), "obs_table"))
  stopifnot(inherits(sm, "wb_primitive"), identical(as.character(sm$kind), "obs_table"))
  stopifnot(identical(as.character(curve$table_type), "trajectory_geneset_dynamics_curve"))
  stopifnot(identical(as.character(dyn$table_type), "trajectory_geneset_dynamics"))
  stopifnot(identical(as.character(top$table_type), "trajectory_geneset_dynamics_top"))
  stopifnot(identical(as.character(drivers$table_type), "trajectory_geneset_dynamics_drivers"))
  stopifnot(identical(as.character(driver_curve$table_type), "trajectory_geneset_dynamics_driver_curve"))

  curve_tbl <- curve$table
  dyn_tbl <- dyn$table
  top_tbl <- top$table
  driver_tbl <- drivers$table
  driver_curve_tbl <- driver_curve$table
  sm_tbl <- sm$table
  stopifnot(is.data.frame(curve_tbl), nrow(curve_tbl) > 0L)
  stopifnot(is.data.frame(dyn_tbl), nrow(dyn_tbl) >= 3L)
  stopifnot(is.data.frame(top_tbl), nrow(top_tbl) <= 2L)
  stopifnot(all(c("feature_set", "namespace", "lineage_id", "bin", "pseudotime", "value", "value_raw", "value_smooth", "value_ci_low", "value_ci_high", "n_cells") %in% colnames(curve_tbl)))
  stopifnot(all(c("feature_set", "curve_class", "passes_filters", "filter_reason", "dynamic_score", "amplitude", "late_minus_early", "spearman_rho", "rank") %in% colnames(dyn_tbl)))
  stopifnot(is.data.frame(driver_tbl), nrow(driver_tbl) > 0L)
  stopifnot(all(c("feature_set", "feature_id", "dynamic_score", "driver_rank") %in% colnames(driver_tbl)))
  stopifnot(is.data.frame(driver_curve_tbl), nrow(driver_curve_tbl) > 0L)
  stopifnot(all(c("feature_set", "feature_id", "driver_rank", "bin", "value", "value_raw", "value_smooth") %in% colnames(driver_curve_tbl)))
  stopifnot(all(as.character(curve_tbl$namespace) == ns))
  stopifnot(all(as.character(dyn_tbl$namespace) == ns))
  stopifnot(all(as.character(dyn_tbl$lineage_id) == lineage))
  stopifnot(all(c(fs_a, fs_b, fs_c) %in% as.character(dyn_tbl$feature_set)))
  stopifnot(is.data.frame(sm_tbl), nrow(sm_tbl) >= 1L)
  stopifnot(all(c("lineage_id", "n_feature_sets_screened", "n_feature_sets_with_rows", "n_bins") %in% colnames(sm_tbl)))

  TRUE
}

test_op_trajectory_geneset_dynamics_promoted_contract <- function(bundle_dir) {
  if (!requireNamespace("slingshot", quietly = TRUE)) {
    message("Skipping trajectory_geneset_dynamics promoted contract test: slingshot not installed.")
    return(TRUE)
  }

  b <- wb_open_bundle(bundle_dir)
  cleanup_feature_sets <- character(0)
  cleanup_matrix_id <- NULL
  cleanup_artifacts <- character(0)
  on.exit({
    for (artifact_id in cleanup_artifacts) {
      try(wb_art_delete(b, artifact_id = artifact_id, recursive = TRUE, force = TRUE), silent = TRUE)
    }
    for (fs_name in cleanup_feature_sets) {
      try(wb_feature_set_delete(b, feature_set = fs_name, matrix_id = cleanup_matrix_id), silent = TRUE)
    }
    try(wb_close_bundle(b), silent = TRUE)
  }, add = TRUE)

  mats <- wb_matrices(b)
  stopifnot(is.data.frame(mats), nrow(mats) >= 1L)
  matrix_id <- as.character(mats$matrix_id[1])
  feats <- as.character(head(wb_feature_ids(b, matrix_id = matrix_id), 40))
  stopifnot(length(feats) >= 24L)

  ns <- paste0(".__test_trajectory_geneset_promoted_ns__.", as.integer(Sys.time()))
  prom_name <- paste0(".__test_trajectory_geneset_promoted__.", as.integer(Sys.time()))
  fs_a <- paste0(ns, ".a")
  fs_b <- paste0(ns, ".b")
  fs_c <- paste0(ns, ".c")
  cleanup_feature_sets <- c(fs_a, fs_b, fs_c)
  cleanup_matrix_id <- matrix_id
  wb_feature_set_replace(
    bundle = b,
    feature_set = fs_a,
    matrix_id = matrix_id,
    feature_ids = feats[1:8],
    created_by = "test",
    namespace = ns,
    origin = "test",
    strict = TRUE
  )
  wb_feature_set_replace(
    bundle = b,
    feature_set = fs_b,
    matrix_id = matrix_id,
    feature_ids = feats[9:16],
    created_by = "test",
    namespace = ns,
    origin = "test",
    strict = TRUE
  )
  wb_feature_set_replace(
    bundle = b,
    feature_set = fs_c,
    matrix_id = matrix_id,
    feature_ids = feats[17:24],
    created_by = "test",
    namespace = ns,
    origin = "test",
    strict = TRUE
  )

  cells <- tryCatch(wb_cells(b, cell_set = "core"), error = function(e) character(0))
  if (length(cells) < 300L) cells <- wb_cells(b, cell_set = "all")
  stopifnot(length(cells) >= 300L)
  cells <- as.character(head(cells, 600))

  sp_tbl <- wb_spaces(b)
  fit_space_id <- NA_character_
  for (sid in as.character(sp_tbl$space_id)) {
    sp <- tryCatch(wb_space(b, space_id = sid, cells = head(cells, 40)), error = function(e) NULL)
    if (is.null(sp)) next
    if (is.matrix(sp) && ncol(sp) >= 2L) {
      fit_space_id <- sid
      break
    }
    if (is.data.frame(sp) && all(c("x", "y") %in% colnames(sp))) {
      fit_space_id <- sid
      break
    }
  }
  stopifnot(nzchar(fit_space_id))

  s <- wb_session_new()
  r1 <- wb_session_run_op(
    session = s,
    bundle = b,
    op_name = "leiden",
    inputs = list(
      cell_set = "all",
      cell_ids = cells,
      space = wb_prim_space(fit_space_id),
      k = 20,
      resolution = 0.3
    ),
    notes = "test promoted trajectory_geneset_dynamics: leiden"
  )
  r2 <- wb_session_run_op(
    session = r1$session,
    bundle = b,
    op_name = "slingshot_fit",
    inputs = list(
      cell_set = "all",
      cell_ids = cells,
      fit_space = wb_prim_space(fit_space_id),
      clusters = wb_ref_run(r1$run$run_id, "clusters")
    ),
    notes = "test promoted trajectory_geneset_dynamics: slingshot fit"
  )
  pt <- r2$run$outputs$pseudotime
  lineage <- as.character(unique(pt$key))[1]
  stopifnot(nzchar(lineage))

  r3 <- wb_session_run_op(
    session = r2$session,
    bundle = b,
    op_name = "trajectory_geneset_dynamics",
    inputs = list(
      cell_set = "all",
      cell_ids = cells,
      matrix = wb_prim_matrix(matrix_id),
      model = wb_ref_run(r2$run$run_id, "model"),
      namespace = ns,
      lineage = lineage,
      n_bins = 20L,
      min_cells_per_bin = 5L,
      min_set_size = 3L,
      top_n = 2L,
      top_driver_genes = 2L,
      smooth_method = "loess",
      min_bins_observed = 5L
    ),
    notes = "test promoted trajectory_geneset_dynamics: run"
  )

  prom <- wb_promote_analysis(
    bundle = b,
    runs = r3$session$runs,
    head_run_id = r3$run$run_id,
    name_prefix = prom_name,
    created_by = "test",
    fail_fast = TRUE
  )
  stopifnot(is.data.frame(prom$promoted), nrow(prom$promoted) >= 5L)
  if ("artifact_id" %in% colnames(prom$promoted)) {
    cleanup_artifacts <- unique(stats::na.omit(as.character(prom$promoted$artifact_id)))
  }

  arts <- wb_art_list(b)
  tt <- DBI::dbGetQuery(
    b$con,
    "SELECT artifact_id, table_type FROM artifact_tables WHERE artifact_id IN (SELECT artifact_id FROM artifacts WHERE type = 'obs_table');"
  )
  arts <- merge(arts, tt, by = "artifact_id", all.x = TRUE, sort = FALSE)
  arts <- arts[as.character(arts$artifact_id) %in% cleanup_artifacts | as.character(arts$name) == prom_name, , drop = FALSE]
  curve_id <- as.character(arts$artifact_id[as.character(arts$table_type) == "trajectory_geneset_dynamics_curve"][1])
  dyn_id <- as.character(arts$artifact_id[as.character(arts$table_type) == "trajectory_geneset_dynamics"][1])
  drivers_id <- as.character(arts$artifact_id[as.character(arts$table_type) == "trajectory_geneset_dynamics_drivers"][1])
  driver_curve_id <- as.character(arts$artifact_id[as.character(arts$table_type) == "trajectory_geneset_dynamics_driver_curve"][1])
  stopifnot(nzchar(curve_id), nzchar(dyn_id), nzchar(drivers_id), nzchar(driver_curve_id))

  ds_curve <- wb_wrangle_plot_dataset(
    plot_type = "pseudotime_signature_line",
    inputs = list(table = paste0("artifact:", curve_id), top_n = 2L),
    bundle = b
  )
  stopifnot(is.data.frame(ds_curve$table), nrow(ds_curve$table) > 0L)
  stopifnot(identical(as.character(ds_curve$dataset_type), "trajectory_geneset_dynamics_curve"))
  wb_plot_validate_dataset("pseudotime_signature_line", ds_curve)

  ds_driver_curve <- wb_wrangle_plot_dataset(
    plot_type = "pseudotime_signature_line",
    inputs = list(table = paste0("artifact:", driver_curve_id), top_n = 2L),
    bundle = b
  )
  stopifnot(is.data.frame(ds_driver_curve$table), nrow(ds_driver_curve$table) > 0L)
  stopifnot(identical(as.character(ds_driver_curve$dataset_type), "trajectory_geneset_dynamics_driver_curve"))
  stopifnot("feature_id" %in% colnames(ds_driver_curve$table))
  wb_plot_validate_dataset("pseudotime_signature_line", ds_driver_curve)

  ds_drivers <- wb_wrangle_plot_dataset(
    plot_type = "ranked_lollipop",
    inputs = list(table = paste0("artifact:", drivers_id), score_col = "dynamic_score"),
    bundle = b
  )
  stopifnot(is.data.frame(ds_drivers$table), nrow(ds_drivers$table) > 0L)
  wb_plot_validate_dataset("ranked_lollipop", ds_drivers)

  nav_sets <- wb_nav_entities(dyn_id, b, entity_kind = "feature_set", lineage_id = lineage, limit = 3L)
  stopifnot(is.data.frame(nav_sets), nrow(nav_sets) >= 1L)
  nav_targets <- wb_nav_targets(dyn_id, b, entity = nav_sets[1, , drop = FALSE], lineage_id = lineage)
  stopifnot(any(as.character(nav_targets$action) == "open_geneset_curve"))
  stopifnot(any(as.character(nav_targets$action) == "open_driver_table"))
  nav_curve <- wb_nav_handoff(dyn_id, "open_geneset_curve", b, entity = nav_sets[1, , drop = FALSE], lineage_id = lineage)
  stopifnot(identical(as.character(nav_curve$plot_type), "pseudotime_signature_line"))

  nav_drivers <- wb_nav_entities(drivers_id, b, entity_kind = "feature", lineage_id = lineage, feature_set = as.character(nav_sets$entity_id[1]), limit = 3L)
  stopifnot(is.data.frame(nav_drivers), nrow(nav_drivers) >= 1L)
  nav_driver_targets <- wb_nav_targets(drivers_id, b, entity = nav_drivers[1, , drop = FALSE], lineage_id = lineage)
  stopifnot(any(as.character(nav_driver_targets$action) == "open_driver_curve"))
  nav_driver_curve <- wb_nav_handoff(drivers_id, "open_driver_curve", b, entity = nav_drivers[1, , drop = FALSE], lineage_id = lineage)
  stopifnot(identical(as.character(nav_driver_curve$plot_type), "pseudotime_signature_line"))

  TRUE
}
