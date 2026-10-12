# Audited Python process adapter for operation-pack ABI v3 / pybench-op-v4.

.wb_operation_pack_v3_python_discover <- function(manifest_path, manifest,
                                                    python, timeout_seconds,
                                                    activate = FALSE, abi = "3") {
  script <- paste(
    "import json,sys",
    "from pybench.operation_packs import OperationPackError,canonical_json",
    paste0("from pybench.operation_packs_v", abi, " import discover_operation_pack_v", abi,
      " as discover_operation_pack_v3,activate_operation_pack_v", abi, " as activate_operation_pack_v3"),
    "try:",
    " d=discover_operation_pack_v3(sys.argv[1])",
    " r=d.public_record()",
    " if sys.argv[2]=='activate': r['activated_operations']=sorted(activate_operation_pack_v3(d).handlers)",
    " print(canonical_json(r))",
    "except OperationPackError as e:",
    " print(json.dumps({'code':e.code,'message':str(e),'phase':e.details.get('phase','authentication')}),file=sys.stderr)",
    " raise SystemExit(2)", sep = "\n")
  result <- .wb_operation_pack_v2_python_run(python,
    c("-c", script, manifest_path,
      if (isTRUE(activate)) "activate" else "discover"),
    timeout_seconds, "discovery")
  discovery <- tryCatch(jsonlite::fromJSON(result$stdout,
    simplifyVector = FALSE), error = function(e) NULL)
  .wb_operation_pack_assert(is.list(discovery) && identical(as.character(
      discovery$schema %||% "")[1], paste0("pybench.operation_pack.discovery.v", abi)) &&
      identical(as.character(discovery$backend %||% "")[1], "Python"),
    "OPERATION_PACK_RUNTIME_ATTESTATION_INVALID",
    "PyBench ABI v3 discovery output is invalid.",
    class = "wb_operation_pack_v3_error")
  source <- discovery$manifest_source_identity %||% list()
  .wb_operation_pack_assert(identical(as.character(source$scheme %||% "")[1],
      "scworkbench.operation_pack.manifest_source.bytes.v1") &&
      identical(as.character(source$sha256 %||% "")[1],
        .wb_operation_pack_v2_file_sha256(manifest_path)),
    "OPERATION_PACK_MANIFEST_IDENTITY_MISMATCH",
    "PyBench did not authenticate the original ABI v3 manifest bytes.",
    class = "wb_operation_pack_v3_error")
  distribution <- discovery$distribution %||% list()
  content <- distribution$artifact_identity %||% list()
  .wb_operation_pack_assert(identical(.wb_operation_pack_python_normalize_name(
      as.character(distribution$declared_name %||% "")[1]),
      .wb_operation_pack_python_normalize_name(manifest$package$name)) &&
      identical(.wb_operation_pack_python_version_key(as.character(
        distribution$version %||% "")[1]),
      .wb_operation_pack_python_version_key(manifest$package$version)) &&
      identical(as.character(content$scheme %||% "")[1],
        "scworkbench.operation_pack.content.v1") &&
      grepl("^[0-9a-f]{64}$", as.character(content$sha256 %||% "")[1]),
    "OPERATION_PACK_DISTRIBUTION_IDENTITY_MISMATCH",
    "PyBench ABI v3 discovery distribution differs from the manifest.",
    class = "wb_operation_pack_v3_error")
  expected <- (if (abi == "4") .wb_operation_pack_v4_identity else .wb_operation_pack_v3_identity)(
    manifest, source$sha256, content)
  observed <- discovery$identity %||% list()
  observed$manifest_relative_path <- NULL
  .wb_operation_pack_assert(identical(.wb_operation_pack_canonical_json(expected),
      .wb_operation_pack_canonical_json(observed)),
    "OPERATION_PACK_IDENTITY_MISMATCH",
    "PyBench and scworkbench disagree on the ABI v3 identity closure.",
    class = "wb_operation_pack_v3_error")
  entry <- discovery$entry_point %||% list()
  entry_value <- paste0(as.character(entry$group %||% "")[1], ":",
    as.character(entry$name %||% "")[1], "=",
    as.character(entry$value %||% "")[1])
  .wb_operation_pack_assert(identical(as.character(entry$group %||% "")[1],
      paste0("scworkbench.operation_packs.v", abi)) &&
      identical(entry_value, manifest$entry_point) &&
      identical(entry$identity, expected$entry_point_identity),
    "OPERATION_PACK_ENTRY_POINT_INVALID",
    "PyBench ABI v3 entry point differs from the admitted manifest.",
    class = "wb_operation_pack_v3_error")
  if (isTRUE(activate)) {
    expected_operations <- sort(vapply(manifest$operations, `[[`,
      character(1), "qualified_name"), method = "radix")
    observed_operations <- sort(as.character(unlist(
      discovery$activated_operations %||% character(), use.names = FALSE)),
      method = "radix")
    .wb_operation_pack_assert(identical(observed_operations,
        expected_operations), "OPERATION_PACK_ENTRY_POINT_INVALID",
      "PyBench ABI v3 activated handler closure differs from the manifest.",
      class = "wb_operation_pack_v3_error")
  }
  discovery$activated_operations <- NULL
  discovery$identity <- expected
  discovery
}

.wb_operation_pack_v3_python_registration <- function(manifest, discovery,
    manifest_path, python, timeout_seconds, abi = "3") {
  expected <- vapply(manifest$operations, `[[`, character(1),
    "qualified_name")
  noop <- function(readers, writers, params, context) invisible(NULL)
  runners <- stats::setNames(rep(list(noop), length(expected)), expected)
  definitions <- stats::setNames(lapply(manifest$operations,
    if (abi == "4") .wb_operation_pack_v4_catalog_definition else .wb_operation_pack_v3_catalog_definition), expected)
  structure(list(manifest = manifest, runners = runners,
    identity = discovery$identity, definitions = definitions,
    protocol_version = abi, manifest_path = manifest_path,
    installed_path = dirname(dirname(manifest_path)),
    runtime_attestation = list(
      schema = paste0("pybench.operation_pack.discovery.v", abi), backend = "Python",
      distribution = discovery$distribution,
      manifest_source_identity = discovery$manifest_source_identity,
      entry_point = discovery$entry_point),
    runtime_config = list(backend = "Python", python = python,
      manifest_path = manifest_path, timeout_seconds = timeout_seconds)),
    class = c(if (abi == "4") "wb_operation_pack_registration_v4", "wb_operation_pack_registration_v3",
      "wb_operation_pack_registration_v2", "wb_operation_pack_registration",
      "list"))
}

.wb_operation_pack_v3_python_sidecar_audit <- function(value, registration,
                                                        request) {
  abi_v4 <- identical(request$pack_abi_version, "4")
  required <- c("schema", "backend", "distribution_identity",
    "request_identity", "capability_identity",
    "operation_definition_identity", "interpreter", "seed", "device",
    "runtime_identity")
  .wb_operation_pack_assert(is.list(value) &&
      setequal(names(value), required) && identical(as.character(
        value$schema)[1], "pybench.operation_pack.python_runtime.v4") &&
      identical(as.character(value$backend)[1], "Python"),
    "OPERATION_PACK_RUNTIME_ATTESTATION_INVALID",
    "Python v4 runtime sidecar has the wrong closed shape.",
    class = "wb_operation_pack_v3_error")
  if (abi_v4) {
    schema <- jsonlite::read_json(system.file("protocol",
      "pybench-op-v5-python-runtime.schema.json", package = "scworkbench"),
      simplifyVector = FALSE)
    validation <- .wb_json_schema_validate_2020(value, schema)
    .wb_operation_pack_assert(isTRUE(validation$ok),
      "OPERATION_PACK_RUNTIME_ATTESTATION_INVALID",
      paste("Process-v5 runtime evidence disagrees with its closed schema:",
        validation$message %||% "invalid field"), class = "wb_operation_pack_v3_error")
  }
  .wb_operation_pack_v3_assert_self_identity(value, "runtime_identity",
    "OPERATION_PACK_RUNTIME_ATTESTATION_INVALID", "receipt")
  .wb_operation_pack_assert(identical(value$distribution_identity,
      registration$identity$distribution_identity) &&
      identical(value$request_identity, request$request_identity) &&
      identical(value$capability_identity,
        request$execution_capability$capability_identity) &&
      identical(value$operation_definition_identity,
        request$operation_authentication$operation_definition_identity),
    "OPERATION_PACK_RUNTIME_IDENTITY_MISMATCH",
    "Python v4 runtime sidecar differs from activation or request.",
    class = "wb_operation_pack_v3_error")
  .wb_operation_pack_assert(identical(as.character(
      value$interpreter$executable_sha256)[1],
      .wb_operation_pack_v2_file_sha256(registration$runtime_config$python)),
    "OPERATION_PACK_RUNTIME_IDENTITY_MISMATCH",
    "Python interpreter identity changed after ABI v3 activation.",
    class = "wb_operation_pack_v3_error")
  invisible(TRUE)
}

.wb_operation_pack_v3_python_audit <- function(stage, request, receipt, graph_connections = list()) {
  abi_v4 <- identical(request$pack_abi_version, "4")
  if (abi_v4) .wb_operation_pack_v4_graph_record_assert(request, receipt, stage, TRUE,
    connections = graph_connections)
  observed <- c(receipt$outputs %||% list(),
    receipt$registry_requests %||% list())
  names_observed <- vapply(observed, `[[`, character(1), "name")
  names_granted <- vapply(request$outputs, `[[`, character(1), "name")
  if (!setequal(names_observed, names_granted) ||
      anyDuplicated(names_observed) || length(observed) != length(names_granted))
    .wb_operation_pack_v3_error("PYBENCH_RECEIPT_MISMATCH",
      "Python v4 outputs are not a bijection with grants.", "receipt")
  for (item in observed) {
    if (abi_v4 && identical(item$descriptor$kind, "graph")) next
    root <- if (identical(as.character(item$descriptor$category)[1],
      "core_registry_request")) "registry_requests" else "outputs"
    path <- file.path(stage, root, item$name, "payload.json")
    if (!file.exists(path) || nzchar(Sys.readlink(path)))
      .wb_operation_pack_v3_error("PYBENCH_OUTPUT_INVALID",
        paste0("Python v4 output is absent or linked: ", item$name), "audit")
    raw <- readChar(path, nchars = file.info(path)$size, useBytes = TRUE)
    .wb_operation_pack_v2_assert_strict_json(raw)
    value <- .wb_operation_pack_parse_canonical_json(raw)
    expected <- as.character(item$descriptor$content_identity$sha256 %||%
      item$descriptor$family_identity$sha256 %||% "")[1]
    authenticated_model_tree <-
      item$descriptor$contained_model_tree %||%
        item$descriptor$contained_model_sibling_tree %||% NULL
    if (is.null(authenticated_model_tree) && nzchar(expected) &&
        !identical(.wb_operation_pack_sha256(value),
        expected)) .wb_operation_pack_v3_error("PYBENCH_OUTPUT_INVALID",
      paste0("Python v4 output content identity differs: ", item$name),
      "audit")
  }
  inventory <- sort(list.files(stage, recursive = TRUE, all.files = TRUE,
    include.dirs = FALSE, no.. = TRUE), method = "radix")
  output_paths <- unlist(lapply(observed, function(item) paste0(
    if (identical(as.character(item$descriptor$category)[1],
      "core_registry_request")) "registry_requests/" else "outputs/",
    item$name, if (abi_v4 && identical(item$descriptor$kind, "graph"))
      c("/payload.json", "/graph.parts.ndjson") else "/payload.json")), use.names = FALSE)
  registry_paths <- vapply(request$registry_reads %||% list(), function(x)
    paste0("registry_reads/", x$name, "/payload.json"), character(1))
  provenance_paths <- vapply(request$provenance_reads %||% list(), function(x)
    paste0("provenance_reads/", x$name, "/payload.json"), character(1))
  typed_slice_axes <- unlist(lapply(request$typed_slice_grants %||% list(),
    function(x) c(x$cells_axis$relative_path,
      x$features_axis$relative_path)), use.names = FALSE)
  typed_slice_sources <- vapply(Filter(function(x) identical(
    x$source_reference$source_kind, "in_memory_selected_projection"),
    request$typed_slice_grants %||% list()), function(x)
      sub("^private_projection:", "typed_slice_sources/",
        paste0(x$source_reference$input_reference, "/matrix.mtx")),
      character(1))
  model_read_files <- unlist(lapply(request$model_payload_grants %||%
    list(), function(grant) vapply(grant$tree_manifest$entries,
      function(entry) file.path(grant$relative_root, entry$path),
      character(1))), use.names = FALSE)
  self_model_read_files <- unlist(lapply(
    request$self_linked_model_payload_grants %||% list(), function(grant)
      vapply(grant$tree_manifest$entries, function(entry)
        file.path(grant$relative_root, entry$path), character(1))),
    use.names = FALSE)
  expected_inventory <- sort(c("python-runtime.json", "receipt.json",
    "request.json", "state.json", output_paths, registry_paths,
    provenance_paths, typed_slice_axes, typed_slice_sources), method = "radix")
  expected_inventory <- sort(c(expected_inventory, model_read_files,
    self_model_read_files), method = "radix")
  model_roots <- paste0("outputs/", vapply(Filter(function(item)
    !is.null(item$descriptor$contained_model_tree) ||
      !is.null(item$descriptor$contained_model_sibling_tree), observed),
    `[[`, character(1), "name"), "/model_tree/")
  dynamic <- if (length(model_roots)) vapply(inventory, function(path)
    any(startsWith(path, model_roots)), logical(1)) else
      rep(FALSE, length(inventory))
  inventory <- inventory[!dynamic]
  if (!identical(inventory, expected_inventory))
    .wb_operation_pack_v3_error("PYBENCH_OUT_OF_SCOPE_MUTATION",
      "Python v4 private stage contains undeclared files.", "audit",
      unexpected = setdiff(inventory, expected_inventory),
      missing = setdiff(expected_inventory, inventory))
  retained <- .wb_operation_pack_v2_record_validate(stage,
    load_payloads = TRUE, graph_connections = graph_connections)
  if (!isTRUE(retained$ok)) .wb_operation_pack_v3_error(
    "PYBENCH_RECEIPT_MISMATCH",
    paste0("Python v4 retained transition audit failed: ", retained$code,
      if (!is.null(retained$output)) paste0(" (", retained$output, ")")
      else ""), "audit")
  invisible(TRUE)
}

.wb_operation_pack_v3_python_supervised_run <- function(request, registration,
    stage, bundle, args) {
  config <- registration$runtime_config
  token <- digest::digest(.wb_allocate_identifier("broker_", 32L,
    purpose = "operation-pack v3 typed-slice broker"), algo = "sha256",
    serialize = FALSE)
  timeout <- as.numeric(config$timeout_seconds)
  broker_script <- paste0(
    "scworkbench:::.wb_operation_pack_v3_broker_main(",
    "commandArgs(TRUE)[1],commandArgs(TRUE)[2],commandArgs(TRUE)[3])")
  source_dir <- as.character(bundle$staging_source_dir %||% bundle$dir)[1]
  broker_args <- c("-e", broker_script, stage, bundle$dir, source_dir)
  broker_root <- file.path(stage, "broker")
  dir.create(broker_root, recursive = TRUE, showWarnings = FALSE)
  if (!dir.exists(broker_root) || nzchar(Sys.readlink(broker_root)))
    .wb_operation_pack_v2_error("OPERATION_PACK_RUNTIME_UNAVAILABLE",
      "Could not create the typed-slice broker endpoint.", "execution")
  broker_env <- c(PYBENCH_OPERATION_PACK_BROKER_TOKEN = token,
    PYBENCH_OPERATION_PACK_BROKER_TIMEOUT = as.character(timeout),
    R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep))
  python_env <- c(PYBENCH_OPERATION_PACK_BROKER_TOKEN = token,
    PYBENCH_OPERATION_PACK_BROKER_ROOT = broker_root,
    PYBENCH_OPERATION_PACK_BROKER_TIMEOUT_SECONDS = as.character(timeout))
  broker <- tryCatch(processx::process$new(file.path(R.home("bin"),
    "Rscript"), broker_args, stdout = "|", stderr = "|",
    env = broker_env, cleanup_tree = TRUE), error = identity)
  if (inherits(broker, "error")) .wb_operation_pack_v2_error(
    "OPERATION_PACK_RUNTIME_UNAVAILABLE",
    paste0("Could not start the typed-slice broker: ",
      conditionMessage(broker)), "execution")
  python <- tryCatch(processx::process$new(config$python, args,
    stdout = "|", stderr = "|", env = python_env, cleanup_tree = TRUE),
    error = identity)
  if (inherits(python, "error")) {
    if (broker$is_alive()) broker$kill_tree()
    .wb_operation_pack_v2_error("OPERATION_PACK_RUNTIME_UNAVAILABLE",
      paste0("Could not start Python ABI v3 execution: ",
        conditionMessage(python)), "execution")
  }
  python_stdout <- character(); python_stderr <- character()
  broker_stdout <- character(); broker_stderr <- character()
  cleanup <- function() {
    if (python$is_alive()) python$kill_tree()
    if (broker$is_alive()) broker$kill_tree()
    try(python$wait(timeout = 2000), silent = TRUE)
    try(broker$wait(timeout = 2000), silent = TRUE)
    unlink(file.path(stage, "broker"), recursive = TRUE, force = TRUE)
  }
  on.exit(cleanup(), add = TRUE)
  deadline <- Sys.time() + timeout
  while (python$is_alive()) {
    python_stdout <- c(python_stdout, python$read_output_lines())
    python_stderr <- c(python_stderr, python$read_error_lines())
    broker_stdout <- c(broker_stdout, broker$read_output_lines())
    broker_stderr <- c(broker_stderr, broker$read_error_lines())
    if (!broker$is_alive()) {
      python$kill_tree()
      error <- tryCatch(jsonlite::read_json(file.path(stage,
        "broker-error.json"), simplifyVector = FALSE), error = function(e)
          list(message = paste(broker_stderr, collapse = "\n")))
      .wb_operation_pack_v2_error("PYBENCH_PROCESS_FAILED",
        paste0("Typed-slice broker exited before Python: ",
          error$message %||% "unknown broker failure"), "execution")
    }
    if (Sys.time() > deadline) {
      python$kill_tree(); broker$kill_tree()
      .wb_operation_pack_v2_error("PYBENCH_PROCESS_FAILED",
        "Python ABI v3 supervised execution timed out.", "execution",
        timed_out = TRUE)
    }
    Sys.sleep(0.02)
  }
  python$wait()
  python_stdout <- c(python_stdout, python$read_all_output_lines())
  python_stderr <- c(python_stderr, python$read_all_error_lines())
  python_status <- as.integer(python$get_exit_status())
  if (!identical(python_status, 0L)) {
    if (broker$is_alive()) broker$kill_tree()
    try(broker$wait(timeout = 2000), silent = TRUE)
    broker_stdout <- c(broker_stdout, tryCatch(
      broker$read_all_output_lines(), error = function(error) character()))
    broker_stderr <- c(broker_stderr, tryCatch(
      broker$read_all_error_lines(), error = function(error) character()))
    return(list(status = python_status, stdout = paste(python_stdout,
      collapse = "\n"), stderr = paste(python_stderr, collapse = "\n")))
  }
  .wb_operation_pack_v2_atomic_json(list(stop = TRUE),
    file.path(stage, "broker", "stop.json"))
  broker$wait(timeout = min(10000, timeout * 1000))
  broker_stdout <- c(broker_stdout, broker$read_all_output_lines())
  broker_stderr <- c(broker_stderr, broker$read_all_error_lines())
  if (broker$is_alive()) .wb_operation_pack_v2_error(
    "PYBENCH_PROCESS_FAILED", "Typed-slice broker did not stop cleanly.",
    "execution")
  if (!identical(as.integer(broker$get_exit_status()), 0L)) {
    error <- tryCatch(jsonlite::read_json(file.path(stage,
      "broker-error.json"), simplifyVector = FALSE), error = function(e)
        list(message = paste(broker_stderr, collapse = "\n")))
    .wb_operation_pack_v2_error("PYBENCH_PROCESS_FAILED",
      paste0("Typed-slice broker failed: ", error$message %||%
        "unknown broker failure"), "execution")
  }
  list(status = python_status, stdout = paste(python_stdout,
    collapse = "\n"), stderr = paste(python_stderr, collapse = "\n"))
}

.wb_operation_pack_v3_python_dispatch <- function(request, registration,
                                                   stage, bundle = NULL) {
  abi_v4 <- identical(request$pack_abi_version, "4")
  supervised_reads <- length(request$typed_slice_grants %||% list()) ||
    (abi_v4 && length(request$graph_read_grants %||% list()))
  config <- registration$runtime_config
  receipt_path <- file.path(stage, "receipt.json")
  runtime_path <- file.path(stage, "python-runtime.json")
  args <- c(
    "-m", if (abi_v4) "pybench.operation_pack_v5_cli" else "pybench.operation_pack_v4_cli", "--manifest",
    config$manifest_path, "--request", file.path(stage, "request.json"),
    "--stage-root", stage, "--receipt", receipt_path,
    "--python-runtime", runtime_path)
  result <- if (supervised_reads) {
    .wb_operation_pack_assert(!is.null(bundle),
      "PYBENCH_CAPABILITY_MISMATCH",
      "Python typed-slice execution requires a trusted bundle binding.",
      class = "wb_operation_pack_v3_error")
    supervised <- .wb_operation_pack_v3_python_supervised_run(request,
      registration, stage, bundle, args)
    if (!identical(as.integer(supervised$status), 0L)) {
      record <- tryCatch(jsonlite::read_json(receipt_path,
        simplifyVector = FALSE), error = function(e) NULL)
      error <- if (is.list(record$error %||% NULL)) record$error else
        if (is.list(record)) record else list()
      .wb_operation_pack_v2_error(as.character(error$error_code %||%
          error$code %||% "PYBENCH_PROCESS_FAILED")[1],
        as.character(error$message %||% if (nzchar(supervised$stderr))
          supervised$stderr else paste0("Python ABI v3 exited with status ",
            supervised$status, "."))[1],
        as.character(error$phase %||% "execution")[1])
    }
    supervised
  } else .wb_operation_pack_v2_python_run(config$python, args,
    config$timeout_seconds, "execution", error_path = receipt_path)
  .wb_operation_pack_v2_fault("python_process_completed", stage = stage)
  receipt <- tryCatch(jsonlite::read_json(receipt_path,
    simplifyVector = FALSE), error = function(e) NULL)
  runtime <- tryCatch(jsonlite::read_json(runtime_path,
    simplifyVector = FALSE), error = function(e) NULL)
  .wb_operation_pack_assert(is.list(receipt) && is.list(runtime),
    "PYBENCH_RECEIPT_MISMATCH",
    "Python v4 process did not publish receipt and runtime sidecar.",
    class = "wb_operation_pack_v3_error")
  .wb_operation_pack_v3_python_sidecar_audit(runtime, registration, request)
  if (length(request$typed_slice_grants %||% list())) {
    observations_path <- file.path(stage, "broker-observations.json")
    observations <- tryCatch(jsonlite::read_json(observations_path,
      simplifyVector = FALSE), error = function(e) NULL)
    .wb_operation_pack_assert(is.list(observations),
      "PYBENCH_RECEIPT_MISMATCH",
      "Typed-slice broker did not retain its call observations.",
      class = "wb_operation_pack_v3_error")
    state <- new.env(parent = emptyenv())
    names_grants <- vapply(request$typed_slice_grants, `[[`, character(1),
      "name")
    state$typed_slice_calls <- stats::setNames(vector("list",
      length(names_grants)), names_grants)
    for (item in observations) {
      name <- as.character(item$name)[1]
      if (!name %in% names_grants) .wb_operation_pack_v3_error(
        "PYBENCH_RECEIPT_MISMATCH",
        "Broker observation names an undeclared typed-slice grant.",
        "receipt")
      state$typed_slice_calls[[name]][[length(
        state$typed_slice_calls[[name]]) + 1L]] <- list(result = item$result,
          chunk_values = as.character(unlist(item$chunk_values,
            use.names = FALSE)))
    }
    expected_usage <- .wb_operation_pack_v3_typed_slice_usage(
      list(state = state), request)
    if (!identical(.wb_operation_pack_canonical_json(expected_usage),
        .wb_operation_pack_canonical_json(receipt$typed_slice_usage %||%
          list()))) .wb_operation_pack_v3_error(
      "PYBENCH_RECEIPT_MISMATCH",
      "Python typed-slice receipt differs from broker-owned evidence.",
      "receipt")
    unlink(observations_path, force = TRUE)
  }
  graph_usage <- NULL
  if (abi_v4 && length(request$graph_read_grants %||% list())) {
    path <- file.path(stage, "graph-broker-observations.json")
    graph_usage <- tryCatch(jsonlite::read_json(path, simplifyVector = FALSE),
      error = function(error) NULL)
    .wb_graph_require(is.list(graph_usage), "GRAPH_READER_INCOMPLETE",
      "Core graph broker did not retain complete read evidence.")
    .wb_graph_require(identical(.wb_operation_pack_canonical_json(graph_usage),
      .wb_operation_pack_canonical_json(receipt$graph_read_usage %||% list())),
      "GRAPH_READER_INCOMPLETE", "Python graph usage differs from core broker evidence.")
    unlink(path)
  } else if (abi_v4) graph_usage <- list()
  if (supervised_reads) {
    unlink(file.path(stage, "broker-error.json"), force = TRUE)
    unlink(file.path(stage, "broker-observations.json"), force = TRUE)
    unlink(file.path(stage, "broker"), recursive = TRUE, force = TRUE)
  }
  list(receipt = receipt, sidecar = runtime, process = result,
    reader_observation = NULL, graph_read_usage = graph_usage)
}
