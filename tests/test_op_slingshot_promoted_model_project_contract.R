test_op_slingshot_promoted_model_project_contract <- function(bundle_dir) {
  b <- wb_open_bundle(bundle_dir)
  on.exit(wb_close_bundle(b), add = TRUE)

  candidate_sets <- c("set:usecase1_btraj_early", "core", "all")
  pick_idx <- which(vapply(candidate_sets, function(cs) {
    length(tryCatch(wb_cells(b, cell_set = cs), error = function(e) character(0))) >= 200
  }, logical(1)))
  stopifnot(length(pick_idx) >= 1)
  cell_set <- candidate_sets[pick_idx[1]]

  cell_ids <- as.character(head(wb_cells(b, cell_set = cell_set), 400))
  stopifnot(length(cell_ids) >= 100)

  s <- wb_session_new()
  x1 <- contract_test_add_core_metadata_labels(
    session = s, bundle = b, cells = cell_ids,
    notes = "test slingshot promoted model: synthetic seed clusters"
  )
  s <- x1$session

  x2 <- wb_session_run_op(
    session = s,
    bundle = b,
    op_name = "slingshot_fit",
    inputs = list(
      cell_set = cell_set,
      cell_ids = cell_ids,
      fit_space = wb_prim_space("peakvi_space"),
      clusters = wb_ref_run(x1$run$run_id, "vector")
    ),
    notes = "test slingshot promoted model: fit"
  )
  s <- x2$session

  prom <- wb_promote_analysis(
    bundle = b,
    runs = s$runs,
    head_run_id = s$head_run_id,
    name_prefix = "test_slingshot_fit_promote",
    created_by = "test",
    fail_fast = TRUE
  )
  stopifnot(is.data.frame(prom$promoted), nrow(prom$promoted) >= 1)

  model_rows <- prom$promoted[
    as.character(prom$promoted$status %||% "") == "ok" &
      as.character(prom$promoted$output %||% "") == "model",
    ,
    drop = FALSE
  ]
  stopifnot(nrow(model_rows) == 1)
  model_art_id <- as.character(model_rows$artifact_id[1])
  stopifnot(nzchar(model_art_id))
  if ("type" %in% names(model_rows)) {
    stopifnot(identical(as.character(model_rows$type[1]), "model_ref"))
  }
  stopifnot(identical(as.character(model_rows$lineage_status[1]), "complete"))

  # Fresh session should be able to project from promoted model artifact.
  s2 <- wb_session_new()
  x3 <- wb_session_run_op(
    session = s2,
    bundle = b,
    op_name = "slingshot_project",
    inputs = list(
      cell_set = cell_set,
      cell_ids = cell_ids,
      model = wb_ref_artifact(model_art_id, "model"),
      plot_space = wb_prim_space_2d("umap.peakvi_space")
    ),
    notes = "test slingshot promoted model: project"
  )

  stopifnot("curves" %in% names(x3$run$outputs))
  stopifnot(length(x3$run$outputs$curves$point) > 0)
  tab_cv <- table(as.character(x3$run$outputs$curves$key))
  stopifnot(all(as.integer(tab_cv) <= 200L))
  stopifnot(identical(as.integer(x3$run$params$approx_points), 200L))

  # Loader should restore slingshot model payload for project op.
  mp <- wb_art_load(b, model_art_id, expected_kind = "model_ref")
  stopifnot(identical(as.character(mp$engine), "slingshot"))
  stopifnot(!is.null(mp$model_obj))
  stopifnot(file.exists(as.character(mp$model_path)))

  TRUE
}
