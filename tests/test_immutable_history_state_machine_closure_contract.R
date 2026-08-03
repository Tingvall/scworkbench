test_immutable_history_state_machine_closure_contract <- function(bundle_dir) {
  stopifnot(
    requireNamespace("BPCells", quietly = TRUE),
    requireNamespace("uwot", quietly = TRUE),
    requireNamespace("digest", quietly = TRUE)
  )

  b <- wb_open_bundle(bundle_dir)
  on.exit(try(wb_close_bundle(b), silent = TRUE), add = TRUE)
  matrix_id <- as.character(wb_matrices(b)$matrix_id[1])

  promote_set <- function(target, source = "set:sample_A", prefix = "state_machine") {
    executed <- wb_session_run_op(
      wb_session_new(), b, "cell_set_derive",
      inputs = list(
        cell_set = source,
        target_cell_set = target,
        role = "analysis_universe",
        status = "accepted",
        overwrite = TRUE,
        min_cells = 1L,
        created_by = "contract"
      )
    )
    promoted <- wb_session_promote_current(
      b, executed$session, outputs = "manifest",
      name_prefix = prefix, created_by = "contract"
    )
    list(executed = executed, promoted = promoted)
  }

  # The golden fixture's sample set is real retained development state but is
  # not provenance-bound. Promotion must atomically turn ephemeral into a
  # content-identified current claim.
  ephemeral_promote_id <- "set:sample_A"
  stopifnot(
    identical(wb_entity_lifecycle(b, "cell_set", ephemeral_promote_id)$provenance_bound[1], 0L)
  )
  wb_entity_mark_ephemeral(
    b, "cell_set", ephemeral_promote_id,
    reason = "Fresh-bundle development set selected by the closure contract."
  )
  stopifnot(
    !(ephemeral_promote_id %in% wb_cell_sets(b)),
    ephemeral_promote_id %in% wb_cell_sets(b, include_history = TRUE),
    length(wb_cells(b, ephemeral_promote_id)) > 0L
  )

  prepared <- wb_session_run_op(
    wb_session_new(), b, "cell_set_derive",
    inputs = list(
      cell_set = ephemeral_promote_id,
      target_cell_set = ephemeral_promote_id,
      role = "analysis_universe",
      status = "accepted",
      overwrite = TRUE,
      min_cells = 1L,
      created_by = "contract"
    )
  )
  before_failed <- wb_entity_lifecycle(b, "cell_set", ephemeral_promote_id)
  before_registry_bindings <- if (DBI::dbExistsTable(b$con, "prov_registry_mutations")) {
    nrow(DBI::dbGetQuery(
      b$con,
      "SELECT * FROM prov_registry_mutations WHERE registry_key_json LIKE ?;",
      params = list(paste0("%", ephemeral_promote_id, "%"))
    ))
  } else 0L
  old_hook <- getOption("scworkbench.promotion_workspace_publish_hook")
  on.exit(options(scworkbench.promotion_workspace_publish_hook = old_hook), add = TRUE)
  options(scworkbench.promotion_workspace_publish_hook = function(...) {
    stop("forced lifecycle publish failure", call. = FALSE)
  })
  failed <- try(
    wb_session_promote_current(
      b, prepared$session, outputs = "manifest",
      name_prefix = "state_machine_rollback", created_by = "contract"
    ),
    silent = TRUE
  )
  options(scworkbench.promotion_workspace_publish_hook = old_hook)
  after_failed <- wb_entity_lifecycle(b, "cell_set", ephemeral_promote_id)
  after_registry_bindings <- if (DBI::dbExistsTable(b$con, "prov_registry_mutations")) {
    nrow(DBI::dbGetQuery(
      b$con,
      "SELECT * FROM prov_registry_mutations WHERE registry_key_json LIKE ?;",
      params = list(paste0("%", ephemeral_promote_id, "%"))
    ))
  } else 0L
  stopifnot(
    inherits(failed, "try-error"),
    grepl("forced lifecycle publish failure", as.character(failed), fixed = TRUE),
    identical(before_failed$lifecycle_state, after_failed$lifecycle_state),
    identical(before_failed$provenance_bound, after_failed$provenance_bound),
    identical(before_failed$identity_hash, after_failed$identity_hash),
    identical(before_registry_bindings, after_registry_bindings)
  )

  promoted_ephemeral <- wb_session_promote_current(
    b, prepared$session, outputs = "manifest",
    name_prefix = "state_machine_ephemeral", created_by = "contract"
  )
  promoted_ephemeral_artifact <- as.character(
    promoted_ephemeral$promoted$artifact_id[promoted_ephemeral$promoted$status == "ok"][1]
  )
  wb_close_bundle(b)
  b <- wb_open_bundle(bundle_dir)
  promoted_state <- wb_entity_lifecycle(b, "cell_set", ephemeral_promote_id)
  stopifnot(
    identical(promoted_state$lifecycle_state[1], "current"),
    identical(promoted_state$provenance_bound[1], 1L),
    !is.na(promoted_state$identity_hash[1]),
    grepl("^[0-9a-f]{64}$", promoted_state$identity_hash[1]),
    ephemeral_promote_id %in% wb_cell_sets(b),
    paste0("cell_set:", ephemeral_promote_id) %in%
      wb_prov_bundle_dag(b, include_superseded = FALSE)$nodes$id
  )

  # Conflicting content identity is rejected without inserting a provenance
  # binding or changing lifecycle state.
  before_conflict <- promoted_state
  conflict <- try(DBI::dbWithTransaction(b$con, {
    scworkbench:::.wb_prov_insert_entity_binding(
      b$con, "closure_conflict", NA_character_, "closure_conflict_run",
      "output", "set", "cell_set", ephemeral_promote_id, "MATERIALIZES",
      content_hash = paste(rep("0", 64L), collapse = ""), source = "contract"
    )
  }), silent = TRUE)
  stopifnot(
    inherits(conflict, "try-error"),
    grepl("Conflicting immutable identity hash", as.character(conflict), fixed = TRUE),
    identical(before_conflict$identity_hash, wb_entity_lifecycle(b, "cell_set", ephemeral_promote_id)$identity_hash)
  )

  # Supersession candidates must be promoted first. The fixture effector set is
  # current but unbound, then explicitly ephemeral; both attempts must fail.
  predecessor <- "set:.__closure_generation_b__."
  generation_a <- "set:effector"
  generation_c <- "set:.__closure_generation_c__."
  promote_set(predecessor, prefix = "closure_generation_b")
  unbound_supersession <- try(wb_entity_supersede(
    b, "cell_set", generation_a, predecessor,
    reason = "must fail while unbound", created_by = "contract"
  ), silent = TRUE)
  wb_entity_mark_ephemeral(
    b, "cell_set", generation_a,
    reason = "Candidate remains development-only until promoted."
  )
  ephemeral_supersession <- try(wb_entity_supersede(
    b, "cell_set", generation_a, predecessor,
    reason = "must fail while ephemeral", created_by = "contract"
  ), silent = TRUE)
  stopifnot(
    inherits(unbound_supersession, "try-error"),
    inherits(ephemeral_supersession, "try-error"),
    grepl("Promote an unbound or ephemeral candidate first", as.character(unbound_supersession), fixed = TRUE),
    grepl("Promote an unbound or ephemeral candidate first", as.character(ephemeral_supersession), fixed = TRUE)
  )

  promote_set(generation_a, source = generation_a, prefix = "closure_generation_a")
  wb_entity_supersede(
    b, "cell_set", generation_a, predecessor,
    reason = "Promoted generation A replaces generation B.", created_by = "contract"
  )
  promote_set(generation_c, prefix = "closure_generation_c")
  wb_entity_supersede(
    b, "cell_set", generation_c, generation_a,
    reason = "Promoted generation C replaces generation A.", created_by = "contract"
  )
  chain <- wb_entity_supersessions(b)
  chain <- chain[
    chain$successor_kind == "cell_set" &
      chain$successor_id %in% c(generation_a, generation_c),
    , drop = FALSE
  ]
  stopifnot(
    nrow(chain) == 2L,
    any(chain$successor_id == generation_a & chain$predecessor_id == predecessor),
    any(chain$successor_id == generation_c & chain$predecessor_id == generation_a),
    identical(wb_entity_lifecycle(b, "cell_set", generation_c)$lifecycle_state[1], "current"),
    identical(wb_entity_lifecycle(b, "cell_set", generation_a)$lifecycle_state[1], "superseded"),
    identical(wb_entity_lifecycle(b, "cell_set", predecessor)$lifecycle_state[1], "superseded"),
    length(wb_cells(b, generation_c)) > 0L,
    length(wb_cells(b, generation_a)) > 0L,
    length(wb_cells(b, predecessor)) > 0L
  )

  # Prepare the remaining terminal/current-view states using retained fixture
  # identities, then prove the central binding path cannot revive any of them.
  rejected_id <- "set:il7"
  retracted_id <- "set:.__closure_retracted__."
  promote_set(retracted_id, prefix = "closure_retracted")
  wb_entity_reject(b, "cell_set", rejected_id, reason = "Rejected closure candidate.")
  wb_entity_retract(b, "cell_set", retracted_id, reason = "Retracted closure candidate.")
  historical_ids <- c(predecessor, rejected_id, retracted_id)
  historical_states <- c("superseded", "rejected", "retracted")
  for (i in seq_along(historical_ids)) {
    id <- historical_ids[[i]]
    before <- wb_entity_lifecycle(b, "cell_set", id)
    before_n <- DBI::dbGetQuery(
      b$con,
      "SELECT COUNT(*) AS n FROM prov_run_entity_bindings WHERE snapshot_id = ?;",
      params = list(paste0("closure_historical_", i))
    )$n[1]
    attempt <- try(DBI::dbWithTransaction(b$con, {
      scworkbench:::.wb_prov_insert_entity_binding(
        b$con, paste0("closure_historical_", i), NA_character_, paste0("closure_run_", i),
        "output", "historical", "cell_set", id, "MATERIALIZES",
        content_hash = before$identity_hash[1], source = "contract"
      )
    }), silent = TRUE)
    after <- wb_entity_lifecycle(b, "cell_set", id)
    after_n <- DBI::dbGetQuery(
      b$con,
      "SELECT COUNT(*) AS n FROM prov_run_entity_bindings WHERE snapshot_id = ?;",
      params = list(paste0("closure_historical_", i))
    )$n[1]
    stopifnot(
      inherits(attempt, "try-error"),
      grepl("Historical identifiers cannot be revived", as.character(attempt), fixed = TRUE),
      identical(before$lifecycle_state[1], historical_states[[i]]),
      identical(before$lifecycle_state, after$lifecycle_state),
      identical(before$provenance_bound, after$provenance_bound),
      identical(before$identity_hash, after$identity_hash),
      identical(before_n, after_n)
    )
  }

  # Keep one explicit ephemeral feature set for the unified current-view rule.
  ephemeral_feature_name <- "golden_activation"
  ephemeral_feature_id <- paste0(matrix_id, "::", ephemeral_feature_name)
  feature_members <- wb_feature_set_get(b, ephemeral_feature_name, matrix_id)
  wb_entity_mark_ephemeral(
    b, "feature_set", ephemeral_feature_id,
    reason = "Unselected feature-set development state."
  )

  # Produce a genuine stored model, then retain it and its space as terminal
  # history. Direct getters must still resolve both payloads.
  model_id <- ".__closure_umap_model__."
  fitted <- wb_session_run_op(
    wb_session_new(), b, "umap_fit",
    inputs = list(
      space = "lsi", space_id_out = model_id, dims = 1:4,
      n_neighbors = 10L, min_dist = 0.2, nn_method = "annoy",
      seed = 811L, cell_set = "all"
    )
  )
  wb_session_promote_current(
    b, fitted$session, outputs = c("model", "space_2d"),
    name_prefix = "closure_model", created_by = "contract"
  )
  model_path <- wb_space_model_path(b, model_id)
  model_hash <- digest::digest(file = model_path, algo = "sha256")
  model_coords <- wb_space(b, model_id)
  wb_entity_reject(b, "model", model_id, reason = "Rejected model candidate.")
  wb_entity_retract(b, "space", model_id, reason = "Retracted fitted coordinate claim.")

  # Artifact discovery now defaults to current. Retraction preserves direct
  # payload and birth-certificate content evidence.
  artifact_before <- wb_art_load(b, promoted_ephemeral_artifact)
  birth_before <- wb_art_birth_certificate(b, promoted_ephemeral_artifact)
  wb_art_delete(b, promoted_ephemeral_artifact)
  artifact_after <- wb_art_load(b, promoted_ephemeral_artifact)
  birth_after <- wb_art_birth_certificate(b, promoted_ephemeral_artifact)

  # The matrix registry follows the same current/history rule. Perform this
  # last so no later operation depends on the now-historical source claim.
  matrix_before <- wb_matrix_info(b, matrix_id)
  wb_entity_reject(b, "matrix", matrix_id, reason = "Rejected matrix claim for view coverage.")

  stopifnot(
    !(ephemeral_feature_name %in% wb_feature_sets(b, matrix_id = matrix_id)$feature_set),
    ephemeral_feature_name %in% wb_feature_sets(b, matrix_id = matrix_id, include_history = TRUE)$feature_set,
    identical(wb_feature_set_get(b, ephemeral_feature_name, matrix_id), feature_members),
    !(generation_a %in% wb_cell_sets(b)),
    !(predecessor %in% wb_cell_sets(b)),
    !(rejected_id %in% wb_cell_sets(b)),
    !(retracted_id %in% wb_cell_sets(b)),
    all(c(generation_a, predecessor, rejected_id, retracted_id) %in% wb_cell_sets(b, include_history = TRUE)),
    !(model_id %in% wb_spaces_with_model(b)),
    model_id %in% wb_spaces_with_model(b, include_history = TRUE),
    identical(digest::digest(file = wb_space_model_path(b, model_id), algo = "sha256"), model_hash),
    nrow(wb_space_model(b, model_id)) == 1L,
    !(model_id %in% wb_spaces(b)$space_id),
    model_id %in% wb_spaces(b, include_history = TRUE)$space_id,
    identical(wb_space(b, model_id), model_coords),
    !(promoted_ephemeral_artifact %in% wb_art_list(b)$artifact_id),
    promoted_ephemeral_artifact %in% wb_art_list(b, include_history = TRUE)$artifact_id,
    identical(artifact_before$kind, artifact_after$kind),
    identical(
      as.character(birth_before$persisted_provenance$links$content_sha256[1]),
      as.character(birth_after$persisted_provenance$links$content_sha256[1])
    ),
    identical(birth_after$lifecycle$state, "retracted"),
    !(matrix_id %in% wb_matrices(b)$matrix_id),
    matrix_id %in% wb_matrices(b, include_history = TRUE)$matrix_id,
    nrow(wb_matrix_info(b, matrix_id)) == nrow(matrix_before)
  )

  lifecycle <- wb_entity_lifecycle(b, include_history = TRUE)
  noncurrent <- lifecycle[lifecycle$lifecycle_state != "current", , drop = FALSE]
  dag_current <- wb_prov_bundle_dag(b, include_superseded = FALSE)
  dag_history <- wb_prov_bundle_dag(b, include_superseded = TRUE)
  noncurrent_node_ids <- paste0(noncurrent$entity_kind, ":", noncurrent$entity_id)
  stopifnot(
    !any(noncurrent_node_ids %in% dag_current$nodes$id),
    any(dag_current$nodes$node_type == "run"),
    any(dag_current$nodes$node_type == "snapshot"),
    all(noncurrent_node_ids %in% dag_history$nodes$id),
    sum(dag_history$edges$edge_type == "SUPERSEDES") >= 2L,
    all(c("current", "ephemeral", "superseded", "rejected", "retracted") %in% lifecycle$lifecycle_state)
  )

  TRUE
}
