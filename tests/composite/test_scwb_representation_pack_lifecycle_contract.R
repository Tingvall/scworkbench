.representation_fixture <- function() {
  root <- tempfile("scwbRepresentation-composite-")
  bundle <- wb_init_bundle(root, overwrite = TRUE)
  cells <- paste0("c", seq_len(8L))
  coords <- rbind(c(-3, -3, 0), c(-3, -2, .2), c(-2, -3, -.2),
    c(-2, -2, .1), c(3, 3, 0), c(3, 2, -.2), c(2, 3, .2),
    c(2, 2, -.1))
  rownames(coords) <- cells
  colnames(coords) <- paste0("D", seq_len(ncol(coords)))
  wb_define_cells(bundle, cells)
  wb_add_space(bundle, "latent", coords, overwrite = TRUE)
  space <- structure(list(kind = "space", space_id = "latent",
    values = coords, dimensions = as.integer(dim(coords)), cell_id = cells,
    storage_profile = "space_dense_v1"), class = "wb_primitive")
  list(root = root, bundle = bundle, cells = cells, space = space)
}

.representation_lifecycle_registry_snapshot <- function() {
  registry <- getFromNamespace(".wb_operation_pack_registry", "scworkbench")
  list(registry = registry, packs = registry$packs,
    operations = registry$operations)
}

.representation_lifecycle_registry_restore <- function(snapshot) {
  snapshot$registry$packs <- snapshot$packs
  snapshot$registry$operations <- snapshot$operations
  invisible(TRUE)
}

test_representation_leiden_atomic_lifecycle_contract <- function() {
  if (!requireNamespace("igraph", quietly = TRUE) ||
      !requireNamespace("RANN", quietly = TRUE))
    return(contract_test_skip("igraph or RANN is not installed."))
  contract_test_activate_representation_pack()
  f <- .representation_fixture(); b <- f$bundle
  on.exit({ options(scworkbench.operation_pack_v2_test_hook = NULL)
    try(wb_close_bundle(b), silent = TRUE); unlink(f$root, recursive = TRUE) },
    add = TRUE)

  state <- function() getFromNamespace(".wb_manifest_registry_snapshot",
    "scworkbench")(b$con)$fingerprint
  before <- state()
  options(scworkbench.operation_pack_v2_test_hook = function(event, ...) {
    if (identical(event, "before_publication"))
      stop("injected Representation publication failure", call. = FALSE)
  })
  execute <- getFromNamespace(".wb_operation_pack_v2_execute",
    "scworkbench")
  failed <- tryCatch(execute(b, "scwbrepresentation::leiden",
    list(space = f$space), list(dims = NULL, k = 5L, resolution = 1,
      n_iterations = 2L, seed = 7L, weight = TRUE),
    effective_cells = f$cells), error = identity)
  options(scworkbench.operation_pack_v2_test_hook = NULL)
  stopifnot(inherits(failed, "error"), identical(before, state()),
    nrow(wb_art_list(b)) == 0L,
    !dir.exists(file.path(b$dir, "operation_pack_v2")))

  run <- wb_session_run_op(wb_session_new(), b, "leiden", inputs = list(
    space = "latent", dims = NULL, k = 5L, resolution = 1,
    n_iterations = 2L, seed = 7L, weight = TRUE, min_cells = 1L))
  stopifnot(identical(run$run$op_name, "scwbrepresentation::leiden"),
    identical(run$run$outputs$clusters$cell_id, f$cells),
    identical(run$run$outputs$clusters$value_type, "categorical"),
    identical(run$run$outputs$clusters$meta,
      list(label = "Leiden clusters")))
  reference <- jsonlite::read_json(file.path(
    Sys.getenv("SCWBREPRESENTATION_SOURCE"), "tests", "fixtures",
    "leiden_old_core_reference.json"), simplifyVector = TRUE)
  stopifnot(identical(as.character(run$run$outputs$clusters$value),
      as.character(reference$terminal$value)),
    identical(as.character(run$run$outputs$clusters$cell_id),
      as.character(reference$terminal$cell_id)))
  promoted <- wb_session_promote_current(b, run$session,
    outputs = "clusters", created_by = "phase4a_composite")
  stopifnot(all(promoted$promoted$status == "ok"))
  artifact_id <- promoted$promoted$artifact_id[[1L]]
  run_id <- run$run$run_id
  artifact <- wb_art_load(b, artifact_id)
  identity <- getFromNamespace(".wb_prov_payload_identity", "scworkbench")
  expected_identity <- identity(b, run$run$outputs$clusters)$content_sha256
  observed_identity <- identity(b, artifact)$content_sha256
  details <- wb_prov_run_details(b, run_id,
    promoted$provenance_snapshot_id)
  reference_params <- reference$retained_effective_parameters[c("k", "dims",
    "resolution", "n_iterations", "seed", "weight")]
  stopifnot(identical(expected_identity, observed_identity),
    identical(expected_identity, reference$terminal$content_sha256),
    identical(details$run$params[names(reference_params)], reference_params),
    identical(as.integer(details$run$execution_inputs$effective_n), 8L),
    identical(details$run$execution_inputs$resolved$space$space_id, "latent"),
    isTRUE(wb_finalize_recipient_bundle(b)$ready))
  artifacts <- wb_art_list(b)
  run$session <- wb_session_discard(run$session)
  wb_close_bundle(b); b <- NULL

  registry <- getFromNamespace(".wb_operation_pack_registry", "scworkbench")
  saved <- .representation_lifecycle_registry_snapshot()
  for (name in saved$packs$scwbrepresentation$operation_names)
    registry$operations[[name]] <- NULL
  registry$packs$scwbrepresentation <- NULL
  b <- wb_open_bundle(f$root, validate = TRUE, read_only = TRUE)
  reloaded <- wb_art_load(b, artifact_id, expected_kind = "cell_vector")
  stopifnot(isTRUE(wb_validate_bundle(f$root, read_only = TRUE)),
    identical(artifacts, wb_art_list(b)), identical(artifact, reloaded))
  history <- wb_prov_run_details(b, run_id)
  stopifnot(identical(history$run$op_name,
    "scwbrepresentation::leiden"))
  wb_close_bundle(b); b <- NULL
  .representation_lifecycle_registry_restore(saved)
  TRUE
}
