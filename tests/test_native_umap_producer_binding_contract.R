.native_umap_binding_fixture <- function() {
  required <- c("scwbRepresentation", "uwot", "rnndescent")
  stopifnot(all(vapply(required, requireNamespace, logical(1), quietly = TRUE)))
  if (!"scwbrepresentation::umap_fit" %in% wb_list_ops())
    wb_operation_pack_activate(system.file("scworkbench", "operation-pack.json",
      package = "scwbRepresentation"), lib.loc = .libPaths())
  root <- tempfile("native_umap_binding_")
  bundle <- wb_init_bundle(root)
  cells <- paste0("c", sprintf("%02d", seq_len(30L)))
  values <- outer(seq_along(cells), seq_len(4L), function(i, j)
    sin(i * j / 7) + cos(i / (j + 1)))
  dimnames(values) <- list(cells, paste0("PC", seq_len(4L)))
  wb_define_cells(bundle, cells)
  wb_add_space(bundle, "pca", values)
  wb_cell_set_replace(bundle, "set:query", cells[seq_len(8L)], source = "native-model-test")
  fit <- wb_session_run_op(wb_session_new(), bundle, "scwbrepresentation::umap_fit",
    inputs = list(space = "pca", dims = 1:3, space_id_out = "umap.pca",
      n_neighbors = 5L, min_dist = .2, nn_method = "nndescent", seed = 17L))
  promoted <- wb_session_promote_current(bundle, fit$session, outputs = "model")
  artifact_id <- promoted$promoted$artifact_id[promoted$promoted$output == "model"][[1L]]
  list(root = root, bundle = bundle, cells = cells, fit = fit,
    artifact_id = artifact_id, space_id = "umap.pca")
}

.native_umap_binding_assert <- function(bundle, fixture, space_run = fixture$fit$run$run_id) {
  subjects <- list(model = c("model", fixture$space_id),
    artifact = c("artifact", fixture$artifact_id), space = c("space", fixture$space_id))
  certificates <- lapply(subjects, function(subject)
    wb_entity_certificate(bundle, subject[[1L]], subject[[2L]]))
  for (name in names(certificates)) {
    value <- certificates[[name]]
    stopifnot(identical(value$producer$status, "available"),
      identical(value$identity$verification_status, "content_verified"),
      identical(value$identity$verification_level, "content"),
      identical(value$lifecycle$state, "current"),
      value$lifecycle$record$value$provenance_bound == 1L,
      identical(value$producer$run_id, if (name == "space") space_run else fixture$fit$run$run_id))
  }
  opaque <- wb_entity_certificate(bundle, "model", paste("uwot", fixture$space_id, "pca", sep = "|"))
  stopifnot(identical(opaque$identity$verification_status, "content_verified"),
    identical(opaque$identity$content_sha256, certificates$model$identity$content_sha256))
  stopifnot(identical(certificates$model$identity$content_identity_scheme,
      "scworkbench.content.file-tree.canonical-json.v1"),
    identical(certificates$model$identity$content_sha256, certificates$artifact$identity$content_sha256),
    identical(certificates$artifact$identity$content_identity_scheme,
      "scworkbench.content.file-tree.canonical-json.v1"),
    identical(certificates$space$identity$content_identity_scheme,
      "scworkbench.content.dense-space-hdf5.sha256.v1"),
    length(certificates$model$relationships$immediate_inputs$items) > 0L,
    wb_space_model(bundle, fixture$space_id)$provenance_bound[[1L]] == 1L)
  certificates
}

test_native_umap_producer_certificates_reopen_and_reuse_contract <- function() {
  fixture <- .native_umap_binding_fixture(); b <- fixture$bundle
  transfer <- tempfile("native_umap_recipient_"); dir.create(transfer)
  on.exit({try(wb_close_bundle(b), silent = TRUE)
    unlink(c(fixture$root, transfer), recursive = TRUE)}, add = TRUE)
  initial <- .native_umap_binding_assert(b, fixture)
  provenance <- jsonlite::fromJSON(wb_space_model(b, fixture$space_id)$provenance_json[[1L]],
    simplifyVector = FALSE)
  stopifnot(identical(provenance$producer_run_id, fixture$fit$run$run_id),
    identical(provenance$producer_output_name, "model"))
  # A reference emitted by a different run cannot acquire native fit ownership.
  before <- DBI::dbGetQuery(b$con, "SELECT * FROM prov_run_entity_bindings WHERE entity_kind='model'")
  stopifnot(identical(scworkbench:::.wb_prov_bind_native_space_model(b,
    fixture$fit$run$outputs$model, "unused", "unused", "different_run", "model"), FALSE),
    identical(before, DBI::dbGetQuery(b$con, "SELECT * FROM prov_run_entity_bindings WHERE entity_kind='model'")))
  stopifnot(wb_finalize_recipient_bundle(b)$ready)
  wb_close_bundle(b); b <- NULL
  stopifnot(file.copy(fixture$root, transfer, recursive = TRUE))
  relocated <- file.path(transfer, basename(fixture$root)); unlink(fixture$root, recursive = TRUE)
  # Fresh R process: no staging handles or in-session producer observations.
  output <- tempfile(fileext = ".rds"); on.exit(unlink(output), add = TRUE)
  code <- paste0('a<-commandArgs(TRUE);.libPaths(c(a[1],.libPaths()));library(scworkbench);',
    'b<-wb_open_bundle(a[2],read_only=TRUE,validate=TRUE);',
    's<-list(c("model",a[3]),c("artifact",a[4]),c("space",a[3]));',
    'saveRDS(lapply(s,function(x)wb_entity_certificate(b,x[1],x[2])),a[5]);wb_close_bundle(b)')
  child <- processx::run(file.path(R.home("bin"), "Rscript"), c("-e", code,
    dirname(find.package("scworkbench")), relocated, fixture$space_id, fixture$artifact_id, output),
    timeout = 60000, error_on_status = FALSE)
  if (child$status != 0L) stop(child$stderr)
  fresh <- readRDS(output)
  stopifnot(all(vapply(fresh, function(x) identical(x$producer$run_id, fixture$fit$run$run_id) &&
    identical(x$identity$verification_status, "content_verified"), logical(1))),
    identical(fresh[[1L]]$identity$content_sha256, initial$model$identity$content_sha256))
  b <- wb_open_bundle(relocated)
  .native_umap_binding_assert(b, fixture)
  projected <- wb_session_run_op(wb_session_new(), b, "scwbrepresentation::umap_transform",
    inputs = list(model = wb_ref_artifact(fixture$artifact_id, "model"), in_space = "pca",
      dims = 1:3, cell_set = "set:query", min_cells = 2L,
      space_id_out = fixture$space_id, overwrite = TRUE))
  saved <- wb_session_promote_current(b, projected$session, outputs = "projection_membership")
  stopifnot(all(saved$promoted$status == "ok"),
    all(is.finite(projected$run$outputs$space_2d$values)))
  after <- .native_umap_binding_assert(b, fixture, space_run = projected$run$run_id)
  stopifnot(identical(after$model$identity$content_sha256, initial$model$identity$content_sha256),
    wb_finalize_recipient_bundle(b)$ready)
  wb_close_bundle(b); b <- NULL
  stopifnot(wb_bundle_validation_report(relocated, "recipient")$ok)
  TRUE
}

