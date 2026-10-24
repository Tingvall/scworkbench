test_fingerprint_scope_transfer_contract <- function() {
  root <- tempfile("fingerprint-scope-"); dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  path <- file.path(root, "producer")
  b <- wb_init_bundle(path)
  wb_define_cells(b, paste0("c", 1:3), metadata = data.frame(cell_id = paste0("c", 1:3), score = 1:3))
  run <- wb_session_run_op(wb_session_new(), b, "metadata_cell_vector", inputs = list(
    source_column = "score", vector_name = "score", value_type = "continuous",
    missing_policy = "error", min_cells = 1L))
  promoted <- wb_session_promote_current(b, run$session, outputs = "vector")
  aid <- promoted$promoted$artifact_id[[1]]
  stopifnot(wb_finalize_recipient_bundle(b)$ready)
  wb_close_bundle(b)
  identity <- function(b) {
    x <- wb_entity_certificate(b, "artifact", aid)$identity
    stopifnot(x$verification_status == "content_verified", x$observed$status == "verified")
    list(scheme = x$content_identity_scheme, sha256 = x$content_sha256)
  }
  original <- wb_open_bundle(path, read_only = TRUE)
  before <- identity(original)
  registry <- wb_manifest(original)$current_state$fingerprint
  wb_close_bundle(original)
  report <- wb_bundle_validation_report(path, "recipient")
  target <- file.path(root, "relocated")
  fs::dir_copy(path, target)
  # A host file-mode difference is deliberately not a logical content change.
  Sys.chmod(file.path(target, "db", "app.sqlite"), mode = "0444")
  ro <- wb_open_bundle(target, read_only = TRUE)
  stopifnot(identical(identity(ro), before), identical(wb_manifest(ro)$current_state$fingerprint, registry))
  wb_close_bundle(ro)
  relocated <- wb_bundle_validation_report(target, "recipient")
  stopifnot(report$ok, relocated$ok,
    identical(report$pre_validation_fingerprint, report$post_validation_fingerprint),
    identical(relocated$pre_validation_fingerprint, relocated$post_validation_fingerprint),
    !identical(report$bundle_path, relocated$bundle_path),
    !identical(report$pre_validation_fingerprint, relocated$pre_validation_fingerprint),
    identical(report$identity_scopes, relocated$identity_scopes),
    identical(report$identity_scopes$filesystem_observation$includes_absolute_root, FALSE),
    identical(report$identity_scopes$filesystem_observation$portable_logical_content_identity, FALSE))
  cat("PORTABLE", before$scheme, before$sha256, "registry", registry, "\n")
  TRUE
}
