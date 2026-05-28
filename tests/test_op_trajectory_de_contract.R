test_op_trajectory_de_contract <- function(bundle_dir) {
  if (!requireNamespace("slingshot", quietly = TRUE)) {
    message("Skipping trajectory_de contract test: slingshot not installed.")
    return(TRUE)
  }

  b <- wb_open_bundle(bundle_dir)
  on.exit(wb_close_bundle(b), add = TRUE)

  iface <- wb_op_interface("trajectory_de", bundle = b)
  stopifnot(is.list(iface))
  stopifnot(identical(as.character(iface$produces$de_table$kind), "feature_table"))
  stopifnot(identical(as.character(iface$produces$fit_summary$kind), "obs_table"))
  stopifnot("trajectory_de" %in% wb_list_ops())

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
  stopifnot(is.data.frame(sp_tbl), nrow(sp_tbl) >= 1L)
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
  stopifnot(is.character(fit_space_id), length(fit_space_id) == 1L, nzchar(fit_space_id))

  s <- wb_session_new()
  x1 <- wb_session_run_op(
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
    notes = "test trajectory_de: leiden seed clusters"
  )
  s <- x1$session

  x2 <- wb_session_run_op(
    session = s,
    bundle = b,
    op_name = "slingshot_fit",
    inputs = list(
      cell_set = "all",
      cell_ids = cells,
      fit_space = wb_prim_space(fit_space_id),
      clusters = wb_ref_run(x1$run$run_id, "clusters")
    ),
    notes = "test trajectory_de: slingshot fit"
  )
  s <- x2$session

  pt <- x2$run$outputs$pseudotime
  stopifnot(inherits(pt, "wb_primitive"), identical(as.character(pt$kind), "cell_vector_family"))
  lineage <- as.character(unique(pt$key))[1]
  stopifnot(nzchar(lineage))

  # Build a temporary feature set for trajectory_de input contract checks.
  fs_name <- ".__test_trajectory_de_feature_set__."
  wb_feature_set_delete(b, feature_set = fs_name, matrix_id = matrix_id)
  fs_feats <- unique(as.character(feats[1:8]))
  wb_feature_set_replace(
    bundle = b,
    feature_set = fs_name,
    matrix_id = matrix_id,
    feature_ids = fs_feats,
    created_by = "test",
    description = "trajectory_de contract test feature set",
    strict = TRUE
  )

  x3 <- wb_session_run_op(
    session = s,
    bundle = b,
    op_name = "trajectory_de",
    inputs = list(
      cell_set = "all",
      cell_ids = cells,
      matrix = wb_prim_matrix(matrix_id),
      model = wb_ref_run(x2$run$run_id, "model"),
      lineage = lineage,
      feature_set = fs_name,
      features = c(fs_feats[1], feats[50]),
      test = "spearman",
      min_pct_nonzero = 0,
      min_sd = 0,
      p_adjust_method = "BH",
      chunk_size = 128L
    ),
    notes = "test trajectory_de: run"
  )

  de <- x3$run$outputs$de_table
  sm <- x3$run$outputs$fit_summary
  stopifnot(inherits(de, "wb_primitive"), identical(as.character(de$kind), "feature_table"))
  stopifnot(inherits(sm, "wb_primitive"), identical(as.character(sm$kind), "obs_table"))

  de_tbl <- de$table
  sm_tbl <- sm$table
  stopifnot(is.data.frame(de_tbl), nrow(de_tbl) > 0L)
  stopifnot(all(c("lineage_id", "feature_id", "rho", "p_val", "p_val_adj", "n_used") %in% colnames(de_tbl)))
  stopifnot(all(as.character(de_tbl$lineage_id) == lineage))
  stopifnot(is.data.frame(sm_tbl), nrow(sm_tbl) >= 1L)
  stopifnot(all(c("lineage_id", "n_cells_used", "n_features_tested") %in% colnames(sm_tbl)))
  stopifnot(any(as.character(sm_tbl$lineage_id) == lineage))
  # Both feature_set + features are provided above; output must follow intersection semantics.
  stopifnot(setequal(unique(as.character(de_tbl$feature_id)), fs_feats[1]))

  # Guardrail: unsupported engines should fail clearly in v1.
  bad_model <- wb_prim_model_ref(
    model_space_id = fit_space_id,
    in_space_id = fit_space_id,
    engine = "palantir"
  )
  err <- try(
    wb_op_trajectory_de(
      bundle = b,
      matrix_id = matrix_id,
      model = bad_model,
      cells = cells,
      features = feats
    ),
    silent = TRUE
  )
  stopifnot(inherits(err, "try-error"))
  stopifnot(grepl("supports model_ref engines 'slingshot' and 'monocle3'", as.character(err)))

  wb_feature_set_delete(b, feature_set = fs_name, matrix_id = matrix_id)

  TRUE
}
