# ABI-v3 contained fitted-model and authenticated space_2d publication.

.wb_operation_pack_v3_selected_dimensions <- function(value, params,
    parameter) {
  dimensions <- as.integer(unlist(params[[as.character(parameter)[1]]] %||%
    seq_len(ncol(value$values)), use.names = FALSE))
  labels <- colnames(value$values)
  .wb_operation_pack_v3_error_if <- function(condition, message) {
    if (isTRUE(condition)) .wb_operation_pack_v3_error(
      "PYBENCH_INPUT_IDENTITY_MISMATCH", message, "resolution")
  }
  .wb_operation_pack_v3_error_if(!length(dimensions) || anyNA(dimensions) ||
    any(dimensions < 1L) || any(dimensions > ncol(value$values)) ||
    anyDuplicated(dimensions),
    "Selected fitted-model dimensions are empty, duplicated, or out of bounds.")
  labels <- if (is.null(labels)) paste0("dim", seq_len(ncol(value$values))) else
    as.character(labels)
  selected <- labels[dimensions]
  list(indices = dimensions, labels = selected, count = length(selected),
    identity = .wb_operation_pack_v2_identity_plain(
      "scworkbench.dimension_order.v1", unname(as.list(selected))))
}

.wb_operation_pack_v3_safe_model_entry <- function(path) {
  path <- as.character(path %||% "")[1]
  nzchar(path) && !.wb_path_is_absolute(path) && !grepl("\\\\", path) &&
    !any(strsplit(path, "/", fixed = TRUE)[[1]] %in% c("", ".", ".."))
}

.wb_operation_pack_v3_model_tree_manifest <- function(root, engine,
    model_type, primary_path, maximum_file_count = 32L,
    maximum_total_bytes = 1073741824, code = "PYBENCH_OUTPUT_INVALID",
    phase = "audit") {
  fail <- function(message) .wb_operation_pack_v3_error(code, message, phase)
  if (!dir.exists(root) || nzchar(Sys.readlink(root)))
    fail("Contained model tree root is absent or linked.")
  paths <- list.files(root, recursive = TRUE, all.files = TRUE,
    include.dirs = TRUE, no.. = TRUE)
  if (!length(paths)) fail("Contained model tree is empty.")
  if (any(!vapply(paths, .wb_operation_pack_v3_safe_model_entry,
      logical(1)))) fail("Contained model tree has an unsafe relative path.")
  absolute <- file.path(root, paths)
  info <- file.info(absolute)
  linked <- nzchar(Sys.readlink(absolute))
  if (any(linked) || any(is.na(info$isdir)))
    fail("Contained model tree has a linked or unreadable entry.")
  files <- paths[!info$isdir]
  file_abs <- absolute[!info$isdir]
  file_info <- info[!info$isdir, , drop = FALSE]
  regular <- vapply(file_abs, function(path) isTRUE(utils::file_test("-f", path)),
    logical(1))
  if (!length(files) || any(!regular) || any(file_info$size <= 0))
    fail("Contained model tree must contain nonempty regular files only.")
  files <- sort(files, method = "radix")
  file_abs <- file.path(root, files)
  sizes <- as.numeric(file.info(file_abs)$size)
  if (length(files) > as.integer(maximum_file_count) ||
      sum(sizes) > as.numeric(maximum_total_bytes))
    fail("Contained model tree exceeds its authenticated resource limits.")
  if (!.wb_operation_pack_v3_safe_model_entry(primary_path) ||
      !primary_path %in% files)
    fail("Contained model tree primary file is missing or unsafe.")
  entries <- Map(function(path, size, absolute) list(path = path,
    size = as.integer(size), sha256 = .wb_operation_pack_v2_file_sha256(
      absolute)), files, sizes, file_abs)
  value <- list(schema =
      "scworkbench.operation_pack.contained_model_tree_manifest.v1",
    engine = as.character(engine)[1], model_type = as.character(model_type)[1],
    primary_path = as.character(primary_path)[1],
    file_count = as.integer(length(entries)), total_size = as.integer(sum(sizes)),
    entries = unname(entries))
  value$manifest_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.contained_model_tree_manifest.v1",
    "manifest excluding manifest_identity", value)
  value
}

.wb_operation_pack_v3_model_payload_identity <- function(manifest) {
  entry_ids <- lapply(manifest$entries, function(entry)
    .wb_operation_pack_v2_identity_plain(
      "scworkbench.operation_pack.payload_file.v1", entry))
  .wb_operation_pack_v2_identity_plain(
    "scworkbench.operation_pack.payload_manifest.v2", list(
      contained_model_tree_manifest_identity =
        .wb_operation_pack_v3_unscoped_identity(manifest$manifest_identity),
      entry_payload_identities = entry_ids))
}

.wb_operation_pack_v3_assert_model_tree_manifest <- function(manifest,
    engine = NULL, model_type = NULL,
    code = "PYBENCH_INPUT_IDENTITY_MISMATCH", phase = "resolution") {
  fail <- function(message) .wb_operation_pack_v3_error(code, message, phase)
  required <- c("schema", "engine", "model_type", "primary_path",
    "file_count", "total_size", "entries", "manifest_identity")
  if (!is.list(manifest) || !all(required %in% names(manifest)) ||
      !identical(as.character(manifest$schema)[1],
        "scworkbench.operation_pack.contained_model_tree_manifest.v1"))
    fail("Contained model tree manifest is absent or malformed.")
  if (!is.null(engine) && !identical(as.character(manifest$engine)[1],
      as.character(engine)[1])) fail("Contained model tree engine changed.")
  if (!is.null(model_type) && !identical(
      as.character(manifest$model_type)[1], as.character(model_type)[1]))
    fail("Contained model tree model type changed.")
  entries <- manifest$entries
  if (!is.list(entries) || !length(entries) ||
      any(!vapply(entries, is.list, logical(1))))
    fail("Contained model tree manifest has no authenticated entries.")
  paths <- vapply(entries, function(entry)
    as.character(entry$path %||% "")[1], character(1))
  sizes <- vapply(entries, function(entry)
    as.numeric(entry$size %||% NA_real_)[1], numeric(1))
  hashes <- vapply(entries, function(entry)
    as.character(entry$sha256 %||% "")[1], character(1))
  if (any(!vapply(paths, .wb_operation_pack_v3_safe_model_entry,
      logical(1))) || anyDuplicated(paths) ||
      !identical(paths, sort(paths, method = "radix")) || anyNA(sizes) ||
      any(sizes <= 0) || any(sizes != floor(sizes)) ||
      any(!grepl("^[a-f0-9]{64}$", hashes)))
    fail("Contained model tree entries are unsafe, duplicated, unordered, or malformed.")
  primary <- as.character(manifest$primary_path %||% "")[1]
  if (!.wb_operation_pack_v3_safe_model_entry(primary) ||
      !primary %in% paths)
    fail("Contained model tree primary path is not an authenticated entry.")
  if (!identical(as.integer(manifest$file_count), as.integer(length(entries))) ||
      !identical(as.numeric(manifest$total_size), sum(sizes)))
    fail("Contained model tree counts do not match its entries.")
  expected <- manifest
  expected$manifest_identity <- NULL
  identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.contained_model_tree_manifest.v1",
    "manifest excluding manifest_identity", expected)
  if (!identical(manifest$manifest_identity, identity))
    fail("Contained model tree manifest identity is invalid.")
  invisible(TRUE)
}

.wb_operation_pack_v3_copy_model_tree <- function(source_root, manifest,
    target_root) {
  .wb_operation_pack_v3_assert_model_tree_manifest(manifest)
  if (!dir.exists(source_root) || nzchar(Sys.readlink(source_root)))
    .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
      "Contained model tree root is absent or linked.", "resolution")
  dir.create(target_root, recursive = TRUE, showWarnings = FALSE)
  for (entry in manifest$entries) {
    relative <- as.character(entry$path)[1]
    source <- file.path(source_root, relative)
    target <- file.path(target_root, relative)
    status <- .wb_path_status(source_root, relative, expected_type = "file",
      must_exist = TRUE, purpose = "authenticated contained model entry")
    if (!isTRUE(status$ok) || nzchar(Sys.readlink(source)))
      .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
        "Contained model tree entry is missing, escaped, or linked.",
        "resolution")
    dir.create(dirname(target), recursive = TRUE, showWarnings = FALSE)
    if (!isTRUE(file.copy(source, target, copy.mode = FALSE,
        copy.date = FALSE)))
      .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
        "Contained model tree could not be copied privately.", "staging")
    Sys.chmod(target, mode = "0444")
  }
  invisible(target_root)
}

.wb_operation_pack_v3_model_path <- function(bundle, value) {
  raw <- as.character(value$model_path %||% "")[1]
  if (!nzchar(raw)) .wb_operation_pack_v3_error(
    "PYBENCH_INPUT_IDENTITY_MISMATCH", "model_ref has no contained payload.",
    "resolution")
  if (.wb_path_is_absolute(raw)) {
    absolute <- normalizePath(raw, winslash = "/", mustWork = FALSE)
    roots <- unique(c(normalizePath(bundle$dir, winslash = "/",
      mustWork = TRUE), if (nzchar(as.character(bundle$staging_source_dir %||%
        "")[1])) normalizePath(bundle$staging_source_dir, winslash = "/",
          mustWork = TRUE) else character()))
    if (!any(vapply(roots, function(root) .wb_path_inside(absolute, root),
        logical(1))) || !file.exists(absolute))
      .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
        "model_ref payload is outside the authenticated bundle boundary.",
        "resolution")
    return(absolute)
  }
  .wb_bundle_path_require(bundle, raw, expected_type = "file",
    must_exist = TRUE, purpose = "contained model input")
}

.wb_operation_pack_v3_model_tree_source <- function(bundle, value, engine,
    model_type) {
  declared <- value$model_tree_manifest %||% NULL
  if (!is.null(declared)) {
    .wb_operation_pack_v3_assert_model_tree_manifest(declared, engine,
      model_type)
    raw_root <- as.character(value$model_tree_root %||%
      value$model_path %||% "")[1]
    if (!nzchar(raw_root)) .wb_operation_pack_v3_error(
      "PYBENCH_INPUT_IDENTITY_MISMATCH",
      "Contained model tree has no durable root.", "resolution")
    root <- if (.wb_path_is_absolute(raw_root)) {
      absolute <- normalizePath(raw_root, winslash = "/", mustWork = FALSE)
      roots <- unique(c(normalizePath(bundle$dir, winslash = "/",
        mustWork = TRUE), if (nzchar(as.character(
          bundle$staging_source_dir %||% "")[1])) normalizePath(
            bundle$staging_source_dir, winslash = "/", mustWork = TRUE) else
              character()))
      if (!any(vapply(roots, function(candidate)
          .wb_path_inside(absolute, candidate), logical(1))) ||
          !dir.exists(absolute)) .wb_operation_pack_v3_error(
            "PYBENCH_INPUT_IDENTITY_MISMATCH",
            "Contained model tree is outside the authenticated bundle boundary.",
            "resolution")
      absolute
    } else .wb_bundle_path_require(bundle, raw_root,
      expected_type = "directory", must_exist = TRUE,
      purpose = "contained model tree")
    observed <- .wb_operation_pack_v3_model_tree_manifest(root, engine,
      model_type, declared$primary_path,
      code = "PYBENCH_INPUT_IDENTITY_MISMATCH", phase = "resolution")
    payload <- .wb_operation_pack_v3_model_payload_identity(observed)
    if (!identical(observed, declared) ||
        (!is.null(value$model_payload_manifest_identity) &&
          !identical(payload, value$model_payload_manifest_identity)))
      .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
        "Durable contained model tree differs from its authenticated manifest.",
        "resolution")
    return(list(root = root, manifest = observed,
      payload_manifest_identity = payload, historical = FALSE))
  }

  # Historical artifacts did not retain a tree manifest. Present a contained
  # single-file model as a one-entry tree at the reader boundary without
  # rewriting durable state. A legacy directory is accepted only when its
  # primary file is unambiguous.
  source <- .wb_operation_pack_v3_model_path(bundle, value)
  if (dir.exists(source)) {
    candidates <- list.files(source, recursive = TRUE, all.files = TRUE,
      include.dirs = FALSE, no.. = TRUE)
    primary <- as.character(value$model_primary_path %||% "")[1]
    if (!nzchar(primary) && "model.uwot" %in% candidates)
      primary <- "model.uwot"
    if (!nzchar(primary) && length(candidates) == 1L)
      primary <- candidates[[1L]]
    if (!nzchar(primary)) .wb_operation_pack_v3_error(
      "PYBENCH_INPUT_IDENTITY_MISMATCH",
      "Historical model directory has no unambiguous primary file.",
      "resolution")
    manifest <- .wb_operation_pack_v3_model_tree_manifest(source, engine,
      model_type, primary, code = "PYBENCH_INPUT_IDENTITY_MISMATCH",
      phase = "resolution")
    return(list(root = source, manifest = manifest,
      payload_manifest_identity =
        .wb_operation_pack_v3_model_payload_identity(manifest),
      historical = TRUE))
  }
  temporary <- tempfile("scwb-model-single-file-")
  dir.create(temporary, recursive = TRUE, showWarnings = FALSE)
  primary <- basename(source)
  if (!isTRUE(file.copy(source, file.path(temporary, primary),
      copy.mode = FALSE, copy.date = FALSE)))
    .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
      "Historical model file could not be normalized.", "staging")
  manifest <- .wb_operation_pack_v3_model_tree_manifest(temporary, engine,
    model_type, primary, code = "PYBENCH_INPUT_IDENTITY_MISMATCH",
    phase = "resolution")
  list(root = temporary, manifest = manifest,
    payload_manifest_identity =
      .wb_operation_pack_v3_model_payload_identity(manifest),
    historical = TRUE, temporary = TRUE)
}

.wb_operation_pack_v3_model_linkage <- function(engine, model_type,
    source_space_id, dimensions) {
  value <- list(engine = as.character(engine)[1],
    model_type = as.character(model_type)[1],
    source_space_id = as.character(source_space_id)[1],
    selected_dimension_count = as.integer(dimensions$count),
    selected_dimension_order_identity = dimensions$identity)
  value$linkage_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.model_linkage.v1",
    "linkage excluding linkage_identity", value)
  value
}

.wb_operation_pack_v3_model_source_linkage_v2 <- function(engine, model_type,
    source_space_id, source_space_content_identity,
    fitted_cell_order_identity, dimensions, source_snapshot_id) {
  value <- list(engine = as.character(engine)[1],
    model_type = as.character(model_type)[1],
    source_space_id = as.character(source_space_id)[1],
    source_space_content_identity = source_space_content_identity,
    fitted_cell_order_identity = fitted_cell_order_identity,
    selected_dimension_count = as.integer(dimensions$count),
    selected_dimension_order_identity = dimensions$identity,
    source_snapshot_id = as.character(source_snapshot_id)[1])
  value$linkage_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.model_source_linkage.v2",
    "linkage excluding linkage_identity", value)
  value
}

.wb_operation_pack_v3_assert_model_source_linkage_v2 <- function(value,
    code = "PYBENCH_INPUT_IDENTITY_MISMATCH", phase = "resolution") {
  required <- c("engine", "model_type", "source_space_id",
    "source_space_content_identity", "fitted_cell_order_identity",
    "selected_dimension_count", "selected_dimension_order_identity",
    "source_snapshot_id", "linkage_identity")
  if (!is.list(value) || !setequal(names(value), required) ||
      !nzchar(as.character(value$source_space_id %||% "")[1]) ||
      !nzchar(as.character(value$source_snapshot_id %||% "")[1]) ||
      !identical(as.character(value$linkage_identity$scheme %||% "")[1],
        "scworkbench.operation_pack.model_source_linkage.v2") ||
      !identical(as.character(value$linkage_identity$scope %||% "")[1],
        "linkage excluding linkage_identity"))
    .wb_operation_pack_v3_error(code,
      "Contained model has no complete durable source linkage v2.", phase)
  .wb_operation_pack_v3_assert_self_identity(value, "linkage_identity",
    code, phase)
  invisible(TRUE)
}

.wb_operation_pack_v3_assert_model_source_linkage <- function(value,
    code = "PYBENCH_INPUT_IDENTITY_MISMATCH", phase = "resolution") {
  if (identical(as.character(value$schema %||% "")[1],
      "scworkbench.operation_pack.model_source_linkage.v3"))
    .wb_operation_pack_v3_assert_model_source_linkage_v3(value, code, phase)
  else .wb_operation_pack_v3_assert_model_source_linkage_v2(value, code,
    phase)
  invisible(TRUE)
}

.wb_operation_pack_v3_prepare_model_reads <- function(bundle, operation,
    inputs, input_records, params, stage_root) {
  grants <- list(); values <- list(); records <- input_records
  temporary_roots <- character()
  on.exit(for (path in unique(temporary_roots))
    unlink(path, recursive = TRUE, force = TRUE), add = TRUE)
  for (declaration in operation$contained_model_reads %||% list()) {
    name <- as.character(declaration$name)[1]
    input_name <- as.character(declaration$input)[1]
    source_name <- as.character(declaration$source_space_input)[1]
    model <- inputs[[input_name]]; source <- inputs[[source_name]]
    engine <- as.character(declaration$engine)[1]
    model_type <- as.character(declaration$model_type)[1]
    if (!identical(as.character(model$engine %||% "")[1], engine) ||
        !identical(as.character(model$model_type %||% engine)[1], model_type))
      .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
        "Contained model engine or model type differs from its declaration.",
        "resolution")
    dimensions <- .wb_operation_pack_v3_selected_dimensions(source, params,
      declaration$dimensions_parameter)
    linkage <- model$model_linkage %||% list()
    expected <- .wb_operation_pack_v3_model_linkage(engine, model_type,
      as.character(model$in_space_id %||% source$space_id)[1], dimensions)
    if (!identical(linkage$linkage_identity, expected$linkage_identity))
      .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
        "Contained model fitted dimensions, engine, or source linkage differ from the query space.",
        "resolution")
    source_tree <- .wb_operation_pack_v3_model_tree_source(bundle, model,
      engine, model_type)
    if (isTRUE(source_tree$temporary))
      temporary_roots <- c(temporary_roots, source_tree$root)
    root_rel <- paste0("model_payload_reads/", name, "/tree")
    root <- file.path(stage_root, root_rel)
    .wb_operation_pack_v3_copy_model_tree(source_tree$root,
      source_tree$manifest, root)
    primary <- source_tree$manifest$primary_path
    tree <- .wb_operation_pack_v3_model_tree_manifest(root, engine,
      model_type, primary, code = "PYBENCH_INPUT_IDENTITY_MISMATCH",
      phase = "staging")
    payload_identity <- .wb_operation_pack_v3_model_payload_identity(tree)
    if (!identical(tree, source_tree$manifest) ||
        !identical(payload_identity,
          source_tree$payload_manifest_identity))
      .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
        "Private contained-model tree copy changed during staging.",
        "staging")
    descriptor <- records[[input_name]]
    descriptor$content_identity <- .wb_operation_pack_v2_identity_plain(
      "scworkbench.model_ref.content.v1", list(
        engine = engine, model_type = model_type,
        linkage_identity = linkage$linkage_identity,
        tree_manifest_identity =
          .wb_operation_pack_v3_unscoped_identity(tree$manifest_identity)))
    descriptor$model_linkage_identity <-
      .wb_operation_pack_v3_unscoped_identity(linkage$linkage_identity)
    descriptor$contained_payload_identity <-
      .wb_operation_pack_v2_identity_plain(
        "scworkbench.operation_pack.contained_payload.v2",
        .wb_operation_pack_v3_unscoped_identity(tree$manifest_identity))
    descriptor$payload_manifest_identity <- payload_identity
    descriptor$descriptor_identity <- NULL
    descriptor$descriptor_identity <- .wb_operation_pack_v2_identity_scoped(
      "scworkbench.operation_pack.input_descriptor.v2",
      "descriptor excluding descriptor_identity", descriptor)
    records[[input_name]] <- descriptor
    grant <- list(schema =
        "scworkbench.operation_pack.contained_model_read_grant.v1",
      name = name, input_name = input_name,
      reader = "read_contained_model_payload", engine = engine,
      model_type = model_type,
      input_descriptor_identity =
        .wb_operation_pack_v3_unscoped_identity(descriptor$descriptor_identity),
      model_content_identity = descriptor$content_identity,
      model_linkage_identity = descriptor$model_linkage_identity,
      contained_payload_identity = descriptor$contained_payload_identity,
      payload_manifest_identity = payload_identity, tree_manifest = tree,
      source_space_binding = list(input_name = source_name,
        input_descriptor_identity = .wb_operation_pack_v3_unscoped_identity(
          records[[source_name]]$descriptor_identity),
        selected_dimension_count = as.integer(dimensions$count),
        selected_dimension_order_identity = dimensions$identity),
      relative_root = root_rel,
      access = "verified_private_copy_read_only_v1",
      call_discipline = "exactly_once")
    grant$grant_identity <- .wb_operation_pack_v2_identity_scoped(
      "scworkbench.operation_pack.contained_model_read_grant.v1",
      "grant excluding grant_identity", grant)
    grants[[name]] <- grant
    values[[name]] <- list(root = root, manifest = tree)
  }
  list(grants = grants, values = values, input_records = records)
}

.wb_operation_pack_v3_prepare_self_linked_model_reads <- function(bundle,
    operation, inputs, input_records, stage_root) {
  grants <- list(); values <- list(); records <- input_records
  for (declaration in operation$self_linked_contained_model_reads %||% list()) {
    name <- as.character(declaration$name)[1]
    input_name <- as.character(declaration$input)[1]
    model <- inputs[[input_name]]
    engine <- as.character(model$engine %||% "")[1]
    model_type <- as.character(model$model_type %||% engine)[1]
    pairs <- vapply(declaration$allowed_models, function(x) paste0(
      as.character(x$engine)[1], "\034", as.character(x$model_type)[1]),
      character(1))
    selected <- paste0(engine, "\034", model_type)
    if (sum(pairs == selected) != 1L) .wb_operation_pack_v3_error(
      "PYBENCH_CAPABILITY_MISMATCH",
      "Self-linked model engine/type is outside its exact allowlist.",
      "resolution")
    linkage <- model$model_source_linkage %||% model$model_linkage %||% list()
    derived_fitted <- identical(as.character(linkage$schema %||% "")[1],
      "scworkbench.operation_pack.model_source_linkage.v3")
    .wb_operation_pack_v3_assert_model_source_linkage(linkage)
    if (!identical(linkage$engine, engine) ||
        !identical(linkage$model_type, model_type))
      .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
        "Self-linked model engine/type differs from its durable linkage.",
        "resolution")
    artifact_id <- as.character(model$artifact_id %||% "")[1]
    if (nzchar(artifact_id)) {
      stored <- DBI::dbGetQuery(bundle$con, paste0(
        "SELECT linkage_json FROM artifact_model_ref WHERE artifact_id = ?;"),
        params = list(artifact_id))
      stored_linkage <- if (nrow(stored) == 1L && !is.na(
          stored$linkage_json[[1L]]) && nzchar(stored$linkage_json[[1L]]))
        jsonlite::fromJSON(stored$linkage_json[[1L]],
          simplifyVector = FALSE) else NULL
      if (is.null(stored_linkage) || !identical(
          .wb_operation_pack_canonical_json(stored_linkage),
          .wb_operation_pack_canonical_json(linkage)))
        .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
          "Self-linked model linkage differs from its durable artifact row.",
          "resolution")
    }
    source_tree_for_linkage <- .wb_operation_pack_v3_model_tree_source(bundle,
      model, engine, model_type)
    fitted_space <- NULL
    if (derived_fitted) {
      fitted_space <- .wb_operation_pack_v3_dfa_reopen(bundle, model, linkage,
        source_tree_for_linkage$root)
    } else {
      source <- wb_prim_space(linkage$source_space_id)
      source$values <- wb_space(bundle, linkage$source_space_id)
      source$cell_id <- rownames(source$values)
      source$dimensions <- as.integer(dim(source$values))
      source$storage_profile <- "space_dense_v1"
      durable_content <- .wb_operation_pack_v3_phase5_primitive_identity(
        bundle, source)
      observed_cells <- .wb_operation_pack_v2_identity_plain(
        "scworkbench.cell_order.v1", unname(as.list(source$cell_id)))
      if (!identical(as.character(
          linkage$source_space_content_identity$scheme)[1],
            "scworkbench.space.content.v1") ||
          !identical(observed_cells, linkage$fitted_cell_order_identity) ||
          !identical(as.character(linkage$source_snapshot_id)[1],
            as.character(durable_content$sha256)[1]))
        .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
          "Self-linked model source space or fitted cell axis changed.",
          "resolution")
    }
    limits <- list(maximum_file_count = as.integer(
      declaration$maximum_file_count), maximum_total_bytes = as.integer(
        declaration$maximum_total_bytes))
    source_tree <- source_tree_for_linkage
    if (source_tree$manifest$file_count > limits$maximum_file_count ||
        source_tree$manifest$total_size > limits$maximum_total_bytes)
      .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
        "Self-linked model tree exceeds its declared limits.", "resolution")
    root_rel <- paste0("model_payload_reads/", name, "/tree")
    root <- file.path(stage_root, root_rel)
    .wb_operation_pack_v3_copy_model_tree(source_tree$root,
      source_tree$manifest, root)
    tree <- .wb_operation_pack_v3_model_tree_manifest(root, engine,
      model_type, source_tree$manifest$primary_path,
      limits$maximum_file_count, limits$maximum_total_bytes)
    payload_identity <- .wb_operation_pack_v3_model_payload_identity(tree)
    if (!identical(tree, source_tree$manifest) || !identical(
        payload_identity, source_tree$payload_manifest_identity))
      .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
        "Self-linked model private copy differs from its durable tree.",
        "staging")
    descriptor <- records[[input_name]]
    descriptor$content_identity <- .wb_operation_pack_v2_identity_plain(
      "scworkbench.model_ref.content.v1", list(engine = engine,
        model_type = model_type, linkage_identity = linkage$linkage_identity,
        tree_manifest_identity = .wb_operation_pack_v3_unscoped_identity(
          tree$manifest_identity)))
    descriptor$model_linkage_identity <- .wb_operation_pack_v3_unscoped_identity(
      linkage$linkage_identity)
    descriptor$contained_payload_identity <- .wb_operation_pack_v2_identity_plain(
      "scworkbench.operation_pack.contained_payload.v2",
      .wb_operation_pack_v3_unscoped_identity(tree$manifest_identity))
    descriptor$payload_manifest_identity <- payload_identity
    descriptor$descriptor_identity <- NULL
    descriptor$descriptor_identity <- .wb_operation_pack_v2_identity_scoped(
      "scworkbench.operation_pack.input_descriptor.v2",
      "descriptor excluding descriptor_identity", descriptor)
    records[[input_name]] <- descriptor
    declaration_identity <- .wb_operation_pack_v2_identity_plain(
      "scworkbench.operation_pack.self_linked_contained_model_read.v1",
      declaration)
    grant <- list(schema =
        "scworkbench.operation_pack.self_linked_contained_model_read_grant.v1",
      name = name, input_name = input_name,
      reader = "read_self_linked_contained_model_payload",
      declaration_identity = declaration_identity,
      selected_model = list(engine = engine, model_type = model_type),
      input_descriptor_identity = .wb_operation_pack_v3_unscoped_identity(
        descriptor$descriptor_identity),
      model_content_identity = descriptor$content_identity,
      model_source_linkage = linkage,
      model_source_linkage_identity = .wb_operation_pack_v3_unscoped_identity(
        linkage$linkage_identity),
      contained_payload_identity = descriptor$contained_payload_identity,
      payload_manifest_identity = payload_identity, tree_manifest = tree,
      limits = limits, relative_root = root_rel,
      access = "verified_private_copy_read_only_v1",
      call_discipline = "exactly_once")
    grant$grant_identity <- .wb_operation_pack_v2_identity_scoped(grant$schema,
      "grant excluding grant_identity", grant)
    grants[[name]] <- grant
    values[[name]] <- list(root = root, manifest = tree,
      fitted_space = fitted_space)
  }
  list(grants = grants, values = values, input_records = records)
}

.wb_operation_pack_v3_all_model_read_grants <- function(request) c(
  request$model_payload_grants %||% list(),
  request$self_linked_model_payload_grants %||% list())

.wb_operation_pack_v3_model_write_grant <- function(output, operation,
    inputs, input_records, params, base_outputs) {
  policy <- output$contained_model_policy
  if (is.null(policy)) return(NULL)
  source_name <- as.character(policy$source_space_input)[1]
  paired_name <- as.character(policy$paired_space_output)[1]
  source <- inputs[[source_name]]
  dims <- .wb_operation_pack_v3_selected_dimensions(source, params,
    policy$dimensions_parameter)
  paired <- base_outputs[[match(paired_name, vapply(base_outputs, `[[`,
    character(1), "name"))]]
  grant <- list(schema =
      "scworkbench.operation_pack.contained_model_write_grant.v1",
    output = as.character(output$name)[1], engine = as.character(policy$engine)[1],
    model_type = as.character(policy$model_type)[1],
    primary_path = as.character(policy$primary_path)[1],
    relative_root = paste0("outputs/", output$name, "/model_tree"),
    source_space = list(input_name = source_name,
      input_descriptor_identity = .wb_operation_pack_v3_unscoped_identity(
        input_records[[source_name]]$descriptor_identity),
      content_identity = input_records[[source_name]]$content_identity,
      cell_order_identity = input_records[[source_name]]$cell_order_identity,
      dimensions = unname(as.list(as.integer(dim(source$values)))),
      selected_dimension_count = as.integer(dims$count),
      selected_dimension_order_identity = dims$identity),
    paired_space_output = list(name = paired_name,
      allocated_id = as.character(paired$allocated_id)[1],
      expected_dimensions = unname(as.list(c(nrow(source$values), 2L))),
      expected_cell_order_identity = input_records[[source_name]]$cell_order_identity),
    limits = list(maximum_file_count = as.integer(policy$maximum_file_count),
      maximum_total_bytes = as.integer(policy$maximum_total_bytes)))
  grant$write_grant_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.contained_model_write_grant.v1",
    "grant excluding write_grant_identity", grant)
  grant
}

.wb_operation_pack_v3_model_sibling_write_grant <- function(bundle, output,
    operation, inputs, input_records, params, output_records) {
  policy <- output$contained_model_sibling_closure_policy
  if (is.null(policy)) return(NULL)
  source_name <- as.character(policy$source_space_input)[1]
  source <- inputs[[source_name]]
  parameter <- policy$dimensions_parameter
  dims <- if (is.null(parameter)) {
    labels <- colnames(source$values)
    if (is.null(labels)) labels <- paste0("dim", seq_len(ncol(source$values)))
    list(indices = seq_len(ncol(source$values)), labels = labels,
      count = ncol(source$values), identity =
        .wb_operation_pack_v2_identity_plain(
          "scworkbench.dimension_order.v1", unname(as.list(labels))))
  } else .wb_operation_pack_v3_selected_dimensions(source, params, parameter)
  engine <- as.character(policy$engine)[1]
  model_type <- as.character(policy$model_type)[1]
  source_record <- input_records[[source_name]]
  # The language-neutral G2 protocol binds the source content field to the
  # authenticated input descriptor.  Retain the independently verified
  # durable payload hash as the source snapshot so G1 can re-authenticate both
  # the ABI projection and its backing bytes after reopen.
  durable_source_identity <- .wb_operation_pack_v3_phase5_primitive_identity(
    bundle, source)
  source_content_identity <- source_record$content_identity
  linkage <- .wb_operation_pack_v3_model_source_linkage_v2(engine,
    model_type, as.character(source$space_id)[1],
    source_content_identity, source_record$cell_order_identity, dims,
    durable_source_identity$sha256)
  sibling_names <- as.character(unlist(policy$required_sibling_terminals,
    use.names = FALSE))
  declarations <- stats::setNames(operation$outputs,
    vapply(operation$outputs, `[[`, character(1), "name"))
  siblings <- lapply(sibling_names, function(name) {
    record <- output_records[[name]]
    kind <- as.character(declarations[[name]]$kind)[1]
    cell_indexed <- kind %in% c("matrix", "space", "space_2d",
      "cell_vector", "cell_vector_family", "relation_family")
    list(name = name, allocated_id = as.character(record$allocated_id)[1],
      kind = kind, grant_identity =
        .wb_operation_pack_v3_unscoped_identity(
          record$descriptor$grant_identity),
      replay_policy = as.character(operation$replay_equivalence[[name]])[1],
      expected_cell_order_identity_if_cell_indexed = if (cell_indexed)
        source_record$cell_order_identity else NULL)
  })
  model_name <- as.character(output$name)[1]
  model_record <- output_records[[model_name]]
  closure_preimage <- list(model_output = model_name,
    model_grant_identity = .wb_operation_pack_v3_unscoped_identity(
      model_record$descriptor$grant_identity),
    model_source_linkage_identity = .wb_operation_pack_v3_unscoped_identity(
      linkage$linkage_identity), promotion_group = as.character(
        output$promotion_group)[1], siblings = lapply(siblings, function(x)
          x[c("name", "grant_identity", "replay_policy")]))
  closure_identity <- .wb_operation_pack_v2_identity_plain(
    "scworkbench.operation_pack.model_sibling_closure.v1", closure_preimage)
  grant <- list(schema =
      "scworkbench.operation_pack.contained_model_sibling_write_grant.v1",
    output = model_name, engine = engine, model_type = model_type,
    primary_path = as.character(policy$primary_path)[1],
    relative_root = paste0("outputs/", model_name, "/model_tree"),
    source_space = list(input_name = source_name,
      input_descriptor_identity = .wb_operation_pack_v3_unscoped_identity(
        source_record$descriptor_identity),
      content_identity = source_record$content_identity,
      cell_order_identity = source_record$cell_order_identity,
      dimensions = unname(as.list(as.integer(dim(source$values)))),
      selected_dimension_count = as.integer(dims$count),
      selected_dimension_order_identity = dims$identity),
    model_source_linkage = linkage,
    required_sibling_terminals = siblings,
    model_sibling_closure_identity = closure_identity,
    limits = list(maximum_file_count = as.integer(policy$maximum_file_count),
      maximum_total_bytes = as.integer(policy$maximum_total_bytes)))
  grant$write_grant_identity <- .wb_operation_pack_v2_identity_scoped(
    grant$schema, "grant excluding write_grant_identity", grant)
  grant
}

.wb_operation_pack_v3_model_adapters <- function(base, request, operation,
    stage_root) {
  grants <- stats::setNames(request$outputs, vapply(request$outputs, `[[`,
    character(1), "name"))
  declarations <- stats::setNames(operation$outputs, vapply(operation$outputs,
    `[[`, character(1), "name"))
  state <- base$state
  state$model_payload_calls <- list()
  model_values <- c(attr(request, "operation_pack_v3_model_read_values") %||%
    list(), attr(request,
      "operation_pack_v3_self_linked_model_read_values") %||% list())
  all_read_grants <- .wb_operation_pack_v3_all_model_read_grants(request)
  if (length(model_values)) {
    model_input_names <- vapply(all_read_grants, `[[`,
      character(1), "input_name")
    base$readers <- base$readers[setdiff(names(base$readers), model_input_names)]
    readers <- stats::setNames(lapply(all_read_grants,
      function(grant) {
        name <- as.character(grant$name)[1]; force(name); force(grant)
        function(...) {
          if (isTRUE(state$used) || length(list(...)) ||
              !is.null(state$model_payload_calls[[name]]))
            .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
              "Contained-model reader is private, no-argument, and exactly once.",
              "execution")
          .wb_operation_pack_v3_validate_model_read(stage_root, grant)
          state$model_payload_calls[[name]] <- 1L
          root <- file.path(stage_root, grant$relative_root)
          safe <- function(path) {
            path <- as.character(path)[1]
            if (!path %in% vapply(grant$tree_manifest$entries, `[[`,
                character(1), "path")) .wb_operation_pack_v3_error(
                  "PYBENCH_CAPABILITY_MISMATCH",
                  "Contained-model reader requested an unauthenticated entry.",
                  "execution")
            file.path(root, path)
          }
          result <- list(primary_path = grant$tree_manifest$primary_path,
            entries = .wb_operation_pack_v2_deep_copy(
              grant$tree_manifest$entries),
            read_bytes = function(path) readBin(safe(path), "raw",
              n = file.info(safe(path))$size))
          fitted <- model_values[[name]]$fitted_space %||% NULL
          if (!is.null(fitted)) result$fitted_source_space <-
            .wb_operation_pack_v2_deep_copy(fitted)
          if (identical(grant$reader,
              "read_self_linked_contained_model_payload"))
            result$runtime_private_path <- safe else result$path <- safe
          result
        }
      }), vapply(all_read_grants, `[[`, character(1), "name"))
    base$readers <- c(base$readers, readers)
  }
  open_model <- function(output) {
    output <- as.character(output)[1]
    grant <- grants[[output]]$descriptor$contained_model_write_grant %||%
      grants[[output]]$descriptor$contained_model_sibling_write_grant %||%
      .wb_operation_pack_v3_dfa_model_grant(state, output) %||% NULL
    if (is.null(grant) || !is.null(state$writes[[output]]))
      .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
        "No unused contained-model writer grant exists for this output.",
        "execution")
    root <- file.path(stage_root, grant$relative_root)
    dir.create(root, recursive = TRUE, showWarnings = FALSE)
    closed <- FALSE
    adoption_grants <- request$supported_external_state_adoption_grants %||%
      list()
    adoption <- Filter(function(x) identical(as.character(
      x$adopted_closure$outputs[[1L]]$name)[1], output), adoption_grants)
    adoption <- if (length(adoption)) adoption[[1L]] else NULL
    path <- function(relative = grant$primary_path) {
      if (closed || !.wb_operation_pack_v3_safe_model_entry(relative))
        .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
          "Contained-model writer requested an unsafe or closed path.",
          "execution")
      target <- file.path(root, relative)
      dir.create(dirname(target), recursive = TRUE, showWarnings = FALSE)
      target
    }
    finish <- function(value, semantic_metadata = list()) {
      if (closed || !.wb_is_primitive(value) ||
          !identical(as.character(value$kind)[1], "model_ref"))
        .wb_operation_pack_v3_error("PYBENCH_OUTPUT_INVALID",
          "Contained-model writer requires one model_ref close.", "audit")
      manifest <- .wb_operation_pack_v3_model_tree_manifest(root,
        grant$engine, grant$model_type, grant$primary_path,
        grant$limits$maximum_file_count, grant$limits$maximum_total_bytes)
      sibling <- as.character(grant$schema)[1] %in% c(
        "scworkbench.operation_pack.contained_model_sibling_write_grant.v1",
        "scworkbench.operation_pack.sealed_model_sibling_grant.v1")
      derived <- identical(as.character(grant$schema)[1],
        "scworkbench.operation_pack.sealed_model_sibling_grant.v1")
      if (sibling && nzchar(as.character(value$in_space_id %||% "")[1]) &&
          !identical(as.character(value$in_space_id)[1],
            as.character(if (derived) grant$source_space_id else
              grant$model_source_linkage$source_space_id)[1]))
        .wb_operation_pack_v3_error("PYBENCH_OUTPUT_INVALID",
          "Contained-model source-space substitution is forbidden.", "audit")
      linkage <- if (sibling) grant$model_source_linkage else
        .wb_operation_pack_v3_model_linkage(grant$engine,
          grant$model_type, as.character(value$in_space_id)[1], list(
            count = grant$source_space$selected_dimension_count,
            identity = grant$source_space$selected_dimension_order_identity))
      value$engine <- grant$engine; value$model_type <- grant$model_type
      if (sibling) value$model_source_linkage <- linkage else
        value$model_linkage <- linkage
      value$model_payload_entry <- grant$primary_path
      payload <- file.path(stage_root, "outputs", output, "payload.rds")
      saveRDS(value, payload, version = 3L, compress = FALSE)
      state$writes[[output]] <- list(value = value, payload = payload,
        semantic_metadata = semantic_metadata %||% list(),
        writer = "write_model_ref", tree_manifest = manifest,
        tree_root = root)
      closed <<- TRUE
      if (derived) .wb_operation_pack_v2_fault(
        "derived_fitted_axis_model_closed", stage_root = stage_root,
        model_output = output)
      invisible(list(name = output,
        allocated_id = grants[[output]]$allocated_id,
        grant_identity = grants[[output]]$descriptor$grant_identity))
    }
    if (!is.null(adoption)) {
      write_bytes <- function(relative, bytes) {
        if (closed || !is.raw(bytes) || !length(bytes) ||
            !relative %in% vapply(adoption$candidate_snapshot$tree_manifest$
              entries, `[[`, character(1), "path"))
          .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
            "Adoption writer accepts only authenticated entries as raw bytes.",
            "execution")
        target <- file.path(root, relative)
        dir.create(dirname(target), recursive = TRUE, showWarnings = FALSE)
        con <- file(target, open = "wb")
        tryCatch(writeBin(bytes, con), finally = close(con))
        invisible(TRUE)
      }
      return(list(primary_path = grant$primary_path,
        write_bytes = write_bytes, finish = finish))
    }
    list(path = path, primary_path = grant$primary_path, finish = finish)
  }
  if (length(request$derived_fitted_axis_grants %||% list()) ||
      any(vapply(grants, function(x) !is.null(x$descriptor$
      contained_model_write_grant) || !is.null(x$descriptor$
        contained_model_sibling_write_grant), logical(1))))
    base$writers$open_model_tree <- open_model
  base
}

.wb_operation_pack_v3_validate_model_read <- function(stage_root, grant) {
  root <- file.path(stage_root, grant$relative_root)
  engine <- grant$engine %||% grant$selected_model$engine
  model_type <- grant$model_type %||% grant$selected_model$model_type
  observed <- .wb_operation_pack_v3_model_tree_manifest(root, engine,
    model_type, grant$tree_manifest$primary_path,
    code = "PYBENCH_INPUT_IDENTITY_MISMATCH", phase = "audit")
  if (!identical(observed, grant$tree_manifest) ||
      !identical(.wb_operation_pack_v3_model_payload_identity(observed),
        grant$payload_manifest_identity))
    .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
      "Private contained-model bytes changed after authentication.", "audit")
  invisible(TRUE)
}

.wb_operation_pack_v3_model_read_observations <- function(request, state) {
  lapply(request$model_payload_grants %||% list(), function(grant) {
    if (!identical(as.integer(state$model_payload_calls[[grant$name]] %||%
        0L), 1L)) .wb_operation_pack_v3_error("PYBENCH_RECEIPT_MISMATCH",
          "Contained-model reader was not consumed exactly once.", "receipt")
    .wb_operation_pack_v3_validate_model_read(
      attr(request, "operation_pack_stage_root"), grant)
    value <- list(schema =
        "scworkbench.operation_pack.observed_contained_model_read.v1",
      name = grant$name,
      grant_identity = .wb_operation_pack_v3_unscoped_identity(
        grant$grant_identity),
      input_descriptor_identity = grant$input_descriptor_identity,
      model_linkage_identity = grant$model_linkage_identity,
      payload_manifest_identity = grant$payload_manifest_identity,
      engine = grant$engine, model_type = grant$model_type,
      use_count = 1L, integrity_status = "unchanged")
    value$observation_identity <- .wb_operation_pack_v2_identity_scoped(
      "scworkbench.operation_pack.observed_contained_model_read.v1",
      "observation excluding observation_identity", value)
    value
  })
}

.wb_operation_pack_v3_self_linked_model_read_observations <- function(request,
    state) {
  lapply(request$self_linked_model_payload_grants %||% list(), function(grant) {
    if (!identical(as.integer(state$model_payload_calls[[grant$name]] %||%
        0L), 1L)) .wb_operation_pack_v3_error("PYBENCH_RECEIPT_MISMATCH",
          "Self-linked model reader was not consumed exactly once.", "receipt")
    .wb_operation_pack_v3_validate_model_read(
      attr(request, "operation_pack_stage_root"), grant)
    value <- list(schema =
      "scworkbench.operation_pack.observed_self_linked_contained_model_read.v1",
      name = grant$name,
      grant_identity = grant$grant_identity,
      input_descriptor_identity = grant$input_descriptor_identity,
      model_source_linkage_identity = grant$model_source_linkage_identity,
      tree_manifest_identity = .wb_operation_pack_v3_unscoped_identity(
        grant$tree_manifest$manifest_identity),
      payload_manifest_identity = grant$payload_manifest_identity,
      engine = grant$selected_model$engine,
      model_type = grant$selected_model$model_type,
      use_count = 1L, integrity_status = "unchanged")
    value$observation_identity <- .wb_operation_pack_v2_identity_scoped(
      value$schema,
      "self_linked_model_read_observation excluding observation_identity",
      value)
    value
  })
}
