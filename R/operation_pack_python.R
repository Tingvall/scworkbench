# Audited Python-backend adapter for operation-pack v1. PyBench owns Python
# distribution discovery, entry-point activation, capability execution, and
# its receipt. scworkbench owns catalog admission, private staging, an
# independent mutation/runtime audit, publication, provenance, and replay.

.wb_operation_pack_python_binary <- function(python = NULL) {
  value <- as.character(python %||% .wb_pybench_default_python())
  value <- value[!is.na(value) & nzchar(value)]
  .wb_operation_pack_assert(length(value) == 1L, "OPERATION_PACK_RUNTIME_UNAVAILABLE",
    paste0("A single PyBench Python interpreter is required. Set ",
           "SCWORKBENCH_PYBENCH_PYTHON or pass python= explicitly."),
    backend = "Python", class = "wb_operation_pack_runtime_unavailable")
  # Preserve a virtual-environment launcher path. normalizePath() on the file
  # itself would resolve its symlink to the base interpreter and silently drop
  # the selected environment's installed distributions.
  path <- file.path(
    normalizePath(dirname(value[[1]]), winslash = "/", mustWork = FALSE),
    basename(value[[1]])
  )
  .wb_operation_pack_assert(file.exists(path) && file.access(path, 1L) == 0L,
    "OPERATION_PACK_RUNTIME_UNAVAILABLE",
    paste0("Configured PyBench Python interpreter is unavailable or not executable: ", value[[1]]),
    backend = "Python", class = "wb_operation_pack_runtime_unavailable")
  path
}

.wb_operation_pack_python_json_error <- function(lines) {
  lines <- rev(as.character(lines %||% character()))
  for (line in lines[nzchar(lines)]) {
    value <- tryCatch(jsonlite::fromJSON(line, simplifyVector = FALSE), error = function(e) NULL)
    if (is.list(value) && nzchar(as.character(value$code %||% "")[1])) return(value)
  }
  NULL
}

.wb_operation_pack_python_process <- function(python, args, timeout_seconds, phase) {
  timeout_seconds <- suppressWarnings(as.numeric(timeout_seconds)[1])
  .wb_operation_pack_assert(is.finite(timeout_seconds) && timeout_seconds > 0,
    "OPERATION_PACK_RUNTIME_UNAVAILABLE", "Python operation-pack timeout must be finite and positive.",
    backend = "Python", class = "wb_operation_pack_runtime_unavailable")
  result <- tryCatch(processx::run(
    python, args = as.character(args), echo = FALSE, error_on_status = FALSE,
    timeout = timeout_seconds
  ), error = identity)
  if (inherits(result, "error")) {
    .wb_operation_pack_abort("OPERATION_PACK_RUNTIME_UNAVAILABLE",
      paste0("Python operation-pack ", phase, " failed: ", conditionMessage(result)),
      backend = "Python", phase = phase, timed_out = inherits(result, c(
        "processx_timeout", "system_command_timeout_error")),
      class = "wb_operation_pack_runtime_unavailable")
  }
  if (isTRUE(result$timeout)) {
    .wb_operation_pack_abort("OPERATION_PACK_RUNTIME_UNAVAILABLE",
      paste0("Python operation-pack ", phase, " exceeded its timeout."),
      backend = "Python", phase = phase, timed_out = TRUE,
      class = "wb_operation_pack_runtime_unavailable")
  }
  if (!identical(as.integer(result$status), 0L)) {
    parsed <- .wb_operation_pack_python_json_error(strsplit(result$stderr %||% "", "\n", fixed = TRUE)[[1]])
    code <- as.character(parsed$code %||% "OPERATION_PACK_RUNTIME_UNAVAILABLE")[1]
    message <- as.character(parsed$message %||% paste0("PyBench ", phase,
      " failed with status ", as.integer(result$status), "."))[1]
    unavailable <- code %in% c("OPERATION_PACK_DISTRIBUTION_UNAVAILABLE",
      "OPERATION_PACK_ENTRY_POINT_UNAVAILABLE", "OPERATION_PACK_RUNTIME_UNAVAILABLE")
    .wb_operation_pack_abort(code, message, backend = "Python", phase = phase,
      status = as.integer(result$status),
      class = if (unavailable) "wb_operation_pack_runtime_unavailable" else "wb_operation_pack_validation_error")
  }
  result
}

.wb_operation_pack_python_runtime_sanitize <- function(runtime) {
  out <- runtime
  if (is.list(out$interpreter)) out$interpreter$executable <- NULL
  out
}

.wb_operation_pack_python_runtime_audit <- function(runtime, manifest, identity,
                                                     discovery = NULL) {
  .wb_operation_pack_named_object(runtime, "Python runtime attestation", allow_empty = FALSE)
  .wb_operation_pack_assert(
    identical(as.character(runtime$schema %||% "")[1],
              "scworkbench.operation_pack_runtime.python.v1") &&
      identical(as.character(runtime$backend %||% "")[1], "Python"),
    "OPERATION_PACK_RUNTIME_ATTESTATION_INVALID",
    "PyBench returned an incompatible operation-pack runtime attestation.",
    class = "wb_operation_pack_validation_error")
  .wb_operation_pack_assert(
    identical(as.character(runtime$identity_scheme %||% "")[1],
              .wb_operation_pack_identity_scheme()),
    "OPERATION_PACK_IDENTITY_SCHEME_MISMATCH",
    "PyBench runtime attestation claims an incompatible canonical identity scheme.",
    expected_identity_scheme = .wb_operation_pack_identity_scheme(),
    observed_identity_scheme = runtime$identity_scheme %||% NULL,
    class = "wb_operation_pack_identity_error")
  manifest_source <- runtime$manifest_source %||% list()
  .wb_operation_pack_assert(
    identical(as.character(manifest_source$scheme %||% "")[1],
              "python-installed-operation-pack-manifest-v1") &&
      nzchar(as.character(manifest_source$distribution_relative_path %||% "")[1]) &&
      grepl("^[0-9a-f]{64}$", as.character(manifest_source$bytes_sha256 %||% "")[1]) &&
      identical(as.character(manifest_source$manifest_sha256 %||% "")[1],
                identity$manifest_sha256),
    "OPERATION_PACK_MANIFEST_IDENTITY_MISMATCH",
    "PyBench runtime did not attest the authenticated installed-distribution manifest.",
    class = "wb_operation_pack_identity_error")
  if (!is.null(discovery)) {
    .wb_operation_pack_assert(
      identical(.wb_operation_pack_canonical_json(manifest_source),
                .wb_operation_pack_canonical_json(discovery$manifest_source %||% list())),
      "OPERATION_PACK_MANIFEST_IDENTITY_MISMATCH",
      "Installed-distribution manifest identity changed after activation.",
      class = "wb_operation_pack_identity_error")
  }
  distribution <- runtime$distribution %||% list()
  expected_normalized <- .wb_operation_pack_python_normalize_name(manifest$package$name)
  .wb_operation_pack_assert(
    identical(as.character(distribution$declared_name %||% "")[1], manifest$package$name) &&
      identical(as.character(distribution$normalized_name %||% "")[1], expected_normalized) &&
      identical(.wb_operation_pack_python_version_key(as.character(distribution$version %||% "")[1]),
                .wb_operation_pack_python_version_key(manifest$package$version)) &&
      identical(.wb_operation_pack_python_normalize_name(
        as.character(distribution$metadata_name %||% "")[1]), expected_normalized) &&
      identical(.wb_operation_pack_python_version_key(
        as.character(distribution$metadata_version %||% "")[1]),
        .wb_operation_pack_python_version_key(manifest$package$version)),
    "OPERATION_PACK_DISTRIBUTION_IDENTITY_MISMATCH",
    "Python runtime distribution identity differs from the admitted manifest.",
    class = "wb_operation_pack_identity_error")
  artifact <- distribution$artifact_identity %||% list()
  .wb_operation_pack_assert(
    identical(as.character(artifact$scheme %||% "")[1],
              "python-installed-distribution-tree-sha256-v1") &&
      grepl("^[0-9a-f]{64}$", as.character(artifact$sha256 %||% "")[1]),
    "OPERATION_PACK_RUNTIME_ATTESTATION_INVALID",
    "Python runtime distribution content identity is absent or malformed.",
    class = "wb_operation_pack_validation_error")
  if (!is.null(discovery)) {
    .wb_operation_pack_assert(
      identical(as.character(artifact$sha256)[1],
                as.character(discovery$distribution$artifact_identity$sha256)[1]),
      "OPERATION_PACK_DISTRIBUTION_IDENTITY_MISMATCH",
      "Python distribution content changed after explicit activation.",
      class = "wb_operation_pack_identity_error")
  }
  entry <- runtime$entry_point %||% list()
  .wb_operation_pack_assert(
    identical(as.character(entry$group %||% "")[1], .wb_operation_pack_python_entry_point_group()) &&
      identical(as.character(entry$name %||% "")[1], manifest$entry_point),
    "OPERATION_PACK_ENTRY_POINT_INVALID",
    "Python runtime entry-point identity differs from the admitted manifest.",
    class = "wb_operation_pack_identity_error")
  interpreter <- runtime$interpreter %||% list()
  .wb_operation_pack_assert(
    all(vapply(c("implementation", "version", "abi", "platform", "executable_sha256"),
      function(name) nzchar(as.character(interpreter[[name]] %||% "")[1]), logical(1))) &&
      grepl("^[0-9a-f]{64}$", as.character(interpreter$executable_sha256)[1]),
    "OPERATION_PACK_RUNTIME_ATTESTATION_INVALID",
    "Python interpreter attestation is incomplete.",
    class = "wb_operation_pack_validation_error")
  dependencies <- runtime$dependencies %||% list()
  rows <- dependencies$distributions %||% list()
  .wb_operation_pack_assert(
    identical(as.character(dependencies$scheme %||% "")[1], "python-distribution-set-v1") &&
      identical(as.character(dependencies$sha256 %||% "")[1], .wb_operation_pack_sha256(rows)),
    "OPERATION_PACK_RUNTIME_ATTESTATION_INVALID",
    "Python dependency-set attestation failed canonical SHA-256 verification.",
    class = "wb_operation_pack_validation_error")
  .wb_operation_pack_assert(
    identical(as.character(runtime$pybench$protocol %||% "")[1], .wb_pyproto_version()),
    "OPERATION_PACK_RUNTIME_ATTESTATION_INVALID",
    "Python runtime attests an incompatible PyBench protocol.",
    class = "wb_operation_pack_validation_error")
  .wb_operation_pack_python_runtime_sanitize(runtime)
}

.wb_operation_pack_python_discover <- function(manifest_path, manifest, identity,
                                                python, timeout_seconds) {
  result <- .wb_operation_pack_python_process(python, c(
    "-m", "pybench.operation_pack_cli", "discover", "--manifest", manifest_path
  ), timeout_seconds, "discovery")
  discovery <- tryCatch(jsonlite::fromJSON(result$stdout, simplifyVector = FALSE),
                        error = function(e) NULL)
  .wb_operation_pack_assert(is.list(discovery) &&
      identical(as.character(discovery$schema %||% "")[1], "pybench.operation_pack_discovery.v1"),
    "OPERATION_PACK_RUNTIME_ATTESTATION_INVALID", "PyBench discovery output is invalid.",
    class = "wb_operation_pack_validation_error")
  observed <- discovery$manifest_identity %||% list()
  .wb_operation_pack_assert(
    identical(as.character(observed$identity_scheme %||% "")[1],
              .wb_operation_pack_identity_scheme()),
    "OPERATION_PACK_IDENTITY_SCHEME_MISMATCH",
    "PyBench discovery claims an incompatible canonical identity scheme.",
    expected_identity_scheme = .wb_operation_pack_identity_scheme(),
    observed_identity_scheme = observed$identity_scheme %||% NULL,
    class = "wb_operation_pack_identity_error")
  .wb_operation_pack_assert(
    identical(.wb_operation_pack_canonical_json(observed),
              .wb_operation_pack_canonical_json(identity)),
    "OPERATION_PACK_IDENTITY_MISMATCH",
    "PyBench and scworkbench disagree on the canonical manifest, definition, or pack identity.",
    expected_pack_sha256 = identity$pack_sha256,
    observed_pack_sha256 = observed$pack_sha256 %||% NULL,
    class = "wb_operation_pack_identity_error")
  manifest_source <- discovery$manifest_source %||% list()
  .wb_require_pkg("digest", "installed operation-pack manifest identity")
  supplied_bytes_sha256 <- digest::digest(
    file = manifest_path, algo = "sha256", serialize = FALSE)
  .wb_operation_pack_assert(
    identical(as.character(manifest_source$scheme %||% "")[1],
              "python-installed-operation-pack-manifest-v1") &&
      nzchar(as.character(manifest_source$distribution_relative_path %||% "")[1]) &&
      identical(as.character(manifest_source$bytes_sha256 %||% "")[1],
                supplied_bytes_sha256) &&
      identical(as.character(manifest_source$manifest_sha256 %||% "")[1],
                identity$manifest_sha256),
    "OPERATION_PACK_MANIFEST_IDENTITY_MISMATCH",
    "PyBench did not authenticate the supplied bytes as the original installed-distribution manifest.",
    expected_bytes_sha256 = supplied_bytes_sha256,
    observed_bytes_sha256 = manifest_source$bytes_sha256 %||% NULL,
    class = "wb_operation_pack_identity_error")
  distribution <- discovery$distribution %||% list()
  .wb_operation_pack_assert(
    identical(as.character(distribution$declared_name %||% "")[1], manifest$package$name) &&
      identical(as.character(distribution$normalized_name %||% "")[1],
                .wb_operation_pack_python_normalize_name(manifest$package$name)) &&
      identical(.wb_operation_pack_python_version_key(
        as.character(distribution$version %||% "")[1]),
        .wb_operation_pack_python_version_key(manifest$package$version)),
    "OPERATION_PACK_DISTRIBUTION_IDENTITY_MISMATCH",
    "PyBench discovery distribution identity differs from the manifest.",
    class = "wb_operation_pack_identity_error")
  entry <- discovery$entry_point %||% list()
  .wb_operation_pack_assert(
    identical(as.character(entry$group %||% "")[1], .wb_operation_pack_python_entry_point_group()) &&
      identical(as.character(entry$name %||% "")[1], manifest$entry_point),
    "OPERATION_PACK_ENTRY_POINT_INVALID",
    "PyBench discovery entry point differs from the manifest.",
    class = "wb_operation_pack_identity_error")
  discovery$distribution$installed_location <- NULL
  discovery$distribution$build_metadata <- NULL
  discovery$runtime_attestation <- .wb_operation_pack_python_runtime_audit(
    discovery$runtime_attestation, manifest, identity, discovery = discovery)
  discovery
}

.wb_operation_pack_python_stage_input <- function(bundle, run, input_name, artifact_id,
                                                   primitive, effective_cells) {
  .wb_operation_pack_assert(identical(as.character(primitive$kind %||% "")[1], "cell_vector"),
    "OPERATION_PACK_PRIMITIVE_RUNTIME_UNAVAILABLE",
    paste0("PyBench operation-pack v1 cannot bind input primitive '",
           as.character(primitive$kind %||% "unknown")[1], "' in this runtime."),
    input = input_name, class = "wb_operation_pack_execution_error")
  ids <- as.character(primitive$cell_id)
  index <- match(as.character(effective_cells), ids)
  values <- suppressWarnings(as.numeric(primitive$value[index]))
  .wb_operation_pack_assert(!anyNA(index) && length(values) && all(is.finite(values)) &&
      identical(as.character(primitive$value_type %||% "")[1], "continuous"),
    "OPERATION_PACK_INPUT_INVALID",
    paste0("Python operation-pack input '", input_name,
           "' must be a finite continuous cell_vector over effective cells."),
    input = input_name, class = "wb_operation_pack_execution_error")
  spec <- stats::setNames(list(list(
    artifact_id = artifact_id, type = "cell_vector",
    name = paste0("Private Python input: ", input_name)
  )), input_name)
  .wb_pybench_preregister_outputs(bundle, run, spec, created_by = "operation-pack-python-adapter")
  rows <- data.frame(
    artifact_id = rep(artifact_id, length(effective_cells)),
    cell_id = as.character(effective_cells), label = as.character(values),
    value_type = rep("continuous", length(effective_cells)), value_num = values,
    stringsAsFactors = FALSE
  )
  .wb_db_append_chunked(bundle$con, "artifact_labels", rows)
  invisible(TRUE)
}

.wb_operation_pack_python_process_error <- function(error, op_name) {
  lines <- as.character(error$stdout_stderr %||% character())
  parsed <- .wb_operation_pack_python_json_error(lines)
  backend_code <- as.character(parsed$code %||% "")[1]
  status <- suppressWarnings(as.integer(error$status %||% NA_integer_))[1]
  if (isTRUE(error$timed_out)) {
    code <- "OPERATION_PACK_EXECUTION_TIMEOUT"
  } else if (!is.na(status) && (status < 0L || status >= 128L)) {
    code <- "OPERATION_PACK_EXECUTION_SIGNALLED"
  } else if (startsWith(backend_code, "OPERATION_PACK_")) {
    code <- backend_code
  } else {
    code <- "OPERATION_PACK_EXECUTION_FAILED"
  }
  message <- as.character(parsed$message %||% conditionMessage(error))[1]
  .wb_operation_pack_abort(code,
    paste0("Python operation-pack operation '", op_name, "' failed: ", message),
    operation = op_name, backend = "Python", backend_code = backend_code,
    status = status, class = "wb_operation_pack_execution_error")
}

.wb_operation_pack_python_runner <- function(op_name, definition, identity, discovery,
                                              manifest_path, python, timeout_seconds) {
  force(op_name); force(definition); force(identity); force(discovery)
  force(manifest_path); force(python); force(timeout_seconds)
  function(bundle, resolved, effective_cells, inputs, ...) {
    run_id <- .wb_pybench_current_run_id(bundle)
    run_tmp <- wb_new_run(op_name, inputs = list(cell_set = inputs$cell_set %||% "all"),
                          outputs = list(), run_id = run_id)
    input_ids <- stats::setNames(vapply(names(resolved), function(name) {
      .wb_new_artifact_id(paste0("pack_input_", name), bundle)
    }, character(1)), names(resolved))
    output_specs <- stats::setNames(lapply(names(definition$produces), function(name) list(
      artifact_id = .wb_new_artifact_id(paste0("pack_output_", name), bundle),
      type = as.character(definition$produces[[name]])[1],
      name = paste0(name, " (", op_name, ")")
    )), names(definition$produces))
    request_inputs <- stats::setNames(lapply(names(resolved), function(name) list(
      artifact_id = input_ids[[name]], type = as.character(resolved[[name]]$kind)[1]
    )), names(resolved))
    params <- stats::setNames(lapply(definition$params %||% list(), function(param) {
      inputs[[as.character(param$name)[1]]]
    }), vapply(definition$params %||% list(), function(param) as.character(param$name)[1], character(1)))
    request <- .wb_pybench_build_request(
      bundle, op_name, run_id = run_id, inputs = request_inputs,
      params = params, outputs = output_specs, mode = "staging_write"
    )
    runtime_path <- tempfile("operation_pack_runtime_", fileext = ".json")
    on.exit(unlink(runtime_path, force = TRUE), add = TRUE)
    output_ids <- vapply(output_specs, function(x) as.character(x$artifact_id)[1], character(1))
    on.exit(.wb_palantir_cleanup_staging_artifacts(
      bundle, output_ids, keep_model_files = FALSE), add = TRUE)
    command_args <- function(request_path, receipt_path) c(
      "-m", "pybench.operation_pack_cli", "execute",
      "--manifest", manifest_path, "--request", request_path,
      "--receipt", receipt_path, "--runtime-attestation", runtime_path,
      "--expected-pack-sha256", identity$pack_sha256,
      "--expected-definition-sha256", identity$operation_definition_sha256[[op_name]],
      "--expected-distribution-sha256", discovery$distribution$artifact_identity$sha256
    )
    prepare <- function(transition, request) {
      .wb_pybench_preregister_outputs(
        transition, run_tmp, output_specs, created_by = "operation-pack-python-adapter")
      for (name in names(resolved)) .wb_operation_pack_python_stage_input(
        transition, run_tmp, name, input_ids[[name]], resolved[[name]], effective_cells)
      invisible(TRUE)
    }
    finalize <- function(transition, request, result) {
      .wb_palantir_cleanup_staging_artifacts(
        transition, unname(input_ids), keep_model_files = FALSE)
      invisible(TRUE)
    }
    runtime <- NULL
    validate <- function(transition, request, result, observed) {
      .wb_operation_pack_assert(file.exists(runtime_path),
        "OPERATION_PACK_RUNTIME_ATTESTATION_INVALID",
        "PyBench did not publish the required runtime-attestation sidecar.",
        operation = op_name, class = "wb_operation_pack_execution_error")
      value <- tryCatch(jsonlite::read_json(runtime_path, simplifyVector = FALSE),
                        error = function(e) NULL)
      value <- .wb_operation_pack_python_runtime_audit(
        value, manifest = definition$source_pack_manifest, identity = identity,
        discovery = discovery)
      activation_runtime <- discovery$runtime_attestation
      .wb_operation_pack_assert(
        identical(as.character(value$interpreter$executable_sha256)[1],
                  as.character(activation_runtime$interpreter$executable_sha256)[1]),
        "OPERATION_PACK_RUNTIME_IDENTITY_MISMATCH",
        "Python interpreter identity changed after operation-pack activation.",
        operation = op_name, class = "wb_operation_pack_execution_error")
      runtime <<- value
      invisible(TRUE)
    }
    bridge <- tryCatch(.wb_pybench_run_module(
      module = NULL, request = request, bundle = bundle, python_bin = python,
      command_args = command_args, timeout_seconds = timeout_seconds,
      prepare_transition = prepare, finalize_transition = finalize,
      validate_transition = validate
    ), wb_pybench_process_error = function(e) .wb_operation_pack_python_process_error(e, op_name))
    .wb_assert(!is.null(runtime), "OPERATION_PACK_RUNTIME_ATTESTATION_INVALID: runtime audit was not completed")
    outputs <- stats::setNames(lapply(names(output_specs), function(name) {
      wb_art_load(bundle, output_specs[[name]]$artifact_id,
                  expected_kind = output_specs[[name]]$type)
    }), names(output_specs))
    list(outputs = outputs, params = params, operation_pack_runtime = runtime,
         operation_pack_receipt = bridge$receipt)
  }
}

.wb_operation_pack_python_registration <- function(manifest, identity, discovery,
                                                    manifest_path, python,
                                                    timeout_seconds) {
  definitions <- stats::setNames(manifest$operations,
    vapply(manifest$operations, function(x) x$name, character(1)))
  runners <- lapply(names(definitions), function(op_name) {
    definition <- definitions[[op_name]]
    # Runtime-only pointer used by the R audit; it is removed before this
    # definition enters the canonical catalog.
    definition$source_pack_manifest <- manifest
    .wb_operation_pack_python_runner(op_name, definition, identity, discovery,
      manifest_path, python, timeout_seconds)
  })
  names(runners) <- names(definitions)
  structure(list(
    manifest = manifest, runners = runners, identity = identity,
    runtime_attestation = discovery$runtime_attestation,
    runtime_config = list(backend = "Python", python = python,
                          manifest_path = manifest_path,
                          timeout_seconds = timeout_seconds)
  ), class = c("wb_operation_pack_registration", "list"))
}
