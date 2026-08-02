test_op_palantir_project_contract <- function(bundle_dir) {
  pybench_python <- .wb_pybench_default_python()
  if (!file.exists(pybench_python)) {
    return(contract_test_skip(paste("Pybench interpreter not found at", pybench_python)))
  }

  b <- wb_open_bundle(bundle_dir)
  on.exit(wb_close_bundle(b), add = TRUE)

  core <- wb_cells(b, "core")
  stopifnot(length(core) >= 3L)
  root_cell <- as.character(core[[1L]])
  terminal_cd3 <- as.character(core[[2L]])
  terminal_cd19 <- as.character(core[[3L]])
  cells <- unique(c(root_cell, terminal_cd3, terminal_cd19,
                    as.character(head(setdiff(core, c(root_cell, terminal_cd3, terminal_cd19)), 900))))

  iface <- wb_op_interface("palantir_project", bundle = b)
  stopifnot(is.list(iface))
  stopifnot(identical(as.character(iface$produces$curves$kind), "path_2d_family"))

  s <- wb_session_new()
  r_fit <- wb_session_run_op(
    session = s,
    bundle = b,
    op_name = "palantir_fit",
    inputs = list(
      cell_set = "all",
      cell_ids = cells,
      fit_space = wb_prim_space("peakvi_space"),
      root_cell = root_cell,
      terminal_cells = c(terminal_cd3, terminal_cd19),
      dims = as.character(1:20),
      knn = 30L,
      n_diffusion_components = 10L,
      n_waypoints = 100L,
      seed = 20L
    ),
    notes = "contract test palantir_fit for project"
  )
  s <- r_fit$session

  r_proj <- wb_session_run_op(
    session = s,
    bundle = b,
    op_name = "palantir_project",
    inputs = list(
      model = wb_ref_run(r_fit$run$run_id, "model"),
      plot_space = wb_prim_space_2d("umap.peakvi_space"),
      prob_min = 0.01,
      smoothness = 1.0,
      min_cells_per_branch = 20L,
      approx_points = 200L
    ),
    notes = "contract test palantir_project"
  )

  cv <- r_proj$run$outputs$curves
  stopifnot(inherits(cv, "wb_primitive"), identical(as.character(cv$kind), "path_2d_family"))
  stopifnot(length(cv$key) > 0L, length(cv$point) == length(cv$key))
  stopifnot(all(grepl("^branch:", as.character(cv$key))))

  bm <- r_fit$run$outputs$branch_membership
  fit_keys <- sort(unique(as.character(bm$key)))
  cv_keys <- sort(unique(as.character(cv$key)))
  stopifnot(setequal(fit_keys, cv_keys))

  cv_ref <- wb_ref_run(r_proj$run$run_id, "curves")
  cv_space <- wb_path_2d_family_space_id(b, cv_ref, runs = r_proj$session$runs)
  stopifnot(identical(as.character(cv_space), "umap.peakvi_space"))

  prom <- wb_session_promote_current(
    bundle = b,
    session = r_proj$session,
    name_prefix = "palantir_project_contract",
    created_by = "test",
    outputs = "curves",
    fail_fast = TRUE
  )
  ok_curves <- prom$promoted[
    as.character(prom$promoted$status %||% "") == "ok" &
      as.character(prom$promoted$output %||% "") == "curves" &
      as.character(prom$promoted$op_name %||% "") == "palantir_project",
    ,
    drop = FALSE
  ]
  stopifnot(nrow(ok_curves) == 1L)
  cv_art <- wb_art_load(b, as.character(ok_curves$artifact_id[1]), expected_kind = "path_2d_family")
  stopifnot(inherits(cv_art, "wb_primitive"), identical(as.character(cv_art$kind), "path_2d_family"))

  TRUE
}
