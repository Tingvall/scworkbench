test_session_dag_contract <- function(bundle_dir = NULL) {
  s <- wb_session_new()

  cl <- c("A" = "c1", "B" = "c1", "C" = "c2")
  r1 <- wb_new_run(
    op_name = "synthetic_core_categorical_labels",
    inputs = list(
      cell_set = "all",
      effective_n = 3L,
      parents = character(0),
      provenance_refs = list(),
      user_inputs = list(k = 20L)
    ),
    params = list(resolution = 0.8),
    outputs = list(clusters = wb_prim_cell_vector(cl)),
    notes = "cluster run"
  )

  r2 <- wb_new_run(
    op_name = "synthetic_dependent_feature_table_run",
    inputs = list(
      cell_set = "all",
      effective_n = 3L,
      parents = c(r1$run_id),
      provenance_refs = list(),
      user_inputs = list(
        clusters_ref = wb_ref_run(r1$run_id, "clusters"),
        legacy_art_ref = wb_ref_artifact("artifact_fake_1", "clusters")
      )
    ),
    params = list(top_n = 10L),
    outputs = list(
      result = wb_prim_feature_table(
        table = data.frame(feature_id = c("g1", "g2"), score = c(1, 2), stringsAsFactors = FALSE),
        table_type = "synthetic_dependent_feature_table"
      )
    ),
    notes = "markers run"
  )

  s <- wb_session_add_run(s, r1)
  s <- wb_session_add_run(s, r2)
  s <- wb_session_set_active(s, "clusters", wb_ref_run(r1$run_id, "clusters"))
  s <- wb_session_set_active(s, "result", wb_ref_run(r2$run_id, "result"))

  dag <- wb_session_dag(s, include_artifacts = FALSE, include_active = TRUE)
  stopifnot(is.list(dag), is.data.frame(dag$nodes), is.data.frame(dag$edges))
  stopifnot(length(dag$run_order) >= 2)
  stopifnot(dag$run_order[1] == r1$run_id)
  stopifnot(dag$run_order[2] == r2$run_id)

  run_nodes <- dag$nodes[dag$nodes$node_type == "run", , drop = FALSE]
  stopifnot(nrow(run_nodes) == 2)
  stopifnot(all(paste0("run:", c(r1$run_id, r2$run_id)) %in% run_nodes$id))

  dep <- dag$edges[
    dag$edges$edge_type == "depends_on_run" &
      dag$edges$from == paste0("run:", r1$run_id) &
      dag$edges$to == paste0("run:", r2$run_id),
    ,
    drop = FALSE
  ]
  stopifnot(nrow(dep) == 1)

  active_edges <- dag$edges[dag$edges$edge_type == "binds_active", , drop = FALSE]
  stopifnot(nrow(active_edges) >= 2)

  det <- wb_session_dag_run_details(s, r2$run_id)
  stopifnot(is.list(det), is.list(det$run))
  stopifnot(identical(det$run$run_id, r2$run_id))
  stopifnot("top_n" %in% names(det$run$params))
  stopifnot(r1$run_id %in% det$parents)
  stopifnot("result" %in% det$active_bindings)
  stopifnot(is.data.frame(det$input_refs), nrow(det$input_refs) >= 2)
  stopifnot(any(det$input_refs$ref_type == "run"))
  stopifnot(any(det$input_refs$ref_type == "artifact"))
  stopifnot(is.data.frame(det$outputs))
  stopifnot(any(det$outputs$output == "result"))

  TRUE
}
