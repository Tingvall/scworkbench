test_durable_session_staged_space_registry_binding_contract <- function() {
  contract_test_activate_representation_pack()
  on.exit(try(wb_operation_pack_unload("scwbrepresentation"), silent = TRUE),
    add = TRUE)
  if (!requireNamespace("uwot", quietly = TRUE))
    return(contract_test_skip("uwot is not installed."))

  bundle_dir <- tempfile("scwb_durable_registry_bundle_")
  workspace_root <- tempfile("scwb_durable_registry_sessions_")
  bundle <- wb_init_bundle(bundle_dir, overwrite = TRUE)
  on.exit({
    try(wb_close_bundle(bundle), silent = TRUE)
    unlink(bundle_dir, recursive = TRUE, force = TRUE)
    unlink(workspace_root, recursive = TRUE, force = TRUE)
  }, add = TRUE)
  cells <- paste0("cell_", seq_len(12L))
  wb_define_cells(bundle, cells)
  coords <- matrix(seq_len(48L) / 10, nrow = 12L,
    dimnames = list(cells, paste0("PC", seq_len(4L))))
  wb_add_space(bundle, "source.pca", coords, source = "contract")

  session <- wb_session_create(bundle, workspace_root, "registry_corrupt")
  executed <- wb_session_run_op(session, bundle, "umap_fit", inputs = list(
    space = "source.pca", cell_set = "all", min_cells = 1L, dims = 1:4,
    space_id_out = "registry.umap", n_neighbors = 3L, min_dist = 0.1,
    metric = "euclidean", nn_method = "annoy", seed = 1L
  ))
  source_before <- .wb_session_source_identity(bundle)$scientific_state_fingerprint
  changed <- DBI::dbExecute(executed$session$staging_bundle$con,
    "UPDATE spaces SET source = ? WHERE space_id = ?;",
    params = list("tampered_registry_binding", "registry.umap"))
  stopifnot(identical(as.integer(changed), 1L))
  bad_resume <- try(wb_session_resume(bundle, executed$session$durable$workspace),
    silent = TRUE)
  bad_promote <- try(wb_session_promote_current(bundle, executed$session,
    # The accepted pack publishes the space as the model's materialization.
    # Request its real terminal so validation reaches the corrupted registry
    # binding rather than correctly rejecting a nonterminal promotion request.
    outputs = "model"), silent = TRUE)
  stopifnot(inherits(bad_resume, "try-error"),
    inherits(bad_promote, "try-error"),
    grepl("DURABLE_SESSION_PAYLOAD_CORRUPT", as.character(bad_resume),
      fixed = TRUE),
    grepl("DURABLE_SESSION_PAYLOAD_CORRUPT", as.character(bad_promote),
      fixed = TRUE),
    identical(source_before,
      .wb_session_source_identity(bundle)$scientific_state_fingerprint))
  wb_session_discard(executed$session)
  TRUE
}
