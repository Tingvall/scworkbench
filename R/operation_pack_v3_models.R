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

.wb_operation_pack_v3_copy_model_file <- function(source, root, primary) {
  if (!file.exists(source) || dir.exists(source) || nzchar(Sys.readlink(source)))
    .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
      "Contained model source is absent, non-regular, or linked.", "resolution")
  target <- file.path(root, primary)
  dir.create(dirname(target), recursive = TRUE, showWarnings = FALSE)
  if (!isTRUE(file.copy(source, target, copy.mode = FALSE, copy.date = FALSE)))
    .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
      "Contained model payload could not be copied privately.", "staging")
  Sys.chmod(target, mode = "0444")
  target
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

.wb_operation_pack_v3_prepare_model_reads <- function(bundle, operation,
    inputs, input_records, params, stage_root) {
  grants <- list(); values <- list(); records <- input_records
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
    root_rel <- paste0("model_payload_reads/", name, "/tree")
    root <- file.path(stage_root, root_rel)
    dir.create(root, recursive = TRUE, showWarnings = FALSE)
    primary <- "model.uwot"
    .wb_operation_pack_v3_copy_model_file(
      .wb_operation_pack_v3_model_path(bundle, model), root, primary)
    tree <- .wb_operation_pack_v3_model_tree_manifest(root, engine,
      model_type, primary, code = "PYBENCH_INPUT_IDENTITY_MISMATCH",
      phase = "staging")
    payload_identity <- .wb_operation_pack_v3_model_payload_identity(tree)
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

.wb_operation_pack_v3_model_adapters <- function(base, request, operation,
    stage_root) {
  grants <- stats::setNames(request$outputs, vapply(request$outputs, `[[`,
    character(1), "name"))
  declarations <- stats::setNames(operation$outputs, vapply(operation$outputs,
    `[[`, character(1), "name"))
  state <- base$state
  state$model_payload_calls <- list()
  model_values <- attr(request, "operation_pack_v3_model_read_values") %||%
    list()
  if (length(model_values)) {
    model_input_names <- vapply(request$model_payload_grants, `[[`,
      character(1), "input_name")
    base$readers <- base$readers[setdiff(names(base$readers), model_input_names)]
    readers <- stats::setNames(lapply(request$model_payload_grants,
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
          list(primary_path = grant$tree_manifest$primary_path,
            entries = .wb_operation_pack_v2_deep_copy(
              grant$tree_manifest$entries),
            path = safe,
            read_bytes = function(path) readBin(safe(path), "raw",
              n = file.info(safe(path))$size))
        }
      }), vapply(request$model_payload_grants, `[[`, character(1), "name"))
    base$readers <- c(base$readers, readers)
  }
  open_model <- function(output) {
    output <- as.character(output)[1]
    grant <- grants[[output]]$descriptor$contained_model_write_grant %||% NULL
    if (is.null(grant) || !is.null(state$writes[[output]]))
      .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
        "No unused contained-model writer grant exists for this output.",
        "execution")
    root <- file.path(stage_root, grant$relative_root)
    dir.create(root, recursive = TRUE, showWarnings = FALSE)
    closed <- FALSE
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
      linkage <- .wb_operation_pack_v3_model_linkage(grant$engine,
        grant$model_type, as.character(value$in_space_id)[1], list(
          count = grant$source_space$selected_dimension_count,
          identity = grant$source_space$selected_dimension_order_identity))
      value$engine <- grant$engine; value$model_type <- grant$model_type
      value$model_linkage <- linkage
      value$model_payload_entry <- grant$primary_path
      payload <- file.path(stage_root, "outputs", output, "payload.rds")
      saveRDS(value, payload, version = 3L, compress = FALSE)
      state$writes[[output]] <- list(value = value, payload = payload,
        semantic_metadata = semantic_metadata %||% list(),
        writer = "write_model_ref", tree_manifest = manifest,
        tree_root = root)
      closed <<- TRUE
      invisible(list(name = output,
        allocated_id = grants[[output]]$allocated_id,
        grant_identity = grants[[output]]$descriptor$grant_identity))
    }
    list(path = path, primary_path = grant$primary_path, finish = finish)
  }
  if (any(vapply(grants, function(x) !is.null(x$descriptor$
      contained_model_write_grant), logical(1))))
    base$writers$open_model_tree <- open_model
  base
}

.wb_operation_pack_v3_validate_model_read <- function(stage_root, grant) {
  root <- file.path(stage_root, grant$relative_root)
  observed <- .wb_operation_pack_v3_model_tree_manifest(root, grant$engine,
    grant$model_type, grant$tree_manifest$primary_path,
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
