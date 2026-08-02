test_umap_promotion_atomicity_contract <- function() {
  if (!requireNamespace("uwot", quietly = TRUE)) {
    return(contract_test_skip("uwot is not installed."))
  }

  root <- tempfile("scwb_umap_promotion_atomicity_")
  b <- wb_init_bundle(root, overwrite = TRUE)
  on.exit({
    options(scworkbench.promotion_workspace_publish_hook = NULL)
    try(wb_close_bundle(b), silent = TRUE)
    unlink(root, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  cells <- paste0("c", seq_len(12L))
  coords <- matrix(seq_len(48L) / 10, nrow = length(cells), ncol = 4L,
                   dimnames = list(cells, paste0("latent_", seq_len(4L))))
  wb_define_cells(b, cells)
  wb_add_space(b, "rna_scvi_unbatched_latent30", coords, source = "scvi", overwrite = TRUE)
  wb_add_space(b, "rna_pca_durable", coords, source = "pca", overwrite = TRUE)

  # This pre-existing directory is the historical escape hatch: linking it as
  # a whole directory made a staged save_uwot() write into the live bundle.
  dir.create(file.path(root, "models", "umap"), recursive = TRUE, showWarnings = FALSE)
  owner_path <- file.path(root, "models", "umap", "user_owned.uwot")
  writeLines("user owned", owner_path, useBytes = TRUE)

  count_table <- function(table) {
    if (!.wb_table_exists(b$con, table)) return(0L)
    as.integer(DBI::dbGetQuery(b$con, paste0("SELECT COUNT(*) AS n FROM ", table, ";"))$n[1])
  }
  live_counts <- function() {
    vapply(c("artifacts", "artifact_model_ref", "prov_commits", "prov_heads", "prov_runs", "prov_edges"),
           count_table, integer(1))
  }
  run_umap <- function(source, target) {
    wb_session_run_op(
      wb_session_new(), b, "umap_fit",
      inputs = list(space = source, cell_set = "all", min_cells = 1L,
                    dims = 1:4, space_id_out = target, n_neighbors = 3L,
                    min_dist = 0.1, metric = "euclidean", nn_method = "annoy", seed = 1L)
    )
  }
  assert_no_residue <- function(target, counts_before) {
    model_rel <- file.path("models", "umap", paste0(target, ".uwot"))
    stopifnot(!file.exists(file.path(root, model_rel)))
    stopifnot(!target %in% as.character(wb_spaces(b)$space_id))
    if (.wb_table_exists(b$con, "space_models")) {
      n_model <- DBI::dbGetQuery(
        b$con, "SELECT COUNT(*) AS n FROM space_models WHERE space_id = ?;", params = list(target)
      )$n[1]
      stopifnot(as.integer(n_model) == 0L)
    }
    stopifnot(identical(live_counts(), counts_before), isTRUE(wb_validate_bundle(root)))
  }

  # Durable PCA source: the model is visible only in the private session view.
  durable_target <- "rna_pca_durable_umap_2d"
  durable <- run_umap("rna_pca_durable", durable_target)
  durable_rel <- file.path("models", "umap", paste0(durable_target, ".uwot"))
  stopifnot(file.exists(file.path(wb_session_view(durable$session)$dir, durable_rel)))
  stopifnot(!file.exists(file.path(root, durable_rel)))
  stopifnot(identical(readLines(owner_path, warn = FALSE), "user owned"))

  before_failure <- live_counts()
  options(scworkbench.promotion_workspace_publish_hook = function(workspace, final_rel) {
    stop("forced UMAP model publication failure", call. = FALSE)
  })
  failed <- try(wb_session_promote_current(
    b, durable$session, outputs = c("model", "space_2d"), created_by = "test"
  ), silent = TRUE)
  options(scworkbench.promotion_workspace_publish_hook = NULL)
  stopifnot(inherits(failed, "try-error"))
  assert_no_residue(durable_target, before_failure)

  # With the private workspace discarded, the same target can safely retry.
  durable$session <- wb_session_discard(durable$session)
  retried <- run_umap("rna_pca_durable", durable_target)
  retried_promotion <- wb_session_promote_current(
    b, retried$session, outputs = c("model", "space_2d"), created_by = "test"
  )
  stopifnot(any(as.character(retried_promotion$promoted$status) == "ok"),
            file.exists(file.path(root, durable_rel)))
  umap_identity <- DBI::dbGetQuery(
    b$con,
    "SELECT output_name, content_sha256, verification_level, verification_status FROM prov_run_outputs WHERE snapshot_id = ? AND run_id = ? ORDER BY output_name;",
    params = list(retried_promotion$provenance_snapshot_id, retried$run$run_id)
  )
  stopifnot(all(c("model", "space_2d") %in% as.character(umap_identity$output_name)),
            all(as.character(umap_identity$verification_level) == "content"),
            all(as.character(umap_identity$verification_status) == "content_verified"),
            all(grepl("^[0-9a-f]{64}$", as.character(umap_identity$content_sha256))))
  retried$session <- wb_session_discard(retried$session)

  # An owned final target is rejected before the runner can write through the
  # staged overlay, and its bytes are never changed or removed.
  collision_target <- "rna_scvi_collision_umap_2d"
  collision_path <- file.path(root, "models", "umap", paste0(collision_target, ".uwot"))
  writeLines("do not touch", collision_path, useBytes = TRUE)
  collision_counts <- live_counts()
  collision <- try(run_umap("rna_scvi_unbatched_latent30", collision_target), silent = TRUE)
  stopifnot(inherits(collision, "try-error"),
            identical(readLines(collision_path, warn = FALSE), "do not touch"),
            identical(live_counts(), collision_counts))

  # A scVI latent branch follows the same staging and rollback rules.
  scvi_target <- "rna_scvi_unbatched_umap_2d"
  scvi <- run_umap("rna_scvi_unbatched_latent30", scvi_target)
  scvi_rel <- file.path("models", "umap", paste0(scvi_target, ".uwot"))
  stopifnot(file.exists(file.path(wb_session_view(scvi$session)$dir, scvi_rel)),
            !file.exists(file.path(root, scvi_rel)))
  scvi_before <- live_counts()
  options(scworkbench.promotion_workspace_publish_hook = function(workspace, final_rel) {
    stop("forced scVI-branch UMAP publication failure", call. = FALSE)
  })
  scvi_failed <- try(wb_session_promote_current(
    b, scvi$session, outputs = c("model", "space_2d"), created_by = "test"
  ), silent = TRUE)
  options(scworkbench.promotion_workspace_publish_hook = NULL)
  stopifnot(inherits(scvi_failed, "try-error"))
  assert_no_residue(scvi_target, scvi_before)
  scvi$session <- wb_session_discard(scvi$session)
  TRUE
}
