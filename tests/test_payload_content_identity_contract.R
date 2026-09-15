test_payload_content_identity_contract <- function() {
  contract_test_activate_core_conformance_pack()
  # Object identities are portable across supported R runtimes.  This fixed
  # typed value has the same digest in the host and provisioned container even
  # though their R minor versions differ.
  portable_fixture <- list(
    a = "x", b = 1L, c = NA_character_,
    d = data.frame(x = 1:2, y = c("a", "b"), stringsAsFactors = FALSE)
  )
  stopifnot(identical(
    scworkbench:::.wb_prov_sha256_object(portable_fixture),
    "4b41b284b7e8ce919f64a0ed31852f481d868792280af36539261d316a277a56"
  ))

  left <- wb_prim_feature_table(data.frame(feature_id = c("g1", "g2"), score = c(1, 2), stringsAsFactors = FALSE), table_type = "de")
  changed <- wb_prim_feature_table(data.frame(feature_id = c("g1", "g2"), score = c(9, 2), stringsAsFactors = FALSE), table_type = "de")
  reordered <- wb_prim_feature_table(data.frame(feature_id = c("g2", "g1"), score = c(2, 1), stringsAsFactors = FALSE), table_type = "de")
  left_id <- scworkbench:::.wb_prov_payload_identity(NULL, left)
  changed_id <- scworkbench:::.wb_prov_payload_identity(NULL, changed)
  reordered_id <- scworkbench:::.wb_prov_payload_identity(NULL, reordered)
  stopifnot(identical(left_id$verification_level, "content"),
            identical(left_id$content_identity_scheme, unname(scworkbench:::.wb_content_identity_schemes()[["table"]])),
            identical(left_id$structural_fingerprint, changed_id$structural_fingerprint),
            left_id$content_sha256 != changed_id$content_sha256,
            left_id$content_sha256 != reordered_id$content_sha256)

  root <- tempfile("scwb_payload_identity_")
  b <- wb_init_bundle(root, overwrite = TRUE)
  on.exit({ try(wb_close_bundle(b), silent = TRUE); unlink(root, recursive = TRUE, force = TRUE) }, add = TRUE)
  ids <- paste0("c", seq_len(8L))
  wb_define_cells(b, ids, metadata = data.frame(cell_id = ids, perturbation = rep(c("ctrl", "drug"), each = 4L), lane = rep(c("L1", "L2"), times = 4L), stringsAsFactors = FALSE), set_name = "core")
  wb_attach_space(b, "identity_umap", data.frame(cell_id = ids, x = seq_along(ids), y = rev(seq_along(ids))))

  # Matrix identity consumes fragment file digests, never a dense matrix read.
  dir.create(file.path(root, "matrix_payload"))
  saveRDS(matrix(c(1, 0, 0, 1), nrow = 2L), file.path(root, "matrix_payload", "payload.rds"))
  DBI::dbExecute(
    b$con,
    "INSERT INTO matrices(matrix_id,n_features,n_cells,storage,path) VALUES('identity_matrix',2,8,'bpcells','matrix_payload');"
  )
  wb_register_matrix_fragment(b$con, "identity_matrix", "matrix_payload", c("g1", "g2"), ids)
  matrix_id <- scworkbench:::.wb_prov_payload_identity(b, wb_prim_matrix("identity_matrix"))
  space_id <- scworkbench:::.wb_prov_payload_identity(b, wb_prim_space_2d("identity_umap"))
  dir.create(file.path(root, "models"))
  saveRDS(list(coefficients = c(1, 2)), file.path(root, "models", "identity_model.rds"))
  model <- wb_prim_model_ref("identity_umap", "identity_matrix", engine = "test")
  model$model_path <- file.path("models", "identity_model.rds")
  model_id <- scworkbench:::.wb_prov_payload_identity(b, model)
  stopifnot(identical(matrix_id$verification_level, "content"), identical(space_id$verification_level, "content"), identical(model_id$verification_level, "content"),
            identical(matrix_id$content_identity_scheme, unname(scworkbench:::.wb_content_identity_schemes()[["matrix"]])),
            identical(space_id$content_identity_scheme, unname(scworkbench:::.wb_content_identity_schemes()[["dense_space"]])),
            identical(model_id$content_identity_scheme, unname(scworkbench:::.wb_content_identity_schemes()[["raw_file"]])),
            identical(model_id$content_sha256, scworkbench:::.wb_prov_file_tree_sha256(file.path(root, "models", "identity_model.rds"))))

  s <- wb_session_new()
  p <- wb_session_run_op(s, b, "metadata_cell_vector", inputs = list(source_column = "perturbation", vector_name = "identity_perturbation", value_type = "categorical", missing_policy = "error", overwrite = TRUE, cell_set = "all", min_cells = 1L)); s <- p$session
  l <- wb_session_run_op(s, b, "metadata_cell_vector", inputs = list(source_column = "lane", vector_name = "identity_lane", value_type = "categorical", missing_policy = "error", overwrite = TRUE, cell_set = "all", min_cells = 1L)); s <- l$session
  a <- wb_session_run_op(s, b, "scwbv2reference::two_table_terminal", inputs = list(a = wb_ref_run(p$run$run_id, "vector"), b = wb_ref_run(l$run$run_id, "vector"), cell_set = "all", min_cells = 1L)); s <- a$session
  promoted <- wb_session_promote_current(b, s, created_by = "payload-identity", outputs = list(wb_ref_run(a$run$run_id, "summary"), wb_ref_run(a$run$run_id, "detail")))
  sid <- as.character(promoted$provenance_snapshot_id)[1]
  stored <- DBI::dbGetQuery(b$con, "SELECT output_name, output_hash, structural_fingerprint, content_sha256, content_identity_scheme, verification_level, verification_status FROM prov_run_outputs WHERE snapshot_id = ? AND run_id = ? ORDER BY output_name;", params = list(sid, a$run$run_id))
  stopifnot(nrow(stored) == 2L, all(stored$verification_level == "content"), all(stored$verification_status == "content_verified"), all(grepl("^[0-9a-f]{64}$", stored$content_sha256)),
            all(stored$content_identity_scheme == unname(scworkbench:::.wb_content_identity_schemes()[["table"]])))
  verified <- wb_prov_validate_replay(b, snapshot_id = sid, profile = "strict", strict = TRUE)
  stopifnot(isTRUE(verified$summary$valid), all(verified$per_output$verification_level == "content"))
  summary_artifact <- as.character(promoted$promoted$artifact_id[promoted$promoted$output == "summary"])[1]
  recipient <- wb_entity_certificate(b, "artifact", summary_artifact)
  stopifnot(identical(as.character(recipient$identity$verification_status), "content_verified"),
            identical(as.character(recipient$identity$content_identity_scheme), unname(scworkbench:::.wb_content_identity_schemes()[["table"]])))

  # Same-kind/same-shape output with a changed SHA must fail strict content validation.
  DBI::dbExecute(b$con, "UPDATE prov_run_outputs SET content_sha256 = ? WHERE snapshot_id = ? AND run_id = ? AND output_name = ?;", params = list(strrep("0", 64L), sid, a$run$run_id, "summary"))
  altered <- wb_prov_validate_replay(b, snapshot_id = sid, profile = "strict", strict = FALSE)
  altered_row <- altered$per_output[altered$per_output$run_id == a$run$run_id & altered$per_output$output_name == "summary", , drop = FALSE]
  stopifnot(nrow(altered_row) == 1L, isTRUE(altered_row$kind_match[1]), !isTRUE(altered_row$hash_match[1]), !isTRUE(altered_row$output_match[1]))

  # Existing records with no content digest remain visible as legacy structural-only.
  DBI::dbExecute(b$con, "UPDATE prov_run_outputs SET content_sha256 = NULL, verification_level = 'structural', verification_status = 'legacy_structural_only' WHERE snapshot_id = ? AND run_id = ? AND output_name = ?;", params = list(sid, a$run$run_id, "detail"))
  detail <- wb_prov_run_details(b, run_id = a$run$run_id, snapshot_id = sid)$outputs
  stopifnot(identical(as.character(detail$verification_status[detail$output_name == "detail"]), "legacy_structural_only"))
  DBI::dbExecute(b$con, "UPDATE prov_run_outputs SET replay_equivalence_policy = NULL, replay_equivalence_status = NULL WHERE snapshot_id = ? AND run_id = ? AND output_name = ?;", params = list(sid, a$run$run_id, "detail"))
  DBI::dbExecute(b$con, "DROP TABLE bundle_schema_migrations;")
  wb_migrate_bundle(b)
  legacy_replay <- DBI::dbGetQuery(b$con, "SELECT replay_equivalence_policy, replay_equivalence_status FROM prov_run_outputs WHERE snapshot_id = ? AND run_id = ? AND output_name = ?;", params = list(sid, a$run$run_id, "detail"))
  stopifnot(identical(as.character(legacy_replay$replay_equivalence_policy[1]), "not_comparable"),
            identical(as.character(legacy_replay$replay_equivalence_status[1]), "legacy_not_comparable"))
  TRUE
}
