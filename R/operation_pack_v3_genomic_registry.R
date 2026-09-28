# Bounded, source-bound genomic and motif registry snapshots for ABI v3.
# These readers carry data, never a bundle handle or filesystem authority.

.wb_operation_pack_v3_registry_scalar <- function(value) {
  if (!length(value) || is.na(value[[1L]])) NULL else
    as.character(value[[1L]])
}

.wb_operation_pack_v3_genomic_matrix <- function(bundle, declaration, inputs,
    input_records, effective_cells) {
  input_name <- as.character(declaration$matrix_input)[1L]
  input <- inputs[[input_name]]
  matrix_id <- as.character(input$matrix_id %||% "")[1L]
  descriptor <- input_records[[input_name]]
  features <- as.character(input$feature_id %||% character())
  cells <- as.character(effective_cells %||% input$cell_id %||% character())
  if (!nzchar(matrix_id) || !length(features) || length(features) > 2000000L ||
      anyNA(features) || any(!nzchar(features)) || anyDuplicated(features) ||
      !length(cells) || anyDuplicated(cells) ||
      !identical(cells, as.character(input$cell_id)))
    .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
      "Genomic source requires one authenticated ordered matrix axis.",
      "resolution")
  matrices <- wb_matrices(bundle)
  row <- matrices[as.character(matrices$matrix_id) == matrix_id, , drop = FALSE]
  peaks <- wb_features(bundle, matrix_id = matrix_id)
  if (nrow(row) != 1L || !identical(as.character(peaks$feature_id), features))
    .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
      "Genomic source matrix or ordered feature rows changed.", "resolution")
  fields <- c("feature_id", "feature_type", "chr", "start", "end")
  peak_rows <- lapply(seq_len(nrow(peaks)), function(i) list(
    feature_id = as.character(peaks$feature_id[[i]]),
    feature_type = .wb_operation_pack_v3_registry_scalar(peaks$feature_type[i]),
    chr = .wb_operation_pack_v3_registry_scalar(peaks$chr[i]),
    start = if (is.na(peaks$start[[i]])) NULL else as.integer(peaks$start[[i]]),
    end = if (is.na(peaks$end[[i]])) NULL else as.integer(peaks$end[[i]])))
  list(schema = "scworkbench.genomic_matrix_source.snapshot.v1",
    matrix_input = input_name, matrix_id = matrix_id,
    input_descriptor_identity = .wb_operation_pack_v3_unscoped_identity(
      descriptor$descriptor_identity),
    input_content_identity = descriptor$content_identity,
    feature_order_identity = .wb_operation_pack_v2_identity_plain(
      "scworkbench.feature_order.v1", unname(as.list(features))),
    cell_order_identity = .wb_operation_pack_v2_identity_plain(
      "scworkbench.cell_order.v1", unname(as.list(cells))),
    consumed_matrix_identity = .wb_operation_pack_v3_matrix_consumed_identity(
      bundle, matrix_id),
    feature_count = as.integer(length(features)),
    cell_count = as.integer(length(cells)),
    cell_id = unname(as.list(cells)),
    feature_type = .wb_operation_pack_v3_registry_scalar(row$feature_type),
    organism = .wb_operation_pack_v3_registry_scalar(row$organism),
    genome_build = .wb_operation_pack_v3_registry_scalar(row$genome_build),
    genome_provider = .wb_operation_pack_v3_registry_scalar(
      row$genome_provider),
    fields = unname(as.list(fields)), peaks = unname(peak_rows))
}

.wb_operation_pack_v3_motif_library <- function(bundle, declaration, params) {
  parameter <- as.character(declaration$library_parameter)[1L]
  library <- as.character(params[[parameter]] %||% "")[1L]
  libraries <- wb_motif_libraries(bundle)
  row <- libraries[as.character(libraries$motif_library) == library,
    , drop = FALSE]
  if (!nzchar(library) || nrow(row) != 1L)
    .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
      "Motif library selection is absent or ambiguous.", "resolution")
  motifs <- wb_motifs(bundle, motif_library = library)
  if (!nrow(motifs) || nrow(motifs) > 10000L ||
      anyDuplicated(as.character(motifs$motif_key)))
    .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
      "Motif library is empty, duplicated or over the bounded reader limit.",
      "resolution")
  library_fields <- c("motif_library", "source_type", "organism",
    "genome_build", "collection", "source_id", "source_version",
    "description", "created_at", "created_by")
  motif_fields <- c("motif_key", "motif_library", "motif_id", "motif_name",
    "source_type", "matrix_class", "payload_json", "metadata_json",
    "created_at", "created_by")
  list(schema = "scworkbench.motif_library.snapshot.v1",
    library_parameter = parameter, motif_library = library,
    library = stats::setNames(lapply(library_fields, function(field)
      .wb_operation_pack_v3_registry_scalar(row[[field]])), library_fields),
    motifs = unname(lapply(seq_len(nrow(motifs)), function(i)
      stats::setNames(lapply(motif_fields, function(field)
        .wb_operation_pack_v3_registry_scalar(motifs[[field]][i])),
        motif_fields))))
}

.wb_operation_pack_v3_motif_match_set <- function(bundle, declaration,
    params) {
  parameter <- as.character(declaration$match_set_parameter)[1L]
  match_set <- params[[parameter]] %||% NULL
  if (is.null(match_set)) return(list(
    schema = "scworkbench.motif_match_set.snapshot.v1",
    match_set_parameter = parameter, selection = NULL,
    match_set = NULL, membership = list()))
  match_set <- as.character(match_set)[1L]
  rows <- wb_motif_match_sets(bundle, motif_match_set = match_set)
  if (!nzchar(match_set) || nrow(rows) != 1L)
    .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
      "Motif match-set selection is absent or ambiguous.", "resolution")
  membership <- wb_motif_match_get(bundle, motif_match_set = match_set)
  if (nrow(membership) > 5000000L)
    .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
      "Motif match membership exceeds the bounded reader limit.",
      "resolution")
  fields <- c("motif_match_set", "matrix_id", "motif_library", "organism",
    "genome_build", "genome_provider", "match_engine",
    "match_params_json", "n_features", "n_motifs", "description",
    "created_at", "created_by")
  binding <- stats::setNames(lapply(fields, function(field) {
    value <- rows[[field]][[1L]]
    if (is.na(value)) NULL else if (field %in% c("n_features", "n_motifs"))
      as.integer(value) else as.character(value)
  }), fields)
  list(schema = "scworkbench.motif_match_set.snapshot.v1",
    match_set_parameter = parameter, selection = match_set,
    match_set = binding,
    membership = unname(lapply(seq_len(nrow(membership)), function(i)
      list(motif_key = as.character(membership$motif_key[[i]]),
        feature_id = as.character(membership$feature_id[[i]])))))
}

.wb_operation_pack_v3_genomic_registry_snapshot <- function(bundle,
    declaration, inputs, input_records, params, effective_cells) {
  kind <- as.character(declaration$kind)[1L]
  if (identical(kind, "genomic_matrix_source"))
    .wb_operation_pack_v3_genomic_matrix(bundle, declaration, inputs,
      input_records, effective_cells)
  else if (identical(kind, "motif_library"))
    .wb_operation_pack_v3_motif_library(bundle, declaration, params)
  else if (identical(kind, "motif_match_set"))
    .wb_operation_pack_v3_motif_match_set(bundle, declaration, params)
  else stop("Unsupported bounded genomic registry kind.", call. = FALSE)
}

.wb_operation_pack_v3_genomic_provider_preflight <- function(bundle,
    operation, inputs, preflight) {
  dependencies <- Filter(function(x) identical(as.character(x$kind %||%
    "")[1L], "dynamic_matrix_registry_package"), operation$dependencies %||%
    list())
  if (!length(dependencies)) return(preflight)
  for (dependency in dependencies) {
    input_name <- as.character(dependency$matrix_input)[1L]
    matrix_id <- as.character(inputs[[input_name]]$matrix_id %||% "")[1L]
    rows <- wb_matrices(bundle)
    row <- rows[as.character(rows$matrix_id) == matrix_id, , drop = FALSE]
    provider <- if (nrow(row) == 1L)
      .wb_operation_pack_v3_registry_scalar(row$genome_provider) else NULL
    if (is.null(provider) || !grepl("^[A-Za-z][A-Za-z0-9.]*$",
        provider, perl = TRUE))
      .wb_operation_pack_v3_error("OPERATION_PACK_DYNAMIC_PROVIDER_INVALID",
        "Core-attested matrix genome provider is absent or malformed.",
        "preflight")
    if (!requireNamespace(provider, quietly = TRUE))
      .wb_operation_pack_v3_error("OPERATION_PACK_DEPENDENCY_MISSING",
        paste0("Core-attested genome provider package '", provider,
          "' is unavailable."), "preflight")
    version <- as.character(utils::packageVersion(provider))
    consumed <- .wb_operation_pack_v3_matrix_consumed_identity(bundle,
      matrix_id, "preflight")
    resolution <- list(requirement_id = dependency$requirement_id,
      selector_identity = .wb_operation_pack_v2_identity_plain(
        "scworkbench.operation_pack.dynamic_dependency_selector.v2",
        dependency),
      input_name = input_name,
      input_identity = list(scheme = consumed$content_identity_scheme,
        sha256 = consumed$content_sha256),
      metadata_field = "genome_provider", ecosystem = "R",
      provider_name = provider,
      package_name_scheme = "r_package_name_v1",
      probe = "r_namespace_exports_v1", disposition = "required",
      resolved_package = list(name = provider, version = version,
        artifact_identity = .wb_operation_pack_v2_identity_plain(
          "scworkbench.r_package.artifact.v1",
          list(name = provider, version = version)),
        probe_evidence_identity = .wb_operation_pack_v2_identity_plain(
          "scworkbench.r_namespace_exports.v1",
          getNamespaceExports(provider))), status = "available")
    resolution$resolution_identity <-
      .wb_operation_pack_v2_identity_scoped(
        "scworkbench.operation_pack.dynamic_dependency_resolution.v2",
        "resolution excluding resolution_identity", resolution)
    preflight$dynamic <- c(preflight$dynamic %||% list(),
      list(resolution))
    preflight$dispositions[[as.character(dependency$requirement_id)[1L]]] <-
      resolution
  }
  preflight$preflight_identity <- .wb_operation_pack_v2_identity_plain(
    "scworkbench.operation_pack.preflight.v2", list(
      declared = preflight$declared, selected = preflight$selected,
      dispositions = preflight$dispositions, dynamic = preflight$dynamic,
      network_policy = "deny"))
  preflight
}

.wb_operation_pack_v3_genomic_provider_assert_current <- function(bundle,
    operation, inputs, preflight) {
  for (dependency in operation$dependencies %||% list()) {
    if (!identical(as.character(dependency$kind %||% "")[1L],
        "dynamic_matrix_registry_package")) next
    resolution <- preflight$dispositions[[as.character(
      dependency$requirement_id)[1L]]]
    matrix_id <- as.character(inputs[[resolution$input_name]]$matrix_id)[1L]
    rows <- wb_matrices(bundle)
    row <- rows[as.character(rows$matrix_id) == matrix_id,
      , drop = FALSE]
    provider <- if (nrow(row) == 1L)
      .wb_operation_pack_v3_registry_scalar(row$genome_provider) else NULL
    observed <- .wb_operation_pack_v3_matrix_consumed_identity(bundle,
      matrix_id, "dispatch")
    if (!identical(provider, resolution$provider_name) ||
        !identical(list(scheme = observed$content_identity_scheme,
          sha256 = observed$content_sha256), resolution$input_identity) ||
        !requireNamespace(provider, quietly = TRUE) ||
        !identical(as.character(utils::packageVersion(provider)),
          resolution$resolved_package$version))
      .wb_operation_pack_v3_error(
        "OPERATION_PACK_DYNAMIC_PROVIDER_CHANGED",
        "Matrix provider or stage-visible source bytes changed after preflight.",
        "dispatch")
  }
  invisible(TRUE)
}

# A staged transition may outlive its original bundle source. Reopen verifies
# the retained bytes, but promotion must also compare them with the *current*
# source before any private payload is copied into the promotion workspace.
.wb_operation_pack_v3_genomic_retained_assert_current <- function(bundle,
    request, stage_root) {
  kinds <- c("genomic_matrix_source", "motif_library", "motif_match_set")
  records <- Filter(function(x) as.character(x$descriptor$kind %||% "")[1L] %in%
    kinds, request$registry_reads %||% list())
  if (!length(records)) return(invisible(TRUE))
  input_records <- stats::setNames(lapply(request$inputs, `[[`, "descriptor"),
    vapply(request$inputs, `[[`, character(1), "name"))
  for (record in records) {
    name <- as.character(record$name)[1L]
    kind <- as.character(record$descriptor$kind)[1L]
    payload <- file.path(stage_root, "registry_reads", name, "payload.json")
    retained <- tryCatch(jsonlite::read_json(payload, simplifyVector = FALSE),
      error = identity)
    if (inherits(retained, "error"))
      .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
        paste0("Retained genomic registry payload is unreadable: ", name),
        "promotion")
    identities <- .wb_operation_pack_v3_registry_snapshot_identities(
      retained, kind)
    if (!identical(identities$content,
        record$descriptor$content_identity) ||
        !identical(identities$source, record$descriptor$source_identity))
      .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
        paste0("Retained genomic registry identity changed: ", name),
        "promotion")
    declaration <- list(kind = kind)
    inputs <- list()
    params <- request$params %||% list()
    cells <- NULL
    if (identical(kind, "genomic_matrix_source")) {
      declaration$matrix_input <- retained$matrix_input
      input_name <- as.character(retained$matrix_input)[1L]
      inputs[[input_name]] <- list(matrix_id = retained$matrix_id,
        feature_id = vapply(retained$peaks, `[[`, character(1), "feature_id"),
        cell_id = unlist(retained$cell_id, use.names = FALSE))
      cells <- inputs[[input_name]]$cell_id
      if (is.null(input_records[[input_name]]))
        .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
          "Retained genomic source lacks its authenticated matrix input.",
          "promotion")
    } else if (identical(kind, "motif_library")) {
      declaration$library_parameter <- retained$library_parameter
      parameter <- as.character(retained$library_parameter)[1L]
      if (!identical(as.character(params[[parameter]])[1L],
          as.character(retained$motif_library)[1L]))
        .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
          "Retained motif library differs from the authenticated parameter.",
          "promotion")
    } else {
      declaration$match_set_parameter <- retained$match_set_parameter
      parameter <- as.character(retained$match_set_parameter)[1L]
      if (!identical(params[[parameter]] %||% NULL,
          retained$selection %||% NULL))
        .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
          "Retained motif match set differs from the authenticated parameter.",
          "promotion")
    }
    current <- .wb_operation_pack_v3_genomic_registry_snapshot(bundle,
      declaration, inputs, input_records, params, cells)
    observed <- .wb_operation_pack_v3_registry_snapshot_identities(current,
      kind)
    if (!identical(observed$content, identities$content) ||
        !identical(observed$source, identities$source))
      .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
        paste0("Genomic registry source changed before promotion: ", name),
        "promotion")
  }
  for (resolution in request$dependency_resolution$dynamic %||% list()) {
    if (!identical(as.character(resolution$metadata_field %||% "")[1L],
        "genome_provider")) next
    input_name <- as.character(resolution$input_name)[1L]
    genomic <- Filter(function(x) identical(as.character(
      x$descriptor$matrix_input %||% "")[1L], input_name), records)
    if (length(genomic) != 1L)
      .wb_operation_pack_v3_error("OPERATION_PACK_DYNAMIC_PROVIDER_CHANGED",
        "Dynamic provider has no unique authenticated genomic source.",
        "promotion")
    matrix_id <- as.character(genomic[[1L]]$descriptor$matrix_id)[1L]
    rows <- wb_matrices(bundle)
    row <- rows[as.character(rows$matrix_id) == matrix_id, , drop = FALSE]
    provider <- if (nrow(row) == 1L)
      .wb_operation_pack_v3_registry_scalar(row$genome_provider) else NULL
    if (!identical(provider, resolution$provider_name) ||
        !requireNamespace(provider, quietly = TRUE) ||
        !identical(as.character(utils::packageVersion(provider)),
          resolution$resolved_package$version))
      .wb_operation_pack_v3_error("OPERATION_PACK_DYNAMIC_PROVIDER_CHANGED",
        "Dynamic provider changed before promotion.", "promotion")
  }
  invisible(TRUE)
}
