# pybench op protocol helpers (request/receipt validation + JSON IO)

.wb_pyproto_version <- function() "pybench-op-v2"

.wb_pyproto_schema_path <- function() {
  installed <- system.file("protocol", "pybench-op-v2.schema.json", package = "scworkbench")
  if (nzchar(installed)) return(installed)
  file.path("inst", "protocol", "pybench-op-v2.schema.json")
}

.wb_pyproto_path_contract <- function() list(
  version = .wb_bundle_path_contract_version(),
  durable_paths = "bundle_relative_contained",
  external_inputs = "explicit_import_only",
  serialized_models = "trusted_provenance_runtime_or_explicit_opt_in"
)

.wb_pyproto_assert_scalar_chr <- function(x, name) {
  .wb_assert(is.character(x) && length(x) == 1L && nzchar(x),
             paste0(name, " must be a length-1 non-empty string"))
}

.wb_pyproto_assert_sha256 <- function(x, name) {
  .wb_pyproto_assert_scalar_chr(as.character(x %||% ""), name)
  .wb_assert(grepl("^[a-f0-9]{64}$", as.character(x)[1]), paste0(name, " must be a lowercase SHA-256 identity"))
}

.wb_pyproto_validate_relative_path <- function(x, name) {
  .wb_pyproto_assert_scalar_chr(as.character(x %||% ""), name)
  value <- gsub("\\\\", "/", as.character(x)[1])
  .wb_assert(!.wb_path_is_absolute(value) && !any(strsplit(value, "/", fixed = TRUE)[[1]] == ".."),
             paste0("PYBENCH_OUT_OF_SCOPE_MUTATION: ", name, " must be a contained bundle-relative path"))
  invisible(TRUE)
}

.wb_pyproto_validate_allowance <- function(x, where, receipt = FALSE) {
  .wb_assert(is.list(x), paste0(where, " must be an object"))
  for (nm in c("output_name", "output_id", "output_kind", "mutation_class")) {
    .wb_pyproto_assert_scalar_chr(as.character(x[[nm]] %||% ""), paste0(where, "$", nm))
  }
  cls <- as.character(x$mutation_class)[1]
  .wb_assert(cls %in% c("sqlite_rows", "payload_tree"), paste0(where, "$mutation_class is unsupported"))
  if (identical(cls, "sqlite_rows")) {
    .wb_pyproto_assert_scalar_chr(as.character(x$table %||% ""), paste0(where, "$table"))
    scope <- x$key_scope %||% list()
    .wb_assert(is.list(scope), paste0(where, "$key_scope must be an object"))
    .wb_pyproto_assert_scalar_chr(as.character(scope$column %||% ""), paste0(where, "$key_scope$column"))
    values <- as.character(scope$values %||% character())
    .wb_assert(length(values) > 0L && all(nzchar(values)), paste0(where, "$key_scope$values must be non-empty strings"))
    .wb_assert(is.null(x$path), paste0(where, " SQLite descriptors cannot contain path"))
  } else {
    .wb_pyproto_validate_relative_path(x$path, paste0(where, "$path"))
    .wb_assert(is.null(x$table) && is.null(x$key_scope), paste0(where, " payload descriptors cannot contain table/key_scope"))
  }
  if (isTRUE(receipt)) {
    count <- as.integer(x$row_count %||% NA_integer_)[1]
    .wb_assert(!is.na(count) && count >= 0L, paste0(where, "$row_count must be a non-negative integer"))
    .wb_pyproto_assert_sha256(x$content_sha256, paste0(where, "$content_sha256"))
  }
  invisible(TRUE)
}

.wb_pyproto_validate_capability <- function(cap, where = "request$execution_capability") {
  .wb_assert(is.list(cap), paste0(where, " must be an object"))
  for (nm in c("capability_id", "mode", "session_id", "run_id")) {
    .wb_pyproto_assert_scalar_chr(as.character(cap[[nm]] %||% ""), paste0(where, "$", nm))
  }
  mode <- as.character(cap$mode)[1]
  .wb_assert(mode %in% c("read_only", "staging_write"), paste0(where, "$mode is unsupported"))
  source <- cap$source_attestation %||% list()
  .wb_assert(identical(as.character(source$scheme %||% "")[1], "scworkbench-scientific-state-v1"),
             paste0(where, "$source_attestation$scheme is unsupported"))
  .wb_pyproto_assert_sha256(source$content_sha256, paste0(where, "$source_attestation$content_sha256"))
  stage <- cap$staging_identity %||% list()
  .wb_pyproto_assert_sha256(stage$root_sha256, paste0(where, "$staging_identity$root_sha256"))
  .wb_pyproto_assert_scalar_chr(as.character(stage$checkpoint_generation %||% ""), paste0(where, "$staging_identity$checkpoint_generation"))
  allow <- cap$write_allowlist %||% list()
  .wb_assert(is.list(allow), paste0(where, "$write_allowlist must be an array"))
  if (identical(mode, "read_only")) {
    .wb_assert(length(allow) == 0L, "PYBENCH_CAPABILITY_MISMATCH: read_only capability must have an empty write allowlist")
  } else {
    .wb_assert(length(allow) > 0L, "PYBENCH_CAPABILITY_MISMATCH: staging_write capability requires an output-bound write allowlist")
  }
  for (i in seq_along(allow)) .wb_pyproto_validate_allowance(allow[[i]], paste0(where, "$write_allowlist[[", i, "]]"))
  invisible(TRUE)
}

.wb_pyproto_validate_output_specs <- function(outputs, where = "request$outputs") {
  .wb_assert(is.list(outputs), paste0(where, " must be a named list"))
  if (!length(outputs)) return(invisible(TRUE))
  .wb_assert(!is.null(names(outputs)) && all(nzchar(names(outputs))), paste0(where, " must be a named list"))
  for (nm in names(outputs)) {
    spec <- outputs[[nm]]
    .wb_assert(is.list(spec), paste0(where, "$", nm, " must be a list"))
    .wb_pyproto_assert_scalar_chr(as.character(spec$artifact_id %||% ""), paste0(where, "$", nm, "$artifact_id"))
    .wb_pyproto_assert_scalar_chr(as.character(spec$type %||% ""), paste0(where, "$", nm, "$type"))
  }
  invisible(TRUE)
}

# Validate a pybench-op-v2 request payload (internal helper).
.wb_pyproto_validate_request <- function(req) {
  .wb_assert(is.list(req), "pybench request must be a list")
  .wb_pyproto_assert_scalar_chr(as.character(req$protocol_version %||% ""), "request$protocol_version")
  .wb_assert(identical(as.character(req$protocol_version), .wb_pyproto_version()),
             paste0("Unsupported pybench protocol version: ", as.character(req$protocol_version)))

  .wb_assert(identical(as.character(req$message_type %||% "")[1], "request"), "request$message_type must be 'request'")
  .wb_pyproto_assert_scalar_chr(as.character(req$bundle_dir %||% ""), "request$bundle_dir")
  .wb_pyproto_assert_scalar_chr(as.character(req$op_name %||% ""), "request$op_name")
  path_contract <- req$path_contract %||% list()
  .wb_assert(is.list(path_contract), "request$path_contract must be a list")
  expected_contract <- .wb_pyproto_path_contract()
  for (field in names(expected_contract)) {
    .wb_assert(identical(as.character(path_contract[[field]] %||% ""), as.character(expected_contract[[field]])),
               paste0("request$path_contract$", field, " does not match the engine containment contract"))
  }

  run <- req$run %||% list()
  .wb_assert(is.list(run), "request$run must be a list")
  .wb_pyproto_assert_scalar_chr(as.character(run$session_id %||% ""), "request$run$session_id")
  .wb_pyproto_assert_scalar_chr(as.character(run$run_id %||% ""), "request$run$run_id")
  cap <- req$execution_capability %||% list()
  .wb_pyproto_validate_capability(cap)
  .wb_assert(identical(as.character(run$session_id)[1], as.character(cap$session_id)[1]) &&
               identical(as.character(run$run_id)[1], as.character(cap$run_id)[1]),
             "PYBENCH_CAPABILITY_MISMATCH: run identity does not match execution capability")

  .wb_assert(is.list(req$inputs), "request$inputs must be a list")
  .wb_assert(is.list(req$params), "request$params must be a list")

  .wb_pyproto_validate_output_specs(req$outputs, where = "request$outputs")
  allow <- cap$write_allowlist %||% list()
  if (length(allow)) for (i in seq_along(allow)) {
    d <- allow[[i]]
    nm <- as.character(d$output_name)[1]
    .wb_assert(nm %in% names(req$outputs), "PYBENCH_CAPABILITY_MISMATCH: allowance names an unknown output")
    spec <- req$outputs[[nm]]
    .wb_assert(identical(as.character(d$output_id)[1], as.character(spec$artifact_id)[1]) &&
                 identical(as.character(d$output_kind)[1], as.character(spec$type)[1]),
               "PYBENCH_CAPABILITY_MISMATCH: allowance output identity/kind does not match request")
    if (identical(as.character(d$mutation_class)[1], "sqlite_rows")) {
      .wb_assert(identical(as.character(d$key_scope$values), as.character(d$output_id)),
                 "PYBENCH_CAPABILITY_MISMATCH: SQLite key scope must bind exactly the requested output ID")
    }
  }
  invisible(TRUE)
}

# Validate a pybench-op-v2 receipt payload (internal helper).
.wb_pyproto_validate_receipt <- function(receipt, request = NULL) {
  .wb_assert(is.list(receipt), "pybench receipt must be a list")
  .wb_pyproto_assert_scalar_chr(as.character(receipt$protocol_version %||% ""), "receipt$protocol_version")
  .wb_assert(identical(as.character(receipt$protocol_version), .wb_pyproto_version()),
             paste0("Unsupported pybench protocol version in receipt: ", as.character(receipt$protocol_version)))

  .wb_assert(identical(as.character(receipt$message_type %||% "")[1], "receipt"), "receipt$message_type must be 'receipt'")
  .wb_pyproto_assert_scalar_chr(as.character(receipt$status %||% ""), "receipt$status")
  .wb_assert(as.character(receipt$status) %in% c("ok", "error"),
             "receipt$status must be 'ok' or 'error'")
  .wb_pyproto_assert_scalar_chr(as.character(receipt$op_name %||% ""), "receipt$op_name")
  .wb_pyproto_assert_scalar_chr(as.character(receipt$run_id %||% ""), "receipt$run_id")
  .wb_pyproto_validate_capability(receipt$capability_echo %||% list(), "receipt$capability_echo")

  if (!is.null(request)) {
    .wb_pyproto_validate_request(request)
    .wb_assert(identical(.wb_prov_sha256_object(receipt$capability_echo),
                         .wb_prov_sha256_object(request$execution_capability)),
               "PYBENCH_CAPABILITY_MISMATCH: receipt capability echo differs from request")
    .wb_assert(identical(as.character(receipt$op_name)[1], as.character(request$op_name)[1]) &&
                 identical(as.character(receipt$run_id)[1], as.character(request$run$run_id)[1]),
               "PYBENCH_RECEIPT_MISMATCH: receipt operation/run binding differs from request")
  }

  if (identical(as.character(receipt$status), "ok")) {
    .wb_assert(is.list(receipt$outputs), "receipt$outputs must be a named list for status='ok'")
    manifest <- receipt$write_manifest %||% list()
    .wb_assert(is.list(manifest), "receipt$write_manifest must be an array")
    for (i in seq_along(manifest)) .wb_pyproto_validate_allowance(manifest[[i]], paste0("receipt$write_manifest[[", i, "]]"), receipt = TRUE)
    if (!is.null(request)) {
      req_outs <- request$outputs %||% list()
      rec_outs <- receipt$outputs %||% list()
      .wb_assert(all(names(rec_outs) %in% names(req_outs)),
                 "receipt$outputs contains unknown output name(s) not present in request")
      for (nm in names(rec_outs)) {
        rec <- rec_outs[[nm]]
        req <- req_outs[[nm]]
        .wb_assert(is.list(rec), paste0("receipt$outputs$", nm, " must be a list"))
        .wb_pyproto_assert_scalar_chr(as.character(rec$artifact_id %||% ""), paste0("receipt$outputs$", nm, "$artifact_id"))
        .wb_pyproto_assert_scalar_chr(as.character(rec$type %||% ""), paste0("receipt$outputs$", nm, "$type"))
        .wb_assert(identical(as.character(rec$artifact_id), as.character(req$artifact_id)),
                   paste0("receipt output artifact_id mismatch for output '", nm, "'"))
        .wb_assert(identical(as.character(rec$type), as.character(req$type)),
                   paste0("receipt output type mismatch for output '", nm, "'"))
      }
      requested <- request$execution_capability$write_allowlist %||% list()
      for (reported in manifest) {
        hit <- vapply(requested, function(allowed) {
          same <- identical(as.character(reported$output_name), as.character(allowed$output_name)) &&
            identical(as.character(reported$output_id), as.character(allowed$output_id)) &&
            identical(as.character(reported$output_kind), as.character(allowed$output_kind)) &&
            identical(as.character(reported$mutation_class), as.character(allowed$mutation_class))
          if (!same) return(FALSE)
          if (identical(as.character(allowed$mutation_class), "sqlite_rows")) {
            return(identical(.wb_pyproto_descriptor_key(reported), .wb_pyproto_descriptor_key(allowed)))
          }
          rel <- as.character(reported$path)[1]; prefix <- as.character(allowed$path)[1]
          identical(rel, prefix) || startsWith(rel, paste0(prefix, "/")) ||
            (identical(dirname(rel), dirname(prefix)) && startsWith(basename(rel), basename(prefix)))
        }, logical(1))
        .wb_assert(sum(hit) == 1L, "PYBENCH_RECEIPT_MISMATCH: write manifest contains an unrequested or ambiguous descriptor")
      }
    }
  } else {
    .wb_pyproto_assert_scalar_chr(as.character(receipt$error_class %||% ""), "receipt$error_class")
    .wb_pyproto_assert_scalar_chr(as.character(receipt$message %||% ""), "receipt$message")
  }

  invisible(TRUE)
}

.wb_pyproto_descriptor_key <- function(x) {
  paste(as.character(x$output_name), as.character(x$output_id), as.character(x$output_kind),
        as.character(x$mutation_class), as.character(x$table %||% ""),
        as.character(x$path %||% ""), as.character((x$key_scope %||% list())$column %||% ""),
        paste(sort(as.character((x$key_scope %||% list())$values %||% character())), collapse = ","), sep = "\r")
}

.wb_pyproto_write_request_json <- function(path, request) {
  .wb_pyproto_validate_request(request)
  jsonlite::write_json(request, path, auto_unbox = TRUE, pretty = TRUE, null = "null")
  invisible(normalizePath(path, winslash = "/", mustWork = TRUE))
}

.wb_pyproto_read_receipt_json <- function(path, request = NULL) {
  .wb_assert(file.exists(path), paste0("Receipt JSON not found: ", path))
  rec <- jsonlite::read_json(path, simplifyVector = FALSE)
  .wb_pyproto_validate_receipt(rec, request = request)
  rec
}
