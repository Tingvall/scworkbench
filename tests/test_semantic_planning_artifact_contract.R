test_semantic_planning_artifact_contract <- function() {
  tmp <- file.path(tempdir(), paste0("scwb_semantic_plan_", as.integer(Sys.time())))
  b <- wb_init_bundle(tmp, overwrite = TRUE)
  on.exit(wb_close_bundle(b), add = TRUE)

  r <- wb_new_run(
    op_name = "feature_set_import",
    inputs = list(
      cell_set = "all",
      effective_n = 100L,
      parents = character(0),
      user_inputs = list(matrix = "RNA_counts", model = "artifact:model")
    ),
    params = list(
      namespace = "immgen",
      score_method = "rank_mean",
      pseudotime_direction = "as_is"
    ),
    outputs = list(
      import_summary = wb_prim_obs_table(
        table = data.frame(
          feature_set = c("metabolism", "signaling"),
          dynamic_score = c(1.2, 0.8),
          curve_class = c("turns_on", "transient"),
          stringsAsFactors = FALSE
        ),
        table_type = "trajectory_geneset_dynamics",
        entity_kind = "feature_set"
      )
    ),
    notes = "synthetic retained trajectory artifact planning test"
  )

  runs <- list()
  runs[[r$run_id]] <- r
  prom <- wb_promote_analysis(
    bundle = b,
    runs = runs,
    head_run_id = r$run_id,
    name_prefix = "Semantic Plan",
    fail_fast = TRUE
  )
  stopifnot(is.data.frame(prom$promoted), nrow(prom$promoted) >= 1)
  aid <- as.character(prom$promoted$artifact_id[1])

  plan <- wb_semantic_plan_artifact_next_steps(b, artifact_id = aid)
  stopifnot(is.list(plan))
  stopifnot(identical(as.character(plan$schema_version), "scworkbench.semantic_artifact_plan.v1"))
  stopifnot(identical(as.character(plan$artifact$table_type), "trajectory_geneset_dynamics"))
  stopifnot(is.data.frame(plan$primitive), any(plan$primitive$record_id == "primitive:obs_table"))
  stopifnot(is.data.frame(plan$wranglers), any(plan$wranglers$record_id == "wrangler:table:client_load_table"))
  stopifnot(is.data.frame(plan$plots), any(plan$plots$record_id == "plot:ranked_lollipop"))
  stopifnot(is.data.frame(plan$recipes), any(plan$recipes$record_id == "recipe:trajectory_geneset_dynamics_discovery"))
  stopifnot(is.data.frame(plan$downstream_ops))
  stopifnot(is.data.frame(plan$graph_edges), nrow(plan$graph_edges) >= 1)
  stopifnot(length(plan$caveats) >= 1)

  TRUE
}
