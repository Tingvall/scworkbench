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

  TRUE
}
