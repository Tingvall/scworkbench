test_immutable_history_supersession_tombstones_contract <- function(bundle_dir) {
  stopifnot(
    requireNamespace("BPCells", quietly = TRUE),
    requireNamespace("uwot", quietly = TRUE),
    requireNamespace("digest", quietly = TRUE)
  )

  b <- wb_open_bundle(bundle_dir)
  on.exit(try(wb_close_bundle(b), silent = TRUE), add = TRUE)
  cells <- as.character(wb_cells(b, "all"))
  matrix_id <- as.character(wb_matrices(b)$matrix_id[1])
  features <- as.character(wb_feature_ids(b, matrix_id))
  stopifnot(length(cells) >= 20L, length(features) >= 6L)

  # A legacy bundle with provenance but no lifecycle tables reconstructs
  # current/bound identities without changing scientific payloads.
  DBI::dbExecute(b$con, "DROP TABLE entity_tombstones;")
  DBI::dbExecute(b$con, "DROP TABLE entity_supersessions;")
  DBI::dbExecute(b$con, "DROP TABLE entity_lifecycle;")
  wb_migrate_artifacts(b)
  migrated <- wb_entity_lifecycle(b)
  stopifnot(
    any(migrated$entity_kind == "matrix" & migrated$entity_id == matrix_id & migrated$provenance_bound == 1L),
    any(migrated$entity_kind == "space" & migrated$entity_id == "lsi" & migrated$provenance_bound == 1L),
    !any(migrated$entity_kind == "external_source" & migrated$lifecycle_state == "retracted")
  )

  # Matrix identities become immutable once the producing run is promoted.
  matrix_v1 <- ".__lifecycle_matrix_v1__."
  norm <- wb_session_run_op(
    wb_session_new(), b, "matrix_log_normalize",
    inputs = list(matrix = matrix_id, output_matrix_id = matrix_v1, cell_set = "all")
  )
  wb_session_promote_current(
    b, norm$session, outputs = "summary", name_prefix = "lifecycle_matrix",
    created_by = "contract"
  )
  matrix_sha <- scworkbench:::.wb_prov_payload_identity(b, wb_prim_matrix(matrix_v1))$content_sha256
  matrix_replace <- try(wb_session_run_op(
    wb_session_new(), b, "matrix_log_normalize",
    inputs = list(matrix = matrix_id, output_matrix_id = matrix_v1, overwrite = TRUE, cell_set = "all")
  ), silent = TRUE)
  stopifnot(
    inherits(matrix_replace, "try-error"),
    grepl("provenance-bound matrix", as.character(matrix_replace), fixed = TRUE),
    identical(matrix_sha, scworkbench:::.wb_prov_payload_identity(b, wb_prim_matrix(matrix_v1))$content_sha256)
  )

  # Fit and promote a real model/space. Neither model nor coordinates can be
  # replaced at the same identifier after promotion.
  umap_id <- ".__lifecycle_umap_v1__."
  fit <- wb_session_run_op(
    wb_session_new(), b, "umap_fit",
    inputs = list(
      space = "lsi", space_id_out = umap_id, dims = 1:4,
      n_neighbors = 10L, min_dist = 0.2, nn_method = "annoy",
      seed = 123L, cell_set = "all"
    )
  )
  wb_session_promote_current(
    b, fit$session, outputs = c("model", "space_2d"),
    name_prefix = "lifecycle_umap", created_by = "contract"
  )
  lifecycle_after_fit <- wb_entity_lifecycle(b)
  stopifnot(
    any(lifecycle_after_fit$entity_kind == "space" & lifecycle_after_fit$entity_id == umap_id & lifecycle_after_fit$provenance_bound == 1L),
    any(lifecycle_after_fit$entity_kind == "model" & lifecycle_after_fit$entity_id == umap_id & lifecycle_after_fit$provenance_bound == 1L)
  )
  coord_sha <- digest::digest(wb_space(b, umap_id), algo = "sha256")
  model_path <- wb_space_model_path(b, umap_id)
  model_sha <- digest::digest(file = model_path, algo = "sha256")
  model_replace <- try(wb_session_run_op(
    wb_session_new(), b, "umap_fit",
    inputs = list(space = "lsi", space_id_out = umap_id, dims = 1:4,
      n_neighbors = 10L, nn_method = "annoy", seed = 321L, cell_set = "all")
  ), silent = TRUE)
  stopifnot(inherits(model_replace, "try-error"))
  space_replace <- try(wb_session_run_op(
    wb_session_new(), b, "pca_fit",
    inputs = list(matrix = matrix_id, feature_ids = head(features, 8L),
      n_components = 2L, backend = "prcomp", space_id_out = umap_id,
      overwrite = TRUE, cell_set = "all")
  ), silent = TRUE)
  stopifnot(
    inherits(space_replace, "try-error"),
    grepl("provenance-bound space", as.character(space_replace), fixed = TRUE),
    identical(coord_sha, digest::digest(wb_space(b, umap_id), algo = "sha256")),
    identical(model_sha, digest::digest(file = model_path, algo = "sha256"))
  )

  # Projection into a bound fitted identity is rejected; a new output identity
  # is the supported path.
  transform_bound <- try(wb_session_run_op(
    wb_session_new(), b, "umap_transform",
    inputs = list(model = umap_id, in_space = "lsi", dims = 1:4, cell_set = "all")
  ), silent = TRUE)
  stopifnot(inherits(transform_bound, "try-error"))
  projected_id <- ".__lifecycle_umap_projection_v2__."
  projected <- wb_session_run_op(
    wb_session_new(), b, "umap_transform",
    inputs = list(model = umap_id, in_space = "lsi", dims = 1:4,
      space_id_out = projected_id, cell_set = "all")
  )
  wb_session_promote_current(
    b, projected$session, outputs = "space_2d",
    name_prefix = "lifecycle_projection", created_by = "contract"
  )
  stopifnot(projected_id %in% wb_spaces(b)$space_id)

  promote_feature_set <- function(set_name, ids) {
    src <- tempfile(fileext = ".rds")
    saveRDS(data.frame(feature_set = set_name, feature_id = ids, namespace = "lifecycle", stringsAsFactors = FALSE), src)
    run <- wb_session_run_op(
      wb_session_new(), b, "feature_set_import",
      inputs = list(matrix = matrix_id, source_path = src, source_format = "rds",
        namespace = "lifecycle", strict = TRUE, overwrite = TRUE, min_cells = 1L)
    )
    wb_session_promote_current(
      b, run$session, outputs = "import_summary",
      name_prefix = paste0("lifecycle_feature_", set_name), created_by = "contract"
    )
    invisible(run)
  }
  feature_v1 <- ".__lifecycle_feature_v1__."
  feature_v2 <- ".__lifecycle_feature_v2__."
  promote_feature_set(feature_v1, features[1:3])
  feature_replace <- try(promote_feature_set(feature_v1, features[4:6]), silent = TRUE)
  stopifnot(
    inherits(feature_replace, "try-error"),
    grepl("provenance-bound feature_set", as.character(feature_replace), fixed = TRUE),
    identical(wb_feature_set_get(b, feature_v1, matrix_id), features[1:3])
  )
  promote_feature_set(feature_v2, features[4:6])
  wb_entity_supersede(
    b, "feature_set",
    paste0(matrix_id, "::", feature_v2), paste0(matrix_id, "::", feature_v1),
    reason = "A revised feature claim uses a new immutable identifier.", created_by = "contract"
  )

  promote_cell_set <- function(set_name, source_set) {
    run <- wb_session_run_op(
      wb_session_new(), b, "cell_set_derive",
      inputs = list(cell_set = source_set, target_cell_set = set_name,
        role = "analysis_universe", status = "accepted", overwrite = TRUE,
        min_cells = 1L, created_by = "contract")
    )
    wb_session_promote_current(
      b, run$session, outputs = "manifest",
      name_prefix = paste0("lifecycle_cell_", sub("^set:", "", set_name)), created_by = "contract"
    )
    invisible(run)
  }
  cell_v1 <- "set:.__lifecycle_cell_v1__."
  cell_v2 <- "set:.__lifecycle_cell_v2__."
  promote_cell_set(cell_v1, "set:sample_A")
  cell_replace <- try(promote_cell_set(cell_v1, "set:effector"), silent = TRUE)
  stopifnot(
    inherits(cell_replace, "try-error"),
    grepl("provenance-bound cell_set", as.character(cell_replace), fixed = TRUE),
    identical(wb_cells(b, cell_v1), wb_cells(b, "set:sample_A"))
  )
  promote_cell_set(cell_v2, "set:effector")
  wb_entity_supersede(
    b, "cell_set", cell_v2, cell_v1,
    reason = "A revised cell-universe claim uses a new immutable identifier.", created_by = "contract"
  )

  # Promoted artifacts retract through tombstones. Payload content, birth
  # certificate, and reconstruction evidence remain resolvable.
  artifacts <- wb_art_list(b, include_history = FALSE)
  retract_id <- as.character(artifacts$artifact_id[1])
  birth_before <- wb_art_birth_certificate(b, retract_id)
  content_before <- as.character(birth_before$persisted_provenance$links$content_sha256[1])
  loaded_before <- wb_art_load(b, retract_id)
  deleted <- wb_art_delete(b, retract_id)
  stopifnot(nrow(deleted) == 1L, identical(deleted$action[1], "retracted"))
  birth_after <- wb_art_birth_certificate(b, retract_id)
  loaded_after <- wb_art_load(b, retract_id)
  force_error <- try(wb_art_delete(b, retract_id, force = TRUE), silent = TRUE)
  purge_error <- try({
    wb_entity_mark_ephemeral(b, "artifact", retract_id, reason = "must fail")
    wb_unsafe_purge_ephemeral_entity(b, "artifact", retract_id,
      confirmation = "PURGE UNREFERENCED EPHEMERAL ENTITY")
  }, silent = TRUE)
  stopifnot(
    identical(birth_after$lifecycle$state, "retracted"),
    identical(content_before, as.character(birth_after$persisted_provenance$links$content_sha256[1])),
    identical(loaded_before$kind, loaded_after$kind),
    retract_id %in% wb_art_list(b, include_history = TRUE)$artifact_id,
    !(retract_id %in% wb_art_list(b, include_history = FALSE)$artifact_id),
    inherits(force_error, "try-error"), inherits(purge_error, "try-error")
  )
  reconstruction <- wb_target_reproduction_plan(b, paste0("artifact:", retract_id))
  stopifnot(is.list(reconstruction), identical(reconstruction$target$entity_id, retract_id))

  # Rejected state is also historical and preserves membership evidence.
  rejected_set <- "set:.__lifecycle_rejected__."
  promote_cell_set(rejected_set, "set:sample_A")
  wb_entity_reject(b, "cell_set", rejected_set, reason = "Rejected contract candidate.", retracted_by = "contract")
  stopifnot(
    identical(wb_entity_lifecycle(b, "cell_set", rejected_set)$lifecycle_state[1], "rejected"),
    !(rejected_set %in% wb_cell_sets(b)),
    rejected_set %in% wb_cell_sets(b, include_history = TRUE),
    length(wb_cells(b, rejected_set)) > 0L
  )

  lifecycle <- wb_entity_lifecycle(b, include_history = TRUE)
  stopifnot(all(c("current", "superseded", "rejected", "retracted") %in% lifecycle$lifecycle_state))
  dag <- wb_prov_bundle_dag(b, include_superseded = TRUE)
  dag_current <- wb_prov_bundle_dag(b, include_superseded = FALSE)
  stopifnot(
    any(dag$edges$edge_type == "SUPERSEDES"),
    any(dag$nodes$status == "retracted"),
    any(dag$nodes$status == "rejected"),
    any(dag$nodes$status == "superseded"),
    !any(dag_current$nodes$status %in% c("superseded", "rejected", "retracted"))
  )
  kg <- wb_kg_provenance_graph(b)
  stopifnot(any(kg$edges$edge_type == "SUPERSEDES"))

  TRUE
}
