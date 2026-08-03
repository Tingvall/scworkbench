test_op_trajectory_route_smooth_contract <- function(bundle_dir) {
  b <- wb_open_bundle(bundle_dir)
  on.exit(wb_close_bundle(b), add = TRUE)

  iface <- wb_op_interface("trajectory_route_smooth", bundle = b)
  stopifnot(is.list(iface))
  stopifnot(identical(as.character(iface$produces$trend_table$kind), "obs_table"))
  stopifnot(identical(as.character(iface$produces$fit_summary$kind), "obs_table"))
  stopifnot("trajectory_route_smooth" %in% wb_list_ops())

  mats <- wb_matrices(b)
  stopifnot(is.data.frame(mats), nrow(mats) >= 1L)
  matrix_id <- as.character(mats$matrix_id[1])
  feats <- as.character(head(wb_feature_ids(b, matrix_id = matrix_id), 50))
  stopifnot(length(feats) >= 10L)

  cells <- tryCatch(wb_cells(b, cell_set = "core"), error = function(e) character(0))
  if (length(cells) < 200L) cells <- wb_cells(b, cell_set = "all")
  stopifnot(length(cells) >= 200L)
  cells <- as.character(head(cells, 200))

  pt_vals <- seq(0, 1, length.out = length(cells))
  names(pt_vals) <- cells
  pt <- wb_prim_cell_vector(pt_vals, value_type = "continuous")

  route_a_cells <- cells[1:160]
  route_b_cells <- cells[41:200]
  bm <- wb_prim_relation_family(
    key = c(rep("route:a", length(route_a_cells)), rep("route:b", length(route_b_cells))),
    cell_id = c(route_a_cells, route_b_cells),
    weight = c(seq(0.2, 1, length.out = length(route_a_cells)), seq(0.3, 1, length.out = length(route_b_cells)))
  )
  stopifnot(inherits(bm, "wb_primitive"), identical(as.character(bm$kind), "relation_family"))

  fs_name <- ".__test_trajectory_route_smooth_feature_set__."
  fs_feats <- unique(as.character(feats[1:8]))
  wb_feature_set_import_list(
    b, matrix_id = matrix_id, sets = stats::setNames(list(fs_feats), fs_name),
    namespace = "contract", created_by = "test", strict = TRUE,
    origin = "imported", is_readonly = FALSE
  )

  s <- wb_session_new()
  r1 <- wb_session_run_op(
    session = s,
    bundle = b,
    op_name = "trajectory_route_smooth",
    inputs = list(
      cell_set = "all",
      cell_ids = cells,
      matrix = wb_prim_matrix(matrix_id),
      pseudotime = pt,
      branch_membership = bm,
      route_key = "route:a",
      feature_set = fs_name,
      features = c(fs_feats[1], feats[20]),
      n_bins = 20L,
      summary_fun = "mean",
      min_cells_per_bin = 5L,
      weight_mode = "probability",
      prob_min = 0.2
    ),
    notes = "test trajectory_route_smooth: probability"
  )

  trend <- r1$run$outputs$trend_table
  sm <- r1$run$outputs$fit_summary
  stopifnot(inherits(trend, "wb_primitive"), identical(as.character(trend$kind), "obs_table"))
  stopifnot(inherits(sm, "wb_primitive"), identical(as.character(sm$kind), "obs_table"))
  stopifnot(identical(as.character(trend$table_type), "trajectory_route_smooth"))

  trend_tbl <- trend$table
  sm_tbl <- sm$table
  stopifnot(is.data.frame(trend_tbl), nrow(trend_tbl) > 0L)
  stopifnot(all(c("feature_id", "route_key", "bin", "pseudotime", "expr", "n_cells", "route_weight_sum") %in% colnames(trend_tbl)))
  stopifnot(all(as.character(trend_tbl$route_key) == "route:a"))
  stopifnot(setequal(unique(as.character(trend_tbl$feature_id)), fs_feats[1]))
  stopifnot(all(is.finite(as.numeric(trend_tbl$route_weight_sum))))

  stopifnot(is.data.frame(sm_tbl), nrow(sm_tbl) == 1L)
  stopifnot(all(c("route_key", "n_cells_route", "route_weight_sum", "n_features_tested", "weight_mode", "prob_min") %in% colnames(sm_tbl)))
  stopifnot(identical(as.character(sm_tbl$route_key[1]), "route:a"))
  stopifnot(identical(as.character(sm_tbl$weight_mode[1]), "probability"))

  r2 <- wb_session_run_op(
    session = r1$session,
    bundle = b,
    op_name = "trajectory_route_smooth",
    inputs = list(
      cell_set = "all",
      cell_ids = cells,
      matrix = wb_prim_matrix(matrix_id),
      pseudotime = pt,
      branch_membership = bm,
      route_key = "route:b",
      features = fs_feats[1],
      n_bins = 20L,
      summary_fun = "median",
      min_cells_per_bin = 5L,
      weight_mode = "binary_threshold",
      prob_min = 0.5
    ),
    notes = "test trajectory_route_smooth: binary threshold"
  )
  trend2 <- r2$run$outputs$trend_table$table
  sm2 <- r2$run$outputs$fit_summary$table
  stopifnot(is.data.frame(trend2), nrow(trend2) > 0L)
  stopifnot(all(as.character(trend2$route_key) == "route:b"))
  stopifnot(all(as.numeric(trend2$route_weight_sum) >= as.numeric(trend2$n_cells)))
  stopifnot(identical(as.character(sm2$weight_mode[1]), "binary_threshold"))

  TRUE
}
