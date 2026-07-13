# pybench op protocol helpers (request/receipt validation + JSON IO)

.wb_pyproto_version <- function() "pybench-op-v1"

.wb_pyproto_assert_scalar_chr <- function(x, name) {
  .wb_assert(is.character(x) && length(x) == 1L && nzchar(x),
             paste0(name, " must be a length-1 non-empty string"))
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

# Validate a pybench-op-v1 request payload (internal helper).
.wb_pyproto_validate_request <- function(req) {
  .wb_assert(is.list(req), "pybench request must be a list")
  .wb_pyproto_assert_scalar_chr(as.character(req$protocol_version %||% ""), "request$protocol_version")
  .wb_assert(identical(as.character(req$protocol_version), .wb_pyproto_version()),
             paste0("Unsupported pybench protocol version: ", as.character(req$protocol_version)))

  .wb_pyproto_assert_scalar_chr(as.character(req$bundle_dir %||% ""), "request$bundle_dir")
  .wb_pyproto_assert_scalar_chr(as.character(req$op_name %||% ""), "request$op_name")

  run <- req$run %||% list()
  .wb_assert(is.list(run), "request$run must be a list")
  .wb_pyproto_assert_scalar_chr(as.character(run$run_id %||% ""), "request$run$run_id")

  .wb_assert(is.list(req$inputs), "request$inputs must be a list")
  .wb_assert(is.list(req$params), "request$params must be a list")

  .wb_pyproto_validate_output_specs(req$outputs, where = "request$outputs")
  invisible(TRUE)
}

# Validate a pybench-op-v1 receipt payload (internal helper).
.wb_pyproto_validate_receipt <- function(receipt, request = NULL) {
  .wb_assert(is.list(receipt), "pybench receipt must be a list")
  .wb_pyproto_assert_scalar_chr(as.character(receipt$protocol_version %||% ""), "receipt$protocol_version")
  .wb_assert(identical(as.character(receipt$protocol_version), .wb_pyproto_version()),
             paste0("Unsupported pybench protocol version in receipt: ", as.character(receipt$protocol_version)))

  .wb_pyproto_assert_scalar_chr(as.character(receipt$status %||% ""), "receipt$status")
  .wb_assert(as.character(receipt$status) %in% c("ok", "error"),
             "receipt$status must be 'ok' or 'error'")
  .wb_pyproto_assert_scalar_chr(as.character(receipt$op_name %||% ""), "receipt$op_name")
  .wb_pyproto_assert_scalar_chr(as.character(receipt$run_id %||% ""), "receipt$run_id")

  if (identical(as.character(receipt$status), "ok")) {
    .wb_assert(is.list(receipt$outputs), "receipt$outputs must be a named list for status='ok'")
    if (!is.null(request)) {
      .wb_pyproto_validate_request(request)
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
    }
  } else {
    .wb_pyproto_assert_scalar_chr(as.character(receipt$error_class %||% ""), "receipt$error_class")
    .wb_pyproto_assert_scalar_chr(as.character(receipt$message %||% ""), "receipt$message")
  }

  invisible(TRUE)
}

.wb_pyproto_write_request_json <- function(path, request) {
  .wb_pyproto_validate_request(request)
  jsonlite::write_json(request, path, auto_unbox = TRUE, pretty = TRUE, null = "null")
  invisible(normalizePath(path, winslash = "/", mustWork = TRUE))
}

.wb_pyproto_read_receipt_json <- function(path, request = NULL) {
  .wb_assert(file.exists(path), paste0("Receipt JSON not found: ", path))
  rec <- jsonlite::read_json(path, simplifyVector = TRUE)
  .wb_pyproto_validate_receipt(rec, request = request)
  rec
}
