test_cell_vector_durable_identity_roundtrip_contract <- function() {
  if (!requireNamespace("igraph", quietly = TRUE)) {
    return(contract_test_skip("igraph is not installed."))
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
                  dims = 1:3, k = 5L, resolution = 0.7,
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

test_object_primitive_family_durable_roundtrip_contract <- function() {
  root <- tempfile("scwb_object_family_roundtrip_")
  b <- wb_init_bundle(root, overwrite = TRUE)
  on.exit({
    try(wb_close_bundle(b), silent = TRUE)
    unlink(root, recursive = TRUE, force = TRUE)
  }, add = TRUE)
  cells <- c("c3", "c1", "c4", "c2")
  wb_define_cells(b, cells)
  wb_attach_space(
    b,
    "latent",
    data.frame(cell_id = cells, d1 = seq_along(cells), d2 = rev(seq_along(cells)))
  )

  metadata <- list(
    label = "durable presentation",
    numeric_double = c(1, 2.5),
    integer_order = c(2L, 1L),
    named = c(left = "L", right = "R")
  )
  primitives <- list(
    cell_vector = wb_prim_cell_vector(
      stats::setNames(c(3.5, 1.5, 4.5, 2.5), cells),
      value_type = "continuous",
      meta = metadata
    ),
    cell_vector_family = wb_prim_cell_vector_family(
      key = c("L2", "L1", "L2", "L1"),
      cell_id = c("c4", "c3", "c2", "c1"),
      value = c(0.4, 0.1, 0.3, 0.2),
      value_type = "probability",
      meta = metadata
    ),
    relation_family = wb_prim_relation_family(
      key = c("edge_b", "edge_a", "edge_b", "edge_a"),
      cell_id = c("c4", "c3", "c2", "c1"),
      weight = c(0.4, 0.1, 0.3, 0.2),
      value = rep(NA_real_, 4L),
      distance = NULL,
      meta = metadata
    ),
    path_2d_family = wb_prim_path_2d_family(
      key = c("path_b", "path_a", "path_b", "path_a"),
      point = c(2L, 2L, 1L, 1L),
      x = c(4, 2, 3, 1),
      y = c(40, 20, 30, 10),
      meta = metadata
    ),
    space_path_family = wb_prim_space_path_family(
      space_id = rep("latent", 4L),
      path_id = c("path_b", "path_a", "path_b", "path_a"),
      point = c(2L, 2L, 1L, 1L),
      dim = c(2L, 1L, 1L, 2L),
      value = c(4, 2, 3, 1),
      meta = metadata
    )
  )

  promoters <- scworkbench:::.wb_promoters_by_kind()
  artifact_ids <- character()
  identities_before <- character()
  for (kind in names(primitives)) {
    primitive <- primitives[[kind]]
    run <- wb_new_run(
      op_name = "durable_object_family_fixture",
      inputs = list(cell_set = "all", parents = character(), user_inputs = list()),
      params = list(kind = kind),
      outputs = stats::setNames(list(primitive), kind)
    )
    artifact_ids[[kind]] <- promoters[[kind]](
      b, run, kind, primitive,
      created_by = "object-family-roundtrip-contract"
    )
    identities_before[[kind]] <- scworkbench:::.wb_prov_payload_identity(
      b, primitive
    )$content_sha256
  }

  loaded <- lapply(artifact_ids, function(id) wb_art_load(b, id))
  for (kind in names(primitives)) {
    stopifnot(
      identical(unclass(loaded[[kind]]), unclass(primitives[[kind]])),
      identical(loaded[[kind]]$meta, metadata),
      identical(
        scworkbench:::.wb_prov_payload_identity(b, loaded[[kind]])$content_sha256,
        identities_before[[kind]]
      )
    )
  }
  stopifnot(
    identical(loaded$cell_vector$value_type, "continuous"),
    identical(loaded$cell_vector_family$value_type, "probability"),
    !is.null(loaded$relation_family$value),
    is.null(loaded$relation_family$distance)
  )

  mutations <- list(
    cell_vector = list(
      sql = "UPDATE artifact_labels SET value_num = value_num + 9 WHERE artifact_id = ? AND cell_id = 'c3';"
    ),
    cell_vector_family = list(
      sql = "UPDATE artifact_pseudotime SET pseudotime = pseudotime + 9 WHERE artifact_id = ? AND lineage_id = 'L2' AND cell_id = 'c4';"
    ),
    relation_family = list(
      sql = "UPDATE artifact_relation_rows SET weight = weight + 9 WHERE artifact_id = ? AND relation_key = 'edge_b' AND cell_id = 'c4';"
    ),
    path_2d_family = list(
      sql = "UPDATE artifact_curves_2d SET x = x + 9 WHERE artifact_id = ? AND lineage_id = 'path_b' AND point = 2;"
    ),
    space_path_family = list(
      sql = "UPDATE artifact_space_path_rows SET value = value + 9 WHERE artifact_id = ? AND path_id = 'path_b' AND point = 2 AND dim = 2;"
    )
  )
  for (kind in names(mutations)) {
    DBI::dbExecute(b$con, mutations[[kind]]$sql, params = list(artifact_ids[[kind]]))
    mutated <- wb_art_load(b, artifact_ids[[kind]])
    stopifnot(
      scworkbench:::.wb_prov_payload_identity(b, mutated)$content_sha256 !=
        identities_before[[kind]]
    )
  }

  TRUE
}
