test_derived_cell_set_lifecycle_contract <- function() {
  tmp <- tempfile("scwb_derived_cell_set_")
  b <- wb_init_bundle(tmp, overwrite = TRUE)
  on.exit({
    options(scworkbench.registry_replay_hook = NULL)
    try(wb_close_bundle(b), silent = TRUE)
    unlink(tmp, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  cells <- paste0("c", seq_len(8))
  meta <- data.frame(
    cell_id = cells,
    dataset_id = "dataset_1",
    lineage = c("B", "B", "B", "T", "B", "B", "M", "B"),
    phase_score = c(0.1, 0.8, 0.3, 0.7, 0.9, 0.2, 0.5, 0.95),
    stringsAsFactors = FALSE
  )
  wb_define_cells(b, cells, metadata = meta, dataset_id = meta$dataset_id)

  wb_cell_set_replace(
    bundle = b,
    cell_set = "set:exclude_doublets",
    cell_ids = c("c2", "c7"),
    source = "test",
    created_by = "test",
    description = "Synthetic exclusion set"
  )

  score <- c(0.05, 0.40, 0.82, 0.91, 0.76, 0.15, 0.88, 0.93)
  names(score) <- cells
  score_run <- wb_new_run(
    op_name = "test_vector",
    inputs = list(cell_set = "all", parents = character(0), provenance_refs = list(), user_inputs = list()),
    params = list(),
    outputs = list(score = wb_prim_cell_vector(score, value_type = "continuous")),
    notes = "derived cell-set numeric vector threshold fixture"
  )
  score_artifact_id <- scworkbench:::.wb_promote_cell_vector(
    bundle = b,
    run = score_run,
    out_name = "score",
    prim = score_run$outputs$score,
    created_by = "test"
  )
  score_ref <- paste0("artifact:", as.character(score_artifact_id))

  b_cells <- wb_sel_meta(b, col = "lineage", values = "B")
  high_score <- wb_sel_vector(b_cells, vector_id = score_ref, min = 0.75)
  excluded_in_high_score <- wb_sel_set(high_score, sets = "set:exclude_doublets")
  derived_cells <- wb_sel_not(excluded_in_high_score, universe = high_score)

  stopifnot(identical(as.character(derived_cells), c("c3", "c5", "c8")))
  stopifnot(!is.null(wb_sel_recipe(derived_cells)))

  res <- wb_cell_set_derive(
    bundle = b,
    cell_set = "set:test_claim_universe",
    cells = derived_cells,
    role = "analysis_universe",
    status = "candidate",
    created_by = "test",
    description = "B lineage high-score universe excluding synthetic doublets"
  )
  stopifnot(is.list(res), is.list(res$outputs))
  stopifnot(identical(as.character(res$outputs$manifest$table_type), "derived_cell_set_manifest"))
  stopifnot(identical(as.character(res$outputs$rule_table$table_type), "derived_cell_set_rules"))
  stopifnot(identical(as.character(wb_cells(b, cell_set = "set:test_claim_universe")), c("c3", "c5", "c8")))

  recipe_row <- wb_get_cell_set_recipe(b, "set:test_claim_universe")
  stopifnot(nrow(recipe_row) == 1L)
  stopifnot(identical(as.character(recipe_row$role[1]), "analysis_universe"))
  stopifnot(identical(as.character(recipe_row$status[1]), "candidate"))

  manifest <- res$outputs$manifest$table
  stopifnot(nrow(manifest) == 1L)
  stopifnot(identical(as.character(manifest$cell_set[1]), "set:test_claim_universe"))
  stopifnot(identical(as.character(manifest$role[1]), "analysis_universe"))
  stopifnot(identical(as.character(manifest$status[1]), "candidate"))
  stopifnot(identical(as.integer(manifest$n_cells[1]), 3L))
  stopifnot(isTRUE(manifest$recipe_available[1]))
  stopifnot(nzchar(as.character(manifest$recipe_json[1])))

  rules <- res$outputs$rule_table$table
  stopifnot(nrow(rules) >= 4L)
  stopifnot(any(as.character(rules$rule_type) == "wb_sel_meta"))
  stopifnot(any(as.character(rules$rule_type) == "wb_sel_vector"))
  stopifnot(any(as.character(rules$rule_type) == "wb_sel_set"))
  stopifnot(any(as.character(rules$rule_type) == "wb_sel_not"))
  not_rule <- rules[as.character(rules$rule_type) == "wb_sel_not", , drop = FALSE][1, , drop = FALSE]
  stopifnot(identical(as.integer(not_rule$output_n[1]), 3L))
  vec_rule <- rules[as.character(rules$rule_type) == "wb_sel_vector", , drop = FALSE][1, , drop = FALSE]
  stopifnot(identical(as.character(vec_rule$operator[1]), "range"))
  stopifnot(grepl("0.75", as.character(vec_rule$value[1]), fixed = TRUE))

  s <- wb_session_new()
  r_label <- wb_session_run_op(
    session = s,
    bundle = b,
    op_name = "cell_suffix_label",
    inputs = list(
      cell_set = "set:test_claim_universe",
      min_cells = 1L,
      sep = "c",
      default_label = "unknown"
    ),
    notes = "downstream op consuming derived set"
  )
  label_tbl <- r_label$run$outputs$label_table$table
  stopifnot(nrow(label_tbl) == 3L)
  stopifnot(setequal(as.character(label_tbl$cell_id), c("c3", "c5", "c8")))

  r_derive <- wb_session_run_op(
    session = wb_session_new(),
    bundle = b,
    op_name = "cell_set_derive",
    inputs = list(
      cell_set = "set:test_claim_universe",
      min_cells = 1L,
      target_cell_set = "set:test_claim_universe_session",
      role = "analysis_universe",
      status = "candidate",
      created_by = "test",
      description = "Session-level derived cell-set contract fixture"
    ),
    notes = "session-derived cell-set fixture"
  )
  stopifnot(identical(as.character(r_derive$run$outputs$manifest$table_type), "derived_cell_set_manifest"))
  stopifnot(identical(
    as.character(wb_cells(wb_session_view(r_derive$session), cell_set = "set:test_claim_universe_session")),
    c("c3", "c5", "c8")
  ))

  prom <- wb_session_promote_current(
    bundle = b,
    session = r_derive$session,
    name_prefix = "Derived Cell Set Contract",
    created_by = "test",
    fail_fast = TRUE,
    outputs = "manifest"
  )
  manifest_artifact_id <- as.character(prom$promoted$artifact_id[
    as.character(prom$promoted$output) == "manifest"
  ][1])
  stopifnot(nzchar(manifest_artifact_id))
  loaded_manifest <- wb_art_load(b, manifest_artifact_id, expected_kind = "obs_table")
  stopifnot(identical(as.character(loaded_manifest$table_type), "derived_cell_set_manifest"))
  wb_close_bundle(b); b <- wb_open_bundle(tmp)
  stopifnot(identical(
    as.character(wb_cells(b, cell_set = "set:test_claim_universe_session")),
    c("c3", "c5", "c8")
  ))
  promoted_recipe <- wb_get_cell_set_recipe(b, "set:test_claim_universe_session")
  stopifnot(nrow(promoted_recipe) == 1L)
  stopifnot(identical(as.character(promoted_recipe$role[1]), "analysis_universe"))
  stopifnot(identical(as.character(promoted_recipe$status[1]), "candidate"))

  dag <- wb_prov_bundle_dag(b)
  stopifnot(any(
    as.character(dag$edges$artifact_id) == manifest_artifact_id &
      as.character(dag$edges$edge_type) == "MUTATES_REGISTRY" &
      as.character(dag$edges$to) == "cell_set:set:test_claim_universe_session"
  ))

  replay_events <- DBI::dbGetQuery(
    b$con,
    "SELECT registry_type, action FROM prov_registry_mutations WHERE run_id = ? ORDER BY registry_type;",
    params = list(r_derive$run$run_id)
  )
  stopifnot(setequal(as.character(replay_events$registry_type), c("cell_set", "cell_set_recipe")))

  failed_derive <- wb_session_run_op(
    wb_session_new(), b, "cell_set_derive",
    inputs = list(
      cell_set = "set:test_claim_universe",
      min_cells = 1L,
      target_cell_set = "set:test_claim_universe_rollback",
      role = "analysis_universe",
      status = "candidate",
      created_by = "test"
    )
  )
  artifact_n_before <- nrow(wb_art_list(b))
  commit_n_before <- DBI::dbGetQuery(b$con, "SELECT COUNT(*) AS n FROM prov_commits;")$n[1]
  replay_calls <- 0L
  options(scworkbench.registry_replay_hook = function(event) {
    replay_calls <<- replay_calls + 1L
    if (replay_calls == 2L) stop("forced cell-set recipe replay failure", call. = FALSE)
  })
  failed_promotion <- try(
    wb_session_promote_current(
      b, failed_derive$session, outputs = "manifest", created_by = "test"
    ),
    silent = TRUE
  )
  options(scworkbench.registry_replay_hook = NULL)
  stopifnot(inherits(failed_promotion, "try-error"), replay_calls == 2L)
  stopifnot(!nrow(DBI::dbGetQuery(
    b$con,
    "SELECT 1 FROM cell_set_membership WHERE cell_set = 'set:test_claim_universe_rollback' LIMIT 1;"
  )))
  stopifnot(!nrow(wb_get_cell_set_recipe(b, "set:test_claim_universe_rollback")))
  stopifnot(nrow(wb_art_list(b)) == artifact_n_before)
  stopifnot(DBI::dbGetQuery(b$con, "SELECT COUNT(*) AS n FROM prov_commits;")$n[1] == commit_n_before)

  TRUE
}
