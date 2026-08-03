test_op_trajectory_branch_compare_contract <- function(bundle_dir) {
  if (!requireNamespace("slingshot", quietly = TRUE)) {
    return(contract_test_skip("slingshot is not installed."))
  }

  b <- wb_open_bundle(bundle_dir)
  on.exit(wb_close_bundle(b), add = TRUE)

  iface <- wb_op_interface("trajectory_branch_compare", bundle = b)
  stopifnot(is.list(iface))
  stopifnot(identical(as.character(iface$produces$branch_de_table$kind), "feature_table"))
  stopifnot(identical(as.character(iface$produces$branch_summary$kind), "obs_table"))
  stopifnot("trajectory_branch_compare" %in% wb_list_ops())

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

  # Durable registry inputs must exist before the session overlay is created.
  fs_name <- ".__test_trajectory_branch_compare_feature_set__."
  fs_feats <- unique(as.character(feats[1:10]))
  wb_feature_set_import_list(
    b, matrix_id = matrix_id, sets = stats::setNames(list(fs_feats), fs_name),
    namespace = "contract", created_by = "test", strict = TRUE,
    origin = "imported", is_readonly = FALSE
  )

  s <- wb_session_new()
  cluster_values <- ifelse(
    seq_along(cells) <= 200L,
    "root",
    ifelse(seq_along(cells) %% 2L == 0L, "branch_a", "branch_b")
  )
  names(cluster_values) <- cells
  r2 <- wb_session_run_op(
    session = s,
    bundle = b,
    op_name = "slingshot_fit",
    inputs = list(
      cell_set = "all",
      cell_ids = cells,
      fit_space = wb_prim_space(fit_space_id),
      clusters = wb_prim_cell_vector(cluster_values, value_type = "categorical"),
      start.clus = "root",
      end.clus = c("branch_a", "branch_b")
    ),
    notes = "test trajectory_branch_compare: slingshot fit"
  )

  pt <- r2$run$outputs$pseudotime
  stopifnot(inherits(pt, "wb_primitive"), identical(as.character(pt$kind), "cell_vector_family"))

  lineages <- unique(as.character(pt$key))
  lineages <- lineages[nzchar(lineages)]
  stopifnot(length(lineages) >= 2L)

  pt_tbl <- wb_primitive_to_table(pt, include_context = FALSE)
  pt_tbl <- pt_tbl[is.finite(suppressWarnings(as.numeric(pt_tbl$value))), , drop = FALSE]
  bm <- wb_prim_relation_family(
    key = as.character(pt_tbl$key),
    cell_id = as.character(pt_tbl$cell_id),
    weight = rep(1, nrow(pt_tbl))
  )
  stopifnot(inherits(bm, "wb_primitive"), identical(as.character(bm$kind), "relation_family"))

  r3 <- wb_session_run_op(
    session = r2$session,
    bundle = b,
    op_name = "trajectory_branch_compare",
    inputs = list(
      cell_set = "all",
      cell_ids = cells,
      matrix = wb_prim_matrix(matrix_id),
      pseudotime = wb_ref_run(r2$run$run_id, "pseudotime"),
      branch_membership = bm,
      branch_a = lineages[1],
      branch_b = lineages[2],
      feature_set = fs_name,
      features = c(fs_feats[1], feats[50]),
      min_pct = 0,
      p_adjust_method = "BH"
    ),
    notes = "test trajectory_branch_compare: run"
  )

  de <- r3$run$outputs$branch_de_table
  sm <- r3$run$outputs$branch_summary
  stopifnot(inherits(de, "wb_primitive"), identical(as.character(de$kind), "feature_table"))
  stopifnot(inherits(sm, "wb_primitive"), identical(as.character(sm$kind), "obs_table"))
  stopifnot(identical(as.character(de$table_type), "trajectory_branch_compare"))

  de_tbl <- de$table
  sm_tbl <- sm$table
  stopifnot(is.data.frame(de_tbl), nrow(de_tbl) > 0L)
  stopifnot(all(c("feature_id", "avg_log1p_fc", "p_val", "p_val_adj", "branch_a", "branch_b", "n_cells_a", "n_cells_b") %in% colnames(de_tbl)))
  stopifnot(all(as.character(de_tbl$branch_a) == lineages[1]))
  stopifnot(all(as.character(de_tbl$branch_b) == lineages[2]))
  stopifnot(setequal(unique(as.character(de_tbl$feature_id)), fs_feats[1]))

  stopifnot(is.data.frame(sm_tbl), nrow(sm_tbl) == 1L)
  stopifnot(all(c("branch_a", "branch_b", "n_cells_a", "n_cells_b", "n_overlap_dropped", "n_features_tested", "mean_pt_a", "mean_pt_b") %in% colnames(sm_tbl)))
  stopifnot(identical(as.character(sm_tbl$branch_a[1]), lineages[1]))
  stopifnot(identical(as.character(sm_tbl$branch_b[1]), lineages[2]))

  TRUE
}
