test_navigation_contract <- function(bundle_dir) {
  b <- wb_open_bundle(bundle_dir)
  on.exit(wb_close_bundle(b), add = TRUE)

  arts <- wb_art_list(b)
  if (!is.data.frame(arts) || !nrow(arts)) return(TRUE)

  tinfo <- try(DBI::dbGetQuery(
    b$con,
    "SELECT artifact_id, table_type
     FROM artifact_tables
     WHERE artifact_id IN (SELECT artifact_id FROM artifacts WHERE type IN ('obs_table', 'feature_table'));"
  ), silent = TRUE)
  if (inherits(tinfo, "try-error") || !is.data.frame(tinfo) || !nrow(tinfo)) return(TRUE)

  arts2 <- merge(arts, tinfo, by = "artifact_id", all.x = TRUE, sort = FALSE)
  de <- arts2[
    as.character(arts2$source_op %||% "") == "trajectory_de" &
      as.character(arts2$type %||% "") == "feature_table" &
      as.character(arts2$table_type %||% "") == "trajectory_de",
    ,
    drop = FALSE
  ]
  sm <- arts2[
    as.character(arts2$source_op %||% "") == "trajectory_smooth" &
      as.character(arts2$type %||% "") == "obs_table" &
      as.character(arts2$table_type %||% "") == "trajectory_smooth",
    ,
    drop = FALSE
  ]
  sig <- arts2[
    as.character(arts2$source_op %||% "") == "trajectory_signature_smooth" &
      as.character(arts2$type %||% "") == "obs_table" &
      as.character(arts2$table_type %||% "") == "trajectory_signature_smooth",
    ,
    drop = FALSE
  ]
  if (!nrow(de) || !nrow(sm)) return(TRUE)

  de_id <- as.character(de$artifact_id[1])
  sm_id <- as.character(sm$artifact_id[1])
  sig_id <- if (nrow(sig)) as.character(sig$artifact_id[1]) else NA_character_

  e_lin <- wb_nav_entities(source = de_id, bundle = b, entity_kind = "lineage")
  stopifnot(is.data.frame(e_lin), nrow(e_lin) >= 1L)
  stopifnot(all(e_lin$entity_kind == "lineage"))
  lin <- as.character(e_lin$entity_id[1])

  e_feat <- wb_nav_entities(source = de_id, bundle = b, entity_kind = "feature", lineage_id = lin, limit = 10L)
  stopifnot(is.data.frame(e_feat), nrow(e_feat) >= 1L)
  stopifnot(all(e_feat$entity_kind == "feature"))
  feat <- e_feat[1, , drop = FALSE]

  tg <- wb_nav_targets(source = de_id, bundle = b, entity = feat, lineage_id = lin)
  stopifnot(is.data.frame(tg), nrow(tg) >= 1L)
  stopifnot(any(as.character(tg$action) == "open_smooth_plot"))

  ho <- wb_nav_handoff(source = de_id, target = "open_smooth_plot", bundle = b, entity = feat, lineage_id = lin)
  stopifnot(is.list(ho), identical(as.character(ho$plot_type), "pseudotime_smooth_panel"))
  stopifnot(identical(as.character(ho$params$feature), as.character(feat$entity_id)))
  stopifnot(identical(as.character(ho$params$lineage), lin))

  ho_cmp_de <- wb_nav_handoff(source = de_id, target = "compare_other_lineage", bundle = b, entity = feat, lineage_id = lin)
  stopifnot(is.list(ho_cmp_de), identical(as.character(ho_cmp_de$plot_type), "ranked_lollipop"))
  stopifnot(identical(as.character(ho_cmp_de$params$feature), as.character(feat$entity_id)))

  s_lin <- wb_nav_entities(source = sm_id, bundle = b, entity_kind = "lineage")
  stopifnot(is.data.frame(s_lin), nrow(s_lin) >= 1L)
  s_lin_id <- as.character(s_lin$entity_id[1])
  s_feat <- wb_nav_entities(source = sm_id, bundle = b, entity_kind = "feature", lineage_id = s_lin_id, limit = 10L)
  stopifnot(is.data.frame(s_feat), nrow(s_feat) >= 1L)

  tg2 <- wb_nav_targets(source = sm_id, bundle = b, entity = s_feat[1, , drop = FALSE], lineage_id = s_lin_id)
  stopifnot(is.data.frame(tg2), nrow(tg2) >= 1L)
  stopifnot(any(as.character(tg2$action) == "open_de_plot"))

  ho_cmp_sm <- wb_nav_handoff(source = sm_id, target = "compare_other_lineage", bundle = b, entity = s_feat[1, , drop = FALSE], lineage_id = s_lin_id)
  stopifnot(is.list(ho_cmp_sm), identical(as.character(ho_cmp_sm$plot_type), "pseudotime_smooth_panel"))
  stopifnot(identical(as.character(ho_cmp_sm$params$feature), as.character(s_feat$entity_id[1])))

  if (nrow(sig)) {
    tg_sig <- wb_nav_targets(
      source = sm_id,
      bundle = b,
      entity = s_lin[1, , drop = FALSE],
      lineage_id = s_lin_id
    )
    stopifnot(is.data.frame(tg_sig), any(as.character(tg_sig$action) == "open_signature_plot"))

    ho_sig <- wb_nav_handoff(source = sm_id, target = "open_signature_plot", bundle = b, entity = s_lin[1, , drop = FALSE], lineage_id = s_lin_id)
    stopifnot(is.list(ho_sig), identical(as.character(ho_sig$plot_type), "pseudotime_signature_line"))
    stopifnot(identical(as.character(ho_sig$params$lineage), s_lin_id))

    sig_lin <- wb_nav_entities(source = sig_id, bundle = b, entity_kind = "lineage")
    stopifnot(is.data.frame(sig_lin), nrow(sig_lin) >= 1L)
    sig_lin_id <- as.character(sig_lin$entity_id[1])
    sig_set <- wb_nav_entities(source = sig_id, bundle = b, entity_kind = "feature", lineage_id = sig_lin_id, limit = 10L)
    stopifnot(is.data.frame(sig_set), nrow(sig_set) >= 1L)
    stopifnot(all(as.character(sig_set$entity_kind) == "feature_set"))

    sig_tg <- wb_nav_targets(source = sig_id, bundle = b, entity = sig_set[1, , drop = FALSE], lineage_id = sig_lin_id)
    stopifnot(is.data.frame(sig_tg), any(as.character(sig_tg$action) == "compare_other_lineage"))

    sig_ho <- wb_nav_handoff(source = sig_id, target = "compare_other_lineage", bundle = b, entity = sig_set[1, , drop = FALSE], lineage_id = sig_lin_id)
    stopifnot(is.list(sig_ho), identical(as.character(sig_ho$plot_type), "pseudotime_signature_line"))
    stopifnot(identical(as.character(sig_ho$params$feature_set), as.character(sig_set$entity_id[1])))
  }

  tmp <- file.path(tempdir(), paste0("scwb_nav_geneset_", as.integer(Sys.time())))
  b2 <- wb_init_bundle(tmp, overwrite = TRUE)
  on.exit(try(wb_close_bundle(b2), silent = TRUE), add = TRUE)
  lin2 <- "L1"
  fs2 <- c("set_a", "set_b")
  curve_tbl <- data.frame(
    feature_set = rep(fs2, each = 4),
    lineage_id = lin2,
    bin = rep(seq_len(4), times = 2),
    pseudotime = rep(seq(0, 1, length.out = 4), times = 2),
    value = c(0, 1, 2, 3, 3, 2, 1, 0),
    value_raw = c(0, 1, 2, 3, 3, 2, 1, 0),
    value_smooth = c(0, 1, 2, 3, 3, 2, 1, 0),
    n_cells = 10L,
    stringsAsFactors = FALSE
  )
  dyn_tbl <- data.frame(
    feature_set = fs2,
    lineage_id = lin2,
    curve_class = c("turns_on", "turns_off"),
    dynamic_score = c(3, 2),
    amplitude = c(3, 3),
    rank = c(1L, 2L),
    passes_filters = TRUE,
    stringsAsFactors = FALSE
  )
  drv_tbl <- data.frame(
    feature_set = rep(fs2, each = 2),
    lineage_id = lin2,
    feature_id = c("g1", "g2", "g3", "g4"),
    driver_rank = c(1L, 2L, 1L, 2L),
    dynamic_score = c(2, 1, 2, 1),
    stringsAsFactors = FALSE
  )
  drv_curve_tbl <- data.frame(
    feature_set = rep(rep(fs2, each = 8), 1),
    feature_id = rep(c("g1", "g2", "g3", "g4"), each = 4),
    driver_rank = rep(c(1L, 2L, 1L, 2L), each = 4),
    lineage_id = lin2,
    bin = rep(seq_len(4), times = 4),
    pseudotime = rep(seq(0, 1, length.out = 4), times = 4),
    value = rep(c(0, 1, 2, 3), times = 4),
    value_raw = rep(c(0, 1, 2, 3), times = 4),
    value_smooth = rep(c(0, 1, 2, 3), times = 4),
    n_cells = 10L,
    stringsAsFactors = FALSE
  )
  run_gs <- wb_new_run(
    op_name = "trajectory_geneset_dynamics",
    inputs = list(
      cell_set = "all",
      effective_n = 20L,
      parents = character(0),
      user_inputs = list(matrix = "RNA_counts", namespace = "test_sets")
    ),
    params = list(matrix_id = "RNA_counts", namespace = "test_sets"),
    outputs = list(
      signature_table = wb_prim_obs_table(curve_tbl, table_type = "trajectory_geneset_dynamics_curve", entity_kind = "trajectory_bin"),
      dynamics_table = wb_prim_obs_table(dyn_tbl, table_type = "trajectory_geneset_dynamics", entity_kind = "feature_set"),
      driver_table = wb_prim_obs_table(drv_tbl, table_type = "trajectory_geneset_dynamics_drivers", entity_kind = "feature"),
      driver_curve_table = wb_prim_obs_table(drv_curve_tbl, table_type = "trajectory_geneset_dynamics_driver_curve", entity_kind = "trajectory_bin")
    ),
    notes = "synthetic trajectory gene-set navigation"
  )
  runs2 <- list()
  runs2[[run_gs$run_id]] <- run_gs
  prom2 <- wb_promote_analysis(
    bundle = b2,
    runs = runs2,
    head_run_id = run_gs$run_id,
    name_prefix = "nav_geneset",
    created_by = "test",
    fail_fast = TRUE
  )
  stopifnot(is.data.frame(prom2$promoted), nrow(prom2$promoted) >= 4L)
  arts_gs <- wb_art_list(b2)
  tt_gs <- DBI::dbGetQuery(
    b2$con,
    "SELECT artifact_id, table_type FROM artifact_tables WHERE artifact_id IN (SELECT artifact_id FROM artifacts WHERE type = 'obs_table');"
  )
  arts_gs <- merge(arts_gs, tt_gs, by = "artifact_id", all.x = TRUE, sort = FALSE)
  dyn_id <- as.character(arts_gs$artifact_id[as.character(arts_gs$table_type) == "trajectory_geneset_dynamics"][1])
  drv_id <- as.character(arts_gs$artifact_id[as.character(arts_gs$table_type) == "trajectory_geneset_dynamics_drivers"][1])
  stopifnot(nzchar(dyn_id), nzchar(drv_id))

  gs_lin <- wb_nav_entities(dyn_id, b2, entity_kind = "lineage")
  stopifnot(is.data.frame(gs_lin), nrow(gs_lin) == 1L, identical(as.character(gs_lin$entity_id[1]), lin2))
  gs_sets <- wb_nav_entities(dyn_id, b2, entity_kind = "feature_set", lineage_id = lin2)
  stopifnot(is.data.frame(gs_sets), nrow(gs_sets) >= 2L, all(as.character(gs_sets$entity_kind) == "feature_set"))
  gs_tg <- wb_nav_targets(dyn_id, b2, entity = gs_sets[1, , drop = FALSE], lineage_id = lin2)
  stopifnot(any(as.character(gs_tg$action) == "open_geneset_curve"))
  stopifnot(any(as.character(gs_tg$action) == "open_driver_table"))
  gs_ho <- wb_nav_handoff(dyn_id, "open_geneset_curve", b2, entity = gs_sets[1, , drop = FALSE], lineage_id = lin2)
  stopifnot(identical(as.character(gs_ho$plot_type), "pseudotime_signature_line"))
  stopifnot(identical(as.character(gs_ho$params$feature_set), as.character(gs_sets$entity_id[1])))

  drv_feats <- wb_nav_entities(drv_id, b2, entity_kind = "feature", lineage_id = lin2, feature_set = as.character(gs_sets$entity_id[1]))
  stopifnot(is.data.frame(drv_feats), nrow(drv_feats) >= 1L, all(as.character(drv_feats$entity_kind) == "feature"))
  drv_tg <- wb_nav_targets(drv_id, b2, entity = drv_feats[1, , drop = FALSE], lineage_id = lin2)
  stopifnot(any(as.character(drv_tg$action) == "open_driver_curve"))
  drv_ho <- wb_nav_handoff(drv_id, "open_driver_curve", b2, entity = drv_feats[1, , drop = FALSE], lineage_id = lin2)
  stopifnot(identical(as.character(drv_ho$plot_type), "pseudotime_signature_line"))
  stopifnot(identical(as.character(drv_ho$params$feature), as.character(drv_feats$entity_id[1])))

  sig_keys <- c("score_a", "score_b")
  sig_curve_tbl <- data.frame(
    signal_key = rep(sig_keys, each = 4),
    feature_set = rep(sig_keys, each = 4),
    lineage_id = lin2,
    bin = rep(seq_len(4), times = 2),
    pseudotime = rep(seq(0, 1, length.out = 4), times = 2),
    value = c(0, 1, 2, 3, 3, 2, 1, 0),
    value_raw = c(0, 1, 2, 3, 3, 2, 1, 0),
    value_smooth = c(0, 1, 2, 3, 3, 2, 1, 0),
    n_cells = 10L,
    stringsAsFactors = FALSE
  )
  sig_dyn_tbl <- data.frame(
    signal_key = sig_keys,
    feature_set = sig_keys,
    lineage_id = lin2,
    curve_class = c("turns_on", "turns_off"),
    dynamic_score = c(3, 2),
    amplitude = c(3, 3),
    rank = c(1L, 2L),
    passes_filters = TRUE,
    stringsAsFactors = FALSE
  )
  run_sig <- wb_new_run(
    op_name = "trajectory_signal_dynamics",
    inputs = list(
      cell_set = "all",
      effective_n = 20L,
      parents = character(0),
      user_inputs = list(signal = "module_scores")
    ),
    params = list(n_signal_keys_input = 2L),
    outputs = list(
      signal_table = wb_prim_obs_table(sig_curve_tbl, table_type = "trajectory_signal_dynamics_curve", entity_kind = "trajectory_bin"),
      dynamics_table = wb_prim_obs_table(sig_dyn_tbl, table_type = "trajectory_signal_dynamics", entity_kind = "signal")
    ),
    notes = "synthetic trajectory signal navigation"
  )
  runs_sig <- list()
  runs_sig[[run_sig$run_id]] <- run_sig
  prom_sig <- wb_promote_analysis(
    bundle = b2,
    runs = runs_sig,
    head_run_id = run_sig$run_id,
    name_prefix = "nav_signal",
    created_by = "test",
    fail_fast = TRUE
  )
  stopifnot(is.data.frame(prom_sig$promoted), nrow(prom_sig$promoted) >= 2L)
  arts_sig <- wb_art_list(b2)
  tt_sig <- DBI::dbGetQuery(
    b2$con,
    "SELECT artifact_id, table_type FROM artifact_tables WHERE artifact_id IN (SELECT artifact_id FROM artifacts WHERE type = 'obs_table');"
  )
  arts_sig <- merge(arts_sig, tt_sig, by = "artifact_id", all.x = TRUE, sort = FALSE)
  sig_dyn_id <- as.character(arts_sig$artifact_id[as.character(arts_sig$table_type) == "trajectory_signal_dynamics"][1])
  stopifnot(nzchar(sig_dyn_id))

  sig_lin <- wb_nav_entities(sig_dyn_id, b2, entity_kind = "lineage")
  stopifnot(is.data.frame(sig_lin), nrow(sig_lin) == 1L, identical(as.character(sig_lin$entity_id[1]), lin2))
  sig_entities <- wb_nav_entities(sig_dyn_id, b2, entity_kind = "feature_set", lineage_id = lin2)
  stopifnot(is.data.frame(sig_entities), nrow(sig_entities) >= 2L)
  sig_tg <- wb_nav_targets(sig_dyn_id, b2, entity = sig_entities[1, , drop = FALSE], lineage_id = lin2)
  stopifnot(any(as.character(sig_tg$action) == "open_signal_curve"))
  sig_ho <- wb_nav_handoff(sig_dyn_id, "open_signal_curve", b2, entity = sig_entities[1, , drop = FALSE], lineage_id = lin2)
  stopifnot(identical(as.character(sig_ho$plot_type), "pseudotime_signature_line"))
  stopifnot(identical(as.character(sig_ho$params$signal_key), as.character(sig_entities$entity_id[1])))

  TRUE
}
