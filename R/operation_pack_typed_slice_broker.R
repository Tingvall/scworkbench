# Private supervised broker for bounded ABI-v3 Python typed-slice reads.

.wb_operation_pack_v3_broker_axis_value <- function(axis, ids) {
  ids <- as.character(ids)
  value <- list(schema =
      "scworkbench.operation_pack.typed_slice_axis_manifest.v1",
    axis = axis, count = as.integer(length(ids)), ids = unname(as.list(ids)),
    order_identity = .wb_operation_pack_v2_identity_plain(
      if (axis == "cells") "scworkbench.cell_order.v1" else
        "scworkbench.feature_order.v1", unname(as.list(ids))))
  value$manifest_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.typed_slice_axis_manifest.v1",
    "axis manifest excluding manifest_identity", value)
  value
}

.wb_operation_pack_v3_broker_open_bundle <- function(bundle_dir) {
  bundle_dir <- normalizePath(bundle_dir, winslash = "/", mustWork = TRUE)
  manifest_path <- .wb_bundle_path_require(bundle_dir, "manifest.json",
    expected_type = "file", purpose = "typed-slice broker manifest")
  manifest <- jsonlite::read_json(manifest_path, simplifyVector = TRUE)
  db_path <- .wb_bundle_path_require(bundle_dir,
    manifest$storage$sqlite$path, expected_type = "file", must_exist = TRUE,
    purpose = "typed-slice broker SQLite database")
  con <- DBI::dbConnect(RSQLite::SQLite(), db_path,
    flags = RSQLite::SQLITE_RO)
  .wb_sqlite_configure_connection(con, writable = FALSE,
    configure_journal = FALSE)
  structure(list(dir = bundle_dir, manifest = manifest, con = con,
    read_only = TRUE, operation_pack_broker = TRUE),
    class = "scworkbench_bundle")
}

.wb_operation_pack_v3_broker_file_record <- function(role, path, root) {
  target <- file.path(root, path)
  list(role = role, path = path, size = as.numeric(file.info(target)$size),
    sha256 = .wb_operation_pack_v2_file_sha256(target))
}

.wb_operation_pack_v3_broker_validate_axis <- function(selected, allowed,
    label) {
  selected <- as.character(selected)
  if (!length(selected) || anyNA(selected) || any(!nzchar(selected)) ||
      anyDuplicated(selected) || length(setdiff(selected, allowed)) ||
      !identical(selected, allowed[match(selected, allowed)]))
    .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
      paste0("Broker ", label, " selection is empty, duplicate, unknown, ",
        "or out of order."), "execution")
  selected
}

.wb_operation_pack_v3_broker_read_control <- function(path, token, request,
                                                        grant, ordinal,
                                                        axes, prior) {
  if (as.numeric(file.info(path)$size) >
      as.numeric(grant$max_control_bytes))
    .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
      "Broker control request exceeds its byte limit.", "execution")
  raw <- readChar(path, nchars = file.info(path)$size, useBytes = TRUE)
  .wb_operation_pack_v2_assert_strict_json(raw)
  control <- .wb_operation_pack_parse_canonical_json(raw)
  required <- c("schema", "request_identity", "grant_identity", "ordinal",
    "features", "cells", "authorization_token", "control_identity")
  if (!setequal(names(control), required) || !identical(control$schema,
      "scworkbench.operation_pack.typed_slice_control_request.v1") ||
      !identical(control$authorization_token, token) ||
      !identical(control$request_identity, request$request_identity) ||
      !identical(control$grant_identity, grant$grant_identity) ||
      !identical(as.integer(control$ordinal), as.integer(ordinal)))
    .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
      "Broker control request differs from its private grant.", "execution")
  .wb_operation_pack_v3_assert_self_identity(control, "control_identity",
    "PYBENCH_CAPABILITY_MISMATCH", "execution")
  features <- .wb_operation_pack_v3_broker_validate_axis(
    unlist(control$features, use.names = FALSE), axes$features, "feature")
  cells <- .wb_operation_pack_v3_broker_validate_axis(
    unlist(control$cells, use.names = FALSE), axes$cells, "cell")
  if (length(features) > as.integer(grant$max_rows) ||
      length(cells) > as.integer(grant$max_columns) ||
      as.double(length(features)) * as.double(length(cells)) >
        as.double(grant$max_elements))
    .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
      "Broker control request exceeds authenticated limits.", "execution")
  chunk_axis <- as.character(grant$chunk_axis)[1]
  chunk_values <- if (chunk_axis == "cells") cells else features
  nonchunk_values <- if (chunk_axis == "cells") features else cells
  allowed_chunk <- axes[[chunk_axis]]
  other_axis <- if (chunk_axis == "cells") "features" else "cells"
  allowed_nonchunk <- axes[[other_axis]]
  if (identical(grant$call_discipline,
      "ordered_partition_exactly_once")) {
    consumed <- sum(vapply(prior, function(x) length(x$chunk_values),
      integer(1)))
    upper <- consumed + length(chunk_values)
    expected <- if (upper <= length(allowed_chunk))
      allowed_chunk[seq.int(consumed + 1L, upper)] else character()
    if (!identical(nonchunk_values, allowed_nonchunk) ||
        !identical(chunk_values, expected) ||
        length(chunk_values) > as.integer(grant$requested_chunk_size))
      .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
        "Broker call violates ordered exactly-once partitioning.",
        "execution")
  } else {
    supported <- as.character(unlist(grant$supported_axes,
      use.names = FALSE))
    if (!(chunk_axis %in% supported) ||
        (!(other_axis %in% supported) &&
          !identical(nonchunk_values, allowed_nonchunk)) ||
        length(chunk_values) > as.integer(grant$requested_chunk_size))
      .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
        "Broker independent slice exceeds its supported axes or limit.",
        "execution")
  }
  list(value = control, features = features, cells = cells)
}

.wb_operation_pack_v3_broker_source <- function(bundle, stage, grant,
                                                  features, cells) {
  source <- grant$source_reference
  if (identical(source$source_kind, "bundle_matrix")) {
    .wb_operation_pack_v3_typed_slice_grant_assert_current(bundle, grant,
      "execution")
    values <- as.matrix(wb_slice(bundle, source$matrix_id,
      features = features, cells = cells))
    .wb_operation_pack_v3_typed_slice_grant_assert_current(bundle, grant,
      "execution")
    return(values)
  }
  matrix <- .wb_operation_pack_v3_private_source_validate(stage, grant)
  all_features <- .wb_operation_pack_v3_broker_axis_ids(stage,
    grant$features_axis)
  all_cells <- .wb_operation_pack_v3_broker_axis_ids(stage,
    grant$cells_axis)
  matrix[match(features, all_features), match(cells, all_cells), drop = FALSE]
}

.wb_operation_pack_v3_broker_axis_ids <- function(stage, descriptor) {
  path <- file.path(stage, descriptor$relative_path)
  value <- jsonlite::read_json(path, simplifyVector = FALSE)
  .wb_operation_pack_v3_assert_self_identity(value, "manifest_identity",
    "PYBENCH_CAPABILITY_MISMATCH", "execution")
  observed <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.payload_manifest.v2",
    "registry read payload manifest", list(path = descriptor$relative_path,
      size = as.numeric(file.info(path)$size),
      sha256 = .wb_operation_pack_v2_file_sha256(path)))
  if (!identical(observed, descriptor$payload_manifest_identity) ||
      !identical(value$manifest_identity, descriptor$axis_manifest_identity))
    .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
      "Broker axis manifest differs from its retained descriptor.",
      "execution")
  as.character(unlist(value$ids, use.names = FALSE))
}

.wb_operation_pack_v3_broker_publish_response <- function(spool, grant,
    request, ordinal, features, cells, values) {
  pending <- file.path(spool, "response.pending")
  response <- file.path(spool, "response")
  if (dir.exists(pending) || dir.exists(response))
    .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
      "Broker response workspace is not empty.", "execution")
  dir.create(pending)
  values <- as.matrix(values)
  dimnames(values) <- list(features, cells)
  .wb_operation_pack_v3_atomic_matrix_market(values,
    file.path(pending, "matrix.mtx"))
  feature_axis <- .wb_operation_pack_v3_broker_axis_value("features",
    features)
  cell_axis <- .wb_operation_pack_v3_broker_axis_value("cells", cells)
  .wb_operation_pack_v3_atomic_canonical_json(feature_axis,
    file.path(pending, "features.json"))
  .wb_operation_pack_v3_atomic_canonical_json(cell_axis,
    file.path(pending, "cells.json"))
  primitive <- structure(list(kind = "matrix", values = values,
    feature_id = features, cell_id = cells), class = "wb_primitive")
  result <- .wb_operation_pack_v3_slice_result(grant, ordinal, primitive)
  manifest <- list(schema =
      "scworkbench.operation_pack.typed_slice_response.v1",
    request_identity = request$request_identity,
    grant_identity = grant$grant_identity,
    source_reference_identity =
      grant$source_reference$source_reference_identity,
    ordinal = as.integer(ordinal), dimensions = result$dimensions,
    nonzero_count = as.integer(sum(values != 0)),
    feature_axis_manifest_identity = feature_axis$manifest_identity,
    cell_axis_manifest_identity = cell_axis$manifest_identity,
    files = list(
      .wb_operation_pack_v3_broker_file_record("matrix_market",
        "matrix.mtx", pending),
      .wb_operation_pack_v3_broker_file_record("features_axis",
        "features.json", pending),
      .wb_operation_pack_v3_broker_file_record("cells_axis",
        "cells.json", pending)),
    semantic_content_identity = result$semantic_content_identity,
    slice_result_identity = result$slice_result_identity)
  manifest$response_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.typed_slice_response.v1",
    "response excluding response_identity", manifest)
  .wb_operation_pack_v3_atomic_canonical_json(manifest,
    file.path(pending, "manifest.json"))
  response_size <- sum(file.info(list.files(pending, full.names = TRUE))$size)
  if (response_size > as.numeric(grant$max_response_bytes) ||
      !file.rename(pending, response))
    .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
      "Broker response exceeds its byte limit or could not publish.",
      "execution")
  list(result = result, response_identity = manifest$response_identity,
    chunk_values = if (grant$chunk_axis == "cells") cells else features)
}

.wb_operation_pack_v3_broker_wait_ack <- function(spool, token, request,
    grant, ordinal, response_identity, deadline) {
  path <- file.path(spool, "acknowledgement.json")
  while (!file.exists(path)) {
    if (Sys.time() > deadline) .wb_operation_pack_v3_error(
      "PYBENCH_PROCESS_FAILED", "Timed out waiting for broker acknowledgement.",
      "execution")
    Sys.sleep(0.02)
  }
  ack <- jsonlite::read_json(path, simplifyVector = FALSE)
  required <- c("schema", "request_identity", "grant_identity", "ordinal",
    "response_identity", "status", "authorization_token",
    "acknowledgement_identity")
  if (!setequal(names(ack), required) || !identical(ack$schema,
      "scworkbench.operation_pack.typed_slice_acknowledgement.v1") ||
      !identical(ack$request_identity, request$request_identity) ||
      !identical(ack$grant_identity, grant$grant_identity) ||
      !identical(as.integer(ack$ordinal), as.integer(ordinal)) ||
      !identical(ack$response_identity, response_identity) ||
      !identical(ack$status, "consumed") ||
      !identical(ack$authorization_token, token))
    .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
      "Broker acknowledgement differs from its response.", "execution")
  .wb_operation_pack_v3_assert_self_identity(ack,
    "acknowledgement_identity", "PYBENCH_CAPABILITY_MISMATCH", "execution")
  unlink(path, force = TRUE)
  unlink(file.path(spool, "response"), recursive = TRUE, force = TRUE)
  invisible(TRUE)
}

.wb_operation_pack_v3_broker_main <- function(stage, bundle_dir,
                                                source_bundle_dir = bundle_dir) {
  stage <- normalizePath(stage, winslash = "/", mustWork = TRUE)
  token <- Sys.getenv("PYBENCH_OPERATION_PACK_BROKER_TOKEN", unset = "")
  if (!grepl("^[0-9a-f]{64}$", token)) stop("invalid broker token")
  timeout <- as.numeric(Sys.getenv("PYBENCH_OPERATION_PACK_BROKER_TIMEOUT",
    unset = "900"))
  spool <- file.path(stage, "broker")
  dir.create(spool, recursive = TRUE, showWarnings = FALSE)
  error_path <- file.path(stage, "broker-error.json")
  tryCatch({
    request <- jsonlite::read_json(file.path(stage, "request.json"),
      simplifyVector = FALSE)
    grants <- stats::setNames(request$typed_slice_grants,
      vapply(request$typed_slice_grants, `[[`, character(1), "name"))
    axes <- lapply(grants, function(grant) list(
      features = .wb_operation_pack_v3_broker_axis_ids(stage,
        grant$features_axis),
      cells = .wb_operation_pack_v3_broker_axis_ids(stage,
        grant$cells_axis)))
    # The broker reads the same stage-visible matrix as the R adapter. The
    # original bundle is only a trusted target for committed-leaf links; it
    # must never substitute its payload for a stage-only or changed source.
    bundle <- .wb_operation_pack_v3_broker_open_bundle(bundle_dir)
    on.exit(wb_close_bundle(bundle), add = TRUE)
    if (!identical(normalizePath(bundle_dir, winslash = "/", mustWork = TRUE),
        normalizePath(source_bundle_dir, winslash = "/", mustWork = TRUE))) {
      source_bundle <- .wb_operation_pack_v3_broker_open_bundle(
        source_bundle_dir)
      on.exit(wb_close_bundle(source_bundle), add = TRUE)
      bundle$staging_source_bundle <- source_bundle
    }
    ordinals <- stats::setNames(rep(0L, length(grants)), names(grants))
    records <- list()
    deadline <- Sys.time() + timeout
    repeat {
      stop_path <- file.path(spool, "stop.json")
      control_path <- file.path(spool, "request.json")
      if (file.exists(stop_path)) {
        unlink(stop_path, force = TRUE)
        break
      }
      if (!file.exists(control_path)) {
        if (Sys.time() > deadline) .wb_operation_pack_v3_error(
          "PYBENCH_PROCESS_FAILED", "Typed-slice broker timed out.",
          "execution")
        Sys.sleep(0.02)
        next
      }
      raw <- jsonlite::read_json(control_path, simplifyVector = FALSE)
      grant_hash <- as.character(raw$grant_identity$sha256 %||% "")[1]
      matches <- names(grants)[vapply(grants, function(x) identical(
        as.character(x$grant_identity$sha256)[1], grant_hash), logical(1))]
      if (length(matches) != 1L) .wb_operation_pack_v3_error(
        "PYBENCH_CAPABILITY_MISMATCH", "Broker grant is unknown.",
        "execution")
      name <- matches[[1]]; grant <- grants[[name]]
      ordinal <- ordinals[[name]] + 1L
      prior <- Filter(function(x) identical(x$name, name), records)
      control <- .wb_operation_pack_v3_broker_read_control(control_path,
        token, request, grant, ordinal, axes[[name]], prior)
      unlink(control_path, force = TRUE)
      values <- .wb_operation_pack_v3_broker_source(bundle, stage, grant,
        control$features, control$cells)
      published <- .wb_operation_pack_v3_broker_publish_response(spool,
        grant, request, ordinal, control$features, control$cells, values)
      .wb_operation_pack_v3_broker_wait_ack(spool, token, request, grant,
        ordinal, published$response_identity, deadline)
      ordinals[[name]] <- ordinal
      records[[length(records) + 1L]] <- list(name = name,
        result = published$result, chunk_values = published$chunk_values)
    }
    .wb_operation_pack_v2_atomic_json(records,
      file.path(stage, "broker-observations.json"))
    invisible(TRUE)
  }, error = function(error) {
    .wb_operation_pack_v2_atomic_json(list(
      code = "PYBENCH_PROCESS_FAILED", phase = "execution",
      message = conditionMessage(error)), error_path)
    stop(error)
  })
}
