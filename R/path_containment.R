# Canonical bundle path containment and payload trust boundary.

.wb_bundle_path_contract_version <- function() "scworkbench-bundle-path-v1"

.wb_path_is_absolute <- function(path) {
  path <- as.character(path %||% "")[1]
  if (is.na(path) || !nzchar(path)) return(FALSE)
  grepl("^(/|[A-Za-z]:[/\\\\]|\\\\\\\\)", path)
}

.wb_path_inside <- function(path, root) {
  identical(path, root) || startsWith(path, paste0(root, "/"))
}

.wb_path_status <- function(root, path,
                            expected_type = c("either", "file", "directory"),
                            must_exist = TRUE,
                            purpose = "durable portable payload",
                            external = c("reject", "declare"),
                            inspect_external = FALSE) {
  expected_type <- match.arg(expected_type)
  external <- match.arg(external)
  raw <- as.character(path %||% "")[1]
  fail <- function(code, observed, resolved = raw, portable = FALSE,
                   trust = "untrusted") {
    list(ok = FALSE, code = code, path = raw, relative = NA_character_,
         absolute = resolved, observed = observed, exists = FALSE,
         portable = portable, external = !portable, trust = trust,
         contract_version = .wb_bundle_path_contract_version(), purpose = purpose)
  }
  if (is.na(raw) || !nzchar(raw)) {
    return(fail("PATH_EMPTY", "empty"))
  }

  root_abs <- normalizePath(root, winslash = "/", mustWork = TRUE)
  normalized_raw <- gsub("\\\\", "/", raw)
  if (.wb_path_is_absolute(normalized_raw)) {
    if (identical(external, "reject")) return(fail("PATH_ABSOLUTE", "absolute"))
    resolved <- if (isTRUE(inspect_external)) {
      normalizePath(normalized_raw, winslash = "/", mustWork = FALSE)
    } else normalized_raw
    present <- isTRUE(inspect_external) && (file.exists(resolved) || dir.exists(resolved))
    return(list(ok = TRUE, code = "LEGACY_EXTERNAL_NONPORTABLE", path = raw,
                relative = NA_character_, absolute = resolved,
                observed = "declared external path", exists = present,
                portable = FALSE, external = TRUE, trust = "untrusted_external",
                contract_version = .wb_bundle_path_contract_version(), purpose = purpose))
  }

  parts <- strsplit(normalized_raw, "/", fixed = TRUE)[[1]]
  if (any(parts == "..")) return(fail("PATH_ESCAPE", "parent traversal"))
  parts <- parts[nzchar(parts) & parts != "."]
  if (!length(parts)) return(fail("PATH_EMPTY", "empty normalized path"))
  relative <- paste(parts, collapse = "/")
  candidate <- file.path(root_abs, relative)

  # Resolve every existing ancestor. This catches a symlink escape even when
  # the final payload is missing and normalizePath(mustWork=FALSE) cannot.
  current <- root_abs
  for (part in parts) {
    current <- file.path(current, part)
    link_target <- Sys.readlink(current)
    is_link <- !is.na(link_target) && nzchar(link_target)
    if (is_link || file.exists(current) || dir.exists(current)) {
      resolved_part <- normalizePath(current, winslash = "/", mustWork = TRUE)
      if (!.wb_path_inside(resolved_part, root_abs)) {
        return(fail("PATH_SYMLINK_ESCAPE", "outside bundle through symlink",
                    resolved = resolved_part))
      }
      current <- resolved_part
    }
  }

  present <- file.exists(candidate) || dir.exists(candidate)
  if (isTRUE(must_exist) && !present) {
    out <- fail("PAYLOAD_MISSING", "missing", resolved = candidate, portable = TRUE,
                trust = "contained_missing")
    out$external <- FALSE
    out$relative <- relative
    return(out)
  }
  resolved <- if (present) normalizePath(candidate, winslash = "/", mustWork = TRUE) else candidate
  if (!.wb_path_inside(resolved, root_abs)) {
    return(fail("PATH_SYMLINK_ESCAPE", "outside bundle", resolved = resolved))
  }
  actual <- if (!present) "missing" else if (dir.exists(candidate)) "directory" else "file"
  if (present && !identical(expected_type, "either") && !identical(actual, expected_type)) {
    out <- fail("PATH_TYPE_MISMATCH", actual, resolved = resolved, portable = TRUE,
                trust = "contained_type_mismatch")
    out$external <- FALSE
    out$relative <- relative
    out$exists <- TRUE
    return(out)
  }
  list(ok = TRUE, code = "OK", path = raw, relative = relative,
       absolute = resolved, observed = actual, exists = present,
       portable = TRUE, external = FALSE, trust = "contained",
       contract_version = .wb_bundle_path_contract_version(), purpose = purpose)
}

.wb_bundle_path_status <- function(bundle_or_dir, path,
                                   expected_type = c("either", "file", "directory"),
                                   must_exist = TRUE,
                                   purpose = "durable portable payload") {
  root <- if (inherits(bundle_or_dir, "scworkbench_bundle")) bundle_or_dir$dir else bundle_or_dir
  status <- .wb_path_status(root, path, expected_type = match.arg(expected_type),
                            must_exist = must_exist, purpose = purpose)
  if (!isTRUE(status$ok) && identical(status$code, "PATH_SYMLINK_ESCAPE") &&
      inherits(bundle_or_dir, "scworkbench_bundle") &&
      nzchar(as.character(bundle_or_dir$staging_source_dir %||% "")[1]) &&
      !.wb_path_is_absolute(path)) {
    # Session overlays deliberately symlink immutable leaves to their one
    # recorded source bundle. That transient engine view may read only that
    # exact source; it can never turn the link into durable state.
    source_root <- normalizePath(bundle_or_dir$staging_source_dir, winslash = "/", mustWork = TRUE)
    source_status <- .wb_path_status(
      source_root, path, expected_type = match.arg(expected_type),
      must_exist = must_exist, purpose = purpose
    )
    resolved <- normalizePath(file.path(bundle_or_dir$dir, path), winslash = "/", mustWork = FALSE)
    if (isTRUE(source_status$ok) && identical(resolved, source_status$absolute)) {
      source_status$code <- "OK_TRANSIENT_TRUSTED_OVERLAY"
      source_status$trust <- "trusted_staging_overlay"
      source_status$portable <- TRUE
      return(source_status)
    }
  }
  status
}

.wb_bundle_path_require <- function(bundle_or_dir, path,
                                    expected_type = c("either", "file", "directory"),
                                    must_exist = TRUE,
                                    purpose = "durable portable payload") {
  status <- .wb_bundle_path_status(
    bundle_or_dir, path, expected_type = match.arg(expected_type),
    must_exist = must_exist, purpose = purpose
  )
  if (!isTRUE(status$ok)) {
    stop(status$code, ": invalid ", purpose, " path '", as.character(path)[1],
         "' (", status$observed, ").", call. = FALSE)
  }
  status$absolute
}

.wb_path_tree_status <- function(root, path, purpose = "durable payload tree") {
  status <- .wb_path_status(root, path, expected_type = "directory",
                            must_exist = TRUE, purpose = purpose)
  if (!isTRUE(status$ok)) return(status)
  entries <- as.character(fs::dir_ls(status$absolute, recurse = TRUE,
                                     type = "any", all = TRUE, follow = FALSE))
  if (!length(entries)) return(status)
  root_abs <- normalizePath(root, winslash = "/", mustWork = TRUE)
  for (entry in entries) {
    target <- Sys.readlink(entry)
    if (is.na(target) || !nzchar(target)) next
    resolved <- if (.wb_path_is_absolute(target)) target else file.path(dirname(entry), target)
    resolved <- normalizePath(resolved, winslash = "/", mustWork = FALSE)
    if (!.wb_path_inside(resolved, root_abs)) {
      status$ok <- FALSE
      status$code <- "PATH_SYMLINK_ESCAPE"
      status$absolute <- resolved
      status$observed <- "payload tree symlink resolves outside bundle"
      status$trust <- "untrusted"
      return(status)
    }
  }
  status
}

#' Inspect a path against the portable bundle containment contract
#'
#' This function performs lexical traversal checks and resolves existing
#' symlink ancestors without opening or deserializing the payload.
#'
#' @param bundle_or_dir Open bundle or bundle directory.
#' @param path Bundle-relative durable path.
#' @param expected_type Expected payload type.
#' @param must_exist Whether absence is an error.
#' @return A structured containment and trust status.
#' @export
wb_bundle_path_status <- function(bundle_or_dir, path,
                                  expected_type = c("either", "file", "directory"),
                                  must_exist = TRUE) {
  .wb_bundle_path_status(bundle_or_dir, path, expected_type = match.arg(expected_type),
                         must_exist = must_exist)
}

.wb_model_deserialization_status <- function(bundle, model_path,
                                             provenance_bound = FALSE,
                                             trusted_runtime = FALSE) {
  contained <- .wb_path_status(bundle$dir, model_path, expected_type = "either",
                               must_exist = TRUE, purpose = "serialized model payload")
  if (!isTRUE(contained$ok)) {
    resolved <- tryCatch(.wb_bundle_path_require(bundle,model_path,expected_type="either",must_exist=TRUE,purpose="serialized model payload"),error=function(e) "")
    if (nzchar(resolved)) contained <- list(ok=TRUE,code="OK_TRANSIENT_TRUSTED_OVERLAY",absolute=resolved,relative=as.character(model_path)[1],portable=FALSE,external=FALSE,trust="trusted_staging_overlay")
  }
  trusted <- isTRUE(contained$ok) && (isTRUE(provenance_bound) || isTRUE(trusted_runtime))
  list(
    containment = contained,
    deserialization_allowed = trusted,
    trust = if (!isTRUE(contained$ok)) "path_untrusted" else if (trusted) "trusted_provenance_or_runtime" else "explicit_opt_in_required",
    executable_payload_loaded = FALSE
  )
}
