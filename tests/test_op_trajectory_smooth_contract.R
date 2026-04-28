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
