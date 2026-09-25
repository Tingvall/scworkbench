test_plot_wranglers_contract <- function(bundle_dir) {
  b <- wb_open_bundle(bundle_dir)
  on.exit(wb_close_bundle(b), add = TRUE)
  if (length(wb_cells(b, cell_set = "all")) < 300L) {
    return(contract_test_skip("Fixture has fewer than 300 cells."))
  }
  mats <- wb_matrices(b)
  stopifnot(nrow(mats) >= 1L)
  mid <- as.character(mats$matrix_id[1])
  m_feats <- as.character(wb_feature_ids(b, matrix_id = mid))
  stopifnot(length(m_feats) >= 5L)

  # registry + contracts
  mm <- wb_plot_mapper_list()
  stopifnot(is.data.frame(mm), nrow(mm) >= 2)
  stopifnot(any(mm$plot_type == "embedding_overlay"))
  stopifnot(any(mm$plot_type == "volcano"))
  stopifnot(any(mm$plot_type == "violin"))
  stopifnot(any(mm$plot_type == "dotplot"))
  stopifnot(any(mm$plot_type == "pseudotime_smooth_panel"))
  stopifnot(any(mm$plot_type == "pseudotime_signature_line"))

  c1 <- wb_plot_contract("embedding_overlay")
  c2 <- wb_plot_contract("volcano")
  c3 <- wb_plot_contract("violin")
  c4 <- wb_plot_contract("dotplot")
  c5 <- wb_plot_contract("pseudotime_smooth_panel")
  c6 <- wb_plot_contract("pseudotime_signature_line")
  stopifnot(identical(c1$plot_type, "embedding_overlay"))
  stopifnot(identical(c2$plot_type, "volcano"))
  stopifnot(identical(c3$plot_type, "violin"))
  stopifnot(identical(c4$plot_type, "dotplot"))
  stopifnot(identical(c5$plot_type, "pseudotime_smooth_panel"))
  stopifnot(identical(c6$plot_type, "pseudotime_signature_line"))

  # volcano from feature_table primitive
  ft <- wb_prim_feature_table(
    table = data.frame(
      feature_id = c("f1", "f2", "f3"),
      avg_log1p_fc = c(1.2, -0.8, 0.1),
      p_val = c(1e-5, 1e-3, 0.4),
      p_val_adj = c(2e-5, 2e-3, 0.5),
      stringsAsFactors = FALSE
    ),
    table_type = "de_wilcox"
  )

  ds_v <- wb_wrangle_plot_dataset(
    plot_type = "volcano",
    inputs = list(table = ft, p_adj_thresh = 0.05, effect_thresh = 0.2, top_n_labels = 2),
    bundle = b
  )
  stopifnot(is.data.frame(ds_v$table), nrow(ds_v$table) == 3)
  stopifnot(all(c("feature_id", "effect", "p_adj", "significant", "direction") %in% colnames(ds_v$table)))
  stopifnot(isTRUE(wb_plot_validate_dataset("volcano", ds_v)))

  sp_v <- wb_plot_spec("volcano", ds_v)
  stopifnot(identical(sp_v$encoding$x, "effect"))
  stopifnot(identical(sp_v$encoding$y_transform, "neg_log10"))
  stopifnot(is.character(sp_v$tooltip_fields), all(c("feature_id", "effect", "p_adj") %in% sp_v$tooltip_fields))

  # embedding overlay from space_2d + color vector
  sp <- wb_spaces(b)
  stopifnot(nrow(sp) > 0)
  sp2 <- sp[sp$dims == 2, , drop = FALSE]
  stopifnot(nrow(sp2) > 0)
  sid <- NA_character_
  for (cand in as.character(sp2$space_id)) {
    xy <- try(scworkbench:::.wb_space_2d_safe(b, cand), silent = TRUE)
    if (!inherits(xy, "try-error") && is.data.frame(xy) && nrow(xy) > 0) {
      sid <- cand
      break
    }
  }
  stopifnot(is.character(sid), length(sid) == 1, nzchar(sid))

  cells <- wb_cells(b, cell_set = "all")
  n <- min(length(cells), 200L)
  vv <- seq_len(n)
  names(vv) <- cells[seq_len(n)]
  cv <- wb_prim_cell_vector(vv, value_type = "continuous")

  ds_e <- wb_wrangle_plot_dataset(
    plot_type = "embedding_overlay",
    inputs = list(space = wb_prim_space_2d(sid), color = cv),
    bundle = b
  )
  stopifnot(is.data.frame(ds_e$table), nrow(ds_e$table) > 0)
  stopifnot(all(c("cell_id", "x", "y") %in% colnames(ds_e$table)))
  stopifnot("color_value" %in% colnames(ds_e$table))
  wb_plot_validate_dataset("embedding_overlay", ds_e)

  sp_e <- wb_plot_spec("embedding_overlay", ds_e)
  stopifnot(identical(sp_e$geom, "point"))
  stopifnot(identical(sp_e$encoding$x, "x"))
  stopifnot(is.character(sp_e$tooltip_fields), "cell_id" %in% sp_e$tooltip_fields)

  # violin from cell_vector (+ group vector)
  n2 <- min(length(cells), 300L)
  vv2 <- stats::runif(n2)
  names(vv2) <- cells[seq_len(n2)]
  gv <- rep(c("A", "B", "C"), length.out = n2)
  names(gv) <- names(vv2)
  prim_val <- wb_prim_cell_vector(vv2, value_type = "continuous")
  prim_grp <- wb_prim_cell_vector(gv, value_type = "categorical")

  ds_vi <- wb_wrangle_plot_dataset(
    plot_type = "violin",
    inputs = list(vector = prim_val, group = prim_grp),
    bundle = b
  )
  stopifnot(is.data.frame(ds_vi$table), nrow(ds_vi$table) == n2)
  stopifnot(all(c("entity_id", "group", "value") %in% colnames(ds_vi$table)))
  wb_plot_validate_dataset("violin", ds_vi)
  sp_vi <- wb_plot_spec("violin", ds_vi)
  stopifnot(identical(sp_vi$geom, "violin"))
  stopifnot(identical(sp_vi$encoding$y, "value"))
  stopifnot(is.character(sp_vi$tooltip_fields), all(c("entity_id", "group", "value") %in% sp_vi$tooltip_fields))

  # raw cell_vector_family compatibility should expose violin and embedding_overlay
  cvf <- wb_prim_cell_vector_family(
    key = c(rep("sigA", n2), rep("sigB", n2)),
    cell_id = c(names(vv2), names(vv2)),
    value = c(as.numeric(vv2), as.numeric(vv2) * 0.5),
    value_type = "continuous"
  )
  cmp_cvf <- wb_plot_compatible_types(ref = cvf, bundle = b)
  stopifnot(is.data.frame(cmp_cvf), nrow(cmp_cvf) >= 1)
  stopifnot(any(cmp_cvf$plot_type == "violin" & cmp_cvf$ok))
  stopifnot(any(cmp_cvf$plot_type == "embedding_overlay" & cmp_cvf$ok))

  inps_cvf <- wb_plot_min_inputs("embedding_overlay", cvf, bundle = b)
  stopifnot(is.list(inps_cvf), !is.null(inps_cvf$space), !is.null(inps_cvf$color))
  ds_cvf <- wb_wrangle_plot_dataset(
    plot_type = "embedding_overlay",
    inputs = inps_cvf,
    bundle = b
  )
  stopifnot(is.data.frame(ds_cvf$table), nrow(ds_cvf$table) > 0)
  stopifnot("color_value" %in% colnames(ds_cvf$table))
  wb_plot_validate_dataset("embedding_overlay", ds_cvf)

  # dotplot from markers-style feature_table
  dft <- data.frame(
    feature_id = rep(c("G1", "G2", "G3"), each = 2),
    cluster = rep(c("c1", "c2"), times = 3),
    pct_a = c(0.8, 0.3, 0.6, 0.4, 0.2, 0.1),
    avg_expr_a = c(2.1, 1.3, 1.8, 1.2, 0.9, 0.7),
    stringsAsFactors = FALSE
  )
  prim_dot <- wb_prim_feature_table(dft, table_type = "markers_topn")
  ds_do <- wb_wrangle_plot_dataset(
    plot_type = "dotplot",
    inputs = list(table = prim_dot),
    bundle = b
  )
  stopifnot(is.data.frame(ds_do$table), nrow(ds_do$table) == nrow(dft))
  stopifnot(all(c("feature_id", "group", "pct_expr", "avg_expr") %in% colnames(ds_do$table)))
  wb_plot_validate_dataset("dotplot", ds_do)
  sp_do <- wb_plot_spec("dotplot", ds_do)
  stopifnot(identical(sp_do$geom, "point"))
  stopifnot(identical(sp_do$encoding$size, "pct_expr"))
  stopifnot(is.character(sp_do$tooltip_fields), all(c("feature_id", "group", "pct_expr", "avg_expr") %in% sp_do$tooltip_fields))

  # pathway_bar from obs_table pathway summary (contract-first, not primitive-kind-first)
  prim_pw <- wb_prim_obs_table(
    data.frame(
      pathway = c("P1", "P2", "P3"),
      namespace = c("ns", "ns", "ns"),
      p_val = c(1e-4, 0.02, 0.5),
      p_val_adj = c(2e-4, 0.03, 0.7),
      enrichment_ratio = c(2.5, 1.7, 1.1),
      overlap = c(10, 7, 2),
      set_size = c(50, 40, 30),
      query_size = c(25, 25, 25),
      stringsAsFactors = FALSE
    ),
    table_type = "pathway_enrich",
    entity_kind = "pathway"
  )
  ds_pw <- wb_wrangle_plot_dataset(
    plot_type = "pathway_bar",
    inputs = list(table = prim_pw, p_adj_thresh = 0.05),
    bundle = b
  )
  stopifnot(is.data.frame(ds_pw$table), nrow(ds_pw$table) == 3)
  stopifnot(all(c("pathway", "p_adj") %in% colnames(ds_pw$table)))
  wb_plot_validate_dataset("pathway_bar", ds_pw)
  sp_pw <- wb_plot_spec("pathway_bar", ds_pw)
  stopifnot(identical(sp_pw$geom, "bar"))
  stopifnot(identical(sp_pw$encoding$x, "pathway"))

  # compatibility discovery should be engine-driven and accept pathway_bar for obs_table.
  cmp <- wb_plot_compatible_types(ref = prim_pw, bundle = b)
  stopifnot(is.data.frame(cmp), nrow(cmp) >= 1)
  stopifnot(any(cmp$plot_type == "pathway_bar" & cmp$ok))
  stopifnot(!any(cmp$plot_type == "volcano" & cmp$ok))

  rep_pw <- wb_plot_compatibility_report(ref = prim_pw, bundle = b)
  stopifnot(is.data.frame(rep_pw), nrow(rep_pw) >= 1)
  stopifnot(all(c("plot_type", "ok", "mapper_id", "reason_code", "reason", "error") %in% names(rep_pw)))
  stopifnot(any(rep_pw$plot_type == "pathway_bar" & rep_pw$ok & rep_pw$reason_code == "ok"))
  stopifnot(any(rep_pw$plot_type == "volcano" & !rep_pw$ok))
  stopifnot(any(rep_pw$plot_type == "volcano" & rep_pw$reason_code %in% c("no_compatible_mapper", "wrangle_error")))
  stopifnot(any(rep_pw$plot_type == "volcano" & nzchar(as.character(rep_pw$reason))))

  # Plot mapping consumes typed tables. Keep this core contract independent of
  # the trajectory pack's scientific runners and fitted-model lifecycle.
  pseudotime <- seq(0, 1, length.out = 5L)
  trend_tbl <- wb_prim_obs_table(data.frame(
    feature_id = rep(m_feats[1:2], each = 5L),
    lineage_id = rep("L1", 10L),
    bin = rep(seq_len(5L), 2L),
    pseudotime = rep(pseudotime, 2L),
    expr = c(seq(1, 2, length.out = 5L), seq(2, 1, length.out = 5L)),
    n_cells = rep(30L, 10L), stringsAsFactors = FALSE),
    table_type = "trajectory_smooth")
  ds_ps <- wb_wrangle_plot_dataset(
    plot_type = "pseudotime_smooth_panel",
    inputs = list(table = trend_tbl), bundle = b)
  stopifnot(is.data.frame(ds_ps$table), nrow(ds_ps$table) > 0)
  stopifnot(all(c("feature_id", "pseudotime", "expr") %in% colnames(ds_ps$table)))
  wb_plot_validate_dataset("pseudotime_smooth_panel", ds_ps)
  sp_ps <- wb_plot_spec("pseudotime_smooth_panel", ds_ps)
  stopifnot(identical(sp_ps$geom, "line"))
  stopifnot(identical(sp_ps$encoding$x, "pseudotime"))
  stopifnot(identical(sp_ps$encoding$facet, "feature_id"))

  signature_tbl <- wb_prim_obs_table(data.frame(
    feature_set = rep("synthetic_set", 5L), lineage_id = rep("L1", 5L),
    bin = seq_len(5L), pseudotime = pseudotime,
    value = seq(0.2, 0.8, length.out = 5L),
    n_cells = rep(30L, 5L), stringsAsFactors = FALSE),
    table_type = "trajectory_signature_smooth")
  ds_sig <- wb_wrangle_plot_dataset(
    plot_type = "pseudotime_signature_line",
    inputs = list(table = signature_tbl), bundle = b)
  stopifnot(is.data.frame(ds_sig$table), nrow(ds_sig$table) > 0)
  stopifnot(all(c("feature_set", "pseudotime", "value") %in% colnames(ds_sig$table)))
  wb_plot_validate_dataset("pseudotime_signature_line", ds_sig)
  sp_sig <- wb_plot_spec("pseudotime_signature_line", ds_sig)
  stopifnot(identical(sp_sig$geom, "line"))
  stopifnot(identical(sp_sig$encoding$x, "pseudotime"))
  stopifnot(identical(sp_sig$encoding$y, "value"))

  gset_curve <- wb_prim_obs_table(data.frame(
    feature_set = rep("synthetic_set", 5L), lineage_id = rep("L1", 5L),
    bin = seq_len(5L), pseudotime = pseudotime,
    value = seq(0.1, 0.9, length.out = 5L),
    value_raw = seq(0.1, 0.9, length.out = 5L),
    value_smooth = seq(0.2, 0.8, length.out = 5L),
    n_cells = rep(30L, 5L), stringsAsFactors = FALSE),
    table_type = "trajectory_geneset_dynamics_curve")
  ds_gset <- wb_wrangle_plot_dataset(
    plot_type = "pseudotime_signature_line",
    inputs = list(table = gset_curve), bundle = b)
  stopifnot(is.data.frame(ds_gset$table), nrow(ds_gset$table) > 0)
  stopifnot(all(c("feature_set", "pseudotime", "value", "value_raw", "value_smooth") %in% colnames(ds_gset$table)))
  stopifnot(identical(ds_gset$dataset_type, "trajectory_geneset_dynamics_curve"))
  wb_plot_validate_dataset("pseudotime_signature_line", ds_gset)

  driver_curve <- wb_prim_obs_table(data.frame(
    feature_set = rep("synthetic_set", 5L),
    feature_id = rep(m_feats[1], 5L), driver_rank = rep(1L, 5L),
    lineage_id = rep("L1", 5L), bin = seq_len(5L),
    pseudotime = pseudotime, value = seq(1, 2, length.out = 5L),
    n_cells = rep(30L, 5L), stringsAsFactors = FALSE),
    table_type = "trajectory_geneset_dynamics_driver_curve")
  ds_driver <- wb_wrangle_plot_dataset(
    plot_type = "pseudotime_signature_line",
    inputs = list(table = driver_curve), bundle = b)
  stopifnot(is.data.frame(ds_driver$table), nrow(ds_driver$table) > 0)
  stopifnot(all(c("feature_set", "feature_id", "driver_rank", "pseudotime", "value") %in% colnames(ds_driver$table)))
  stopifnot(identical(ds_driver$dataset_type, "trajectory_geneset_dynamics_driver_curve"))
  wb_plot_validate_dataset("pseudotime_signature_line", ds_driver)
  sp_driver <- wb_plot_spec("pseudotime_signature_line", ds_driver)
  stopifnot(identical(sp_driver$encoding$color, "feature_id"))
  stopifnot(identical(sp_driver$encoding$facet, "feature_set"))

  TRUE
}
