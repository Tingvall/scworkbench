# Audited Python process adapter for operation-pack ABI v3 / pybench-op-v4.

.wb_operation_pack_v3_python_discover <- function(manifest_path, manifest,
                                                    python, timeout_seconds,
                                                    activate = FALSE) {
  script <- paste(
    "import json,sys",
    "from pybench.operation_packs import OperationPackError,canonical_json",
    "from pybench.operation_packs_v3 import discover_operation_pack_v3,activate_operation_pack_v3",
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
      discovery$schema %||% "")[1], "pybench.operation_pack.discovery.v3") &&
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
  expected <- .wb_operation_pack_v3_identity(manifest, source$sha256, content)
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
      "scworkbench.operation_packs.v3") &&
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
    manifest_path, python, timeout_seconds) {
  expected <- vapply(manifest$operations, `[[`, character(1),
    "qualified_name")
  noop <- function(readers, writers, params, context) invisible(NULL)
  runners <- stats::setNames(rep(list(noop), length(expected)), expected)
  definitions <- stats::setNames(lapply(manifest$operations,
    .wb_operation_pack_v3_catalog_definition), expected)
  structure(list(manifest = manifest, runners = runners, finalizers = list(),
    identity = discovery$identity, definitions = definitions,
    protocol_version = "3", manifest_path = manifest_path,
    installed_path = dirname(dirname(manifest_path)),
    runtime_attestation = list(
      schema = "pybench.operation_pack.discovery.v3", backend = "Python",
      distribution = discovery$distribution,
      manifest_source_identity = discovery$manifest_source_identity,
      entry_point = discovery$entry_point),
    runtime_config = list(backend = "Python", python = python,
      manifest_path = manifest_path, timeout_seconds = timeout_seconds)),
    class = c("wb_operation_pack_registration_v3",
      "wb_operation_pack_registration_v2", "wb_operation_pack_registration",
      "list"))
}

.wb_operation_pack_v3_python_sidecar_audit <- function(value, registration,
                                                        request) {
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

.wb_operation_pack_v3_python_audit <- function(stage, request, receipt) {
  observed <- c(receipt$outputs %||% list(),
    receipt$registry_requests %||% list())
  names_observed <- vapply(observed, `[[`, character(1), "name")
  names_granted <- vapply(request$outputs, `[[`, character(1), "name")
  if (!setequal(names_observed, names_granted) ||
      anyDuplicated(names_observed) || length(observed) != length(names_granted))
    .wb_operation_pack_v3_error("PYBENCH_RECEIPT_MISMATCH",
      "Python v4 outputs are not a bijection with grants.", "receipt")
  for (item in observed) {
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
    if (nzchar(expected) && !identical(.wb_operation_pack_sha256(value),
        expected)) .wb_operation_pack_v3_error("PYBENCH_OUTPUT_INVALID",
      paste0("Python v4 output content identity differs: ", item$name),
      "audit")
  }
  inventory <- sort(list.files(stage, recursive = TRUE, all.files = TRUE,
    include.dirs = FALSE, no.. = TRUE), method = "radix")
  output_paths <- vapply(observed, function(item) paste0(
    if (identical(as.character(item$descriptor$category)[1],
      "core_registry_request")) "registry_requests/" else "outputs/",
    item$name, "/payload.json"), character(1))
  registry_paths <- vapply(request$registry_reads %||% list(), function(x)
    paste0("registry_reads/", x$name, "/payload.json"), character(1))
  provenance_paths <- vapply(request$provenance_reads %||% list(), function(x)
    paste0("provenance_reads/", x$name, "/payload.json"), character(1))
  expected_inventory <- sort(c("python-runtime.json", "receipt.json",
    "request.json", "state.json", output_paths, registry_paths,
    provenance_paths), method = "radix")
  if (!identical(inventory, expected_inventory))
    .wb_operation_pack_v3_error("PYBENCH_OUT_OF_SCOPE_MUTATION",
      "Python v4 private stage contains undeclared files.", "audit",
      unexpected = setdiff(inventory, expected_inventory),
      missing = setdiff(expected_inventory, inventory))
  retained <- .wb_operation_pack_v2_record_validate(stage,
    load_payloads = TRUE)
  if (!isTRUE(retained$ok)) .wb_operation_pack_v3_error(
    "PYBENCH_RECEIPT_MISMATCH",
    paste0("Python v4 retained transition audit failed: ", retained$code,
      if (!is.null(retained$output)) paste0(" (", retained$output, ")")
      else ""), "audit")
  invisible(TRUE)
}

.wb_operation_pack_v3_python_dispatch <- function(request, registration,
                                                   stage) {
  config <- registration$runtime_config
  receipt_path <- file.path(stage, "receipt.json")
  runtime_path <- file.path(stage, "python-runtime.json")
  result <- .wb_operation_pack_v2_python_run(config$python, c(
    "-m", "pybench.operation_pack_v4_cli", "--manifest",
    config$manifest_path, "--request", file.path(stage, "request.json"),
    "--stage-root", stage, "--receipt", receipt_path,
    "--python-runtime", runtime_path), config$timeout_seconds, "execution",
    error_path = receipt_path)
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
  list(receipt = receipt, sidecar = runtime, process = result,
    reader_observation = NULL)
}
