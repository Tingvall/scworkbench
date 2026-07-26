test_all <- function(bundle_dir){

  fixture_n_cells <- tryCatch({
    fixture_bundle <- wb_open_bundle(bundle_dir)
    on.exit(try(wb_close_bundle(fixture_bundle), silent = TRUE), add = TRUE)
    length(wb_cells(fixture_bundle, cell_set = "all"))
  }, error = function(e) 0L)
  large_trajectory_fixture <- fixture_n_cells >= 500L
  if (!large_trajectory_fixture) {
    message("Skipping large-fixture trajectory integration contracts (fixture has ",
            fixture_n_cells, " cells; require at least 500).")
  }

  if (exists("test_primitives_contract", mode = "function")) {
    stopifnot(test_primitives_contract())
  }
  if (exists("test_fullstack_monocle3_dependency_closure_contract", mode = "function")) {
    stopifnot(test_fullstack_monocle3_dependency_closure_contract())
  }
  if (exists("test_legacy_cell_vector_contract", mode = "function")) {
    stopifnot(test_legacy_cell_vector_contract())
  }
  if (exists("test_foundation_data_getters_selectors", mode = "function")) {
    stopifnot(test_foundation_data_getters_selectors(bundle_dir))
  }
  if (exists("test_foundation_hardening_1to5", mode = "function")) {
    stopifnot(test_foundation_hardening_1to5(bundle_dir))
  }
  if (exists("test_ingest_adapters_contract", mode = "function")) {
    stopifnot(test_ingest_adapters_contract(bundle_dir))
  }
  if (exists("test_attach_adapters_contract", mode = "function")) {
    stopifnot(test_attach_adapters_contract(bundle_dir))
  }
  if (exists("test_bundle_ingest_containers_contract", mode = "function")) {
    stopifnot(test_bundle_ingest_containers_contract(bundle_dir))
  }
  if (exists("test_op_contract_conformance", mode = "function")) {
    stopifnot(test_op_contract_conformance())
  }
  if (exists("test_op_catalog_semantic_contract", mode = "function")) {
    stopifnot(test_op_catalog_semantic_contract())
  }
  if (exists("test_promotion_output_contract", mode = "function")) {
    stopifnot(test_promotion_output_contract())
  }
  if (exists("test_peakvi_project_promotion_contract", mode = "function")) {
    stopifnot(test_peakvi_project_promotion_contract())
  }
  if (exists("test_plot_catalog_semantic_contract", mode = "function")) {
    stopifnot(test_plot_catalog_semantic_contract())
  }
  if (exists("test_getter_catalog_semantic_contract", mode = "function")) {
    stopifnot(test_getter_catalog_semantic_contract())
  }
  if (exists("test_contract_catalogs_semantic", mode = "function")) {
    stopifnot(test_contract_catalogs_semantic())
  }
  if (exists("test_semantic_catalog_unified_contract", mode = "function")) {
    stopifnot(test_semantic_catalog_unified_contract())
  }
  if (exists("test_semantic_graph_views_contract", mode = "function")) {
    stopifnot(test_semantic_graph_views_contract())
  }
  if (exists("test_parameter_semantics_catalog_contract", mode = "function")) {
    stopifnot(test_parameter_semantics_catalog_contract())
  }
  if (exists("test_recipe_semantics_catalog_contract", mode = "function")) {
    stopifnot(test_recipe_semantics_catalog_contract())
  }
  if (exists("test_semantic_planning_artifact_contract", mode = "function")) {
    stopifnot(test_semantic_planning_artifact_contract())
  }
  if (exists("test_knowledge_graph_contract", mode = "function")) {
    stopifnot(test_knowledge_graph_contract(bundle_dir))
  }
  if (exists("test_op_knn_neighbors_contract", mode = "function")) {
    stopifnot(test_op_knn_neighbors_contract(bundle_dir))
  }
  if (exists("test_op_matrix_log_normalize_contract", mode = "function")) {
    stopifnot(test_op_matrix_log_normalize_contract())
  }
  if (exists("test_op_matrix_log_normalize_multifragment_contract", mode = "function")) {
    stopifnot(test_op_matrix_log_normalize_multifragment_contract())
  }
  if (exists("test_session_run_op_parameter_contract", mode = "function")) {
    stopifnot(test_session_run_op_parameter_contract())
  }
  if (exists("test_op_hvg_pca_contract", mode = "function")) {
    stopifnot(test_op_hvg_pca_contract())
  }
  if (exists("test_transitive_promotion_pbmc_vertical_slice_contract", mode = "function")) {
    stopifnot(test_transitive_promotion_pbmc_vertical_slice_contract())
  }
  if (exists("test_provenance_attestation_contract", mode = "function")) {
    stopifnot(test_provenance_attestation_contract())
  }
  if (exists("test_recipient_audit_external_source_contract", mode = "function")) {
    stopifnot(test_recipient_audit_external_source_contract())
  }
  if (exists("test_promotion_workspace_matrix_atomicity_contract", mode = "function")) {
    stopifnot(test_promotion_workspace_matrix_atomicity_contract())
  }
  if (exists("test_promotion_workspace_mixed_matrix_space_atomicity_contract", mode = "function")) {
    stopifnot(test_promotion_workspace_mixed_matrix_space_atomicity_contract())
  }
  if (exists("test_umap_promotion_atomicity_contract", mode = "function")) {
    stopifnot(test_umap_promotion_atomicity_contract())
  }
  if (exists("test_promotion_artifact_payload_atomicity_contract", mode = "function")) {
    stopifnot(test_promotion_artifact_payload_atomicity_contract())
  }
  if (exists("test_promotion_staged_model_payload_contract", mode = "function")) {
    stopifnot(test_promotion_staged_model_payload_contract())
  }
  if (exists("test_registry_replay_closure_contract", mode = "function")) {
    stopifnot(test_registry_replay_closure_contract())
  }
  if (exists("test_op_umap_runtime_preflight_contract", mode = "function")) {
    stopifnot(test_op_umap_runtime_preflight_contract())
  }
  if (exists("test_op_umap_same_session_transform_promotion_contract", mode = "function")) {
    stopifnot(test_op_umap_same_session_transform_promotion_contract())
  }
  if (exists("test_op_chromvar_contract", mode = "function")) {
    stopifnot(test_op_chromvar_contract(bundle_dir))
  }
  if (exists("test_op_cell_vector_family_reduce_contract", mode = "function")) {
    stopifnot(test_op_cell_vector_family_reduce_contract())
  }
  if (exists("test_op_cell_vector_family_calibrate_contract", mode = "function")) {
    stopifnot(test_op_cell_vector_family_calibrate_contract())
  }
  if (exists("test_op_cell_vector_family_qc_contract", mode = "function")) {
    stopifnot(test_op_cell_vector_family_qc_contract())
  }
  if (exists("test_op_cell_vector_family_graph_smooth_contract", mode = "function")) {
    stopifnot(test_op_cell_vector_family_graph_smooth_contract())
  }
  if (exists("test_op_cell_vector_winners_contract", mode = "function")) {
    stopifnot(test_op_cell_vector_winners_contract())
  }
  if (exists("test_op_chunking_metadata_contract", mode = "function")) {
    stopifnot(test_op_chunking_metadata_contract())
  }
  if (exists("test_op_chunking_helper_contract", mode = "function")) {
    stopifnot(test_op_chunking_helper_contract())
  }
  if (exists("test_op_feature_trend_spearman_chunking_contract", mode = "function")) {
    stopifnot(test_op_feature_trend_spearman_chunking_contract())
  }
  if (exists("test_op_cell_vector_compare_contract", mode = "function")) {
    stopifnot(test_op_cell_vector_compare_contract())
  }
  if (exists("test_op_ucell_contract", mode = "function")) {
    stopifnot(test_op_ucell_contract())
  }
  if (exists("test_op_ucell_chunking_contract", mode = "function")) {
    stopifnot(test_op_ucell_chunking_contract())
  }
  if (exists("test_chromvar_seqlevels_contract", mode = "function")) {
    stopifnot(test_chromvar_seqlevels_contract(bundle_dir))
  }
  if (exists("test_op_pathway_enrich_contract", mode = "function")) {
    stopifnot(test_op_pathway_enrich_contract(bundle_dir))
  }
  if (exists("test_op_slingshot_fit_project_contract", mode = "function")) {
    stopifnot(test_op_slingshot_fit_project_contract(bundle_dir))
  }
  if (exists("test_op_peakvi_fit_contract", mode = "function")) {
    stopifnot(test_op_peakvi_fit_contract(bundle_dir))
  }
  if (exists("test_op_scvi_train_contract", mode = "function")) {
    stopifnot(test_op_scvi_train_contract(bundle_dir))
  }
  if (large_trajectory_fixture && exists("test_op_space_path_contract", mode = "function")) {
    stopifnot(test_op_space_path_contract(bundle_dir))
  }
  if (large_trajectory_fixture && exists("test_op_slingshot_promoted_model_project_contract", mode = "function")) {
    stopifnot(test_op_slingshot_promoted_model_project_contract(bundle_dir))
  }
  if (large_trajectory_fixture && exists("test_op_trajectory_de_contract", mode = "function")) {
    stopifnot(test_op_trajectory_de_contract(bundle_dir))
  }
  if (large_trajectory_fixture && exists("test_op_trajectory_branch_compare_contract", mode = "function")) {
    stopifnot(test_op_trajectory_branch_compare_contract(bundle_dir))
  }
  if (large_trajectory_fixture && exists("test_op_trajectory_smooth_contract", mode = "function")) {
    stopifnot(test_op_trajectory_smooth_contract(bundle_dir))
  }
  if (large_trajectory_fixture && exists("test_op_trajectory_signature_smooth_contract", mode = "function")) {
    stopifnot(test_op_trajectory_signature_smooth_contract(bundle_dir))
  }
  if (large_trajectory_fixture && exists("test_op_trajectory_vector_smooth_contract", mode = "function")) {
    stopifnot(test_op_trajectory_vector_smooth_contract(bundle_dir))
  }
  if (large_trajectory_fixture && exists("test_op_trajectory_signal_dynamics_contract", mode = "function")) {
    stopifnot(test_op_trajectory_signal_dynamics_contract(bundle_dir))
  }
  if (exists("test_trajectory_geneset_dynamic_metrics_contract", mode = "function")) {
    stopifnot(test_trajectory_geneset_dynamic_metrics_contract())
  }
  if (large_trajectory_fixture && exists("test_op_trajectory_signal_dynamics_promoted_contract", mode = "function")) {
    stopifnot(test_op_trajectory_signal_dynamics_promoted_contract(bundle_dir))
  }
  if (large_trajectory_fixture && exists("test_op_trajectory_geneset_dynamics_contract", mode = "function")) {
    stopifnot(test_op_trajectory_geneset_dynamics_contract(bundle_dir))
  }
  if (large_trajectory_fixture && exists("test_op_trajectory_geneset_dynamics_promoted_contract", mode = "function")) {
    stopifnot(test_op_trajectory_geneset_dynamics_promoted_contract(bundle_dir))
  }
  if (large_trajectory_fixture && exists("test_trajectory_family_helpers_contract", mode = "function")) {
    stopifnot(test_trajectory_family_helpers_contract(bundle_dir))
  }
  if (exists("test_op_trajectory_segment_join_contract", mode = "function")) {
    stopifnot(test_op_trajectory_segment_join_contract())
  }
  if (exists("test_trajectory_segment_contract", mode = "function")) {
    stopifnot(test_trajectory_segment_contract())
  }
  if (exists("test_composite_pseudotime_dynamics_contract", mode = "function")) {
    stopifnot(test_composite_pseudotime_dynamics_contract())
  }
  if (exists("test_feature_sets_contract", mode = "function")) {
    stopifnot(test_feature_sets_contract(bundle_dir))
  }
  if (exists("test_derived_cell_set_lifecycle_contract", mode = "function")) {
    stopifnot(test_derived_cell_set_lifecycle_contract())
  }
  if (exists("test_op_feature_set_import_qc_contract", mode = "function")) {
    stopifnot(test_op_feature_set_import_qc_contract(bundle_dir))
  }
  if (exists("test_feature_set_namespace_transfer_contract", mode = "function")) {
    stopifnot(test_feature_set_namespace_transfer_contract())
  }
  if (exists("test_feature_set_namespace_transfer_intersect_contract", mode = "function")) {
    stopifnot(test_feature_set_namespace_transfer_intersect_contract())
  }
  if (exists("test_motif_registry_contract", mode = "function")) {
    stopifnot(test_motif_registry_contract(bundle_dir))
  }
  if (exists("test_motif_match_contract", mode = "function")) {
    stopifnot(test_motif_match_contract(bundle_dir))
  }
  if (exists("test_feature_selection_plan_contract", mode = "function")) {
    stopifnot(test_feature_selection_plan_contract(bundle_dir))
  }
  if (exists("test_compute_profile_contract", mode = "function")) {
    stopifnot(test_compute_profile_contract())
  }
  if (exists("test_session_dag_contract", mode = "function")) {
    stopifnot(test_session_dag_contract(bundle_dir))
  }
  if (exists("test_session_input_ref_ergonomics_contract", mode = "function")) {
    stopifnot(test_session_input_ref_ergonomics_contract())
  }
  if (exists("test_report_draft_contract", mode = "function")) {
    stopifnot(test_report_draft_contract(bundle_dir))
  }
  if (exists("test_provenance_snapshot_contract", mode = "function")) {
    stopifnot(test_provenance_snapshot_contract(bundle_dir))
  }
  if (exists("test_provenance_bundle_dag_contract", mode = "function")) {
    stopifnot(test_provenance_bundle_dag_contract(bundle_dir))
  }
  if (exists("test_chunked_provenance_replay_contract", mode = "function")) {
    stopifnot(test_chunked_provenance_replay_contract())
  }
  if (exists("test_space_path_promotion_contract", mode = "function")) {
    stopifnot(test_space_path_promotion_contract())
  }
  if (exists("test_promoted_workflow_continue_replay_contract", mode = "function")) {
    stopifnot(test_promoted_workflow_continue_replay_contract(bundle_dir))
  }
  if (exists("test_plot_wranglers_contract", mode = "function")) {
    stopifnot(test_plot_wranglers_contract(bundle_dir))
  }
  if (exists("test_navigation_contract", mode = "function")) {
    stopifnot(test_navigation_contract(bundle_dir))
  }

  cat("Opening bundle\n")
  b <- wb_open_bundle(bundle_dir)

  cat("bundle is opened\n")
  cat("Basic sanity\n")

  stopifnot(inherits(b, "scworkbench_bundle"))
  stopifnot(dir.exists(b$dir))
  stopifnot(DBI::dbIsValid(b$con))
  stopifnot(!is.null(wb_manifest(b)$bundle_id))
  cat("Registries exist and have rows\n")
  mats <- wb_list(b, "matrices")
  feats <- wb_list(b, "features")
  sp   <- wb_list(b, "spaces")
  ds   <- wb_list(b, "datasets")

  cat("Cells and meta alignment\n")

  stopifnot(nrow(ds) >= 1)
  stopifnot(nrow(mats) >= 0)   # can be 0 if write_matrices=FALSE
  stopifnot(nrow(feats) >= 0)  # can be 0 in minimal bundles
  stopifnot(nrow(sp) >= 0)

  cells_all <- wb_cells(b)
  stopifnot(length(cells_all) == nrow(wb_meta(b, cols = c("cell_id"))))
  stopifnot(identical(cells_all, wb_meta(b, cells = cells_all, cols = c("cell_id"))$cell_id))

  cells_20 <- head(cells_all, 20)
  meta_20  <- wb_meta(b, cells = cells_20, cols = c("cell_id", "dataset_id"))
  stopifnot(identical(meta_20$cell_id, cells_20))

  cat("Features registry + ordering per matrix_id\n")

  if (nrow(mats) > 0) {
    mid <- mats$matrix_id[1]
    fids  <- wb_feature_ids(b, mid)
    stopifnot(length(fids) > 0)

    # check features table contains them
    ftab <- wb_features(b, matrix_id = mid)
    stopifnot(all(fids %in% ftab$feature_id))
  }
  cat("BPCells handle opens + dimension sanity\n")

  if (nrow(mats) > 0) {
    mid <- mats$matrix_id[1]
    mh  <- wb_matrix(b, mid)
    d   <- dim(mh)

    stopifnot(length(d) == 2)
    stopifnot(d[2] == length(wb_cells(b)))
  }
  cat("BPCells slice path (small slice → sparse Matrix)\n")
  if (nrow(mats) > 0) {
    mid <- mats$matrix_id[1]

    feat10 <- head(wb_feature_ids(b, mid), 10)
    cell50 <- head(wb_cells(b), 50)

    x <- wb_slice(b, mid, features = feat10, cells = cell50)
    stopifnot(inherits(x, "Matrix"))
    stopifnot(identical(rownames(x), feat10))
    stopifnot(identical(colnames(x), cell50))
    stopifnot(all(dim(x) == c(length(feat10), length(cell50))))
  }
  cat("Vector getter agrees with slice\n")
  if (nrow(mats) > 0) {
    mid <- mats$matrix_id[1]

    gene <- wb_feature_ids(b, mid)[1]
    cell50 <- head(wb_cells(b), 50)

    v <- wb_vector(b, mid, gene, cells = cell50)
    x <- wb_slice(b, mid, features = gene, cells = cell50)

    stopifnot(length(v) == length(cell50))
    stopifnot(identical(names(v), cell50))
    stopifnot(all(as.numeric(x[1, ]) == as.numeric(v)))
  }
  cat("Space getter (2D and long)\n")
  if (nrow(sp) > 0) {
    sid <- sp$space_id[1]
    cells_20 <- head(wb_cells(b), 20)

    s <- wb_space(b, sid, cells = cells_20)

    if (is.data.frame(s)) {
      stopifnot(all(c("cell_id", "x", "y") %in% colnames(s)))
      stopifnot(nrow(s) == length(cells_20))
      stopifnot(identical(s$cell_id, cells_20))
    } else {
      stopifnot(is.matrix(s))
      stopifnot(nrow(s) == length(cells_20))
      stopifnot(identical(rownames(s), cells_20))
    }
  }
  cat("close bundle\n")
  wb_close_bundle(b)

  TRUE

}
