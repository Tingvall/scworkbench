test_atomic_authoritative_manifest_contract <- function() {
  if (!requireNamespace("BPCells", quietly = TRUE)) {
    return(contract_test_skip("BPCells is not installed."))
  }

  root <- tempfile("scwb_atomic_manifest_")
  b <- wb_init_bundle(root, overwrite = TRUE)
  old_hook <- getOption("scworkbench.manifest_test_hook")
  on.exit({
    options(scworkbench.manifest_test_hook = old_hook)
    try(wb_close_bundle(b), silent = TRUE)
    unlink(root, recursive = TRUE, force = TRUE)
  }, add = TRUE)
  manifest_path <- file.path(root, "manifest.json")
  cells <- paste0("cell", seq_len(12L))
  features <- paste0("gene", seq_len(5L))
  wb_define_cells(b, cells, dataset_id = "dataset_1", metadata = data.frame(
    cell_id = cells, atomic_group = rep(c("a", "b"), length.out = length(cells)),
    stringsAsFactors = FALSE
  ))
  wb_attach_matrix(
    b, "RNA_counts",
    Matrix::Matrix(
      matrix(seq_len(60L), nrow = 5L, dimnames = list(features, cells)),
      sparse = TRUE
    ),
    feature_type = "gene"
  )

  direct_manifest <- function() jsonlite::read_json(manifest_path, simplifyVector = TRUE)
  manifest_bytes <- function() readBin(manifest_path, "raw", n = file.info(manifest_path)$size)
  assert_agreement <- function(checkpoint) {
    direct <- direct_manifest()
    public <- wb_manifest(b)
    diagnostic <- wb_manifest(b, view = "reconstructed")
    if (!isTRUE(diagnostic$publication$durable_registry_agreement)) {
      stop("manifest disagreement at checkpoint: ", checkpoint, call. = FALSE)
    }
    stopifnot(
      identical(direct, public),
      identical(as.character(public$publication$state_source), "durable_manifest"),
      identical(as.character(diagnostic$publication$state_source), "reconstructed_diagnostic"),
      identical(as.character(direct$current_state$fingerprint),
                as.character(diagnostic$current_state$fingerprint))
    )
    invisible(direct)
  }
  initial <- assert_agreement("initial ingestion")
  wb_close_bundle(b)
  b <- wb_open_bundle(root)

  # Interruption after the complete temporary file is flushed leaves the old
  # durable name byte-for-byte intact while the already committed registry
  # difference remains explicitly diagnosable and recoverable.
  old_bytes <- manifest_bytes()
  options(scworkbench.manifest_test_hook = function(event, staged, ...) {
    if (identical(event, "staged")) writeLines("{", staged, useBytes = TRUE)
  })
  interrupted <- try(wb_attach_apply(
    b,
    metadata = data.frame(cell_id = cells, interrupted_value = seq_along(cells)),
    source = "atomic_manifest_contract"
  ), silent = TRUE)
  stopifnot(
    inherits(interrupted, "try-error"),
    grepl("Staged bundle manifest failed JSON validation", as.character(interrupted), fixed = TRUE),
    identical(manifest_bytes(), old_bytes),
    is.list(direct_manifest()),
    !isTRUE(wb_manifest(b, "reconstructed")$publication$durable_registry_agreement)
  )
  options(scworkbench.manifest_test_hook = NULL)
  scworkbench:::.wb_with_mutation_context(
    b, route = "ingestion", code = wb_refresh_manifest(b)
  )
  after_recovery <- assert_agreement("failure recovery")
  stopifnot(!identical(initial$current_state$fingerprint,
                       after_recovery$current_state$fingerprint))

  # A declared registry mutation route also receives the outer writer's
  # authoritative publication tail step.
  before_registry <- after_recovery$current_state$fingerprint
  scworkbench:::.wb_with_mutation_context(
    b, route = "ingestion", code = wb_cell_set_replace(
      b, "set:atomic_manifest_registry", cells[1:6],
      source = "atomic_manifest_contract", strict = TRUE
    )
  )
  after_registry <- assert_agreement("registry mutation")
  stopifnot(
    !identical(before_registry, after_registry$current_state$fingerprint),
    "set:atomic_manifest_registry" %in% wb_cell_sets(b)
  )

  # A publication failure immediately before rename also preserves the old
  # complete file. A simulated interruption after the rename leaves the new
  # complete authoritative file; neither boundary can expose mixed JSON.
  old_bytes <- manifest_bytes()
  options(scworkbench.manifest_test_hook = function(event, ...) {
    if (identical(event, "before_publish")) stop("forced manifest publication failure", call. = FALSE)
  })
  failed_publish <- try(wb_attach_apply(
    b,
    metadata = data.frame(cell_id = cells, publication_failure_value = rev(seq_along(cells))),
    source = "atomic_manifest_contract"
  ), silent = TRUE)
  stopifnot(
    inherits(failed_publish, "try-error"),
    grepl("forced manifest publication failure", as.character(failed_publish), fixed = TRUE),
    identical(manifest_bytes(), old_bytes), is.list(direct_manifest())
  )

  options(scworkbench.manifest_test_hook = function(event, ...) {
    if (identical(event, "published")) stop("forced interruption after manifest commit", call. = FALSE)
  })
  published_then_interrupted <- try(wb_attach_apply(
    b,
    metadata = data.frame(cell_id = cells, post_commit_value = seq_along(cells) * 2L),
    source = "atomic_manifest_contract"
  ), silent = TRUE)
  stopifnot(
    inherits(published_then_interrupted, "try-error"),
    grepl("forced interruption after manifest commit", as.character(published_then_interrupted), fixed = TRUE),
    !identical(manifest_bytes(), old_bytes), is.list(direct_manifest())
  )
  options(scworkbench.manifest_test_hook = NULL)
  assert_agreement("post-rename interruption")

  # Promotion publishes artifact/provenance registries only after their
  # coordinator transaction commits.
  executed <- wb_session_run_op(
    wb_session_new(), b, "metadata_cell_vector",
    inputs = list(source_column = "atomic_group", vector_name = "atomic_group_1",
      value_type = "categorical", missing_policy = "error",
      cell_set = "all", min_cells = 1L)
  )
  before_promotion <- wb_manifest(b)$current_state$fingerprint
  promoted <- wb_session_promote_current(
    b, executed$session, outputs = "vector",
    name_prefix = "atomic_manifest_contract"
  )
  stopifnot(any(promoted$promoted$status == "ok"))
  after_promotion <- assert_agreement("promotion")
  stopifnot(!identical(before_promotion, after_promotion$current_state$fingerprint))

  # A second promoted artifact can supersede the first without stale lifecycle
  # or supersession state in the durable manifest.
  executed_2 <- wb_session_run_op(
    wb_session_new(), b, "metadata_cell_vector",
    inputs = list(source_column = "atomic_group", vector_name = "atomic_group_2",
      value_type = "categorical", missing_policy = "error",
      cell_set = "all", min_cells = 1L)
  )
  promoted_2 <- wb_session_promote_current(
    b, executed_2$session, outputs = "vector",
    name_prefix = "atomic_manifest_contract_successor"
  )
  predecessor <- as.character(promoted$promoted$artifact_id[promoted$promoted$status == "ok"])[1]
  successor <- as.character(promoted_2$promoted$artifact_id[promoted_2$promoted$status == "ok"])[1]
  wb_entity_supersede(
    b, "artifact", successor, predecessor,
    reason = "atomic manifest supersession regression", created_by = "contract"
  )
  superseded_manifest <- assert_agreement("supersession")
  stopifnot(
    as.integer(superseded_manifest$current_state$tables$entity_supersessions$row_count) >= 1L,
    any(wb_entity_lifecycle(b, "artifact", predecessor)$lifecycle_state == "superseded")
  )

  # Finalization refreshes under the same writer lock. Recipient immutable-open
  # validation proves direct manifest/registry agreement without repair.
  finalized <- wb_finalize_recipient_bundle(b)
  stopifnot(isTRUE(finalized$ready))
  assert_agreement("finalization")
  wb_close_bundle(b)
  b <- NULL
  recipient <- wb_open_bundle(root, read_only = TRUE)
  on.exit(try(wb_close_bundle(recipient), silent = TRUE), add = TRUE)
  stopifnot(identical(wb_manifest(recipient), direct_manifest()))
  report <- wb_bundle_validation_report(root, "recipient")
  stopifnot(
    isTRUE(report$ok),
    !any(as.character(report$diagnostics$code) == "MANIFEST_REGISTRY_MISMATCH")
  )
  wb_close_bundle(recipient)
  recipient <- NULL

  transient <- list.files(root, all.files = TRUE, no.. = TRUE)
  stopifnot(!any(grepl("^\\.manifest[.]json[.](staging|backup)-", transient)))
  TRUE
}
