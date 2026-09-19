test_artifact_model_ref_lifecycle_validation_contract <- function() {
  contract_test_activate_representation_pack()
  on.exit(try(wb_operation_pack_unload("scwbrepresentation"), silent = TRUE),
    add = TRUE)
  required <- c("BPCells", "Matrix")
  missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
  python <- .wb_pybench_default_python()
  if (length(missing) || !file.exists(python)) {
    return(contract_test_skip(paste(
      c(if (length(missing)) paste("Missing runtime dependencies:", paste(missing, collapse = ", ")),
        if (!file.exists(python)) paste("PyBench interpreter unavailable:", python)),
      collapse = "; "
    )))
  }

  root <- tempfile("scwb_artifact_model_lifecycle_")
  bundle_dir <- file.path(root, "valid.bundle")
  dir.create(root, recursive = TRUE)
  old_mock <- Sys.getenv("PYBENCH_TEST_MOCK_TRAINING", unset = NA_character_)
  Sys.setenv(PYBENCH_TEST_MOCK_TRAINING = "1")
  b <- wb_init_bundle(bundle_dir, overwrite = TRUE)
  on.exit({
    if (is.na(old_mock)) Sys.unsetenv("PYBENCH_TEST_MOCK_TRAINING") else
      Sys.setenv(PYBENCH_TEST_MOCK_TRAINING = old_mock)
    try(wb_close_bundle(b), silent = TRUE)
    unlink(root, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  cells <- paste0("cell_", seq_len(12L))
  genes <- paste0("gene_", seq_len(5L))
  wb_define_cells(b, cells, metadata = data.frame(
    cell_id = cells, batch = rep(c("a", "b"), each = 6L), stringsAsFactors = FALSE
  ))
  counts <- Matrix::Matrix(
    matrix((seq_len(60L) %% 5L), nrow = 5L, dimnames = list(genes, cells)),
    sparse = TRUE
  )
  wb_attach_matrix(b, "RNA_counts", counts, layer = "counts", feature_type = "gene")

  # Execute the registered scVI op and its real session/staging/promotion path;
  # only the expensive Python training implementation is mocked by PyBench.
  trained <- wb_session_run_op(wb_session_new(), b, "scvi_train", inputs = list(
    matrix = "RNA_counts", batch_key = "batch", n_latent = 3L,
    output_space_id = "rna.scvi.lifecycle", cell_set = "all", min_cells = 2L
  ))
  scvi_run_id <- as.character(trained$run$run_id)
  embedded <- wb_session_run_op(trained$session, b, "umap_fit", inputs = list(
    space = wb_ref_run(scvi_run_id, "space"), cell_set = "all", min_cells = 2L,
    dims = 1:3, space_id_out = "rna.umap.scvi.lifecycle", n_neighbors = 3L,
    min_dist = 0.1, metric = "euclidean", nn_method = "annoy", seed = 7L
  ))
  umap_run_id <- as.character(embedded$run$run_id)
  promoted <- wb_session_promote_current(
    b, embedded$session, created_by = "artifact-model-lifecycle-contract",
    outputs = list(
      wb_ref_run(scvi_run_id, "model"),
      wb_ref_run(scvi_run_id, "fit_summary"),
      wb_ref_run(umap_run_id, "model")
    )
  )
  stopifnot(all(promoted$promoted$status == "ok"))
  scvi_artifact <- as.character(promoted$promoted$artifact_id[
    promoted$promoted$run_id == scvi_run_id & promoted$promoted$output == "model"
  ][1L])
  umap_artifact <- as.character(promoted$promoted$artifact_id[
    promoted$promoted$run_id == umap_run_id & promoted$promoted$output == "model"
  ][1L])
  scvi_model <- wb_art_load(b, scvi_artifact, "model_ref")
  umap_model <- wb_art_load(b, umap_artifact, "model_ref")
  artifact_identity <- function(artifact_id) DBI::dbGetQuery(b$con, "
    SELECT binding.entity_id
    FROM prov_run_outputs output
    JOIN prov_run_entity_bindings binding
      ON binding.snapshot_id=output.snapshot_id AND binding.run_id=output.run_id
     AND binding.binding_name=output.output_name
    WHERE output.artifact_id=? AND output.primitive_kind='model_ref'
      AND binding.entity_kind='model_ref' AND binding.direction='output';
  ", params = list(artifact_id))$entity_id[[1L]]
  scvi_id <- artifact_identity(scvi_artifact)
  umap_id <- artifact_identity(umap_artifact)
  scvi_presence <- .wb_model_ref_physical_presence(b, scvi_id)
  umap_presence <- .wb_model_ref_physical_presence(b, umap_id)
  stopifnot(isTRUE(scvi_presence$present), identical(scvi_presence$storage, "artifact_model_ref"),
            identical(scvi_presence$artifact_id, scvi_artifact),
            isTRUE(umap_presence$present),
            identical(umap_presence$storage, "artifact_model_ref"),
            identical(umap_presence$artifact_id, umap_artifact),
            dir.exists(umap_presence$absolute_model_path))

  # Exercise distinct artifact-backed identity shapes/writer routes for PeakVI
  # and Palantir through ordinary analysis promotion.
  promote_fixture_model <- function(engine, model_space_id, in_space_id) {
    rel <- file.path("artifact_models", paste0(engine, "_lifecycle_fixture"))
    dir.create(file.path(bundle_dir, rel), recursive = TRUE, showWarnings = FALSE)
    writeLines(paste(engine, "fixture"), file.path(bundle_dir, rel, "model.txt"))
    prim <- wb_prim_model_ref(model_space_id, in_space_id, engine = engine)
    prim$model_type <- paste0(engine, "_fit")
    prim$model_path <- file.path(bundle_dir, rel)
    run <- wb_new_run(
      paste0(engine, "_fit"), inputs = list(cell_set = "all", user_inputs = list()),
      outputs = list(model = prim), notes = paste(engine, "artifact lifecycle fixture")
    )
    result <- wb_promote_analysis(
      b, setNames(list(run), run$run_id), run$run_id,
      outputs = "model", name_prefix = paste0(engine, "_lifecycle"), created_by = "test"
    )
    artifact_id <- as.character(result$promoted$artifact_id[result$promoted$output == "model"][[1L]])
    loaded <- wb_art_load(b, artifact_id, "model_ref")
    identity <- artifact_identity(artifact_id)
    presence <- .wb_model_ref_physical_presence(b, identity)
    stopifnot(isTRUE(presence$present), identical(presence$storage, "artifact_model_ref"),
              identical(presence$artifact_id, artifact_id))
    list(artifact_id = artifact_id, identity = identity, model_path = presence$model_path)
  }
  peakvi <- promote_fixture_model("peakvi", "atac.peakvi.lifecycle", "ATAC_counts")
  palantir <- promote_fixture_model("palantir", "rna.palantir.lifecycle", "rna.scvi.lifecycle")

  finalized <- wb_finalize_recipient_bundle(b)
  stopifnot(isTRUE(finalized$ready))
  wb_close_bundle(b)
  recipient <- wb_bundle_validation_report(bundle_dir, "recipient")
  stopifnot(isTRUE(recipient$ok),
            identical(recipient$pre_validation_fingerprint, recipient$post_validation_fingerprint),
            !"ILLEGAL_HISTORICAL_ENTITY_DELETION" %in% recipient$diagnostics$code)

  # Writable reopen with validate=TRUE must use the same resolver during its
  # lifecycle migration/backfill and must not retract artifact-backed models.
  b <- wb_open_bundle(bundle_dir, validate = TRUE)
  life <- wb_entity_lifecycle(b, "model_ref", c(scvi_id, peakvi$identity, palantir$identity, umap_id))
  stopifnot(nrow(life) == 4L, all(life$lifecycle_state == "current"),
            all(life$provenance_bound == 1L))
  wb_close_bundle(b)

  copy_bundle <- function(label) {
    destination <- file.path(root, label)
    dir.create(destination, recursive = TRUE, showWarnings = FALSE)
    entries <- list.files(bundle_dir, recursive = TRUE, full.names = TRUE, all.files = TRUE, no.. = TRUE)
    dirs <- entries[dir.exists(entries)]
    for (path in dirs) dir.create(file.path(destination, substring(path, nchar(bundle_dir) + 2L)),
                                  recursive = TRUE, showWarnings = FALSE)
    files <- entries[!dir.exists(entries)]
    for (path in files) {
      target <- file.path(destination, substring(path, nchar(bundle_dir) + 2L))
      dir.create(dirname(target), recursive = TRUE, showWarnings = FALSE)
      stopifnot(file.copy(path, target, overwrite = TRUE, copy.mode = TRUE, copy.date = TRUE))
    }
    destination
  }
  mutate_db <- function(path, sql, params = NULL) {
    con <- DBI::dbConnect(RSQLite::SQLite(), file.path(path, "db", "app.sqlite"))
    on.exit(DBI::dbDisconnect(con), add = TRUE)
    if (is.null(params)) DBI::dbExecute(con, sql) else DBI::dbExecute(con, sql, params = params)
  }
  expect_code <- function(path, code) {
    report <- wb_bundle_validation_report(path, "content")
    stopifnot(isFALSE(report$ok), code %in% as.character(report$diagnostics$code))
  }

  missing_path <- copy_bundle("missing_model_path")
  unlink(file.path(missing_path, scvi_presence$model_path), recursive = TRUE, force = TRUE)
  expect_code(missing_path, "MODEL_REF_ARTIFACT_PAYLOAD_INVALID")

  escaped_path <- copy_bundle("escaped_model_path")
  mutate_db(escaped_path, "UPDATE artifact_model_ref SET model_path='../unrelated' WHERE artifact_id=?;",
            list(scvi_artifact))
  expect_code(escaped_path, "MODEL_REF_ARTIFACT_PAYLOAD_INVALID")

  missing_owner <- copy_bundle("missing_artifact_owner")
  mutate_db(missing_owner, "DELETE FROM artifacts WHERE artifact_id=?;", list(scvi_artifact))
  expect_code(missing_owner, "MODEL_REF_ARTIFACT_OWNER_INVALID")

  missing_payload <- copy_bundle("missing_artifact_payload")
  mutate_db(missing_payload, "DELETE FROM artifact_model_ref WHERE artifact_id=?;", list(scvi_artifact))
  expect_code(missing_payload, "MODEL_REF_ARTIFACT_PAYLOAD_MISSING")

  wrong_identity <- copy_bundle("wrong_semantic_identity")
  mutate_db(wrong_identity, "UPDATE artifact_model_ref SET engine='unrelated' WHERE artifact_id=?;",
            list(scvi_artifact))
  expect_code(wrong_identity, "MODEL_REF_ARTIFACT_IDENTITY_MISMATCH")

  missing_binding <- copy_bundle("missing_provenance_binding")
  mutate_db(missing_binding,
            "DELETE FROM prov_run_entity_bindings WHERE entity_kind='model_ref' AND entity_id=?;",
            list(scvi_id))
  expect_code(missing_binding, "MODEL_REF_PROVENANCE_BINDING_MISSING")

  missing_materialization <- copy_bundle("missing_provenance_materialization")
  mutate_db(missing_materialization, "
    DELETE FROM prov_materializations
    WHERE EXISTS (
      SELECT 1 FROM prov_run_entity_bindings binding
      WHERE binding.entity_kind='model_ref' AND binding.entity_id=?
        AND binding.direction='output'
        AND binding.commit_id=prov_materializations.commit_id
        AND binding.run_id=prov_materializations.run_id
        AND binding.binding_name=prov_materializations.output_name
    );
  ", list(scvi_id))
  expect_code(missing_materialization, "MODEL_REF_PROVENANCE_MATERIALIZATION_INVALID")
  TRUE
}
