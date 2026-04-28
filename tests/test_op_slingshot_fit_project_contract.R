test_op_slingshot_fit_project_contract <- function(bundle_dir) {
  b <- wb_open_bundle(bundle_dir)
  on.exit(wb_close_bundle(b), add = TRUE)

  # Prefer the known B-lineage/trajectory subset in cooltest; fall back to core.
  candidate_sets <- c("set:usecase1_btraj_early", "core", "all")
  cell_set <- candidate_sets[which(vapply(candidate_sets, function(cs) {
    length(tryCatch(wb_cells(b, cell_set = cs), error = function(e) character(0))) >= 200
  }, logical(1)))[1]]
  stopifnot(length(cell_set) == 1, nzchar(cell_set))

  cells <- wb_cells(b, cell_set = cell_set)
  stopifnot(length(cells) >= 100)
  cell_ids <- as.character(head(cells, 600))

  s <- wb_session_new()

  x1 <- wb_session_run_op(
    session = s,
    bundle = b,
    op_name = "leiden",
    inputs = list(
      cell_set = cell_set,
      cell_ids = cell_ids,
      space = wb_prim_space("peakvi_space"),
      k = 20,
      resolution = 0.3
    ),
    notes = "test slingshot fit/project: leiden seed clusters"
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
      clusters = wb_ref_run(x1$run$run_id, "clusters")
    ),
    notes = "test slingshot fit/project: fit"
  )
  s <- x2$session

  stopifnot("pseudotime" %in% names(x2$run$outputs))
  stopifnot("model" %in% names(x2$run$outputs))
  stopifnot(identical(as.character(x2$run$outputs$model$engine), "slingshot"))
  stopifnot(!is.null(x2$run$outputs$model$model_obj))
  model_cells <- x2$run$outputs$model$cells
  if (is.null(model_cells)) model_cells <- character(0)
  stopifnot(length(as.character(model_cells)) >= 10)

  x3 <- wb_session_run_op(
    session = s,
    bundle = b,
    op_name = "slingshot_project",
    inputs = list(
      cell_set = cell_set,
      cell_ids = cell_ids,
      model = wb_ref_run(x2$run$run_id, "model"),
      plot_space = wb_prim_space_2d("umap.peakvi_space")
    ),
    notes = "test slingshot fit/project: project to umap"
  )

  stopifnot("curves" %in% names(x3$run$outputs))
  cv <- x3$run$outputs$curves
  stopifnot(identical(cv$kind, "path_2d_family"))
  stopifnot(length(cv$point) > 0)
  stopifnot(length(unique(as.character(cv$key))) >= 1)
  tab_cv <- table(as.character(cv$key))
  stopifnot(all(as.integer(tab_cv) <= 200L))

  # Provenance params should make fit/display distinction explicit in the new ops.
  stopifnot(identical(as.character(x2$run$params$fit_space_id), "peakvi_space"))
  stopifnot(identical(as.character(x3$run$params$plot_space_id), "umap.peakvi_space"))
  stopifnot(identical(as.integer(x3$run$params$approx_points), 200L))

  TRUE
}
