.geneprograms_composite_fixture <- function() {
  root <- tempfile("scwbGenePrograms-composite-")
  bundle <- wb_init_bundle(root, overwrite = TRUE)
  cells <- paste0("c", seq_len(8L)); features <- paste0("g", seq_len(8L))
  values <- matrix(c(9,8,7,6,1,0,1,0, 8,7,6,5,0,1,0,1,
    1,0,1,0,9,8,7,6, 0,1,0,1,8,7,6,5,
    2,3,2,3,2,3,2,3, 3,2,3,2,3,2,3,2,
    4,4,3,3,2,2,1,1, 1,1,2,2,3,3,4,4), nrow = 8L,
    byrow = TRUE, dimnames = list(features, cells))
  wb_define_cells(bundle, cells)
  wb_attach_matrix(bundle, "RNA", Matrix::Matrix(values, sparse = TRUE),
    feature_type = "gene")
  coords <- cbind(x = seq_along(cells), y = rep(c(1, 2), 4L)); rownames(coords) <- cells
  wb_add_space(bundle, "fixture_space", coords, overwrite = TRUE)
  list(root = root, bundle = bundle, cells = cells, features = features)
}

test_geneprograms_promotion_reopen_replay_recipient_contract <- function() {
  contract_test_activate_geneprograms_pack()
  f <- .geneprograms_composite_fixture(); b <- f$bundle
  on.exit({ try(wb_close_bundle(b), silent = TRUE); unlink(f$root, recursive = TRUE) },
    add = TRUE)
  first <- wb_session_run_op(wb_session_new(), b, "addmodulescore", inputs = list(
    matrix = "RNA", features = list(A = f$features[1:2], B = f$features[3:4]),
    pool = f$features, nbin = 4L, ctrl = 2L, seed = 7L, min_cells = 1L))
  second <- wb_session_run_op(first$session, b, "cell_vector_family_reduce",
    inputs = list(signal = wb_ref_run(first$run$run_id, "module_scores"),
      rule = "argmax", min_margin = 0, ties = "unknown", min_cells = 1L))
  third <- wb_session_run_op(second$session, b, "cell_vector_winners",
    inputs = list(signal = wb_ref_run(first$run$run_id, "module_scores"),
      min_winners = 1L, tie_method = "first", min_cells = 1L))
  fourth <- wb_session_run_op(third$session, b, "winner_cell_sets", inputs = list(
    winners = wb_ref_run(third$run$run_id, "winners"),
    cell_set_prefix = "winner_", replace = TRUE, min_cells = 1L))
  promotion <- wb_promote_analysis(b, fourth$session$runs,
    c(second$run$run_id, fourth$run$run_id),
    staging_bundle = wb_session_view(fourth$session),
    created_by = "composite", fail_fast = TRUE)
  stopifnot(all(promotion$promoted$status == "ok"),
    all(vapply(list(first, second, third, fourth), function(x)
      startsWith(x$run$op_name, "scwbgeneprograms::"), logical(1))))
  snapshot <- promotion$provenance_snapshot_id
  replay <- wb_prov_validate_replay(b, snapshot_id = snapshot,
    profile = "strict", strict = TRUE)
  stopifnot(isTRUE(replay$summary$valid),
    isTRUE(wb_finalize_recipient_bundle(b)$ready))
  artifacts <- wb_art_list(b); stopifnot(nrow(artifacts) >= 10L)
  wb_close_bundle(b); b <- NULL

  registry <- getFromNamespace(".wb_operation_pack_registry", "scworkbench")
  saved <- .geneprograms_registry_snapshot()
  for (name in saved$packs$scwbgeneprograms$operation_names)
    registry$operations[[name]] <- NULL
  registry$packs$scwbgeneprograms <- NULL
  b <- wb_open_bundle(f$root, validate = TRUE, read_only = TRUE)
  stopifnot(isTRUE(wb_validate_bundle(f$root, read_only = TRUE)),
    nrow(wb_art_list(b)) == nrow(artifacts))
  for (id in wb_art_list(b)$artifact_id)
    stopifnot(inherits(wb_art_load(b, id), "wb_primitive"))
  missing <- tryCatch(getFromNamespace(".wb_op", "scworkbench")(
    "addmodulescore"), error = identity)
  stopifnot(inherits(missing, "wb_operation_pack_error"),
    identical(missing$code, "OPERATION_PACK_REQUIRED"))
  wb_close_bundle(b); b <- NULL
  .geneprograms_registry_restore(saved)
  TRUE
}

test_geneprograms_graph_ancestry_omitted_explicit_contract <- function() {
  if (!requireNamespace("RANN", quietly = TRUE))
    return(contract_test_skip("RANN is not installed."))
  contract_test_activate_geneprograms_pack()
  f <- .geneprograms_composite_fixture(); b <- f$bundle
  on.exit({ try(wb_close_bundle(b), silent = TRUE); unlink(f$root, recursive = TRUE) },
    add = TRUE)
  score <- wb_session_run_op(wb_session_new(), b, "addmodulescore", inputs = list(
    matrix = "RNA", features = list(A = f$features[1:2], B = f$features[3:4]),
    pool = f$features, nbin = 4L, ctrl = 2L, seed = 7L, min_cells = 1L))
  promoted <- wb_session_promote_current(b, score$session,
    outputs = "module_scores", created_by = "composite")
  artifact <- promoted$promoted$artifact_id[[1L]]
  omitted <- wb_session_run_op(wb_session_new(), b,
    "cell_vector_family_graph_smooth", inputs = list(
      signal = wb_ref_artifact(artifact, "module_scores"), space = wb_prim_space("fixture_space"),
      k = 2L, alpha = .5, query_chunk_size = 3L, min_cells = 1L))
  meta <- omitted$run$outputs$smoothed_signal$meta
  explicit <- wb_session_run_op(wb_session_new(), b,
    "cell_vector_family_graph_smooth", inputs = list(
      signal = wb_ref_artifact(artifact, "module_scores"), space = wb_prim_space("fixture_space"),
      k = 2L, alpha = .5, query_chunk_size = 3L,
      source_signal_artifact_id = artifact, source_run_id = meta$source_run_id,
      source_snapshot_id = meta$source_snapshot_id, min_cells = 1L))
  stopifnot(identical(omitted$run$outputs$smoothed_signal,
      explicit$run$outputs$smoothed_signal),
    identical(meta$source_signal_artifact_id, artifact))
  stale <- tryCatch(wb_session_run_op(wb_session_new(), b,
    "cell_vector_family_graph_smooth", inputs = list(
      signal = wb_ref_artifact(artifact, "module_scores"), space = wb_prim_space("fixture_space"),
      k = 2L, source_run_id = "run_wrong", min_cells = 1L)), error = identity)
  stopifnot(inherits(stale, "wb_operation_pack_error"))
  TRUE
}
