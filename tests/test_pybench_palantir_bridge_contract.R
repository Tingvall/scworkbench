test_pybench_palantir_bridge_contract <- function(bundle_dir,
                                                  pybench_python = .wb_pybench_default_python()) {
  if (!file.exists(pybench_python)) {
    return(contract_test_skip(paste("Pybench interpreter not found at", pybench_python)))
  }
  b <- wb_open_bundle(bundle_dir)
  workspace <- tempfile("scwb_palantir_v2_sessions_")
  on.exit({ try(wb_close_bundle(b), silent = TRUE); unlink(workspace, recursive = TRUE, force = TRUE) }, add = TRUE)
  core <- as.character(wb_cells(b, "core"))
  stopifnot(length(core) >= 300L)
  cells <- head(core, 800L)
  s <- wb_session_create(b, workspace, session_id = "palantir_v2")
  rr <- wb_session_run_op(s, b, "palantir_fit", inputs = list(
    fit_space = "peakvi_space", cell_set = "core", root_cell = cells[1],
    terminal_cells = cells[c(2, 3)], dims = 1:20, knn = 30L,
    n_diffusion_components = 10L, n_waypoints = 100L, seed = 20L,
    min_cells = 10L
  ))
  staged <- rr$run$outputs
  stopifnot(all(c("pseudotime", "branch_membership", "branch_summary", "entropy", "model") %in% names(staged)),
            identical(staged$pseudotime$kind, "cell_vector"),
            identical(staged$branch_membership$kind, "relation_family"),
            identical(staged$branch_summary$kind, "obs_table"),
            identical(staged$model$kind, "model_ref"))
  session_workspace <- rr$session$durable$workspace
  run_id <- rr$run$run_id
  wb_close_bundle(b); b <- wb_open_bundle(bundle_dir)
  resumed <- wb_session_resume(b, session_workspace)
  stopifnot(identical(resumed$head_run_id, run_id))
  promoted <- wb_session_promote_current(b, resumed,
    outputs = c("pseudotime", "branch_membership", "branch_summary", "entropy", "model"),
    created_by = "pybench-palantir-v2-contract")
  stopifnot(all(promoted$promoted$status == "ok"), promoted$session$durable$state == "promoted")
  ids <- stats::setNames(as.character(promoted$promoted$artifact_id), as.character(promoted$promoted$output_name))
  wb_close_bundle(b); b <- wb_open_bundle(bundle_dir)
  pt <- wb_art_load(b, ids[["pseudotime"]], "cell_vector")
  bm <- wb_art_load(b, ids[["branch_membership"]], "relation_family")
  bs <- wb_art_load(b, ids[["branch_summary"]], "obs_table")
  en <- wb_art_load(b, ids[["entropy"]], "cell_vector")
  mr <- wb_art_load(b, ids[["model"]], "model_ref")
  stopifnot(length(pt$cell_id) == length(core), length(en$cell_id) == length(core),
            nrow(wb_primitive_to_table(bm, include_context = FALSE)) > 0L,
            is.data.frame(bs$table), identical(mr$engine, "palantir"),
            file.exists(mr$model_path))
  TRUE
}
