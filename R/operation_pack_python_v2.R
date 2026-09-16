# Audited Python process adapter for operation-pack ABI v2 / pybench-op-v3.
# PyBench owns process-local pack activation and private staged writes. Core owns
# identities, the staging generation, independent audit, durable publication,
# replay prevention, recovery, reopen, and recipient validation.

.wb_operation_pack_v2_python_schema <- function() {
  path <- system.file("protocol", "pybench-op-v3-python-runtime.schema.json",
    package = "scworkbench")
  if (!nzchar(path)) path <- file.path("inst", "protocol",
    "pybench-op-v3-python-runtime.schema.json")
  normalizePath(path, winslash = "/", mustWork = TRUE)
}

.wb_operation_pack_v2_python_error_record <- function(text) {
  lines <- rev(strsplit(as.character(text %||% ""), "\n", fixed = TRUE)[[1]])
  for (line in lines[nzchar(lines)]) {
    value <- tryCatch(jsonlite::fromJSON(line, simplifyVector = FALSE),
      error = function(e) NULL)
    if (is.list(value) && nzchar(as.character(value$code %||% "")[1])) return(value)
  }
  NULL
}

.wb_operation_pack_v2_python_run <- function(python, args, timeout_seconds,
                                               phase, error_path = NULL) {
  timeout_seconds <- suppressWarnings(as.numeric(timeout_seconds)[1])
  .wb_operation_pack_assert(is.finite(timeout_seconds) && timeout_seconds > 0,
    "OPERATION_PACK_RUNTIME_UNAVAILABLE",
    "Python ABI v2 timeout must be finite and positive.", phase,
    class = "wb_operation_pack_runtime_unavailable")
  result <- tryCatch(processx::run(python, args = as.character(args), echo = FALSE,
    error_on_status = FALSE, timeout = timeout_seconds), error = identity)
  if (inherits(result, "error")) {
    code <- if (inherits(result, c("processx_timeout", "system_command_timeout_error"))) {
      "PYBENCH_PROCESS_FAILED"
    } else "OPERATION_PACK_RUNTIME_UNAVAILABLE"
    .wb_operation_pack_v2_error(code,
      paste0("Python ABI v2 ", phase, " failed: ", conditionMessage(result)),
      phase = if (phase == "discovery") "authentication" else "execution",
      timed_out = inherits(result, c("processx_timeout", "system_command_timeout_error")))
  }
  if (!identical(as.integer(result$status), 0L)) {
    record <- NULL
    if (!is.null(error_path) && file.exists(error_path)) {
      record <- tryCatch(jsonlite::read_json(error_path, simplifyVector = FALSE),
        error = function(e) NULL)
      if (!is.list(record) || !identical(as.character(record$status %||% "")[1], "error")) {
        record <- NULL
      }
    }
    if (is.null(record)) record <- .wb_operation_pack_v2_python_error_record(
      paste(result$stdout %||% "", result$stderr %||% "", sep = "\n"))
    error_record <- if (is.list(record$error)) record$error else list()
    code <- as.character(error_record$code %||% record$error_code %||%
        record$code %||%
      if (phase == "discovery") "OPERATION_PACK_RUNTIME_UNAVAILABLE" else
        "PYBENCH_PROCESS_FAILED")[1]
    error_phase <- as.character(error_record$phase %||% record$phase %||%
      if (phase == "discovery") "authentication" else "execution")[1]
    message <- as.character(error_record$message %||% record$message %||%
      paste0("Python ABI v2 ", phase, " exited with status ", result$status, "."))[1]
    .wb_operation_pack_v2_error(code, message, error_phase,
      status = as.integer(result$status))
  }
  result
}

.wb_operation_pack_v2_python_discover <- function(manifest_path, manifest,
                                                    python, timeout_seconds,
                                                    activate = FALSE) {
  script <- paste(
    "import json,sys",
    "from pybench.operation_packs import OperationPackError,canonical_json",
    "from pybench.operation_packs_v2 import discover_operation_pack_v2,activate_operation_pack_v2",
    "try:",
    " d=discover_operation_pack_v2(sys.argv[1])",
    " r=d.public_record()",
    " if sys.argv[2]=='activate': r['activated_operations']=sorted(activate_operation_pack_v2(d).handlers)",
    " print(canonical_json(r))",
    "except OperationPackError as e:",
    " print(json.dumps({'code':e.code,'message':str(e),'phase':e.details.get('phase','authentication')}),file=sys.stderr)",
    " raise SystemExit(2)", sep = "\n")
  result <- .wb_operation_pack_v2_python_run(python,
    c("-c", script, manifest_path, if (isTRUE(activate)) "activate" else "discover"),
    timeout_seconds, "discovery")
  discovery <- tryCatch(jsonlite::fromJSON(result$stdout, simplifyVector = FALSE),
    error = function(e) NULL)
  .wb_operation_pack_assert(is.list(discovery) &&
      identical(as.character(discovery$schema %||% "")[1],
        "pybench.operation_pack.discovery.v2") &&
      identical(as.character(discovery$backend %||% "")[1], "Python"),
    "OPERATION_PACK_RUNTIME_ATTESTATION_INVALID",
    "PyBench ABI v2 discovery output is invalid.",
    class = "wb_operation_pack_v2_error")
  source <- discovery$manifest_source_identity %||% list()
  .wb_operation_pack_assert(identical(as.character(source$scheme %||% "")[1],
      "scworkbench.operation_pack.manifest_source.bytes.v1") &&
      identical(as.character(source$sha256 %||% "")[1],
        .wb_operation_pack_v2_file_sha256(manifest_path)),
    "OPERATION_PACK_MANIFEST_IDENTITY_MISMATCH",
    "PyBench did not authenticate the original installed manifest bytes.",
    class = "wb_operation_pack_v2_error")
  distribution <- discovery$distribution %||% list()
  content <- distribution$artifact_identity %||% list()
  .wb_operation_pack_assert(
    identical(.wb_operation_pack_python_normalize_name(
      as.character(distribution$declared_name %||% "")[1]),
      .wb_operation_pack_python_normalize_name(manifest$package$name)) &&
    identical(.wb_operation_pack_python_version_key(
      as.character(distribution$version %||% "")[1]),
      .wb_operation_pack_python_version_key(manifest$package$version)) &&
    identical(as.character(content$scheme %||% "")[1],
      "scworkbench.operation_pack.content.v1") &&
    grepl("^[0-9a-f]{64}$", as.character(content$sha256 %||% "")[1]),
    "OPERATION_PACK_DISTRIBUTION_IDENTITY_MISMATCH",
    "PyBench discovery distribution identity differs from the manifest.",
    class = "wb_operation_pack_v2_error")
  expected <- .wb_operation_pack_v2_identity(manifest, source$sha256, content)
  observed <- discovery$identity %||% list()
  observed$manifest_relative_path <- NULL
  .wb_operation_pack_assert(identical(.wb_operation_pack_canonical_json(expected),
      .wb_operation_pack_canonical_json(observed)),
    "OPERATION_PACK_IDENTITY_MISMATCH",
    "PyBench and scworkbench disagree on the ABI v2 manifest, definition, entry-point, distribution, or pack identity.",
    class = "wb_operation_pack_v2_error")
  entry <- discovery$entry_point %||% list()
  entry_manifest_value <- paste0(as.character(entry$group %||% "")[1], ":",
    as.character(entry$name %||% "")[1], "=",
    as.character(entry$value %||% "")[1])
  .wb_operation_pack_assert(
    identical(as.character(entry$group %||% "")[1],
      "scworkbench.operation_packs.v2") &&
    identical(entry_manifest_value, manifest$entry_point) &&
    identical(.wb_operation_pack_canonical_json(entry$identity %||% list()),
      .wb_operation_pack_canonical_json(expected$entry_point_identity)),
    "OPERATION_PACK_ENTRY_POINT_INVALID",
    "PyBench discovery entry point differs from the admitted manifest.",
    class = "wb_operation_pack_v2_error")
  if (isTRUE(activate)) {
    expected_operations <- sort(vapply(manifest$operations, `[[`, character(1),
      "qualified_name"), method = "radix")
    observed_operations <- sort(as.character(unlist(
      discovery$activated_operations %||% character(), use.names = FALSE)),
      method = "radix")
    .wb_operation_pack_assert(identical(observed_operations,
        expected_operations), "OPERATION_PACK_ENTRY_POINT_INVALID",
      "PyBench activated handler closure differs from the manifest.",
      class = "wb_operation_pack_v2_error")
  }
  discovery$activated_operations <- NULL
  discovery$identity <- expected
  discovery
}

.wb_operation_pack_v2_python_registration <- function(manifest, discovery,
                                                        manifest_path, python,
                                                        timeout_seconds) {
  expected <- vapply(manifest$operations, `[[`, character(1), "qualified_name")
  noop <- function(readers, writers, params, context) invisible(NULL)
  runners <- stats::setNames(rep(list(noop), length(expected)), expected)
  definitions <- stats::setNames(lapply(manifest$operations,
    .wb_operation_pack_v2_catalog_definition), expected)
  expectations <- structure(list(), names = character())
  if (identical(as.character(manifest$namespace)[1], "scwbpyv2reference")) {
    expectations <- list(
      path_2d = list(row_order = list(list("p"), list(1L))),
      space_path = list(row_order = list(list("space_file"), list("p"),
        list(1L), list(1L)), linked_space = list("space_file")))
  }
  structure(list(
    manifest = manifest, runners = runners, identity = discovery$identity,
    definitions = definitions, protocol_version = "2",
    manifest_path = manifest_path,
    runtime_attestation = list(
      schema = "pybench.operation_pack.discovery.v2", backend = "Python",
      distribution = discovery$distribution,
      manifest_source_identity = discovery$manifest_source_identity,
      entry_point = discovery$entry_point),
    runtime_config = list(backend = "Python", python = python,
      manifest_path = manifest_path, timeout_seconds = timeout_seconds,
      conformance_expectations = expectations)
  ), class = c("wb_operation_pack_registration_v2",
    "wb_operation_pack_registration", "list"))
}

.wb_operation_pack_v2_python_probe_distribution <- function(registration, name) {
  config <- registration$runtime_config
  script <- paste(
    "import importlib.metadata as m,importlib.util,json,sys",
    "from pybench.operation_packs import canonical_json",
    "from pybench.operation_packs_v2 import distribution_identity_v2",
    "d=m.distribution(sys.argv[1])",
    "v={'name':d.metadata['Name'],'version':d.version,'artifact_identity':distribution_identity_v2(d),'import_available':importlib.util.find_spec(sys.argv[1].replace('-','_')) is not None}",
    "print(canonical_json(v))", sep = "\n")
  result <- .wb_operation_pack_v2_python_run(config$python,
    c("-c", script, name), config$timeout_seconds, "preflight")
  value <- tryCatch(jsonlite::fromJSON(result$stdout, simplifyVector = FALSE),
    error = function(e) NULL)
  .wb_operation_pack_assert(is.list(value) && isTRUE(value$import_available) &&
      identical(as.character(value$artifact_identity$scheme %||% "")[1],
        "scworkbench.operation_pack.content.v1"),
    "OPERATION_PACK_DEPENDENCY_MISSING",
    paste0("Python distribution or import probe is unavailable: ", name, "."),
    class = "wb_operation_pack_v2_error")
  value$import_available <- NULL
  value
}

.wb_operation_pack_v2_transport_matrix <- function(value) {
  matrix_value <- value$values
  if (is.null(dim(matrix_value))) return(matrix_value)
  lapply(seq_len(nrow(matrix_value)), function(i) unname(as.list(matrix_value[i, ])))
}

.wb_operation_pack_v2_transport_value <- function(value, kind = value$kind) {
  kind <- as.character(kind)[1]
  meta <- value$meta %||% structure(list(), names = character())
  dimensions <- unname(as.list(.wb_operation_pack_v2_dimensions(value, kind)))
  profile <- .wb_operation_pack_v2_input_profile(kind, value)
  out <- switch(kind,
    matrix = list(kind = kind, dimensions = dimensions,
      cell_id = unname(as.list(as.character(value$cell_id))),
      feature_id = unname(as.list(as.character(value$feature_id))),
      values = .wb_operation_pack_v2_transport_matrix(value),
      storage_profile = profile, meta = meta),
    space = list(kind = kind, dimensions = dimensions,
      cell_id = unname(as.list(as.character(value$cell_id))),
      values = .wb_operation_pack_v2_transport_matrix(value),
      storage_profile = profile, meta = meta),
    space_2d = list(kind = kind, dimensions = dimensions,
      cell_id = unname(as.list(as.character(value$cell_id))),
      values = .wb_operation_pack_v2_transport_matrix(value),
      storage_profile = profile, meta = meta),
    model_ref = list(kind = kind, dimensions = dimensions,
      engine = as.character(value$engine %||% "")[1],
      model_space_id = as.character(value$model_space_id %||% "")[1],
      in_space_id = as.character(value$in_space_id %||% "")[1],
      payload_tree = value$payload_tree %||% structure(list(), names = character()),
      storage_profile = profile, meta = meta),
    cell_vector = list(kind = kind, dimensions = dimensions,
      cell_id = unname(as.list(as.character(value$cell_id))),
      value = unname(as.list(value$value)),
      storage_profile = profile, meta = meta),
    cell_vector_family = list(kind = kind, dimensions = dimensions,
      cell_id = unname(as.list(as.character(value$cell_id))),
      key = unname(as.list(as.character(value$key))),
      value = unname(as.list(value$value)), storage_profile = profile, meta = meta),
    relation_family = list(kind = kind, dimensions = dimensions,
      cell_id = unname(as.list(as.character(value$cell_id))),
      key = unname(as.list(as.character(value$key))),
      value = unname(as.list(value$value)), storage_profile = profile, meta = meta),
    feature_table = list(kind = kind, dimensions = dimensions,
      feature_id = unname(as.list(as.character(value$table$feature_id))),
      rows = lapply(seq_len(nrow(value$table)), function(i) as.list(value$table[i, , drop = FALSE])),
      storage_profile = profile, meta = meta),
    obs_table = list(kind = kind, dimensions = dimensions,
      rows = lapply(seq_len(nrow(value$table)), function(i) as.list(value$table[i, , drop = FALSE])),
      storage_profile = profile, meta = meta),
    path_2d_family = list(kind = kind, dimensions = dimensions,
      key = unname(as.list(as.character(value$key))),
      point = unname(as.list(as.integer(value$point))),
      x = unname(as.list(as.numeric(value$x))), y = unname(as.list(as.numeric(value$y))),
      storage_profile = profile, meta = meta),
    space_path_family = list(kind = kind, dimensions = dimensions,
      space_id = unname(as.list(as.character(value$space_id))),
      path_id = unname(as.list(as.character(value$path_id))),
      point = unname(as.list(as.integer(value$point))),
      dim = unname(as.list(as.integer(value$dim))),
      value = unname(as.list(as.numeric(value$value))),
      storage_profile = profile, meta = meta),
    .wb_operation_pack_v2_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
      paste0("No Python transport projection for primitive kind '", kind, "'."),
      "resolution"))
  out
}

.wb_operation_pack_v2_python_stage_inputs <- function(stage, inputs) {
  for (name in names(inputs)) {
    path <- file.path(stage, "inputs", name, "payload.json")
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    .wb_operation_pack_v2_atomic_json(inputs[[name]], path)
  }
  invisible(TRUE)
}

.wb_operation_pack_v2_python_chunk_observation_audit <- function(value, request,
                                                                  registration) {
  op_name <- as.character(request$operation_authentication$name %||% "")[1]
  operation <- Filter(function(x) identical(as.character(x$qualified_name)[1],
    op_name), registration$manifest$operations)
  .wb_operation_pack_assert(length(operation) == 1L,
    "OPERATION_PACK_RUNTIME_ATTESTATION_INVALID",
    "Python chunk observation operation is not uniquely authenticated.",
    phase = "receipt", class = "wb_operation_pack_v2_error")
  chunk <- operation[[1]]$chunking %||% NULL
  observation <- value$chunk_observation %||% NULL
  .wb_operation_pack_assert(xor(is.null(chunk), !is.null(observation)),
    "OPERATION_PACK_RUNTIME_ATTESTATION_INVALID",
    if (is.null(chunk)) {
      "Python runtime sidecar includes a chunk observation for an undeclared operation."
    } else {
      "Python runtime sidecar omits the required chunk observation."
    }, phase = "receipt", class = "wb_operation_pack_v2_error")
  if (is.null(chunk)) return(NULL)

  .wb_operation_pack_v2_assert_self_identity(observation,
    "observation_identity", "OPERATION_PACK_RUNTIME_ATTESTATION_INVALID",
    "receipt")
  input_name <- as.character(chunk$input)[1]
  input <- Filter(function(x) identical(as.character(x$name)[1], input_name),
    request$inputs)
  .wb_operation_pack_assert(length(input) == 1L,
    "OPERATION_PACK_RUNTIME_ATTESTATION_INVALID",
    "Python chunk observation input is not uniquely bound to the request.",
    phase = "receipt", class = "wb_operation_pack_v2_error")
  expected_identities <- list(
    request_identity = request$request_identity,
    capability_identity = request$execution_capability$capability_identity,
    operation_definition_identity =
      request$operation_authentication$operation_definition_identity,
    input_descriptor_identity = input[[1]]$descriptor$descriptor_identity)
  for (name in names(expected_identities)) {
    .wb_operation_pack_assert(identical(.wb_operation_pack_canonical_json(
      observation[[name]]), .wb_operation_pack_canonical_json(
        expected_identities[[name]])),
      "OPERATION_PACK_RUNTIME_ATTESTATION_INVALID",
      paste0("Python chunk observation differs at ", name, "."),
      phase = "receipt", class = "wb_operation_pack_v2_error")
  }

  sequence_parameter <- as.character(chunk$sequence_parameter)[1]
  size_parameter <- as.character(chunk$size_parameter)[1]
  sequence <- as.character(unlist(request$params[[sequence_parameter]],
    use.names = FALSE))
  size <- as.integer(request$params[[size_parameter]])[1]
  expected_batches <- if (!length(sequence)) list() else unname(split(sequence,
    ceiling(seq_along(sequence) / size)))
  observed_batches <- lapply(observation$observed_batches,
    function(x) as.character(unlist(x, use.names = FALSE)))
  observed_sizes <- as.integer(unlist(observation$observed_batch_sizes,
    use.names = FALSE))
  valid <- identical(as.character(observation$input_name)[1], input_name) &&
    identical(as.character(observation$axis)[1], as.character(chunk$axis)[1]) &&
    identical(as.character(observation$sequence_parameter)[1],
      sequence_parameter) &&
    identical(as.character(observation$size_parameter)[1], size_parameter) &&
    identical(as.integer(observation$requested_chunk_size)[1], size) &&
    identical(as.integer(observation$observed_call_count)[1],
      length(expected_batches)) &&
    identical(observed_sizes, as.integer(lengths(expected_batches))) &&
    identical(unname(observed_batches), expected_batches)
  .wb_operation_pack_assert(valid,
    "OPERATION_PACK_RUNTIME_ATTESTATION_INVALID",
    "Python chunk observation differs from the authenticated request schedule.",
    expected_batches = expected_batches, observed_batches = observed_batches,
    phase = "receipt", class = "wb_operation_pack_v2_error")
  list(axis = as.character(chunk$axis)[1], requested_chunk_size = size,
    observed_call_count = length(observed_batches),
    observed_batch_sizes = observed_sizes, observed_batches = observed_batches,
    observation_identity = observation$observation_identity)
}

.wb_operation_pack_v2_python_sidecar_audit <- function(value, registration,
                                                         request) {
  schema <- .wb_operation_pack_v2_read_schema(.wb_operation_pack_v2_python_schema())
  result <- .wb_json_schema_validate_2020(value, schema)
  if (!isTRUE(result$ok)) .wb_operation_pack_v2_error(
    "OPERATION_PACK_RUNTIME_ATTESTATION_INVALID",
    paste0("Python runtime sidecar failed Draft 2020-12 validation at ",
      result$path, ": ", result$message), "receipt")
  .wb_operation_pack_v2_assert_self_identity(value, "runtime_identity",
    "OPERATION_PACK_RUNTIME_ATTESTATION_INVALID", "receipt")
  expected_distribution <- registration$identity$distribution_identity
  .wb_operation_pack_assert(identical(.wb_operation_pack_canonical_json(
      value$distribution_identity), .wb_operation_pack_canonical_json(expected_distribution)),
    "OPERATION_PACK_RUNTIME_IDENTITY_MISMATCH",
    "Python runtime sidecar distribution identity differs from activation.",
    class = "wb_operation_pack_v2_error")
  executable <- registration$runtime_config$python
  .wb_operation_pack_assert(identical(as.character(value$interpreter$executable_sha256)[1],
      .wb_operation_pack_v2_file_sha256(executable)),
    "OPERATION_PACK_RUNTIME_IDENTITY_MISMATCH",
    "Python interpreter identity changed after activation.",
    class = "wb_operation_pack_v2_error")
  .wb_operation_pack_v2_python_chunk_observation_audit(value, request,
    registration)
}

.wb_operation_pack_v2_python_payload_path <- function(stage, item) {
  root <- if (identical(as.character(item$descriptor$category)[1],
      "core_registry_request")) "registry_requests" else "outputs"
  file.path(stage, root, item$name, "payload.json")
}

.wb_operation_pack_v2_python_audit <- function(stage, request, receipt) {
  observed <- c(receipt$outputs %||% list(), receipt$registry_requests %||% list())
  entries <- vector("list", length(observed))
  for (i in seq_along(observed)) {
    item <- observed[[i]]
    path <- .wb_operation_pack_v2_python_payload_path(stage, item)
    .wb_operation_pack_assert(file.exists(path) && !nzchar(Sys.readlink(path)),
      "PYBENCH_OUTPUT_INVALID", paste0("Python output is absent or linked: ", item$name),
      class = "wb_operation_pack_v2_error")
    raw <- readChar(path, nchars = file.info(path)$size, useBytes = TRUE)
    .wb_operation_pack_v2_assert_strict_json(raw)
    value <- .wb_operation_pack_parse_canonical_json(raw)
    descriptor <- item$descriptor
    registry_request <- identical(as.character(descriptor$category)[1],
      "core_registry_request")
    content_ok <- if (registry_request) {
      if (identical(as.character(descriptor$kind)[1],
          "cell_set_family_admission")) {
        identical(.wb_operation_pack_sha256(value),
          as.character(descriptor$family_identity$sha256 %||% "")[1])
      } else {
        cells <- as.character(unlist(value$cells %||% character(),
          use.names = FALSE))
        identical(.wb_operation_pack_sha256(value$cells %||% list()),
          as.character(descriptor$membership_identity$sha256 %||% "")[1]) &&
          !anyDuplicated(cells)
      }
    } else identical(.wb_operation_pack_sha256(value),
      as.character(descriptor$content_identity$sha256 %||% "")[1])
    .wb_operation_pack_assert(identical(as.character(value$kind %||% "")[1],
        as.character(descriptor$kind)[1]) && content_ok,
      "PYBENCH_OUTPUT_INVALID",
      paste0("Python output content identity differs: ", item$name),
      class = "wb_operation_pack_v2_error")
    relative <- substring(normalizePath(path, winslash = "/", mustWork = TRUE),
      nchar(normalizePath(stage, winslash = "/", mustWork = TRUE)) + 2L)
    payload_value <- list(path = relative, size = as.numeric(file.info(path)$size),
      sha256 = .wb_operation_pack_v2_file_sha256(path))
    if (!registry_request) .wb_operation_pack_assert(
      identical(.wb_operation_pack_sha256(payload_value),
        as.character(descriptor$payload_manifest_identity$sha256 %||% "")[1]),
      "PYBENCH_OUTPUT_INVALID", paste0("Python output payload manifest differs: ",
        item$name), class = "wb_operation_pack_v2_error")
    entries[[i]] <- list(path = relative,
      sha256 = .wb_operation_pack_v2_file_sha256(path))
  }
  mutation <- receipt$mutation_manifest
  .wb_operation_pack_assert(length(entries) == as.integer(mutation$entry_count) &&
      identical(as.integer(mutation$unexpected_entries), 0L) &&
      identical(.wb_operation_pack_sha256(entries),
        as.character(mutation$entries_identity$sha256)[1]),
    "PYBENCH_OUT_OF_SCOPE_MUTATION",
    "Core mutation audit differs from the Python mutation manifest.",
    class = "wb_operation_pack_v2_error")
  allowed <- sort(c("request.json", "state.json", "receipt.json",
    "python-runtime.json", vapply(entries, `[[`, character(1), "path")),
    method = "radix")
  actual <- sort(list.files(stage, recursive = TRUE, all.files = TRUE,
    include.dirs = FALSE, no.. = TRUE), method = "radix")
  .wb_operation_pack_assert(identical(actual, allowed),
    "PYBENCH_OUT_OF_SCOPE_MUTATION",
    "Private Python stage contains undeclared files after input retirement.",
    unexpected = setdiff(actual, allowed), class = "wb_operation_pack_v2_error")
  invisible(TRUE)
}

.wb_operation_pack_v2_python_dispatch <- function(request, registration, stage) {
  config <- registration$runtime_config
  pending <- paste0(.Platform$file.sep, ".pending", .Platform$file.sep)
  .wb_operation_pack_assert(grepl(pending, paste0(normalizePath(stage,
      winslash = "/", mustWork = TRUE), "/"), fixed = TRUE),
    "PYBENCH_STALE_STAGING_IDENTITY",
    "Core refuses Python execution outside the current private generation.",
    class = "wb_operation_pack_v2_error")
  receipt_path <- file.path(stage, "receipt.json")
  runtime_path <- file.path(stage, "python-runtime.json")
  result <- .wb_operation_pack_v2_python_run(config$python, c(
    "-m", "pybench.operation_pack_v3_cli",
    "--manifest", config$manifest_path,
    "--request", file.path(stage, "request.json"),
    "--stage-root", stage,
    "--receipt", receipt_path,
    "--python-runtime", runtime_path), config$timeout_seconds, "execution",
    error_path = receipt_path)
  .wb_operation_pack_v2_fault("python_process_completed", stage = stage)
  receipt <- tryCatch(jsonlite::read_json(receipt_path, simplifyVector = FALSE),
    error = function(e) NULL)
  runtime <- tryCatch(jsonlite::read_json(runtime_path, simplifyVector = FALSE),
    error = function(e) NULL)
  .wb_operation_pack_assert(is.list(receipt) && is.list(runtime),
    "PYBENCH_RECEIPT_MISMATCH",
    "Python process did not publish both a shared receipt and runtime sidecar.",
    class = "wb_operation_pack_v2_error")
  .wb_operation_pack_v2_fault("python_receipt_loaded", stage = stage,
    receipt = receipt, runtime = runtime)
  reader_observation <- .wb_operation_pack_v2_python_sidecar_audit(runtime,
    registration, request)
  list(receipt = receipt, sidecar = runtime, process = result,
    reader_observation = reader_observation)
}

.wb_operation_pack_v2_python_to_primitive <- function(value, descriptor) {
  kind <- as.character(descriptor$kind)[1]
  meta <- value$meta %||% structure(list(), names = character())
  rows <- function(x) {
    if (!length(x)) return(data.frame())
    names_all <- unique(unlist(lapply(x, names), use.names = FALSE))
    as.data.frame(stats::setNames(lapply(names_all, function(name)
      unlist(lapply(x, `[[`, name), use.names = FALSE)), names_all),
      stringsAsFactors = FALSE)
  }
  matrix_value <- function(x) {
    if (!length(x)) return(matrix(numeric(), 0L, 0L))
    do.call(rbind, lapply(x, function(row) as.numeric(unlist(row, use.names = FALSE))))
  }
  out <- switch(kind,
    matrix = structure(list(kind = kind, values = matrix_value(value$values),
      dimensions = as.integer(unlist(value$dimensions)), cell_id = as.character(value$cell_id),
      feature_id = as.character(value$feature_id),
      storage_profile = descriptor$storage_profile, meta = meta), class = "wb_primitive"),
    space = structure(list(kind = kind, values = matrix_value(value$values),
      dimensions = as.integer(unlist(value$dimensions)), cell_id = as.character(value$cell_id),
      storage_profile = descriptor$storage_profile, meta = meta), class = "wb_primitive"),
    space_2d = structure(list(kind = kind, values = matrix_value(value$values),
      dimensions = as.integer(unlist(value$dimensions)), cell_id = as.character(value$cell_id),
      storage_profile = descriptor$storage_profile, meta = meta), class = "wb_primitive"),
    cell_vector = wb_prim_cell_vector(stats::setNames(unlist(value$value,
      use.names = FALSE), as.character(value$cell_id)),
      value_type = descriptor$semantic_validation$value_kind %||%
        if (all(vapply(value$value, is.numeric, logical(1)))) "continuous" else "categorical",
      meta = meta),
    cell_vector_family = wb_prim_cell_vector_family(as.character(value$key),
      as.character(value$cell_id), as.numeric(unlist(value$value)), meta = meta),
    relation_family = wb_prim_relation_family(as.character(value$key),
      as.character(value$cell_id), value = as.numeric(unlist(value$value)), meta = meta),
    feature_table = wb_prim_feature_table(rows(value$rows),
      table_type = "operation_pack_v2", meta = meta),
    obs_table = wb_prim_obs_table(rows(value$rows),
      table_type = "operation_pack_v2", meta = meta),
    path_2d_family = wb_prim_path_2d_family(as.character(value$key),
      as.integer(unlist(value$point)), as.numeric(unlist(value$x)),
      as.numeric(unlist(value$y)), meta = meta),
    space_path_family = wb_prim_space_path_family(as.character(value$space_id),
      as.character(value$path_id), as.integer(unlist(value$point)),
      as.integer(unlist(value$dim)), as.numeric(unlist(value$value)), meta = meta),
    model_ref = structure(c(value, list(storage_profile = descriptor$storage_profile,
      meta = meta)), class = "wb_primitive"),
    cell_set_admission = list(kind = kind, name = as.character(value$name)[1],
      cells = as.character(value$cells)),
    cell_set_family_admission = value,
    .wb_operation_pack_v2_error("PYBENCH_OUTPUT_INVALID",
      paste0("No pack-free reconstruction for Python kind '", kind, "'."), "reopen"))
  out
}
