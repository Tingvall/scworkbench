# Canonical source-input declarations and mutation-free preflight.

.wb_source_scopes <- function() c("public_file", "external_file", "in_memory", "internal_assembly")

.wb_source_nonempty <- function(x) {
  length(x) == 1L && !is.na(x) && nzchar(trimws(as.character(x)))
}

#' Stream a local file SHA-256 identity
#'
#' Hashes bytes directly from disk without materializing the file in R memory.
#'
#' @param path Existing local file.
#' @return Lower-case 64-character SHA-256 string.
#' @export
wb_source_sha256 <- function(path) {
  .wb_assert(is.character(path) && length(path) == 1L && !is.na(path) && nzchar(path),
             "path must be one non-empty local file path")
  .wb_assert(file.exists(path) && !dir.exists(path), paste0("source file does not exist: ", path))
  tolower(as.character(digest::digest(file = path, algo = "sha256", serialize = FALSE)))
}

.wb_source_checksum <- function(input, diagnostics, index) {
  sha <- as.character(input$sha256 %||% "")[1]
  checksum <- as.character(input$checksum %||% "")[1]
  if (is.na(sha)) sha <- ""
  if (is.na(checksum)) checksum <- ""
  if (nzchar(sha) && nzchar(checksum) && !identical(tolower(sha), tolower(checksum))) {
    diagnostics[[length(diagnostics) + 1L]] <- list("SOURCE_CHECKSUM_ALIASES_CONFLICT", index, "sha256/checksum", "Checksum aliases disagree.")
  }
  value <- if (nzchar(sha)) sha else checksum
  algorithm <- tolower(as.character(input$checksum_algorithm %||% if (nzchar(value)) "sha256" else "")[1])
  list(value = tolower(value), algorithm = algorithm, diagnostics = diagnostics)
}

.wb_source_uri_diagnostic <- function(uri, accession, accession_derived) {
  if (!.wb_source_nonempty(uri)) return(NULL)
  uri <- as.character(uri)[1]
  match <- regexec("^([A-Za-z][A-Za-z0-9+.-]*):/{2}([^/]+)(/.*)?$", uri)
  parts <- regmatches(uri, match)[[1]]
  if (!length(parts) || !nzchar(parts[3])) return("URI must contain a valid scheme and non-empty authority.")
  path <- parts[4] %||% ""
  if ((grepl("{", path, fixed = TRUE) && grepl("}", path, fixed = TRUE)) ||
      (grepl("<", path, fixed = TRUE) && grepl(">", path, fixed = TRUE))) {
    return("URI contains an unresolved placeholder.")
  }
  if (grepl("//", substring(path, 2L), fixed = TRUE)) return("URI contains an empty interpolated path component.")
  if (isTRUE(accession_derived) && .wb_source_nonempty(accession)) {
    components <- strsplit(path, "/", fixed = TRUE)[[1]]
    if (!as.character(accession)[1] %in% components) return("Accession-derived URI does not contain the declared accession as a path component.")
  }
  NULL
}

.wb_source_diag_df <- function(items) {
  if (!length(items)) return(data.frame(code=character(), input_index=integer(), field=character(), message=character(), stringsAsFactors=FALSE))
  out <- do.call(rbind, lapply(items, function(x) data.frame(code=x[[1]], input_index=as.integer(x[[2]]), field=x[[3]], message=x[[4]], stringsAsFactors=FALSE)))
  rownames(out) <- NULL
  out
}

.wb_source_identity_preflight <- function(source_identity, verify_files = TRUE) {
  diagnostics <- list()
  if (is.null(source_identity)) return(list(valid=TRUE, normalized=NULL, diagnostics=.wb_source_diag_df(diagnostics)))
  if (!is.list(source_identity) || is.null(names(source_identity)) || any(!nzchar(names(source_identity)))) {
    diagnostics[[1L]] <- list("SOURCE_IDENTITY_NOT_NAMED", 0L, "source_identity", "source_identity must be a named list.")
    return(list(valid=FALSE, normalized=source_identity, diagnostics=.wb_source_diag_df(diagnostics)))
  }
  has_inputs <- !is.null(source_identity$inputs)
  inputs <- source_identity$inputs %||% list()
  if (!is.list(inputs)) {
    diagnostics[[1L]] <- list("SOURCE_INPUTS_NOT_LIST", 0L, "inputs", "source_identity$inputs must be a list.")
    return(list(valid=FALSE, normalized=source_identity, diagnostics=.wb_source_diag_df(diagnostics)))
  }
  if (!has_inputs) return(list(valid=TRUE, normalized=source_identity, diagnostics=.wb_source_diag_df(diagnostics)))
  normalized <- source_identity
  explicit_v2 <- !is.null(source_identity$schema) || any(vapply(inputs,function(x) is.list(x) && (!is.null(x$scope) || !is.null(x$source_scope)),logical(1)))
  if (explicit_v2) normalized$schema <- as.character(source_identity$schema %||% "scworkbench.source_identity.v2")[1]
  normalized$inputs <- vector("list", length(inputs))
  ids <- character(length(inputs))
  for (i in seq_along(inputs)) {
    x <- inputs[[i]]
    if (!is.list(x) || is.null(names(x))) {
      diagnostics[[length(diagnostics)+1L]] <- list("SOURCE_INPUT_NOT_NAMED", i, "input", "Source input must be a named list.")
      next
    }
    scope <- as.character(x$scope %||% x$source_scope %||% "legacy_external")[1]
    if (!scope %in% c(.wb_source_scopes(), "legacy_external")) diagnostics[[length(diagnostics)+1L]] <- list("SOURCE_SCOPE_UNSUPPORTED", i, "scope", "Unsupported source scope.")
    id <- trimws(as.character(x$source_id %||% "")[1]); ids[i] <- id
    file_scope <- scope %in% c("public_file", "external_file")
    required <- if (identical(scope, "public_file")) c("source_id", "accession", "role", "format") else if (file_scope || identical(scope, "in_memory")) c("source_id", "role", "format") else character()
    if (isTRUE(x$accession_derived) && !"accession" %in% required) required <- c(required, "accession")
    for (field in required) if (!.wb_source_nonempty(x[[field]])) diagnostics[[length(diagnostics)+1L]] <- list(paste0("SOURCE_", toupper(field), "_MISSING"), i, field, paste0("Strict ", scope, " declarations require ", field, "."))
    path <- as.character(x$path %||% x$local_path %||% "")[1]
    uri <- as.character(x$uri %||% "")[1]
    if (file_scope && !nzchar(path) && !nzchar(uri)) diagnostics[[length(diagnostics)+1L]] <- list("SOURCE_LOCATION_MISSING", i, "path/uri", "Strict file declarations require a local path or URI.")
    check <- .wb_source_checksum(x, diagnostics, i); diagnostics <- check$diagnostics
    if (file_scope && !nzchar(check$value)) diagnostics[[length(diagnostics)+1L]] <- list("SOURCE_SHA256_MISSING", i, "sha256", "Strict file declarations require SHA-256 identity.")
    if (nzchar(check$value) && (!identical(check$algorithm, "sha256") || !grepl("^[0-9a-f]{64}$", check$value))) diagnostics[[length(diagnostics)+1L]] <- list("SOURCE_CHECKSUM_MALFORMED", i, "checksum", "Only SHA-256 with exactly 64 hexadecimal characters is supported.")
    if (nzchar(path) && isTRUE(verify_files) && file_scope) {
      if (!file.exists(path) || dir.exists(path)) diagnostics[[length(diagnostics)+1L]] <- list("SOURCE_FILE_MISSING", i, "path", paste0("Declared local source file is missing: ", path))
      else if (grepl("^[0-9a-f]{64}$", check$value) && !identical(wb_source_sha256(path), check$value)) diagnostics[[length(diagnostics)+1L]] <- list("SOURCE_CHECKSUM_MISMATCH", i, "sha256", paste0("Local source file checksum mismatch: ", path))
    }
    bundled <- isTRUE(x$bundled %||% x$bundle_owned %||% FALSE)
    if (bundled && nzchar(path) && grepl("^(?:/|[A-Za-z]:[/\\])", path)) diagnostics[[length(diagnostics)+1L]] <- list("SOURCE_BUNDLED_PATH_CONTRADICTION", i, "bundled/path", "Bundled source paths must be bundle-relative, not absolute ingestion paths.")
    uri_problem <- .wb_source_uri_diagnostic(uri, x$accession %||% "", isTRUE(x$accession_derived %||% FALSE))
    if (!is.null(uri_problem)) diagnostics[[length(diagnostics)+1L]] <- list("SOURCE_URI_MALFORMED", i, "uri", uri_problem)
    y <- x
    y$scope <- scope
    y$source_id <- if (nzchar(id)) id else NULL
    y$path <- if (nzchar(path)) path else NULL
    y$local_path <- NULL
    y$checksum <- if (nzchar(check$value)) check$value else NULL
    y$sha256 <- if (nzchar(check$value)) check$value else NULL
    y$checksum_algorithm <- if (nzchar(check$algorithm)) check$algorithm else NULL
    y$bundled <- bundled
    normalized$inputs[[i]] <- y
  }
  duplicate_ids <- unique(ids[nzchar(ids) & (duplicated(ids) | duplicated(ids, fromLast=TRUE))])
  for (id in duplicate_ids) diagnostics[[length(diagnostics)+1L]] <- list("SOURCE_ID_DUPLICATE", match(id, ids), "source_id", paste0("Duplicate source_id: ", id))
  composition <- normalized$nested_ingestion %||% NULL
  if (!is.null(composition)) {
    schema <- as.character(composition$schema %||% "")[1]
    parent_id <- as.character(composition$authoritative_source_id %||% "")[1]
    child_id <- as.character(composition$conversion_source_id %||% "")[1]
    relation <- as.character(composition$relation %||% "")[1]
    importer <- as.character(composition$importer %||% "")[1]
    if (!identical(schema, "scworkbench.nested_ingestion.v1")) {
      diagnostics[[length(diagnostics)+1L]] <- list("SOURCE_NESTED_SCHEMA_UNSUPPORTED", 0L, "nested_ingestion.schema", "Nested ingestion must use scworkbench.nested_ingestion.v1.")
    }
    if (!identical(relation, "CONVERTS_TO")) {
      diagnostics[[length(diagnostics)+1L]] <- list("SOURCE_NESTED_RELATION_INVALID", 0L, "nested_ingestion.relation", "Nested ingestion must declare the CONVERTS_TO relation.")
    }
    if (!identical(importer, "wb_bundle_from_h5ad")) {
      diagnostics[[length(diagnostics)+1L]] <- list("SOURCE_NESTED_IMPORTER_INVALID", 0L, "nested_ingestion.importer", "The supported nested-ingestion owner is wb_bundle_from_h5ad.")
    }
    parent_at <- match(parent_id, ids)
    child_at <- match(child_id, ids)
    if (is.na(parent_at) || !nzchar(parent_id)) {
      diagnostics[[length(diagnostics)+1L]] <- list("SOURCE_NESTED_PARENT_MISSING", 0L, "nested_ingestion.authoritative_source_id", "Nested ingestion parent must name an input in the same declaration.")
    } else {
      parent_scope <- as.character(normalized$inputs[[parent_at]]$scope %||% "")[1]
      if (!parent_scope %in% c("public_file", "external_file")) {
        diagnostics[[length(diagnostics)+1L]] <- list("SOURCE_NESTED_PARENT_NOT_EXTERNAL", parent_at, "scope", "Nested ingestion parent must be a checksummed public_file or external_file input.")
      }
    }
    if (is.na(child_at) || !nzchar(child_id)) {
      diagnostics[[length(diagnostics)+1L]] <- list("SOURCE_NESTED_CHILD_MISSING", 0L, "nested_ingestion.conversion_source_id", "Nested ingestion child must name an input in the same declaration.")
    } else {
      child <- normalized$inputs[[child_at]]
      if (!identical(as.character(child$scope %||% "")[1], "in_memory") ||
          !identical(as.character(child$parent_source_id %||% "")[1], parent_id) ||
          !identical(as.character(child$source_relation %||% "")[1], relation)) {
        diagnostics[[length(diagnostics)+1L]] <- list("SOURCE_NESTED_CHILD_FORGED", child_at, "parent_source_id/source_relation", "Conversion child must be an in-memory input bound to the declared parent and relation.")
      }
    }
  }
  diag <- .wb_source_diag_df(diagnostics)
  list(valid=!nrow(diag), normalized=normalized, diagnostics=diag)
}

#' Construct a canonical source-input declaration
#'
#' @param path Optional local file path.
#' @param uri Optional declared URI; no network request is made.
#' @param source_id Stable identity within one declaration.
#' @param accession Public archive accession, required for `public_file`. Optional
#'   for an honest local `external_file` declaration; do not invent an accession.
#' @param role Source role in ingestion.
#' @param format File/object format.
#' @param scope Explicit source scope.
#' @param bundled Whether `path` is a bundle-owned relative payload path.
#' @param checksum,sha256 Checksum aliases; disagreement is rejected.
#' @param accession_derived Whether the URI path is derived from `accession`.
#' @return A named scalar list suitable for JSON or one-row data-frame/TSV conversion.
#' @export
wb_source_input <- function(path=NULL, uri=NULL, source_id, accession=NULL, role,
                            format, scope=c("public_file", "external_file", "in_memory", "internal_assembly"),
                            bundled=FALSE, checksum=NULL, sha256=NULL, accession_derived=FALSE) {
  scope <- match.arg(scope)
  computed <- scope %in% c("public_file", "external_file") && is.null(checksum) && is.null(sha256) && .wb_source_nonempty(path) && file.exists(path)
  if (computed) sha256 <- wb_source_sha256(path)
  identity <- list(inputs=list(list(scope=scope, source_id=source_id, accession=accession, role=role, format=format,
                                         path=path, uri=uri, bundled=isTRUE(bundled), checksum=checksum, sha256=sha256,
                                         checksum_algorithm=if (!is.null(checksum)||!is.null(sha256)) "sha256" else NULL,
                                         accession_derived=isTRUE(accession_derived))))
  out <- wb_source_preflight(identity, verify_files=!computed, strict=TRUE)$source_identity$inputs[[1L]]
  out
}

#' Preflight source identity without writing a bundle
#'
#' @param source_identity Named identity with an `inputs` list.
#' @param verify_files Verify declared local files and SHA-256 values.
#' @param strict Stop on diagnostics; otherwise return them.
#' @return Validation result containing normalized declarations and diagnostics.
#' @export
wb_source_preflight <- function(source_identity, verify_files=TRUE, strict=TRUE) {
  result <- .wb_source_identity_preflight(source_identity, verify_files=verify_files)
  out <- list(schema_version="scworkbench.source_preflight.v1", valid=isTRUE(result$valid),
              source_identity=result$normalized, inputs=result$normalized$inputs %||% list(), diagnostics=result$diagnostics)
  if (isTRUE(strict) && !isTRUE(out$valid)) stop(paste(c("Source identity preflight failed before mutation:", paste0(" - ", out$diagnostics$code, ": ", out$diagnostics$message)), collapse="\n"), call.=FALSE)
  out
}
