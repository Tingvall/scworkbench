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

.wb_operation_pack_v3_broker_projection_budget <- function(bundle, policy = NULL) {
  budget <- new.env(parent = emptyenv())
  limit <- as.numeric(getOption("scworkbench.max_dense_materialize_mb", 256)) * 1024^2
  if (is.null(policy) && !is.null(bundle$con)) policy <- bundle$con@ref$wb_graph_policy
  if (!is.null(policy)) limit <- min(limit, as.numeric(policy$memory_bytes) -
    as.numeric(policy$sqlite_cache_kib) * 1024 -
    8 * as.numeric(policy$partition_bytes) - 65536 -
      .wb_graph_fd_metadata_reservation(policy))
  # Keep half of the remaining existing allowance for delivery and transient
  # allocations. This is an aggregate cache admission, not a new user limit.
  budget$limit <- if (length(limit) == 1L && is.finite(limit) && limit > 0)
    floor(limit / 2) else 0
  budget$memory <- if (length(limit) == 1L && is.finite(limit) && limit > 0) limit else 0
  budget$policy <- policy
  budget$disk <- 0
  budget$used <- 0
  budget
}

.wb_operation_pack_v3_broker_free_bytes <- function(path) {
  output <- tryCatch(suppressWarnings(system2("df", c("-Pk", shQuote(path)),
    stdout = TRUE, stderr = TRUE)), error = function(error) character())
  status <- attr(output, "status")
  if (!length(output) || (!is.null(status) && status != 0L))
    .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
      "Private projection spill capacity is unavailable (requires POSIX df -Pk).", "execution")
  fields <- regmatches(tail(output, 1L), regexec(paste0(
    "[[:space:]]([0-9]+)[[:space:]]+([0-9]+)[[:space:]]+",
    "([0-9]+)[[:space:]]+[0-9]+%[[:space:]]"), tail(output, 1L), perl = TRUE))[[1L]]
  available <- if (length(fields) == 4L) suppressWarnings(as.double(fields[[4L]]) * 1024) else NA_real_
  if (length(available) != 1L || !is.finite(available) || available < 0)
    .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
      "Private projection spill capacity could not be measured.", "execution")
  available
}

.wb_operation_pack_v3_broker_spill_guard <- function(root) {
  observe <- function() {
    paths <- sort(as.character(fs::dir_ls(root, recurse = TRUE, all = TRUE,
      type = "any", follow = FALSE)), method = "radix")
    info <- file.info(paths)
    if (!dir.exists(root) || !length(paths) || anyNA(info$size) ||
        any(nzchar(Sys.readlink(paths)))) stop("Private projection spill changed.", call. = FALSE)
    list(paths = paths, resolved = normalizePath(paths, winslash = "/", mustWork = TRUE),
      info = info[, c("size", "isdir", "mode", "mtime", "ctime"), drop = FALSE])
  }
  initial <- observe()
  function() {
    current <- tryCatch(observe(), error = function(error) NULL)
    if (!identical(initial, current)) .wb_operation_pack_v3_error(
      "PYBENCH_INPUT_IDENTITY_MISMATCH", "Private projection spill changed after creation.", "execution")
    invisible(TRUE)
  }
}

.wb_operation_pack_v3_broker_projection_guard <- function(stage, grant) {
  relative <- c(sub("^private_projection:", "typed_slice_sources/",
    paste0(grant$source_reference$input_reference, "/matrix.mtx")),
    grant$features_axis$relative_path, grant$cells_axis$relative_path)
  observe <- function() {
    paths <- vapply(relative, function(path) .wb_bundle_path_require(stage,
      path, expected_type = "file", purpose = "private broker projection"),
      character(1))
    original <- file.path(stage, relative)
    info <- file.info(original)
    if (anyNA(info$size) || any(info$isdir) || any(nzchar(Sys.readlink(original))))
      stop("Private broker projection files changed.", call. = FALSE)
    list(paths = paths, info = info[, c("size", "isdir", "mode", "mtime", "ctime"),
      drop = FALSE])
  }
  initial <- observe()
  function() {
    current <- tryCatch(observe(), error = function(error) NULL)
    if (!identical(initial, current)) .wb_operation_pack_v3_error(
      "PYBENCH_INPUT_IDENTITY_MISMATCH",
      "Private broker projection files or axes changed after authentication.",
      "execution")
    invisible(TRUE)
  }
}

.wb_operation_pack_v3_broker_reader <- function(bundle, stage, grant, axes,
                                               budget = NULL) {
  source <- grant$source_reference
  if (is.null(budget)) budget <- .wb_operation_pack_v3_broker_projection_budget(bundle)
  if (!identical(source$source_kind, "bundle_matrix"))
    return(.wb_operation_pack_v3_private_source_validate(stage, grant,
      bounded = TRUE, return_reader = TRUE, budget = budget))
  plan <- NULL; closed <- FALSE
  close <- function() {
    if (!closed) {
      if (!is.null(plan)) plan$close()
      plan <<- NULL; closed <<- TRUE
    }
    invisible(TRUE)
  }
  ready <- FALSE
  on.exit(if (!ready) close(), add = TRUE)
  .wb_operation_pack_v3_typed_slice_grant_assert_current(bundle, grant, "execution")
  guard <- .wb_operation_pack_matrix_light_guard(bundle, source$matrix_id)
  mode <- if (isTRUE(budget$mixed_graph)) "bundle_slice" else "bundle_stream"
  read <- function(features, cells) {
    tryCatch({
      if (closed) .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
        "Broker source reader has already closed.", "execution")
      if (anyNA(match(features, axes$features)) || anyNA(match(cells, axes$cells)))
        .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
          "Broker read is outside its admitted projection.", "execution")
      guard()
      values <- if (identical(mode, "bundle_stream")) {
        if (is.null(plan)) plan <<- .wb_matrix_stream_reader(bundle,
          source$matrix_id, grant$chunk_axis %||% "cells",
          features = axes$features, cells = axes$cells)
        as.matrix(plan$read(features, cells))
      } else as.matrix(wb_slice(bundle, source$matrix_id, features = features, cells = cells))
      guard()
      values
    }, error = function(error) { close(); stop(error) })
  }
  ready <- TRUE
  list(read = read, close = close, mode = mode, spill_root = NULL)
}

.wb_operation_pack_v3_broker_source <- function(bundle, stage, grant,
                                                  features, cells) {
  axes <- if (!is.null(grant$features_axis) && !is.null(grant$cells_axis)) list(
    features = .wb_operation_pack_v3_broker_axis_ids(stage, grant$features_axis),
    cells = .wb_operation_pack_v3_broker_axis_ids(stage, grant$cells_axis)) else
      list(features = features, cells = cells)
  # Explicit one-off reads start a new authenticated lifetime. They cannot
  # inherit a previous broker's source observation or retained projection.
  reader <- .wb_operation_pack_v3_broker_reader(bundle, stage, grant, axes)
  on.exit(reader$close(), add = TRUE)
  reader$read(features, cells)
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

.wb_operation_pack_v3_broker_graph_reservation <- function(bundle, budget, policy) {
  reserved <- policy
  for (field in c("memory_bytes", "token_bytes")) {
    available <- as.numeric(policy[[field]]) -
      if (field == "memory_bytes") budget$used else budget$disk
    if (!is.finite(available) || available <= 0)
      .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
        "Private matrix reservations exhaust the graph working allowance.", "execution")
    reserved[[field]] <- format(floor(available), scientific = FALSE, trim = TRUE)
  }
  reserved <- .wb_graph_budgets(reserved)
  .wb_graph_fd_metadata_reservation(reserved)
  .wb_operation_pack_v4_scoped_graph_budgets(bundle, reserved)
}

.wb_operation_pack_v3_broker_response_admit <- function(budget, features, cells) {
  # Response values, sparse/dense conversions, identity tokens and the bounded
  # Matrix Market writer coexist. Graph response carriers have been released.
  elements <- as.double(length(features)) * length(cells)
  # Four dense-value widths cover input/returned copies and conversion. Writer
  # and canonical slice work are separately block-capped, not 128 bytes for
  # every element of a wide response (which would reject valid bounded reads).
  memory <- 32 * elements + min(33554432, 64 * elements) +
    256 * (length(features) + length(cells)) + 65536
  # The ordinary max_dense option guards fallback coercion/cache admission;
  # it is not a newly imposed process-wide RAM cap. Nonmixed responses retain
  # their authenticated max_elements/response-byte limits. Mixed graph requests
  # additionally own the existing declared aggregate working-memory budget.
  if (!is.finite(memory) || (!is.null(budget$policy) &&
      memory > budget$memory - budget$used))
    .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
      "Typed matrix response exceeds its bounded working-memory admission.", "execution")
  if (!is.null(budget$policy)) {
    bytes <- 128 * elements + 8 * sum(nchar(c(features, cells), type = "bytes")) + 16384
    usage <- .wb_graph_transient_usage(budgets = budget$policy)
    if (!is.finite(bytes) || usage$owned_spill_bytes + budget$disk + bytes +
        .wb_graph_session_copy_reservation(budget$policy) > as.numeric(budget$policy$token_bytes))
      .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
        "Typed matrix response exceeds the shared graph scratch admission.", "execution")
  }
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
    grants <- stats::setNames(request$typed_slice_grants %||% list(),
      vapply(request$typed_slice_grants %||% list(), `[[`, character(1), "name"))
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
    readers <- list()
    on.exit(for (reader in readers) reader$close(), add = TRUE)
    graph_enabled <- length(request$graph_read_grants %||% list()) > 0L ||
      length(request$graph_write_grants %||% list()) > 0L
    graph_policy <- if (graph_enabled)
      .wb_operation_pack_v4_lowest_graph_budgets(lapply(request$graph_write_grants %||%
        list(), `[[`, "resource_budgets")) else NULL
    if (graph_enabled) {
      restore_graph <- .wb_operation_pack_v4_scoped_graph_budgets(bundle, graph_policy)
      on.exit(restore_graph(), add = TRUE, after = FALSE)
      graph_policy <- .wb_graph_effective_budgets(bundle$con, graph_policy)
    }
    projection_budget <- .wb_operation_pack_v3_broker_projection_budget(bundle, graph_policy)
    projection_budget$mixed_graph <- graph_enabled && length(grants) > 0L
    for (name in names(grants)) readers[[name]] <-
      .wb_operation_pack_v3_broker_reader(bundle, stage, grants[[name]],
        axes[[name]], projection_budget)
    if (graph_enabled) {
      restore_reservation <- .wb_operation_pack_v3_broker_graph_reservation(
        bundle, projection_budget, graph_policy)
      on.exit(restore_reservation(), add = TRUE, after = FALSE)
    }
    graph_cursors <- stats::setNames(lapply(request$graph_read_grants %||% list(),
      function(grant) .wb_operation_pack_v4_graph_cursor(bundle, grant)),
      vapply(request$graph_read_grants %||% list(), `[[`, character(1), "input_name"))
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
      if (identical(request$pack_abi_version, "4"))
        .wb_graph_require(file.info(control_path)$size <= 1048576,
          "GRAPH_RESOURCE_EXCEEDED", "Broker control exceeds maximum decoded admission.")
      raw <- jsonlite::read_json(control_path, simplifyVector = FALSE)
      if (identical(raw$schema, "scworkbench.graph.broker_read_request.v1")) {
        .wb_operation_pack_v4_graph_service(spool, request, bundle, graph_cursors, token, deadline)
        next
      }
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
      .wb_operation_pack_v3_broker_response_admit(projection_budget,
        control$features, control$cells)
      values <- readers[[name]]$read(control$features, control$cells)
      published <- .wb_operation_pack_v3_broker_publish_response(spool,
        grant, request, ordinal, control$features, control$cells, values)
      .wb_operation_pack_v3_broker_wait_ack(spool, token, request, grant,
        ordinal, published$response_identity, deadline)
      ordinals[[name]] <- ordinal
      records[[length(records) + 1L]] <- list(name = name,
        result = published$result, chunk_values = published$chunk_values)
      # The broker is serial. Do not retain the previous matrix payload and
      # response/control carriers while the next graph branch is serviced.
      rm(values, published, control, raw, prior)
    }
    .wb_operation_pack_v2_atomic_json(records,
      file.path(stage, "broker-observations.json"))
    if (length(graph_cursors)) .wb_operation_pack_v2_atomic_json(
      unname(lapply(graph_cursors, function(cursor) cursor$usage())),
      file.path(stage, "graph-broker-observations.json"))
    invisible(TRUE)
  }, error = function(error) {
    .wb_operation_pack_v2_atomic_json(list(
      code = "PYBENCH_PROCESS_FAILED", phase = "execution",
      message = conditionMessage(error)), error_path)
    stop(error)
  })
}
