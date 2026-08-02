test_promoted_workflow_continue_replay_contract <- function(bundle_dir) {
  b <- wb_open_bundle(bundle_dir)
  on.exit(wb_close_bundle(b), add = TRUE)

  mats <- wb_matrices(b)
  stopifnot(is.data.frame(mats), nrow(mats) >= 1)
  mid <- as.character(mats$matrix_id[1])

  cells <- wb_cells(b)
  feats <- wb_feature_ids(b, matrix_id = mid)
  if (length(cells) < 20L || length(feats) < 60L) {
    return(contract_test_skip("Fixture has fewer than 20 cells or 60 features."))
  }

  # Small synthetic namespace for fast pathway_enrich on top of a small DE table.
  ns <- paste0("test_continue_promote_", paste0(sample(c(letters, 0:9), 8, TRUE), collapse = ""))
  wb_feature_set_replace(
    bundle = b,
    feature_set = "set_alpha",
    matrix_id = mid,
    feature_ids = as.character(feats[1:20]),
    created_by = "test",
    namespace = ns,
    origin = "test",
    strict = TRUE
  )
  wb_feature_set_replace(
    bundle = b,
    feature_set = "set_beta",
    matrix_id = mid,
    feature_ids = as.character(feats[21:40]),
    created_by = "test",
    namespace = ns,
    origin = "test",
    strict = TRUE
  )

  # Stage 1: run + promote DE on a tiny feature/cell subset for speed.
  s1 <- wb_session_new()
  rr1 <- wb_session_run_op(
    session = s1,
    bundle = b,
    op_name = "de_wilcox",
    inputs = list(
      matrix = mid,
      group_a = as.character(cells[1:8]),
      group_b = as.character(cells[9:16]),
      features = as.character(feats[1:40]),
      min_pct = 0,
      p_adjust_method = "BH"
    ),
    notes = "test continue-promote stage1 de"
  )
  s1 <- rr1$session

  p1 <- wb_promote_analysis(
    bundle = b,
    runs = s1$runs,
    head_run_id = s1$head_run_id,
    name_prefix = "test_continue_promote_stage1",
    created_by = "test",
    fail_fast = TRUE
  )
  stopifnot(is.data.frame(p1$promoted), nrow(p1$promoted) >= 1)
  de_rows <- p1$promoted[
    as.character(p1$promoted$status %||% "") == "ok" &
      as.character(p1$promoted$output %||% "") == "de_table",
    ,
    drop = FALSE
  ]
  stopifnot(nrow(de_rows) == 1)
  de_art_id <- as.character(de_rows$artifact_id[1])
  stopifnot(nzchar(de_art_id))

  # Stage 2: continue analysis from promoted DE artifact (inline ref ergonomics path).
  s2 <- wb_session_new()
  rr2 <- wb_session_run_op(
    session = s2,
    bundle = b,
    op_name = "pathway_enrich",
    inputs = list(
      matrix = mid,
      feature_table = wb_ref_artifact(de_art_id, "de_table"),
      namespace = ns,
      p_adj_col = "__not_present__",
      p_adj_max = 1,
      lfc_col = "__not_present__",
      direction = "any",
      lfc_min_abs = 0,
      min_set_size = 5,
      max_set_size = 5000,
      p_adjust_method = "BH"
    ),
    notes = "test continue-promote stage2 pathway"
  )
  s2 <- rr2$session

  p2 <- wb_promote_analysis(
    bundle = b,
    runs = s2$runs,
    head_run_id = s2$head_run_id,
    name_prefix = "test_continue_promote_stage2",
    created_by = "test",
    fail_fast = TRUE
  )
  stopifnot(is.data.frame(p2$promoted), nrow(p2$promoted) >= 1)
  pw_rows <- p2$promoted[
    as.character(p2$promoted$status %||% "") == "ok" &
      as.character(p2$promoted$output %||% "") == "pathways",
    ,
    drop = FALSE
  ]
  stopifnot(nrow(pw_rows) == 1)
  leaf_art_id <- as.character(pw_rows$artifact_id[1])
  stopifnot(nzchar(leaf_art_id))
  stopifnot(identical(as.character(pw_rows$lineage_status[1]), "complete"))

  # Artifact DAG should capture cross-promotion dependency (de artifact -> pathway artifact).
  deps <- wb_art_dependencies(
    bundle = b,
    artifact_id = leaf_art_id,
    direction = "parents",
    recursive = TRUE
  )
  stopifnot(is.data.frame(deps))
  stopifnot(any(as.character(deps$artifact_id %||% character(0)) == de_art_id))

  # Birth certificate should provide persisted provenance link for the leaf.
  bc <- wb_art_birth_certificate(
    b,
    artifact_id = leaf_art_id,
    include_parents = TRUE,
    include_children = FALSE,
    include_snapshot_run = TRUE
  )
  stopifnot(is.list(bc))
  link <- bc$persisted_provenance$selected_link
  stopifnot(is.data.frame(link), nrow(link) == 1)
  stopifnot(nzchar(as.character(link$snapshot_id[1])))
  stopifnot(nzchar(as.character(link$run_id[1])))

  # Minimal replay script for the leaf artifact should be emitted and target the leaf.
  txt <- wb_art_emit_r_script(
    bundle = b,
    artifact_id = leaf_art_id,
    mode = "symbolic",
    style = "bench_pretty"
  )
  stopifnot(is.character(txt), length(txt) == 1, nzchar(txt))
  stopifnot(grepl("wb_session_run_op", txt, fixed = TRUE))
  stopifnot(grepl(paste0("# target_artifact_id: ", leaf_art_id), txt, fixed = TRUE))
  stopifnot(grepl(de_art_id, txt, fixed = TRUE))

  # Because stage 2 was promoted separately, the minimal replay subgraph should be just that run.
  n_calls <- lengths(regmatches(txt, gregexpr("wb_session_run_op", txt, fixed = TRUE)))
  stopifnot(length(n_calls) == 1, identical(as.integer(n_calls[[1]]), 1L))

  TRUE
}
