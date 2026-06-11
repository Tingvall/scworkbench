test_provenance_bundle_dag_contract <- function(bundle_dir) {
  b <- wb_open_bundle(bundle_dir)
  on.exit(wb_close_bundle(b), add = TRUE)

  r1 <- wb_new_run(
    op_name = "de_wilcox",
    inputs = list(
      cell_set = "all",
      effective_n = 12L,
      parents = character(0),
      user_inputs = list(group_a = "set:a", group_b = "set:b")
    ),
    params = list(min_pct = 0, p_adjust_method = "BH"),
    outputs = list(
      de_table = wb_prim_feature_table(
        table = data.frame(feature_id = c("g1", "g2"), score = c(1.2, 0.4), stringsAsFactors = FALSE),
        table_type = "de_wilcox"
      )
    ),
    notes = "synthetic bundle dag stage 1"
  )
  runs1 <- list()
  runs1[[r1$run_id]] <- r1
  p1 <- wb_promote_analysis(
    bundle = b,
    runs = runs1,
    head_run_id = r1$run_id,
    name_prefix = "bundle_dag_stage1",
    created_by = "test",
    fail_fast = TRUE
  )
  a1 <- p1$promoted$artifact_id[as.character(p1$promoted$output) == "de_table"][1]
  a1 <- as.character(a1)
  stopifnot(nzchar(a1))

  r2 <- wb_new_run(
    op_name = "markers_topn",
    inputs = list(
      cell_set = "all",
      effective_n = 12L,
      parents = character(0),
      provenance_refs = list(feature_table = wb_ref_artifact(a1, "de_table")),
      user_inputs = list(feature_table = wb_ref_artifact(a1, "de_table")),
      symbolic_inputs = list(
        cell_set = "all",
        feature_table = wb_ref_artifact(a1, "de_table")
      )
    ),
    params = list(top_n = 2L),
    outputs = list(
      markers = wb_prim_feature_table(
        table = data.frame(feature_id = c("g1", "g2"), score = c(2.1, 1.4), stringsAsFactors = FALSE),
        table_type = "markers_topn"
      )
    ),
    notes = "synthetic bundle dag stage 2"
  )
  runs2 <- list()
  runs2[[r2$run_id]] <- r2
  p2 <- wb_promote_analysis(
    bundle = b,
    runs = runs2,
    head_run_id = r2$run_id,
    name_prefix = "bundle_dag_stage2",
    created_by = "test",
    fail_fast = TRUE
  )
  a2 <- p2$promoted$artifact_id[as.character(p2$promoted$output) == "markers"][1]
  a2 <- as.character(a2)
  stopifnot(nzchar(a2))

  dag <- wb_prov_bundle_dag(b)
  stopifnot(is.list(dag), identical(as.character(dag$schema), "scworkbench.provenance.bundle_dag.v1"))
  stopifnot(is.data.frame(dag$nodes), is.data.frame(dag$edges))
  expected_node_cols <- c(
    "id", "node_type", "label", "title", "artifact_id", "run_id", "snapshot_id",
    "artifact_type", "primitive_kind", "op_name", "created_at", "status",
    "lineage_status", "canonical", "superseded"
  )
  expected_edge_cols <- c("from", "to", "edge_type", "label", "run_id", "snapshot_id", "artifact_id")
  stopifnot(all(expected_node_cols %in% colnames(dag$nodes)))
  stopifnot(all(expected_edge_cols %in% colnames(dag$edges)))
  stopifnot(any(dag$nodes$id == paste0("artifact:", a1)))
  stopifnot(any(dag$nodes$id == paste0("artifact:", a2)))
  stopifnot(any(dag$nodes$id == paste0("run:", r1$run_id)))
  stopifnot(any(dag$nodes$id == paste0("run:", r2$run_id)))
  stopifnot(any(dag$nodes$node_type == "snapshot"))

  edge_key <- paste(dag$edges$from, dag$edges$to, dag$edges$edge_type, sep = "|")
  stopifnot(any(edge_key == paste(paste0("run:", r1$run_id), paste0("artifact:", a1), "PRODUCES", sep = "|")))
  stopifnot(any(edge_key == paste(paste0("artifact:", a1), paste0("run:", r2$run_id), "CONSUMES", sep = "|")))
  stopifnot(any(edge_key == paste(paste0("run:", r2$run_id), paste0("artifact:", a2), "PRODUCES", sep = "|")))
  stopifnot(any(edge_key == paste(paste0("artifact:", a1), paste0("artifact:", a2), "DERIVED_FROM", sep = "|")))

  lin <- wb_prov_artifact_lineage(b, artifact_id = a2, direction = "upstream")
  stopifnot(is.list(lin), is.data.frame(lin$nodes), is.data.frame(lin$edges))
  stopifnot(any(lin$nodes$id == paste0("artifact:", a1)))
  stopifnot(any(lin$nodes$id == paste0("run:", r2$run_id)))
  stopifnot(any(lin$nodes$id == paste0("artifact:", a2)))

  snap <- wb_prov_bundle_dag(b, snapshot_id = p2$provenance_snapshot_id)
  stopifnot(any(snap$nodes$id == paste0("run:", r2$run_id)))
  stopifnot(!any(snap$nodes$id == paste0("run:", r1$run_id)))

  centered <- wb_prov_bundle_dag(b, artifact_id = a1, direction = "downstream", max_depth = 2L)
  stopifnot(any(centered$nodes$id == paste0("artifact:", a1)))
  stopifnot(any(centered$nodes$id == paste0("run:", r2$run_id)))
  stopifnot(any(centered$nodes$id == paste0("artifact:", a2)))

  TRUE
}
