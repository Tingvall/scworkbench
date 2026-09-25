test_navigation_contract <- function(bundle_dir) {
  retained <- tempfile("scwb_s2_retained_navigation_")
  dir.create(retained)
  on.exit(unlink(retained, recursive = TRUE, force = TRUE), add = TRUE)
  fixture <- file.path("tests", "fixtures", "phase5_s2_retained_old_core_bundle.tar.gz")
  utils::untar(fixture, exdir = retained)
  b <- wb_open_bundle(file.path(retained, "forge1-s2-retained-bundle"))
  on.exit(wb_close_bundle(b), add = TRUE)

  # The retained bundle was promoted with the accepted pre-migration core.
  # Its historical source_op and table_type identities must survive reopen.
  stopifnot(!any(c("trajectory_de", "trajectory_smooth") %in% wb_list_ops()))

  arts <- wb_art_list(b)
  stopifnot(is.data.frame(arts), nrow(arts) >= 2L)

  tinfo <- try(DBI::dbGetQuery(
    b$con,
    "SELECT artifact_id, table_type
     FROM artifact_tables
     WHERE artifact_id IN (SELECT artifact_id FROM artifacts WHERE type IN ('obs_table', 'feature_table'));"
  ), silent = TRUE)
  stopifnot(!inherits(tinfo, "try-error"), is.data.frame(tinfo), nrow(tinfo) >= 2L)

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
  stopifnot(nrow(de) >= 1L, nrow(sm) >= 1L)

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

  lin2 <- "L1"
  arts_gs <- wb_art_list(b)
  tt_gs <- DBI::dbGetQuery(
    b$con,
    "SELECT artifact_id, table_type FROM artifact_tables WHERE artifact_id IN (SELECT artifact_id FROM artifacts WHERE type = 'obs_table');"
  )
  arts_gs <- merge(arts_gs, tt_gs, by = "artifact_id", all.x = TRUE, sort = FALSE)
  dyn_id <- as.character(arts_gs$artifact_id[as.character(arts_gs$table_type) == "trajectory_geneset_dynamics"][1])
  drv_id <- as.character(arts_gs$artifact_id[as.character(arts_gs$table_type) == "trajectory_geneset_dynamics_drivers"][1])
  stopifnot(nzchar(dyn_id), nzchar(drv_id))

  gs_lin <- wb_nav_entities(dyn_id, b, entity_kind = "lineage")
  stopifnot(is.data.frame(gs_lin), nrow(gs_lin) == 1L, identical(as.character(gs_lin$entity_id[1]), lin2))
  gs_sets <- wb_nav_entities(dyn_id, b, entity_kind = "feature_set", lineage_id = lin2)
  stopifnot(is.data.frame(gs_sets), nrow(gs_sets) >= 2L, all(as.character(gs_sets$entity_kind) == "feature_set"))
  gs_tg <- wb_nav_targets(dyn_id, b, entity = gs_sets[1, , drop = FALSE], lineage_id = lin2)
  stopifnot(any(as.character(gs_tg$action) == "open_geneset_curve"))
  stopifnot(any(as.character(gs_tg$action) == "open_driver_table"))
  gs_ho <- wb_nav_handoff(dyn_id, "open_geneset_curve", b, entity = gs_sets[1, , drop = FALSE], lineage_id = lin2)
  stopifnot(identical(as.character(gs_ho$plot_type), "pseudotime_signature_line"))
  stopifnot(identical(as.character(gs_ho$params$feature_set), as.character(gs_sets$entity_id[1])))

  drv_feats <- wb_nav_entities(drv_id, b, entity_kind = "feature", lineage_id = lin2, feature_set = as.character(gs_sets$entity_id[1]))
  stopifnot(is.data.frame(drv_feats), nrow(drv_feats) >= 1L, all(as.character(drv_feats$entity_kind) == "feature"))
  drv_tg <- wb_nav_targets(drv_id, b, entity = drv_feats[1, , drop = FALSE], lineage_id = lin2)
  stopifnot(any(as.character(drv_tg$action) == "open_driver_curve"))
  drv_ho <- wb_nav_handoff(drv_id, "open_driver_curve", b, entity = drv_feats[1, , drop = FALSE], lineage_id = lin2)
  stopifnot(identical(as.character(drv_ho$plot_type), "pseudotime_signature_line"))
  stopifnot(identical(as.character(drv_ho$params$feature), as.character(drv_feats$entity_id[1])))

  arts_sig <- wb_art_list(b)
  tt_sig <- DBI::dbGetQuery(
    b$con,
    "SELECT artifact_id, table_type FROM artifact_tables WHERE artifact_id IN (SELECT artifact_id FROM artifacts WHERE type = 'obs_table');"
  )
  arts_sig <- merge(arts_sig, tt_sig, by = "artifact_id", all.x = TRUE, sort = FALSE)
  sig_dyn_id <- as.character(arts_sig$artifact_id[as.character(arts_sig$table_type) == "trajectory_signal_dynamics"][1])
  stopifnot(nzchar(sig_dyn_id))

  sig_lin <- wb_nav_entities(sig_dyn_id, b, entity_kind = "lineage")
  stopifnot(is.data.frame(sig_lin), nrow(sig_lin) == 1L, identical(as.character(sig_lin$entity_id[1]), lin2))
  sig_entities <- wb_nav_entities(sig_dyn_id, b, entity_kind = "feature_set", lineage_id = lin2)
  stopifnot(is.data.frame(sig_entities), nrow(sig_entities) >= 2L)
  sig_tg <- wb_nav_targets(sig_dyn_id, b, entity = sig_entities[1, , drop = FALSE], lineage_id = lin2)
  stopifnot(any(as.character(sig_tg$action) == "open_signal_curve"))
  sig_ho <- wb_nav_handoff(sig_dyn_id, "open_signal_curve", b, entity = sig_entities[1, , drop = FALSE], lineage_id = lin2)
  stopifnot(identical(as.character(sig_ho$plot_type), "pseudotime_signature_line"))
  stopifnot(identical(as.character(sig_ho$params$signal_key), as.character(sig_entities$entity_id[1])))

  TRUE
}
