test_operation_pack_v3_durable_model_tree_contract <- function() {
  root <- tempfile("scwb-durable-model-tree-")
  source_bundle <- file.path(root, "source.bundle")
  relocated <- file.path(root, "relocated", "transferred.bundle")
  dir.create(root, recursive = TRUE, showWarnings = FALSE)
  b <- wb_init_bundle(source_bundle, overwrite = TRUE)
  staged_session <- NULL
  on.exit({
    if (!is.null(staged_session))
      try(wb_session_discard(staged_session), silent = TRUE)
    try(wb_close_bundle(b), silent = TRUE)
    unlink(root, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  cells <- c("c1", "c2", "c3")
  source_values <- matrix(seq_len(6L), nrow = 3L,
    dimnames = list(cells, c("PC1", "PC2")))
  wb_define_cells(b, cells)
  wb_add_space(b, "pca", source_values)
  staged <- .wb_session_stage_bundle(b, wb_session_new())
  staged_session <- staged$session
  tree_rel <- file.path("operation_pack_v2", "transitions", "fixture",
    "outputs", "model", "model_tree")
  tree_root <- file.path(staged$bundle$dir, tree_rel)
  dir.create(file.path(tree_root, "support"), recursive = TRUE,
    showWarnings = FALSE)
  primary_bytes <- charToRaw("primary-model-bytes-v1")
  secondary_bytes <- charToRaw("required-secondary-bytes-v1")
  writeBin(primary_bytes, file.path(tree_root, "model.bin"))
  writeBin(secondary_bytes, file.path(tree_root, "support", "required.bin"))
  tree <- .wb_operation_pack_v3_model_tree_manifest(tree_root,
    "fixture", "two_file_model", "model.bin")
  payload_identity <- .wb_operation_pack_v3_model_payload_identity(tree)
  source_primitive <- structure(list(kind = "space", space_id = "pca",
    values = source_values), class = "wb_primitive")
  dimensions <- .wb_operation_pack_v3_selected_dimensions(source_primitive,
    list(dims = 1:2), "dims")
  model <- wb_prim_model_ref("fixture.model", "pca", engine = "fixture")
  model$model_type <- "two_file_model"
  model$model_path <- normalizePath(tree_root, winslash = "/",
    mustWork = TRUE)
  model$model_tree_root <- model$model_path
  model$model_primary_path <- tree$primary_path
  model$model_tree_manifest <- tree
  model$model_payload_manifest_identity <- payload_identity
  model$model_linkage <- .wb_operation_pack_v3_model_linkage("fixture",
    "two_file_model", "pca", dimensions)
  run <- wb_new_run("slingshot_adopt",
    inputs = list(cell_set = "all", parents = character(),
      user_inputs = list()), outputs = list(model = model))
  promoted <- wb_promote_analysis(b, setNames(list(run), run$run_id),
    run$run_id, outputs = "model", staging_bundle = staged$bundle)
  artifact_id <- as.character(promoted$promoted$artifact_id[
    promoted$promoted$output == "model" &
      promoted$promoted$status == "ok"][[1L]])
  stopifnot(nzchar(artifact_id))
  registry <- DBI::dbGetQuery(b$con, paste0(
    "SELECT model_path, model_primary_path, model_tree_manifest_json, ",
    "payload_manifest_identity_json FROM artifact_model_ref ",
    "WHERE artifact_id=?;"), params = list(artifact_id))
  stopifnot(nrow(registry) == 1L, dir.exists(file.path(source_bundle,
    registry$model_path[[1L]])), identical(registry$model_primary_path[[1L]],
      "model.bin"), !.wb_path_is_absolute(registry$model_path[[1L]]))
  staged_session <- wb_session_discard(staged_session)
  stopifnot(dir.exists(file.path(source_bundle, registry$model_path[[1L]])))
  stopifnot(isTRUE(wb_finalize_recipient_bundle(b)$ready))
  stopifnot(dir.exists(file.path(source_bundle, registry$model_path[[1L]])))
  wb_close_bundle(b)
  stopifnot(dir.exists(file.path(source_bundle, registry$model_path[[1L]])))
  dir.create(dirname(relocated), recursive = TRUE, showWarnings = FALSE)
  fs::dir_copy(source_bundle, relocated)
  stopifnot(dir.exists(file.path(relocated, registry$model_path[[1L]])))
  b <- wb_open_bundle(relocated)

  loaded <- wb_art_load(b, artifact_id, expected_kind = "model_ref")
  stopifnot(dir.exists(loaded$model_path),
    startsWith(normalizePath(loaded$model_path, winslash = "/",
      mustWork = TRUE), normalizePath(relocated, winslash = "/",
        mustWork = TRUE)),
    identical(loaded$model_tree_manifest, tree),
    identical(loaded$model_payload_manifest_identity, payload_identity),
    identical(loaded$model_primary_path, "model.bin"))
  retained_json <- .wb_operation_pack_canonical_json(list(
    tree = loaded$model_tree_manifest,
    payload = loaded$model_payload_manifest_identity,
    linkage = loaded$model_linkage))
  stopifnot(!grepl(normalizePath(source_bundle, winslash = "/",
    mustWork = FALSE), retained_json, fixed = TRUE),
    !grepl(normalizePath(relocated, winslash = "/", mustWork = FALSE),
      retained_json, fixed = TRUE))

  historical <- wb_prim_model_ref("fixture.model", "pca",
    engine = "fixture")
  historical$model_type <- "two_file_model"
  historical$model_path <- file.path(loaded$model_path,
    loaded$model_primary_path)
  historical_tree <- .wb_operation_pack_v3_model_tree_source(b,
    historical, "fixture", "two_file_model")
  stopifnot(isTRUE(historical_tree$historical),
    historical_tree$manifest$file_count == 1L,
    identical(historical_tree$manifest$primary_path, "model.bin"))
  unlink(historical_tree$root, recursive = TRUE, force = TRUE)

  # Exercise the actual core successor-read boundary. It must stage every
  # authenticated entry, preserve relative paths, and expose the retained
  # primary and manifest identities without revealing the committed root.
  records <- list(
    model = list(kind = "model_ref", content_identity = list(
      scheme = "fixture", sha256 = paste(rep("1", 64L), collapse = ""))),
    in_space = list(descriptor_identity = list(scheme = "fixture",
      sha256 = paste(rep("2", 64L), collapse = "")))
  )
  operation <- list(contained_model_reads = list(list(
    name = "fitted_model", input = "model", source_space_input = "in_space",
    engine = "fixture", model_type = "two_file_model",
    dimensions_parameter = "dims")))
  successor_root <- tempfile("scwb-successor-model-read-")
  dir.create(successor_root, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(successor_root, recursive = TRUE, force = TRUE), add = TRUE)
  prepared <- .wb_operation_pack_v3_prepare_model_reads(b, operation,
    list(model = loaded, in_space = source_primitive), records,
    list(dims = 1:2), successor_root)
  private <- prepared$values$fitted_model
  stopifnot(identical(private$manifest, tree),
    identical(prepared$grants$fitted_model$tree_manifest, tree),
    identical(prepared$grants$fitted_model$payload_manifest_identity,
      payload_identity),
    identical(readBin(file.path(private$root, "model.bin"), "raw",
      n = length(primary_bytes)), primary_bytes),
    identical(readBin(file.path(private$root, "support", "required.bin"),
      "raw", n = length(secondary_bytes)), secondary_bytes),
    !startsWith(normalizePath(private$root, winslash = "/", mustWork = TRUE),
      normalizePath(relocated, winslash = "/", mustWork = TRUE)))
  stopifnot(isTRUE(wb_finalize_recipient_bundle(b)$ready))
  wb_close_bundle(b)
  b <- NULL
  recipient <- wb_bundle_validation_report(relocated, "recipient")
  if (!isTRUE(recipient$ok)) stop(paste(
    recipient$diagnostics$code, recipient$diagnostics$message,
    collapse = " | "), call. = FALSE)
  copy_bundle <- function(label) {
    destination <- file.path(root, label, "copy.bundle")
    dir.create(dirname(destination), recursive = TRUE, showWarnings = FALSE)
    fs::dir_copy(relocated, destination)
    destination
  }
  mutate_registry_manifest <- function(path, mutate) {
    con <- DBI::dbConnect(RSQLite::SQLite(),
      file.path(path, "db", "app.sqlite"))
    on.exit(DBI::dbDisconnect(con), add = TRUE)
    row <- DBI::dbGetQuery(con, paste0(
      "SELECT model_tree_manifest_json FROM artifact_model_ref ",
      "WHERE artifact_id=?;"), params = list(artifact_id))
    manifest <- jsonlite::fromJSON(row$model_tree_manifest_json[[1L]],
      simplifyVector = FALSE)
    manifest <- mutate(manifest)
    DBI::dbExecute(con, paste0(
      "UPDATE artifact_model_ref SET model_tree_manifest_json=? ",
      "WHERE artifact_id=?;"), params = list(as.character(jsonlite::toJSON(
        manifest, auto_unbox = TRUE, null = "null", digits = NA)),
          artifact_id))
  }
  expect_rejected_without_residue <- function(path) {
    candidate <- wb_open_bundle(path, validate = FALSE)
    before <- c(
      artifacts = DBI::dbGetQuery(candidate$con,
        "SELECT COUNT(*) AS n FROM artifacts;")$n[[1L]],
      runs = DBI::dbGetQuery(candidate$con,
        "SELECT COUNT(*) AS n FROM prov_runs;")$n[[1L]],
      commits = DBI::dbGetQuery(candidate$con,
        "SELECT COUNT(*) AS n FROM prov_commits;")$n[[1L]])
    dispatched <- FALSE
    failure <- tryCatch({
      value <- wb_art_load(candidate, artifact_id, expected_kind = "model_ref")
      .wb_operation_pack_v3_prepare_model_reads(candidate, operation,
        list(model = value, in_space = source_primitive), records,
        list(dims = 1:2), tempfile("scwb-rejected-dispatch-"))
      dispatched <- TRUE
      NULL
    }, error = identity)
    after <- c(
      artifacts = DBI::dbGetQuery(candidate$con,
        "SELECT COUNT(*) AS n FROM artifacts;")$n[[1L]],
      runs = DBI::dbGetQuery(candidate$con,
        "SELECT COUNT(*) AS n FROM prov_runs;")$n[[1L]],
      commits = DBI::dbGetQuery(candidate$con,
        "SELECT COUNT(*) AS n FROM prov_commits;")$n[[1L]])
    wb_close_bundle(candidate)
    stopifnot(inherits(failure, "error"), !dispatched,
      identical(before, after))
  }

  secondary_corrupt <- copy_bundle("secondary-corrupt")
  secondary_path <- file.path(secondary_corrupt, registry$model_path[[1L]],
    "support", "required.bin")
  Sys.chmod(secondary_path, mode = "0644")
  writeBin(charToRaw("changed-secondary"), secondary_path)
  expect_rejected_without_residue(secondary_corrupt)
  missing <- copy_bundle("missing-entry")
  unlink(file.path(missing, registry$model_path[[1L]], "support",
    "required.bin"), force = TRUE)
  expect_rejected_without_residue(missing)
  extra <- copy_bundle("extra-entry")
  writeBin(as.raw(1:3), file.path(extra, registry$model_path[[1L]],
    "extra.bin"))
  expect_rejected_without_residue(extra)

  escaped <- copy_bundle("escaped-entry")
  mutate_registry_manifest(escaped, function(x) {
    x$entries[[2L]]$path <- "../escaped.bin"; x
  })
  expect_rejected_without_residue(escaped)
  duplicate <- copy_bundle("duplicate-entry")
  mutate_registry_manifest(duplicate, function(x) {
    x$entries[[2L]]$path <- x$entries[[1L]]$path; x
  })
  expect_rejected_without_residue(duplicate)
  absent_primary <- copy_bundle("absent-primary")
  mutate_registry_manifest(absent_primary, function(x) {
    x$primary_path <- "absent.bin"; x
  })
  expect_rejected_without_residue(absent_primary)
  substituted <- copy_bundle("substituted-entry")
  mutate_registry_manifest(substituted, function(x) {
    x$entries[[2L]]$sha256 <- paste(rep("0", 64L), collapse = "")
    x$manifest_identity <- NULL
    x$manifest_identity <- .wb_operation_pack_v2_identity_scoped(
      "scworkbench.operation_pack.contained_model_tree_manifest.v1",
      "manifest excluding manifest_identity", x)
    x
  })
  expect_rejected_without_residue(substituted)
  TRUE
}
