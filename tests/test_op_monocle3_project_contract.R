test_op_monocle3_project_contract <- function(bundle_dir) {
  if (!requireNamespace("monocle3", quietly = TRUE)) {
    return(contract_test_skip("monocle3 is not installed."))
  }

  b <- wb_open_bundle(bundle_dir)
  on.exit(wb_close_bundle(b), add = TRUE)

  cells <- tryCatch(wb_cells(b, cell_set = "core"), error = function(e) character(0))
  stopifnot(length(cells) >= 300)
  cells <- as.character(head(cells, 700))
  root_cells <- as.character(head(cells, 20))

  s <- wb_session_new()
  r_fit <- wb_session_run_op(
    session = s,
    bundle = b,
    op_name = "monocle3_fit",
    inputs = list(
      cell_set = "all",
      cell_ids = cells,
      fit_space = wb_prim_space("peakvi_space"),
      dims = as.character(1:20),
      root_cells = root_cells,
      use_partition = FALSE,
      close_loop = FALSE
    ),
    notes = "contract test monocle3_fit for project"
  )
  s <- r_fit$session

  r_proj <- wb_session_run_op(
    session = s,
    bundle = b,
    op_name = "monocle3_project",
    inputs = list(
      cell_set = "all",
      cell_ids = cells,
      model = wb_ref_run(r_fit$run$run_id, "model"),
      plot_space = wb_prim_space_2d("umap.peakvi_space"),
      approx_points = 200L
    ),
    notes = "contract test monocle3_project"
  )

  cv <- r_proj$run$outputs$curves
  stopifnot(inherits(cv, "wb_primitive"), identical(as.character(cv$kind), "path_2d_family"))
  stopifnot(length(cv$key) > 0L, length(cv$point) == length(cv$key))
  stopifnot(all(grepl("^root:[^:]+::lineage:[^:]+$", as.character(cv$key))))

  # Keys should align with branch_membership lineage keys from the fit run.
  bm <- r_fit$run$outputs$branch_membership
  fit_keys <- sort(unique(as.character(bm$key)))
  cv_keys <- sort(unique(as.character(cv$key)))
  stopifnot(length(intersect(fit_keys, cv_keys)) >= 1L)

  # Birth-certificate plot space lookup should work for session refs.
  cv_ref <- wb_ref_run(r_proj$run$run_id, "curves")
  cv_space <- wb_path_2d_family_space_id(b, cv_ref, runs = r_proj$session$runs)
  stopifnot(identical(as.character(cv_space), "umap.peakvi_space"))

  # Promotion/load roundtrip for projected curves and promoted monocle3 model.
  prom <- wb_session_promote_current(
    bundle = b,
    session = r_proj$session,
    name_prefix = "monocle3_project_contract",
    created_by = "test",
    outputs = list(
      wb_ref_run(r_proj$run$run_id, "curves"),
      wb_ref_run(r_fit$run$run_id, "model")
    ),
    fail_fast = TRUE
  )
  ok_curves <- prom$promoted[
    as.character(prom$promoted$status %||% "") == "ok" &
      as.character(prom$promoted$output %||% "") == "curves",
    ,
    drop = FALSE
  ]
  stopifnot(nrow(ok_curves) == 1L)
  cv_art <- wb_art_load(b, as.character(ok_curves$artifact_id[1]), expected_kind = "path_2d_family")
  stopifnot(inherits(cv_art, "wb_primitive"), identical(as.character(cv_art$kind), "path_2d_family"))

  ok_model <- prom$promoted[
    as.character(prom$promoted$status %||% "") == "ok" &
      as.character(prom$promoted$output %||% "") == "model" &
      as.character(prom$promoted$op_name %||% "") == "monocle3_fit",
    ,
    drop = FALSE
  ]
  stopifnot(nrow(ok_model) == 1L)
  mr_art <- wb_art_load(b, as.character(ok_model$artifact_id[1]), expected_kind = "model_ref")
  stopifnot(identical(as.character(mr_art$engine), "monocle3"))
  stopifnot(!is.null(mr_art$model_obj))

  # Continue from promoted model should also work.
  s2 <- wb_session_new()
  r_proj2 <- wb_session_run_op(
    session = s2,
    bundle = b,
    op_name = "monocle3_project",
    inputs = list(
      model = wb_ref_artifact(as.character(ok_model$artifact_id[1]), "model"),
      plot_space = wb_prim_space_2d("umap.peakvi_space"),
      approx_points = 120L
    ),
    notes = "contract test monocle3_project from promoted model"
  )
  cv2 <- r_proj2$run$outputs$curves
  stopifnot(inherits(cv2, "wb_primitive"), identical(as.character(cv2$kind), "path_2d_family"))
  stopifnot(length(cv2$key) > 0L)

  TRUE
}
