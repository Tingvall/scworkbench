test_scwb_representation_cell_vector_durable_identity_roundtrip_contract <- function() {
  contract_test_activate_representation_pack()
  required <- c("igraph", "RANN")
  missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing)) {
    return(contract_test_skip(paste("Missing runtime dependencies:", paste(missing, collapse = ", "))))
  }

  root <- tempfile("scwb_cell_vector_roundtrip_")
  b <- wb_init_bundle(root, overwrite = TRUE)
  on.exit({
    try(wb_close_bundle(b), silent = TRUE)
    unlink(root, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  # Deliberately non-lexicographic order makes the durable cell-order contract
  # observable instead of accidentally relying on SQLite row order.
  cells <- c("cell_10", "cell_2", "cell_1", "cell_12", "cell_3", "cell_11",
             "cell_4", "cell_9", "cell_5", "cell_8", "cell_6", "cell_7")
  category <- stats::setNames(rep(c("control", "treated", "washout"), 4L), cells)
  score <- stats::setNames(c(0.5, 1.25, 2.75, 4.5, 8.25, 16.5,
                             3.125, 6.25, 12.5, 25, 50, 100), cells)
  metadata <- data.frame(
    cell_id = cells,
    category = unname(category),
    score = unname(score),
    stringsAsFactors = FALSE
  )
  coords <- data.frame(
    cell_id = cells,
    d1 = seq_along(cells),
    d2 = ((seq_along(cells) * 7L) %% 13L) + seq_along(cells) / 10,
    d3 = sin(seq_along(cells)),
    stringsAsFactors = FALSE
  )
  wb_define_cells(b, cells, metadata = metadata, set_name = "core")
  wb_attach_space(b, "latent", coords)

  inherited_before <- list(
    cells = DBI::dbGetQuery(b$con, "SELECT * FROM cells ORDER BY rowid;"),
    spaces = DBI::dbGetQuery(b$con, "SELECT * FROM spaces ORDER BY space_id;"),
    payload = DBI::dbGetQuery(b$con, "SELECT * FROM space_payloads WHERE space_id = 'latent';"),
    identity = scworkbench:::.wb_prov_payload_identity(b, wb_prim_space("latent"))$content_sha256
  )

  session <- wb_session_new()
  categorical <- wb_session_run_op(
    session, b, "metadata_cell_vector",
    inputs = list(source_column = "category", vector_name = "durable_category",
                  value_type = "categorical", missing_policy = "error",
                  cell_set = "all", min_cells = 1L)
  )
  session <- categorical$session
  continuous <- wb_session_run_op(
    session, b, "metadata_cell_vector",
    inputs = list(source_column = "score", vector_name = "durable_score",
                  value_type = "continuous", missing_policy = "error",
                  cell_set = "all", min_cells = 1L)
  )
  session <- continuous$session
  leiden <- wb_session_run_op(
    session, b, "leiden",
    inputs = list(space = "latent", cell_set = "all", min_cells = 1L,
                  dims = NULL, k = 5L, resolution = 0.7,
                  n_iterations = 2L, seed = 17L, weight = TRUE)
  )
  session <- leiden$session

  originals <- list(
    categorical = categorical$run$outputs$vector,
    continuous = continuous$run$outputs$vector,
    leiden = leiden$run$outputs$clusters
  )
  stopifnot(
    identical(originals$leiden$meta, list(label = "Leiden clusters")),
    !is.null(originals$leiden$meta),
    is.null(originals$categorical$meta),
    is.null(originals$continuous$meta)
  )
  identities_before <- lapply(
    originals,
    function(primitive) scworkbench:::.wb_prov_payload_identity(b, primitive)$content_sha256
  )

  promoted <- wb_session_promote_current(
    b,
    session,
    outputs = list(
      wb_ref_run(categorical$run$run_id, "vector"),
      wb_ref_run(continuous$run$run_id, "vector"),
      wb_ref_run(leiden$run$run_id, "clusters")
    ),
    created_by = "cell-vector-roundtrip-contract"
  )
  ok <- promoted$promoted[as.character(promoted$promoted$status) == "ok", , drop = FALSE]
  stopifnot(nrow(ok) == 3L, all(as.character(ok$lineage_status) == "complete"))
  artifact_for_run <- stats::setNames(as.character(ok$artifact_id), as.character(ok$run_id))
  artifact_ids <- c(
    categorical = unname(artifact_for_run[[categorical$run$run_id]]),
    continuous = unname(artifact_for_run[[continuous$run$run_id]]),
    leiden = unname(artifact_for_run[[leiden$run$run_id]])
  )
  loaded <- lapply(artifact_ids, function(id) wb_art_load(b, id, expected_kind = "cell_vector"))
  identities_after <- lapply(
    loaded,
    function(primitive) scworkbench:::.wb_prov_payload_identity(b, primitive)$content_sha256
  )

  for (name in names(originals)) {
    stopifnot(
      identical(loaded[[name]]$cell_id, originals[[name]]$cell_id),
      identical(loaded[[name]]$value, originals[[name]]$value),
      identical(loaded[[name]]$value_type, originals[[name]]$value_type),
      identical(loaded[[name]]$meta, originals[[name]]$meta),
      identical(identities_after[[name]], identities_before[[name]])
    )
  }

  # Presentation metadata is explicitly durable and identity-bearing. Changing
  # it changes identity; empty metadata retains the historical object shape.
  relabelled <- wb_prim_cell_vector(
    stats::setNames(originals$leiden$value, originals$leiden$cell_id),
    value_type = originals$leiden$value_type,
    meta = list(label = "Different presentation label")
  )
  stopifnot(
    scworkbench:::.wb_prov_payload_identity(b, relabelled)$content_sha256 != identities_before$leiden,
    !"meta" %in% names(wb_prim_cell_vector(stats::setNames("x", "cell_10")))
  )

  inherited_after_promotion <- list(
    cells = DBI::dbGetQuery(b$con, "SELECT * FROM cells ORDER BY rowid;"),
    spaces = DBI::dbGetQuery(b$con, "SELECT * FROM spaces ORDER BY space_id;"),
    payload = DBI::dbGetQuery(b$con, "SELECT * FROM space_payloads WHERE space_id = 'latent';"),
    identity = scworkbench:::.wb_prov_payload_identity(b, wb_prim_space("latent"))$content_sha256
  )
  stopifnot(identical(inherited_before, inherited_after_promotion))

  finalized <- wb_finalize_recipient_bundle(b)
  stopifnot(isTRUE(finalized$ready))
  wb_close_bundle(b)
  b <- NULL
  before_validation <- scworkbench:::.wb_prov_path_identity(root)$content_sha256
  recipient <- wb_bundle_validation_report(root, level = "recipient")
  after_validation <- scworkbench:::.wb_prov_path_identity(root)$content_sha256
  stopifnot(
    isTRUE(recipient$ok),
    identical(recipient$pre_validation_fingerprint, recipient$post_validation_fingerprint),
    identical(before_validation, after_validation)
  )

  read_only <- wb_open_bundle(root, read_only = TRUE, validate = TRUE)
  reopened <- lapply(artifact_ids, function(id) wb_art_load(read_only, id, expected_kind = "cell_vector"))
  stopifnot(
    identical(reopened$leiden$meta, list(label = "Leiden clusters")),
    identical(reopened$categorical$cell_id, originals$categorical$cell_id),
    identical(reopened$continuous$value, originals$continuous$value),
    identical(
      scworkbench:::.wb_prov_payload_identity(read_only, reopened$leiden)$content_sha256,
      identities_before$leiden
    )
  )
  wb_close_bundle(read_only)

  # A scientific payload mutation still fails closed. Validation observes but
  # does not repair the recorded provenance identity.
  mutant_parent <- tempfile("scwb_cell_vector_mutant_")
  dir.create(mutant_parent)
  on.exit(unlink(mutant_parent, recursive = TRUE, force = TRUE), add = TRUE)
  stopifnot(file.copy(root, mutant_parent, recursive = TRUE))
  mutant <- file.path(mutant_parent, basename(root))
  mutant_con <- DBI::dbConnect(RSQLite::SQLite(), file.path(mutant, "db", "app.sqlite"))
  recorded_before <- DBI::dbGetQuery(
    mutant_con,
    "SELECT content_sha256 FROM prov_run_outputs WHERE artifact_id = ?;",
    params = list(artifact_ids[["leiden"]])
  )$content_sha256[[1L]]
  changed_cell <- originals$leiden$cell_id[[1L]]
  DBI::dbExecute(
    mutant_con,
    "UPDATE artifact_labels SET label = 'mutated-cluster' WHERE artifact_id = ? AND cell_id = ?;",
    params = list(artifact_ids[["leiden"]], changed_cell)
  )
  DBI::dbDisconnect(mutant_con)
  mutant_report <- wb_bundle_validation_report(mutant, level = "recipient")
  mutant_con <- DBI::dbConnect(RSQLite::SQLite(), file.path(mutant, "db", "app.sqlite"))
  recorded_after <- DBI::dbGetQuery(
    mutant_con,
    "SELECT content_sha256 FROM prov_run_outputs WHERE artifact_id = ?;",
    params = list(artifact_ids[["leiden"]])
  )$content_sha256[[1L]]
  DBI::dbDisconnect(mutant_con)
  stopifnot(
    !isTRUE(mutant_report$ok),
    "ARTIFACT_CONTENT_IDENTITY_MISMATCH" %in% as.character(mutant_report$diagnostics$code),
    identical(recorded_before, recorded_after),
    identical(recorded_before, identities_before$leiden)
  )

  TRUE
}
