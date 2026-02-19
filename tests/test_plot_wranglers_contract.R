test_plot_wranglers_contract <- function(bundle_dir) {
  b <- wb_open_bundle(bundle_dir)
  on.exit(wb_close_bundle(b), add = TRUE)

  # registry + contracts
  mm <- wb_plot_mapper_list()
  stopifnot(is.data.frame(mm), nrow(mm) >= 2)
  stopifnot(any(mm$plot_type == "embedding_overlay"))
  stopifnot(any(mm$plot_type == "volcano"))
  stopifnot(any(mm$plot_type == "violin"))
  stopifnot(any(mm$plot_type == "dotplot"))

  c1 <- wb_plot_contract("embedding_overlay")
  c2 <- wb_plot_contract("volcano")
  c3 <- wb_plot_contract("violin")
  c4 <- wb_plot_contract("dotplot")
  stopifnot(identical(c1$plot_type, "embedding_overlay"))
  stopifnot(identical(c2$plot_type, "volcano"))
  stopifnot(identical(c3$plot_type, "violin"))
  stopifnot(identical(c4$plot_type, "dotplot"))

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

  TRUE
}
