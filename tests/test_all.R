test_all <- function(bundle_dir){

  if (exists("test_primitives_contract", mode = "function")) {
    stopifnot(test_primitives_contract())
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
  if (exists("test_op_contract_conformance", mode = "function")) {
    stopifnot(test_op_contract_conformance())
  }
  if (exists("test_op_catalog_semantic_contract", mode = "function")) {
    stopifnot(test_op_catalog_semantic_contract())
  }
  if (exists("test_op_knn_neighbors_contract", mode = "function")) {
    stopifnot(test_op_knn_neighbors_contract(bundle_dir))
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
  if (exists("test_op_space_path_contract", mode = "function")) {
    stopifnot(test_op_space_path_contract(bundle_dir))
  }
  if (exists("test_op_slingshot_promoted_model_project_contract", mode = "function")) {
    stopifnot(test_op_slingshot_promoted_model_project_contract(bundle_dir))
  }
  if (exists("test_op_trajectory_de_contract", mode = "function")) {
    stopifnot(test_op_trajectory_de_contract(bundle_dir))
  }
  if (exists("test_op_trajectory_branch_compare_contract", mode = "function")) {
    stopifnot(test_op_trajectory_branch_compare_contract(bundle_dir))
  }
  if (exists("test_op_trajectory_smooth_contract", mode = "function")) {
    stopifnot(test_op_trajectory_smooth_contract(bundle_dir))
  }
  if (exists("test_op_trajectory_signature_smooth_contract", mode = "function")) {
    stopifnot(test_op_trajectory_signature_smooth_contract(bundle_dir))
  }
  if (exists("test_op_trajectory_vector_smooth_contract", mode = "function")) {
    stopifnot(test_op_trajectory_vector_smooth_contract(bundle_dir))
  }
  if (exists("test_op_trajectory_signal_dynamics_contract", mode = "function")) {
    stopifnot(test_op_trajectory_signal_dynamics_contract(bundle_dir))
  }
  if (exists("test_op_trajectory_signal_dynamics_promoted_contract", mode = "function")) {
    stopifnot(test_op_trajectory_signal_dynamics_promoted_contract(bundle_dir))
  }
  if (exists("test_op_trajectory_geneset_dynamics_contract", mode = "function")) {
    stopifnot(test_op_trajectory_geneset_dynamics_contract(bundle_dir))
  }
  if (exists("test_op_trajectory_geneset_dynamics_promoted_contract", mode = "function")) {
    stopifnot(test_op_trajectory_geneset_dynamics_promoted_contract(bundle_dir))
  }
  if (exists("test_trajectory_family_helpers_contract", mode = "function")) {
    stopifnot(test_trajectory_family_helpers_contract(bundle_dir))
  }
  if (exists("test_feature_sets_contract", mode = "function")) {
    stopifnot(test_feature_sets_contract(bundle_dir))
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
    stopifnot(all(dim(x) == c(10, 50)))
  }
  cat("Vector getter agrees with slice\n")
  if (nrow(mats) > 0) {
    mid <- mats$matrix_id[1]

    gene <- wb_feature_ids(b, mid)[1]
    cell50 <- head(wb_cells(b), 50)

    v <- wb_vector(b, mid, gene, cells = cell50)
    x <- wb_slice(b, mid, features = gene, cells = cell50)

    stopifnot(length(v) == 50)
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
      stopifnot(nrow(s) == 20)
      stopifnot(identical(s$cell_id, cells_20))
    } else {
      stopifnot(is.matrix(s))
      stopifnot(nrow(s) == 20)
      stopifnot(identical(rownames(s), cells_20))
    }
  }
  cat("close bundle\n")
  wb_close_bundle(b)

  TRUE

}
