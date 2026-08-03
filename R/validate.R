# Authoritative, read-only bundle integrity validation.

.wb_validation_levels <- function() c("structural", "content", "recipient")

.wb_validation_empty_diagnostics <- function() {
  data.frame(
    code = character(), severity = character(), check_class = character(),
    entity_kind = character(), entity_id = character(), path = character(),
    table = character(), expected = character(), observed = character(),
    message = character(), stringsAsFactors = FALSE
  )
}

.wb_validation_empty_skipped <- function() {
  data.frame(
    check_class = character(), minimum_level = character(), reason = character(),
    stringsAsFactors = FALSE
  )
}

.wb_validation_value <- function(x) {
  if (is.null(x) || !length(x)) return(NA_character_)
  if (length(x) > 1L) return(paste(as.character(x), collapse = ","))
  as.character(x)[1]
}

.wb_validation_nonempty <- function(x) {
  length(x) == 1L && !is.na(x) && nzchar(as.character(x))
}

.wb_validation_path <- function(root, raw, expected_type = c("either", "file", "directory")) {
  expected_type <- match.arg(expected_type)
  raw <- as.character(raw %||% "")[1]
  if (is.na(raw) || !nzchar(raw)) {
    return(list(ok = FALSE, code = "PATH_EMPTY", absolute = NA_character_, observed = "empty"))
  }
  if (.wb_path_is_absolute(raw)) {
    return(list(ok = FALSE, code = "PATH_ABSOLUTE", absolute = raw, observed = "absolute"))
  }
  parts <- strsplit(gsub("\\\\", "/", raw), "/", fixed = TRUE)[[1]]
  if (any(parts == "..")) {
    return(list(ok = FALSE, code = "PATH_ESCAPE", absolute = raw, observed = "parent traversal"))
  }
  root_abs <- normalizePath(root, winslash = "/", mustWork = TRUE)
  candidate <- file.path(root_abs, raw)
  if (!file.exists(candidate) && !dir.exists(candidate)) {
    return(list(ok = FALSE, code = "PAYLOAD_MISSING", absolute = candidate, observed = "missing"))
  }
  resolved <- normalizePath(candidate, winslash = "/", mustWork = TRUE)
  prefix <- paste0(root_abs, "/")
  if (!identical(resolved, root_abs) && !startsWith(resolved, prefix)) {
    return(list(ok = FALSE, code = "PATH_SYMLINK_ESCAPE", absolute = resolved, observed = "outside bundle"))
  }
  actual <- if (dir.exists(candidate)) "directory" else "file"
  if (!identical(expected_type, "either") && !identical(actual, expected_type)) {
    return(list(ok = FALSE, code = "PATH_TYPE_MISMATCH", absolute = resolved, observed = actual))
  }
  list(ok = TRUE, code = "OK", absolute = resolved, observed = actual)
}

.wb_validation_json <- function(x) {
  tryCatch(jsonlite::fromJSON(as.character(x)[1], simplifyVector = FALSE), error = function(e) NULL)
}

.wb_validation_artifact_payload_table <- function(type) {
  switch(as.character(type)[1],
    cell_vector = "artifact_labels",
    cell_vector_family = "artifact_pseudotime",
    relation_family = "artifact_relation_rows",
    path_2d_family = "artifact_curves_2d",
    space_path_family = "artifact_space_path_rows",
    space_2d = "artifact_space_2d",
    model_ref = "artifact_model_ref",
    feature_table = "artifact_tables",
    obs_table = "artifact_tables",
    NA_character_
  )
}

#' Produce a structured bundle-integrity validation report
#'
#' Validation is cumulative. `structural` proves that the manifest and supported
#' SQLite schema can be opened without mutation, required registries exist, their
#' references are well formed, registry counts agree, and durable paths are
#' contained and have the expected type. It does not read matrix identities,
#' hash payload bytes, or prove provenance content identity.
#'
#' `content` additionally runs SQLite integrity checking; verifies exact ordered
#' matrix cell/feature identities and fragment coverage; checks spaces, models,
#' artifact payload rows, source declarations, provenance runs/edges/bindings,
#' commits, registry mutations, materializations, lifecycle history, and recorded
#' SHA-256 identities. External sources not declared as bundled and unavailable
#' locally are reported as unverifiable warnings, not corruption.
#'
#' `recipient` adds finalized-transfer invariants: no active writer, SQLite
#' WAL/SHM/journal sidecars, pending publication or commit, and an immutable
#' SQLite connection. It fingerprints the bundle before and after validation and
#' fails if validation changed it.
#'
#' The default is `content`: measurements on the package's tiny fixture and the
#' three published use-case shapes showed acceptable read-only cost, while the
#' historical validator already opened every matrix payload. Callers needing a
#' registry-only preflight can explicitly request `structural`; finalized copies
#' should explicitly request `recipient`.
#'
#' @param bundle_dir Path to the bundle directory (not an open bundle handle).
#' @param level Cumulative validation level.
#' @return A deterministic named report containing status, stable diagnostics,
#'   skipped checks, and elapsed time by check class.
#' @export
wb_bundle_validation_report <- function(bundle_dir,
                                        level = c("content", "structural", "recipient")) {
  level <- match.arg(level)
  if (!is.character(bundle_dir) || length(bundle_dir) != 1L || is.na(bundle_dir) || !nzchar(bundle_dir)) {
    stop("wb_bundle_validation_report(): bundle_dir must be one non-empty path string; pass bundle$dir, not an open scworkbench_bundle handle.", call. = FALSE)
  }
  started <- Sys.time()
  gc_before <- suppressWarnings(gc(reset = TRUE))
  diagnostics <- .wb_validation_empty_diagnostics()
  skipped <- .wb_validation_empty_skipped()
  timings <- data.frame(check_class = character(), elapsed_seconds = numeric(), stringsAsFactors = FALSE)
  add <- function(code, severity = "error", check_class = "structural",
                  entity_kind = NA_character_, entity_id = NA_character_, path = NA_character_,
                  table = NA_character_, expected = NA_character_, observed = NA_character_, message = code) {
    diagnostics[nrow(diagnostics) + 1L, ] <<- list(
      as.character(code), as.character(severity), as.character(check_class),
      .wb_validation_value(entity_kind), .wb_validation_value(entity_id), .wb_validation_value(path),
      .wb_validation_value(table), .wb_validation_value(expected), .wb_validation_value(observed),
      as.character(message)[1]
    )
    invisible(FALSE)
  }
  skip <- function(check_class, minimum_level, reason) {
    skipped[nrow(skipped) + 1L, ] <<- list(check_class, minimum_level, reason)
  }
  timed <- function(check_class, code) {
    t0 <- proc.time()[["elapsed"]]
    force(code)
    timings[nrow(timings) + 1L, ] <<- list(check_class, proc.time()[["elapsed"]] - t0)
    invisible(TRUE)
  }
  requested_index <- match(level, .wb_validation_levels())
  has_level <- function(x) requested_index >= match(x, .wb_validation_levels())
  root <- normalizePath(bundle_dir, winslash = "/", mustWork = FALSE)

  fingerprint <- function() {
    if (!dir.exists(root)) return(NA_character_)
    files <- sort(list.files(root, recursive = TRUE, full.names = TRUE, all.files = TRUE, no.. = TRUE))
    files <- files[!dir.exists(files)]
    info <- file.info(files)
    .wb_prov_sha256_object(list(
      paths = substring(files, nchar(root) + 2L),
      size = as.numeric(info$size), mode = as.character(info$mode),
      sha256 = vapply(files,.wb_prov_sha256_file,character(1))
    ))
  }
  before_fingerprint <- if (has_level("recipient")) fingerprint() else NA_character_
  manifest <- NULL
  con <- NULL
  bundle <- NULL
  manifest_version <- NA_character_

  timed("bundle_layout", {
    if (!dir.exists(root)) {
      add("BUNDLE_DIRECTORY_MISSING", path = root, observed = "missing", message = "Bundle directory does not exist.")
    } else {
      manifest_path <- file.path(root, "manifest.json")
      if (!file.exists(manifest_path)) {
        add("MANIFEST_MISSING", path = "manifest.json", observed = "missing", message = "manifest.json is missing.")
      } else {
        manifest <- tryCatch(jsonlite::read_json(manifest_path, simplifyVector = TRUE), error = function(e) e)
        if (inherits(manifest, "error")) {
          add("MANIFEST_MALFORMED", path = "manifest.json", observed = conditionMessage(manifest), message = "manifest.json is not valid JSON.")
          manifest <- NULL
        }
      }
    }
  })

  if (!is.null(manifest)) timed("manifest", {
    manifest_version <- as.character(manifest$scworkbench_manifest_version %||% manifest$manifest_version %||% "")[1]
    if (!manifest_version %in% c("2.0.0", "2.1.0")) {
      add("SCHEMA_VERSION_UNSUPPORTED", table = "manifest.json", expected = "2.0.0 or 2.1.0",
          observed = manifest_version, message = "Bundle manifest schema version is unsupported; validation never migrates it.")
    }
    for (field in c("bundle_id", "bundle_name", "created_at", "storage")) {
      if (is.null(manifest[[field]]) || !length(manifest[[field]]) || !nzchar(.wb_validation_value(manifest[[field]]))) {
        add("MANIFEST_CREATION_METADATA_INVALID", entity_kind = "manifest", entity_id = field,
            table = "manifest.json", observed = "missing or empty", message = paste0("Manifest creation field is invalid: ", field))
      }
    }
    creation <- manifest$creation
    if (!is.null(creation)) {
      for (field in c("bundle_id", "bundle_name", "created_at")) {
        if (!identical(.wb_validation_value(creation[[field]]), .wb_validation_value(manifest[[field]]))) {
          add("MANIFEST_CREATION_METADATA_MISMATCH", entity_kind = "manifest", entity_id = field,
              table = "manifest.json", expected = creation[[field]], observed = manifest[[field]],
              message = paste0("Immutable creation metadata disagrees with the manifest field: ", field))
        }
      }
    } else if (identical(manifest_version, "2.1.0")) {
      add("MANIFEST_CREATION_METADATA_INVALID", entity_kind = "manifest", entity_id = "creation",
          table = "manifest.json", observed = "missing", message = "Manifest 2.1.0 requires immutable creation metadata.")
    }
    db_rel <- as.character(manifest$storage$sqlite$path %||% "")[1]
    checked <- .wb_validation_path(root, db_rel, "file")
    if (!isTRUE(checked$ok)) {
      add(checked$code, check_class = "paths", entity_kind = "sqlite", entity_id = "main",
          path = db_rel, expected = "contained file", observed = checked$observed,
          message = "The manifest SQLite path is not a contained bundle file.")
    } else {
      # SQLite's immutable mode is the only read-only open that cannot create a
      # WAL/SHM sidecar. An actively open assembly already has SHM state, so a
      # normal SQLITE_RO connection is used there to see its WAL frames without
      # creating a new sidecar. A lone WAL is never trusted by immutable mode;
      # content validation emits an unresolved-WAL diagnostic below.
      shm_present <- file.exists(paste0(checked$absolute,"-shm"))
      uri_suffix <- if (shm_present) "?mode=ro" else "?immutable=1"
      con <- tryCatch(DBI::dbConnect(
        RSQLite::SQLite(), paste0("file:", checked$absolute, uri_suffix), flags = RSQLite::SQLITE_RO
      ), error = function(e) e)
      if (inherits(con, "error")) {
        add("SQLITE_OPEN_FAILED", check_class = "sqlite", entity_kind = "sqlite", entity_id = "main",
            path = db_rel, observed = conditionMessage(con), message = "SQLite could not be opened read-only.")
        con <- NULL
      } else {
        attr(con, "scworkbench_read_only") <- TRUE
        bundle <- structure(list(dir = root, manifest = manifest, con = con, read_only = TRUE), class = "scworkbench_bundle")
      }
    }
  })
  on.exit(if (!is.null(con)) try(DBI::dbDisconnect(con), silent = TRUE), add = TRUE)

  if (!is.null(con)) timed("schema_and_registry", {
    tables <- DBI::dbListTables(con)
    required <- c("cells", "datasets", "features", "matrices", "spaces", "space_coords", "space_2d")
    for (table in setdiff(required, tables)) {
      add("REQUIRED_TABLE_MISSING", table = table, observed = "missing", message = paste0("Required table is missing: ", table))
    }
    if (all(c("cells", "datasets", "features", "matrices", "spaces") %in% tables)) {
      counts <- c(
        n_cells = DBI::dbGetQuery(con, "SELECT COUNT(*) n FROM cells;")$n[1],
        n_datasets = DBI::dbGetQuery(con, "SELECT COUNT(*) n FROM datasets;")$n[1],
        n_spaces = DBI::dbGetQuery(con, "SELECT COUNT(*) n FROM spaces;")$n[1],
        n_features = DBI::dbGetQuery(con, "SELECT COUNT(*) n FROM features;")$n[1],
        n_matrices = DBI::dbGetQuery(con, "SELECT COUNT(*) n FROM matrices;")$n[1],
        n_artifacts = if ("artifacts" %in% tables) DBI::dbGetQuery(con, "SELECT COUNT(*) n FROM artifacts;")$n[1] else 0L
      )
      for (nm in names(counts)) {
        cached <- suppressWarnings(as.integer(manifest$counts[[nm]] %||% NA_integer_)[1])
        observed <- as.integer(counts[[nm]])
        if (is.na(cached) || cached != observed) {
          add("MANIFEST_REGISTRY_MISMATCH", check_class = "manifest", entity_kind = "registry", entity_id = nm,
              table = "manifest.json", expected = observed, observed = cached,
              message = paste0("Cached manifest count disagrees with authoritative registry: ", nm))
        }
      }
      collect_manifest_ids <- function(x, field) {
        if (is.null(x) || !length(x)) return(character())
        if (is.data.frame(x) && field %in% names(x)) return(as.character(x[[field]]))
        if (is.list(x) && field %in% names(x) && !is.list(x[[field]])) return(as.character(x[[field]]))
        if (is.list(x)) return(unlist(lapply(x,collect_manifest_ids,field=field),use.names=FALSE))
        character()
      }
      manifest_ids <- list(
        matrix = collect_manifest_ids(manifest$storage$matrices %||% list(),"matrix_id"),
        space = collect_manifest_ids(manifest$spaces %||% list(),"space_id"),
        artifact = collect_manifest_ids(manifest$artifacts %||% list(),"artifact_id")
      )
      registry_ids <- list(
        matrix = as.character(DBI::dbGetQuery(con,"SELECT matrix_id FROM matrices ORDER BY matrix_id;")$matrix_id),
        space = as.character(DBI::dbGetQuery(con,"SELECT space_id FROM spaces ORDER BY space_id;")$space_id),
        artifact = if ("artifacts" %in% tables) as.character(DBI::dbGetQuery(con,"SELECT artifact_id FROM artifacts ORDER BY artifact_id;")$artifact_id) else character()
      )
      for (kind in names(registry_ids)) {
        cached_ids <- sort(unique(manifest_ids[[kind]][!is.na(manifest_ids[[kind]]) & nzchar(manifest_ids[[kind]])]))
        authoritative_ids <- sort(unique(registry_ids[[kind]]))
        if (!identical(cached_ids,authoritative_ids)) add("MANIFEST_REGISTRY_MISMATCH",check_class="manifest",entity_kind=kind,entity_id="registry_ids",table="manifest.json",expected=.wb_prov_sha256_object(authoritative_ids),observed=.wb_prov_sha256_object(cached_ids),message=paste0("Manifest ",kind," inventory disagrees with the authoritative registry."))
      }
      cells <- DBI::dbGetQuery(con, "SELECT cell_id, dataset_id FROM cells ORDER BY rowid;")
      if (anyNA(cells$cell_id) || any(!nzchar(as.character(cells$cell_id))) || anyDuplicated(cells$cell_id)) {
        add("CELL_IDENTITY_DUPLICATE_OR_EMPTY", entity_kind = "cell", table = "cells",
            observed = "duplicate, missing, or empty cell_id", message = "Canonical cell identities must be non-empty and unique.")
      }
      datasets <- DBI::dbGetQuery(con, "SELECT dataset_id, n_cells FROM datasets ORDER BY rowid;")
      actual_ds <- table(as.character(cells$dataset_id), useNA = "ifany")
      for (i in seq_len(nrow(datasets))) {
        id <- as.character(datasets$dataset_id[i]); actual <- as.integer(actual_ds[[id]] %||% 0L)
        if (is.na(datasets$n_cells[i]) || as.integer(datasets$n_cells[i]) != actual) {
          add("DATASET_CELL_COUNT_MISMATCH", entity_kind = "dataset", entity_id = id, table = "datasets",
              expected = actual, observed = datasets$n_cells[i], message = "Dataset count disagrees with canonical cells.")
        }
      }
      unregistered_ds <- setdiff(unique(as.character(cells$dataset_id)), as.character(datasets$dataset_id))
      for (id in unregistered_ds) add("DANGLING_DATASET_REFERENCE", entity_kind = "dataset", entity_id = id,
                                      table = "cells", observed = "not registered", message = "A cell references an unregistered dataset.")
    }
  })

  check_paths <- function() {
    if (is.null(con)) return(invisible(FALSE))
    specifications <- list(
      list(table = "matrices", id = "matrix_id", column = "path", type = "directory", kind = "matrix"),
      list(table = "matrix_fragments", id = "fragment_id", column = "path", type = "directory", kind = "matrix_fragment"),
      list(table = "space_models", id = "space_id", column = "model_path", type = "either", kind = "model"),
      list(table = "artifact_umap_model", id = "artifact_id", column = "model_path", type = "either", kind = "artifact"),
      list(table = "artifact_model_ref", id = "artifact_id", column = "model_path", type = "either", kind = "artifact"),
      list(table = "prov_materializations", id = "output_name", column = "path", type = "either", kind = "materialization")
    )
    for (spec in specifications) {
      if (!.wb_table_exists(con, spec$table) || !all(c(spec$id, spec$column) %in% DBI::dbListFields(con, spec$table))) next
      rows <- DBI::dbGetQuery(con, paste0("SELECT ", spec$id, ", ", spec$column, " FROM ", spec$table, " ORDER BY ", spec$id, ";"))
      if (!nrow(rows)) next
      for (i in seq_len(nrow(rows))) {
        raw <- as.character(rows[[spec$column]][i] %||% "")[1]
        checked <- .wb_validation_path(root, raw, spec$type)
        if (!isTRUE(checked$ok)) add(
          checked$code, check_class = "paths", entity_kind = spec$kind, entity_id = rows[[spec$id]][i],
          path = raw, table = spec$table, expected = paste("contained", spec$type), observed = checked$observed,
          message = paste0("Invalid durable payload path in ", spec$table, ".")
        )
      }
    }
  }
  timed("paths", check_paths())

  if (has_level("content") && !is.null(con)) {
    db_path <- file.path(root,as.character(manifest$storage$sqlite$path %||% ""))
    wal_path <- paste0(db_path,"-wal")
    if (file.exists(wal_path) && !file.exists(paste0(db_path,"-shm")) && isTRUE(file.info(wal_path)$size > 0)) add("SQLITE_UNRESOLVED_WAL_STATE",check_class="sqlite_integrity",entity_kind="sqlite",entity_id="main",path=substring(wal_path,nchar(root)+2L),observed=paste0(file.info(wal_path)$size," bytes without SHM"),message="A lone non-empty WAL cannot be safely included by immutable read-only validation; finalize the bundle before content transfer.")
    timed("sqlite_integrity", {
      result <- tryCatch(DBI::dbGetQuery(con, "PRAGMA integrity_check;")[[1]], error = function(e) conditionMessage(e))
      if (!identical(as.character(result), "ok")) add("SQLITE_INTEGRITY_FAILED", check_class = "sqlite_integrity",
        entity_kind = "sqlite", entity_id = "main", expected = "ok", observed = result,
        message = "SQLite integrity_check did not return ok.")
    })

    timed("matrix_content", {
      if (all(c("matrices", "features", "cells") %in% DBI::dbListTables(con))) {
        mats <- DBI::dbGetQuery(con, "SELECT * FROM matrices ORDER BY matrix_id;")
        canonical_cells <- as.character(DBI::dbGetQuery(con, "SELECT cell_id FROM cells ORDER BY rowid;")$cell_id)
        for (i in seq_len(nrow(mats))) {
          id <- as.character(mats$matrix_id[i])
          features <- as.character(DBI::dbGetQuery(con, "SELECT feature_id FROM features WHERE matrix_id=? ORDER BY rowid;", params = list(id))$feature_id)
          if (anyNA(features) || any(!nzchar(features)) || anyDuplicated(features)) add(
            "MATRIX_FEATURE_IDENTITY_DUPLICATE_OR_EMPTY", check_class = "matrix_content", entity_kind = "matrix", entity_id = id,
            table = "features", observed = "duplicate, missing, or empty", message = "Matrix feature identities must be non-empty and unique.")
          expected_cells <- if (.wb_table_exists(con, "matrix_cells")) {
            as.character(DBI::dbGetQuery(con, "SELECT mc.cell_id FROM matrix_cells mc JOIN cells c ON c.cell_id=mc.cell_id WHERE mc.matrix_id=? ORDER BY c.rowid;", params = list(id))$cell_id)
          } else canonical_cells
          if (!length(expected_cells) && as.integer(mats$n_cells[i]) == length(canonical_cells)) expected_cells <- canonical_cells
          if (as.integer(mats$n_features[i]) != length(features)) add("MATRIX_FEATURE_COUNT_MISMATCH", check_class = "matrix_content", entity_kind = "matrix", entity_id = id, table = "matrices", expected = length(features), observed = mats$n_features[i], message = "Matrix registry feature count disagrees with canonical identities.")
          if (as.integer(mats$n_cells[i]) != length(expected_cells)) add("MATRIX_CELL_COUNT_MISMATCH", check_class = "matrix_content", entity_kind = "matrix", entity_id = id, table = "matrices", expected = length(expected_cells), observed = mats$n_cells[i], message = "Matrix registry cell count disagrees with canonical identities.")
          frags <- if (.wb_table_exists(con, "matrix_fragments")) DBI::dbGetQuery(con, "SELECT * FROM matrix_fragments WHERE matrix_id=? ORDER BY created_at, rowid;", params = list(id)) else data.frame()
          if (!nrow(frags)) {
            frags <- data.frame(fragment_id = id, path = as.character(mats$path[i]), n_features = mats$n_features[i], n_cells = mats$n_cells[i], feature_ids_json = NA_character_, cell_ids_json = NA_character_, stringsAsFactors = FALSE)
          }
          covered <- character()
          for (j in seq_len(nrow(frags))) {
            fid <- as.character(frags$fragment_id[j]); rel <- as.character(frags$path[j])
            checked <- .wb_validation_path(root, rel, "directory")
            if (!isTRUE(checked$ok)) next
            fm <- tryCatch(.wb_bp_open_matrix_dir(checked$absolute), error = function(e) e)
            if (inherits(fm, "error")) {
              add("MATRIX_PAYLOAD_UNREADABLE", check_class = "matrix_content", entity_kind = "matrix_fragment", entity_id = fid, path = rel, observed = conditionMessage(fm), message = "Matrix fragment payload cannot be opened.")
              next
            }
            actual_features <- as.character(rownames(fm) %||% character())
            actual_cells <- as.character(colnames(fm) %||% character())
            declared_features <- if (!is.na(frags$feature_ids_json[j] %||% NA_character_)) tryCatch(as.character(jsonlite::fromJSON(frags$feature_ids_json[j])), error = function(e) character()) else features
            declared_cells <- if (!is.na(frags$cell_ids_json[j] %||% NA_character_)) tryCatch(as.character(jsonlite::fromJSON(frags$cell_ids_json[j])), error = function(e) character()) else expected_cells
            if (.wb_table_exists(con,"matrix_fragment_features")) {
              normalized <- as.character(DBI::dbGetQuery(con,"SELECT feature_id FROM matrix_fragment_features WHERE fragment_id=? ORDER BY rowid;",params=list(fid))$feature_id)
              if (!identical(normalized,declared_features)) add("MATRIX_FRAGMENT_FEATURE_REGISTRY_MISMATCH",check_class="matrix_content",entity_kind="matrix_fragment",entity_id=fid,table="matrix_fragment_features",expected=.wb_prov_sha256_object(declared_features),observed=.wb_prov_sha256_object(normalized),message="Normalized fragment feature membership disagrees with ordered JSON identities.")
            }
            if (.wb_table_exists(con,"matrix_fragment_cells")) {
              normalized <- as.character(DBI::dbGetQuery(con,"SELECT cell_id FROM matrix_fragment_cells WHERE fragment_id=? ORDER BY rowid;",params=list(fid))$cell_id)
              if (!identical(normalized,declared_cells)) add("MATRIX_FRAGMENT_CELL_REGISTRY_MISMATCH",check_class="matrix_content",entity_kind="matrix_fragment",entity_id=fid,table="matrix_fragment_cells",expected=.wb_prov_sha256_object(declared_cells),observed=.wb_prov_sha256_object(normalized),message="Normalized fragment cell membership disagrees with ordered JSON identities.")
            }
            if (anyDuplicated(declared_features) || anyDuplicated(actual_features)) add("MATRIX_FEATURE_IDENTITY_DUPLICATE", check_class = "matrix_content", entity_kind = "matrix_fragment", entity_id = fid, table = "matrix_fragments", message = "Fragment feature identities contain duplicates.")
            if (anyDuplicated(declared_cells) || anyDuplicated(actual_cells)) add("MATRIX_CELL_IDENTITY_DUPLICATE", check_class = "matrix_content", entity_kind = "matrix_fragment", entity_id = fid, table = "matrix_fragments", message = "Fragment cell identities contain duplicates.")
            if (!identical(declared_features, features)) add("MATRIX_FRAGMENT_FEATURE_ORDER_MISMATCH", check_class = "matrix_content", entity_kind = "matrix_fragment", entity_id = fid, table = "matrix_fragments", expected = .wb_prov_sha256_object(features), observed = .wb_prov_sha256_object(declared_features), message = "Fragment declared feature identities/order disagree with the canonical matrix feature universe.")
            if (length(actual_features) && !identical(actual_features, declared_features)) add("MATRIX_PAYLOAD_FEATURE_ORDER_MISMATCH", check_class = "matrix_content", entity_kind = "matrix_fragment", entity_id = fid, path = rel, expected = .wb_prov_sha256_object(declared_features), observed = .wb_prov_sha256_object(actual_features), message = "Matrix payload row identities/order disagree with its fragment registry.")
            if (length(actual_cells) && !identical(actual_cells, declared_cells)) add("MATRIX_PAYLOAD_CELL_ORDER_MISMATCH", check_class = "matrix_content", entity_kind = "matrix_fragment", entity_id = fid, path = rel, expected = .wb_prov_sha256_object(declared_cells), observed = .wb_prov_sha256_object(actual_cells), message = "Matrix payload column identities/order disagree with its fragment registry.")
            if (!identical(as.integer(dim(fm)), c(length(declared_features), length(declared_cells)))) add("MATRIX_PAYLOAD_DIMENSION_MISMATCH", check_class = "matrix_content", entity_kind = "matrix_fragment", entity_id = fid, path = rel, expected = paste(length(declared_features), length(declared_cells), sep = "x"), observed = paste(dim(fm), collapse = "x"), message = "Matrix payload dimensions disagree with declared identities.")
            if (length(intersect(covered, declared_cells))) add("MATRIX_FRAGMENT_CELL_OVERLAP", check_class = "matrix_content", entity_kind = "matrix", entity_id = id, table = "matrix_fragments", observed = paste(head(intersect(covered, declared_cells), 10L), collapse = ","), message = "Matrix fragments overlap in cell identity.")
            covered <- c(covered, declared_cells)
          }
          if (!identical(covered, expected_cells)) {
            code <- if (setequal(covered, expected_cells)) "MATRIX_FRAGMENT_CELL_ORDER_MISMATCH" else "MATRIX_FRAGMENT_CELL_COVERAGE_GAP"
            add(code, check_class = "matrix_content", entity_kind = "matrix", entity_id = id, table = "matrix_fragments", expected = .wb_prov_sha256_object(expected_cells), observed = .wb_prov_sha256_object(covered), message = "Ordered fragment cell coverage does not exactly equal the canonical matrix cell universe.")
          }
        }
      }
    })

    timed("spaces_and_models", {
      if (.wb_table_exists(con, "spaces")) {
        spaces <- DBI::dbGetQuery(con, "SELECT * FROM spaces ORDER BY space_id;")
        for (i in seq_len(nrow(spaces))) {
          id <- as.character(spaces$space_id[i]); dims <- as.integer(spaces$dims[i]); storage <- as.character(spaces$storage[i] %||% "")
          if (grepl("wide:space_2d", storage, fixed = TRUE) || identical(dims, 2L)) {
            rows <- DBI::dbGetQuery(con, "SELECT cell_id,x,y FROM space_2d WHERE space_id=? ORDER BY rowid;", params = list(id))
            bad <- anyDuplicated(rows$cell_id) || nrow(rows) == 0L || anyNA(rows[, c("cell_id", "x", "y"), drop = FALSE])
            if (bad) add("SPACE_PAYLOAD_INVALID", check_class = "spaces_and_models", entity_kind = "space", entity_id = id, table = "space_2d", observed = "empty, duplicate, or missing coordinate", message = "Wide space payload is incomplete or invalid.")
          } else {
            rows <- DBI::dbGetQuery(con, "SELECT cell_id,dim,value FROM space_coords WHERE space_id=? ORDER BY rowid;", params = list(id))
            keys <- paste(rows$cell_id, rows$dim, sep = "\r")
            expected_n <- length(unique(rows$cell_id)) * dims
            if (!nrow(rows) || anyDuplicated(keys) || anyNA(rows) || nrow(rows) != expected_n || !setequal(unique(as.integer(rows$dim)), seq_len(dims))) add("SPACE_PAYLOAD_INVALID", check_class = "spaces_and_models", entity_kind = "space", entity_id = id, table = "space_coords", expected = paste0(dims, " dimensions per cell"), observed = nrow(rows), message = "Long space payload has incomplete/duplicate dimensions or missing values.")
          }
          space_cells <- unique(as.character(rows$cell_id))
          dangling <- setdiff(space_cells, as.character(DBI::dbGetQuery(con, "SELECT cell_id FROM cells;")$cell_id))
          if (length(dangling)) add("SPACE_DANGLING_CELL_REFERENCE", check_class = "spaces_and_models", entity_kind = "space", entity_id = id, table = if (dims == 2L) "space_2d" else "space_coords", observed = paste(head(dangling, 10L), collapse = ","), message = "Space payload references cells outside the canonical bundle universe.")
        }
      }
      if (.wb_table_exists(con, "space_models")) {
        models <- DBI::dbGetQuery(con, "SELECT * FROM space_models ORDER BY space_id;")
        spaces_ids <- if (.wb_table_exists(con, "spaces")) DBI::dbGetQuery(con, "SELECT space_id FROM spaces;")$space_id else character()
        for (i in seq_len(nrow(models))) {
          id <- as.character(models$space_id[i])
          if (!as.character(models$source_space_id[i]) %in% spaces_ids) add("MODEL_DANGLING_SOURCE_SPACE", check_class = "spaces_and_models", entity_kind = "model", entity_id = id, table = "space_models", observed = models$source_space_id[i], message = "Model references an unregistered source space.")
          checked <- .wb_validation_path(root, models$model_path[i], "either")
          if (isTRUE(checked$ok)) {
            loaded <- tryCatch(if (grepl("uwot", as.character(models$model_type[i]), ignore.case = TRUE)) uwot::load_uwot(checked$absolute) else readRDS(checked$absolute), error = function(e) e)
            if (inherits(loaded, "error")) add("MODEL_PAYLOAD_UNREADABLE", check_class = "spaces_and_models", entity_kind = "model", entity_id = id, path = models$model_path[i], observed = conditionMessage(loaded), message = "Model payload cannot be loaded.")
          }
        }
      }
    })

    timed("artifacts", {
      if (.wb_table_exists(con, "artifacts")) {
        arts <- DBI::dbGetQuery(con, "SELECT * FROM artifacts ORDER BY artifact_id;")
        payload_tables <- intersect(grep("^artifact_", DBI::dbListTables(con), value = TRUE), setdiff(DBI::dbListTables(con), "artifacts"))
        known <- as.character(arts$artifact_id)
        for (table in payload_tables) if ("artifact_id" %in% DBI::dbListFields(con, table)) {
          dangling <- DBI::dbGetQuery(con, paste0("SELECT DISTINCT artifact_id FROM ", table, " WHERE artifact_id NOT IN (SELECT artifact_id FROM artifacts);"))$artifact_id
          for (id in dangling) add("ARTIFACT_DANGLING_PAYLOAD_ROW", check_class = "artifacts", entity_kind = "artifact", entity_id = id, table = table, observed = "registry row missing", message = "Artifact payload rows have no artifact registry owner.")
        }
        for (i in seq_len(nrow(arts))) {
          id <- as.character(arts$artifact_id[i]); type <- as.character(arts$type[i]); table <- .wb_validation_artifact_payload_table(type)
          if (!is.na(table)) {
            n <- if (.wb_table_exists(con, table)) DBI::dbGetQuery(con, paste0("SELECT COUNT(*) n FROM ", table, " WHERE artifact_id=?;"), params = list(id))$n[1] else 0L
            # Empty tabular artifacts are legitimate but still require their header row.
            if (n < 1L) add("ARTIFACT_PAYLOAD_MISSING", check_class = "artifacts", entity_kind = "artifact", entity_id = id, table = table, expected = ">=1 registry/payload row", observed = n, message = "Artifact has no payload row for its declared primitive type.")
          }
          prov <- tryCatch(jsonlite::fromJSON(as.character(arts$provenance_json[i]), simplifyVector = FALSE), error = function(e) NULL)
          if (is.null(prov)) add("ARTIFACT_PROVENANCE_MALFORMED", check_class = "artifacts", entity_kind = "artifact", entity_id = id, table = "artifacts", observed = "invalid JSON", message = "Artifact provenance_json is malformed.")
        }
      }
    })

    timed("provenance", {
      tables <- DBI::dbListTables(con)
      has <- function(x) x %in% tables
      runs <- if (has("prov_runs")) DBI::dbGetQuery(con, "SELECT snapshot_id,run_id FROM prov_runs;") else data.frame(snapshot_id=character(),run_id=character())
      run_key <- paste(runs$snapshot_id, runs$run_id, sep = "\r")
      heads <- if (has("prov_heads")) DBI::dbGetQuery(con, "SELECT * FROM prov_heads ORDER BY snapshot_id;") else data.frame()
      head_ids <- as.character(heads$snapshot_id %||% character())
      commits <- if (has("prov_commits")) DBI::dbGetQuery(con, "SELECT * FROM prov_commits ORDER BY commit_id;") else data.frame()
      commit_ids <- as.character(commits$commit_id %||% character())
      if (nrow(heads)) for (i in seq_len(nrow(heads))) {
        sid <- as.character(heads$snapshot_id[i]); actual <- sum(runs$snapshot_id == sid)
        if (as.integer(heads$n_runs[i]) != actual) add("PROVENANCE_HEAD_RUN_COUNT_MISMATCH", check_class = "provenance", entity_kind = "snapshot", entity_id = sid, table = "prov_heads", expected = actual, observed = heads$n_runs[i], message = "Snapshot run count disagrees with stored runs.")
        declared_heads <- tryCatch(as.character(jsonlite::fromJSON(heads$head_run_ids_json[i])), error = function(e) character())
        if (any(!paste(sid, declared_heads, sep = "\r") %in% run_key)) add("PROVENANCE_DANGLING_HEAD_RUN", check_class = "provenance", entity_kind = "snapshot", entity_id = sid, table = "prov_heads", observed = paste(setdiff(declared_heads, runs$run_id[runs$snapshot_id == sid]), collapse = ","), message = "Snapshot head references a missing run.")
        cid <- as.character(heads$commit_id[i] %||% "")[1]
        if (.wb_validation_nonempty(cid) && !cid %in% commit_ids) add("PROVENANCE_DANGLING_COMMIT", check_class = "provenance", entity_kind = "snapshot", entity_id = sid, table = "prov_heads", observed = cid, message = "Snapshot references a missing commit.")
      }
      if (nrow(runs)) for (i in seq_len(nrow(runs))) if (!runs$snapshot_id[i] %in% head_ids) add("PROVENANCE_DANGLING_RUN_SNAPSHOT", check_class = "provenance", entity_kind = "run", entity_id = runs$run_id[i], table = "prov_runs", observed = runs$snapshot_id[i], message = "Run references a missing snapshot.")
      if (has("prov_run_edges")) {
        edges <- DBI::dbGetQuery(con, "SELECT * FROM prov_run_edges;")
        for (i in seq_len(nrow(edges))) {
          p <- paste(edges$snapshot_id[i], edges$parent_run_id[i], sep = "\r"); c <- paste(edges$snapshot_id[i], edges$child_run_id[i], sep = "\r")
          if (!p %in% run_key || !c %in% run_key) add("PROVENANCE_DANGLING_DAG_EDGE", check_class = "provenance", entity_kind = "dag_edge", entity_id = paste(edges$parent_run_id[i], edges$child_run_id[i], sep = "->"), table = "prov_run_edges", observed = edges$snapshot_id[i], message = "DAG edge endpoint is missing from its snapshot.")
        }
      }
      outputs <- if (has("prov_run_outputs")) DBI::dbGetQuery(con, "SELECT * FROM prov_run_outputs;") else data.frame()
      if (nrow(outputs)) for (i in seq_len(nrow(outputs))) {
        key <- paste(outputs$snapshot_id[i], outputs$run_id[i], sep = "\r")
        if (!key %in% run_key) add("PROVENANCE_DANGLING_OUTPUT_RUN", check_class = "provenance", entity_kind = "run_output", entity_id = paste(outputs$run_id[i], outputs$output_name[i], sep = "::"), table = "prov_run_outputs", message = "Run output references a missing run.")
        aid <- as.character(outputs$artifact_id[i] %||% "")[1]
        if (.wb_validation_nonempty(aid) && (!has("artifacts") || !nrow(DBI::dbGetQuery(con, "SELECT 1 FROM artifacts WHERE artifact_id=?;", params=list(aid))))) add("PROVENANCE_DANGLING_OUTPUT_ARTIFACT", check_class = "provenance", entity_kind = "artifact", entity_id = aid, table = "prov_run_outputs", message = "Run output references a missing artifact.")
        sha <- if ("content_sha256" %in% names(outputs)) as.character(outputs$content_sha256[i] %||% "")[1] else ""
        if (.wb_validation_nonempty(sha) && !grepl("^[A-Fa-f0-9]{64}$", sha)) add("CONTENT_IDENTITY_MALFORMED", check_class = "provenance", entity_kind = "run_output", entity_id = paste(outputs$run_id[i], outputs$output_name[i], sep = "::"), table = "prov_run_outputs", expected = "64 hexadecimal SHA-256", observed = sha, message = "Recorded output content identity is malformed.")
        if (.wb_validation_nonempty(aid) && .wb_validation_nonempty(sha) && has("artifacts")) {
          actual <- tryCatch({
            atype <- DBI::dbGetQuery(con,"SELECT type FROM artifacts WHERE artifact_id=?;",params=list(aid))$type[1]
            if (as.character(atype) %in% c("feature_table","obs_table")) .wb_prov_stored_table_content_sha256(con,aid) else {
              prim <- wb_art_load(bundle, aid); .wb_prov_payload_identity(bundle, prim)$content_sha256
            }
          }, error = function(e) NA_character_)
          if (!is.na(actual) && nzchar(actual) && !identical(tolower(actual), tolower(sha))) add("ARTIFACT_CONTENT_IDENTITY_MISMATCH", check_class = "provenance", entity_kind = "artifact", entity_id = aid, table = "prov_run_outputs", expected = sha, observed = actual, message = "Artifact payload no longer matches its recorded content identity.")
        }
      }
      if (has("prov_run_entity_bindings")) {
        bindings <- DBI::dbGetQuery(con, "SELECT * FROM prov_run_entity_bindings;")
        physical <- .wb_entity_physical_inventory(bundle)
        lifecycle <- if (has("entity_lifecycle")) DBI::dbGetQuery(con, "SELECT * FROM entity_lifecycle;") else data.frame()
        tomb <- if (has("entity_tombstones")) DBI::dbGetQuery(con, "SELECT * FROM entity_tombstones;") else data.frame()
        for (i in seq_len(nrow(bindings))) {
          sid <- as.character(bindings$snapshot_id[i]); rid <- as.character(bindings$run_id[i]); kind <- as.character(bindings$entity_kind[i]); id <- as.character(bindings$entity_id[i])
          if (!paste(sid, rid, sep = "\r") %in% run_key) add("PROVENANCE_DANGLING_ENTITY_BINDING_RUN", check_class = "provenance", entity_kind = kind, entity_id = id, table = "prov_run_entity_bindings", observed = paste(sid,rid,sep="/"), message = "Entity binding references a missing run.")
          cid <- as.character(bindings$commit_id[i] %||% "")[1]
          if (.wb_validation_nonempty(cid) && !cid %in% commit_ids) add("PROVENANCE_DANGLING_ENTITY_BINDING_COMMIT", check_class = "provenance", entity_kind = kind, entity_id = id, table = "prov_run_entity_bindings", observed = cid, message = "Entity binding references a missing commit.")
          present <- any(physical$entity_kind == kind & physical$entity_id == id)
          # model_ref is a binding identity whose durable path is authoritative.
          bound_path <- as.character(bindings$path[i] %||% "")[1]
          if (kind == "model_ref") {
            present <- .wb_validation_nonempty(bound_path) && isTRUE(.wb_validation_path(root, bound_path, "either")$ok)
            bits <- strsplit(id, "|", fixed = TRUE)[[1]]
            if (!present && length(bits) >= 2L && has("artifact_model_ref")) {
              refs <- DBI::dbGetQuery(con, "SELECT model_path FROM artifact_model_ref WHERE engine=? AND model_space_id=?;", params=list(bits[1],bits[2]))
              present <- nrow(refs) && any(vapply(refs$model_path, function(p) isTRUE(.wb_validation_path(root,p,"either")$ok), logical(1)))
            }
            if (!present && length(bits) >= 2L && has("space_models")) {
              refs <- DBI::dbGetQuery(con, "SELECT model_path FROM space_models WHERE space_id=?;", params=list(bits[2]))
              present <- nrow(refs) && any(vapply(refs$model_path, function(p) isTRUE(.wb_validation_path(root,p,"either")$ok), logical(1)))
            }
          }
          tombstoned <- nrow(tomb) && any(tomb$entity_kind == kind & tomb$entity_id == id)
          if (!present && !tombstoned && kind != "registry") add("PROVENANCE_DANGLING_ENTITY_BINDING", check_class = "provenance", entity_kind = kind, entity_id = id, table = "prov_run_entity_bindings", observed = "durable entity missing", message = "Provenance binding has neither a durable entity nor a valid tombstone.")
          recorded_hash <- as.character(bindings$content_hash[i] %||% "")[1]
          if (present && .wb_validation_nonempty(recorded_hash) && grepl("^[A-Fa-f0-9]{64}$", recorded_hash)) {
            actual_hash <- tryCatch({
              if (kind == "matrix") {
                .wb_prov_payload_identity(bundle, wb_prim_matrix(id))$content_sha256
              } else if (kind == "space") {
                sr <- DBI::dbGetQuery(con, "SELECT dims FROM spaces WHERE space_id=?;", params=list(id))
                prims <- if (nrow(sr) && identical(as.integer(sr$dims[1]), 2L)) list(wb_prim_space(id), wb_prim_space_2d(id)) else list(wb_prim_space(id))
                hashes <- vapply(prims, function(prim) .wb_prov_payload_identity(bundle, prim)$content_sha256, character(1))
                hit <- hashes[tolower(hashes) == tolower(recorded_hash)]
                if (length(hit)) hit[1] else hashes[1]
              } else if (kind %in% c("model", "model_ref")) {
                candidate <- ""
                bits <- strsplit(id,"|",fixed=TRUE)[[1]]
                if (kind == "model_ref" && length(bits)>=2L && has("artifact_model_ref")) {
                  mr <- DBI::dbGetQuery(con,"SELECT model_path FROM artifact_model_ref WHERE engine=? AND model_space_id=? ORDER BY artifact_id;",params=list(bits[1],bits[2]))
                  if (nrow(mr)) candidate <- as.character(mr$model_path[1])
                }
                if (!.wb_validation_nonempty(candidate) && kind == "model_ref" && length(bits)>=2L && has("space_models")) {
                  mr <- DBI::dbGetQuery(con,"SELECT model_path FROM space_models WHERE space_id=?;",params=list(bits[2]))
                  if (nrow(mr)) candidate <- as.character(mr$model_path[1])
                }
                if (!.wb_validation_nonempty(candidate) && kind == "model" && has("space_models")) {
                  mr <- DBI::dbGetQuery(con, "SELECT model_path FROM space_models WHERE space_id=?;", params=list(id))
                  if (nrow(mr)) candidate <- as.character(mr$model_path[1])
                }
                if (!.wb_validation_nonempty(candidate)) candidate <- bound_path
                checked <- .wb_validation_path(root, candidate, "either")
                if (isTRUE(checked$ok)) .wb_prov_file_tree_sha256(checked$absolute) else NA_character_
              } else NA_character_
            }, error=function(e) NA_character_)
            if (.wb_validation_nonempty(actual_hash) && !identical(tolower(actual_hash),tolower(recorded_hash))) {
              code <- switch(kind, matrix="MATRIX_CONTENT_IDENTITY_MISMATCH", space="SPACE_CONTENT_IDENTITY_MISMATCH", model="MODEL_CONTENT_IDENTITY_MISMATCH", model_ref="MODEL_CONTENT_IDENTITY_MISMATCH", "ENTITY_CONTENT_IDENTITY_MISMATCH")
              add(code,check_class="provenance",entity_kind=kind,entity_id=id,table="prov_run_entity_bindings",expected=recorded_hash,observed=actual_hash,message="Durable entity payload no longer matches its provenance-bound content identity.")
            }
          }
        }
      }
      if (nrow(commits)) for (i in seq_len(nrow(commits))) {
        state <- as.character(commits$state[i]); if (!state %in% c("complete", "failed")) add("INCOMPLETE_COMMIT", check_class = "provenance", entity_kind = "commit", entity_id = commits$commit_id[i], table = "prov_commits", expected = "complete or failed", observed = state, message = "A provenance commit is not finalized.")
      }
      if (has("prov_materializations")) {
        mats <- DBI::dbGetQuery(con, "SELECT * FROM prov_materializations;")
        for (i in seq_len(nrow(mats))) {
          id <- paste(mats$run_id[i], mats$output_name[i], sep = "::"); cid <- as.character(mats$commit_id[i])
          if (!cid %in% commit_ids) add("MATERIALIZATION_DANGLING_COMMIT", check_class = "provenance", entity_kind = "materialization", entity_id = id, table = "prov_materializations", observed = cid, message = "Materialization references a missing commit.")
          if (!as.character(mats$run_id[i]) %in% as.character(runs$run_id)) add("MATERIALIZATION_DANGLING_RUN",check_class="provenance",entity_kind="materialization",entity_id=id,table="prov_materializations",observed=mats$run_id[i],message="Materialization references a missing provenance run.")
          checked <- .wb_validation_path(root, mats$path[i], "either")
          if (isTRUE(checked$ok) && "content_sha256" %in% names(mats)) {
            sha <- as.character(mats$content_sha256[i] %||% "")[1]
            if (.wb_validation_nonempty(sha)) {
              actual <- .wb_prov_file_tree_sha256(checked$absolute)
              if (!identical(tolower(actual), tolower(sha))) add("MATERIALIZATION_CONTENT_IDENTITY_MISMATCH", check_class = "provenance", entity_kind = "materialization", entity_id = id, path = mats$path[i], expected = sha, observed = actual, message = "Materialization payload no longer matches its content identity.")
            }
          }
        }
      }
      if (has("prov_registry_mutations")) {
        reg <- DBI::dbGetQuery(con, "SELECT rowid AS mutation_order,* FROM prov_registry_mutations ORDER BY rowid;")
        entities <- vector("list",nrow(reg))
        for (i in seq_len(nrow(reg))) {
          if (!as.character(reg$commit_id[i]) %in% commit_ids) add("REGISTRY_MUTATION_DANGLING_COMMIT", check_class = "provenance", entity_kind = "registry_mutation", entity_id = reg$event_id[i], table = "prov_registry_mutations", message = "Registry mutation references a missing commit.")
          key <- .wb_validation_json(reg$registry_key_json[i])
          if (is.null(key)) add("REGISTRY_MUTATION_MALFORMED", check_class = "provenance", entity_kind = "registry_mutation", entity_id = reg$event_id[i], table = "prov_registry_mutations", observed = "invalid registry_key_json", message = "Registry mutation key is malformed.")
          if (.wb_validation_nonempty(reg$payload_json[i]) && is.null(.wb_validation_json(reg$payload_json[i]))) add("REGISTRY_MUTATION_MALFORMED",check_class="provenance",entity_kind="registry_mutation",entity_id=reg$event_id[i],table="prov_registry_mutations",observed="invalid payload_json",message="Registry mutation payload is malformed.")
          entities[[i]] <- if (is.null(key)) NULL else .wb_registry_event_entity(as.character(reg$registry_type[i]),key)
          sha <- as.character(reg$content_hash[i] %||% "")[1]; if (.wb_validation_nonempty(sha) && !grepl("^[A-Fa-f0-9]{64}$", sha)) add("REGISTRY_MUTATION_CONTENT_IDENTITY_MALFORMED", check_class = "provenance", entity_kind = "registry_mutation", entity_id = reg$event_id[i], table = "prov_registry_mutations", observed = sha, message = "Registry mutation content identity is malformed.")
        }
        entity_ids <- vapply(entities,function(x) if(is.null(x)) "" else paste(x$kind,x$id,sep="\r"),character(1))
        for (entity_key in unique(entity_ids[nzchar(entity_ids)])) {
          index <- utils::tail(which(entity_ids==entity_key),1L); entity <- entities[[index]]; expected_hash <- as.character(reg$content_hash[index] %||% "")[1]
          if (.wb_validation_nonempty(expected_hash)) {
            actual_hash <- tryCatch(.wb_registry_entity_content_hash(bundle,entity$kind,entity$id),error=function(e) NA_character_)
            if (.wb_validation_nonempty(actual_hash) && !identical(tolower(actual_hash),tolower(expected_hash))) add("REGISTRY_MUTATION_CONTENT_IDENTITY_MISMATCH",check_class="provenance",entity_kind=entity$kind,entity_id=entity$id,table="prov_registry_mutations",expected=expected_hash,observed=actual_hash,message="Current durable registry entity disagrees with the latest recorded mutation identity.")
          }
        }
      }
    })

    timed("source_inputs", {
      if (.wb_table_exists(con, "prov_source_inputs")) {
        src <- DBI::dbGetQuery(con, "SELECT * FROM prov_source_inputs ORDER BY snapshot_id,run_id,source_id;")
        runs <- if (.wb_table_exists(con, "prov_runs")) DBI::dbGetQuery(con, "SELECT snapshot_id,run_id FROM prov_runs;") else data.frame()
        for (i in seq_len(nrow(src))) {
          id <- as.character(src$source_id[i]); x <- .wb_validation_json(src$source_json[i])
          if (is.null(x)) { add("SOURCE_IDENTITY_MALFORMED", check_class = "source_inputs", entity_kind = "external_source", entity_id = id, table = "prov_source_inputs", observed = "invalid JSON", message = "Source input declaration is malformed."); next }
          if (!paste(src$snapshot_id[i],src$run_id[i],sep="\r") %in% paste(runs$snapshot_id,runs$run_id,sep="\r")) add("SOURCE_INPUT_DANGLING_RUN", check_class = "source_inputs", entity_kind = "external_source", entity_id = id, table = "prov_source_inputs", message = "Source input references a missing run.")
          alg <- tolower(as.character(x$checksum_algorithm %||% if (!is.null(x$sha256)) "sha256" else "")[1]); sha <- as.character(x$sha256 %||% x$checksum %||% "")[1]
          if (.wb_validation_nonempty(sha) && (!identical(alg,"sha256") || !grepl("^[A-Fa-f0-9]{64}$", sha))) { add("SOURCE_CHECKSUM_MALFORMED", check_class = "source_inputs", entity_kind = "external_source", entity_id = id, table = "prov_source_inputs", expected = "sha256 plus 64 hexadecimal characters", observed = paste(alg,sha), message = "Source checksum syntax is invalid."); next }
          raw <- as.character(x$path %||% "")[1]; bundled <- isTRUE(x$bundled %||% x$bundle_owned %||% FALSE)
          local <- if (!.wb_validation_nonempty(raw)) "" else if (.wb_path_is_absolute(raw)) raw else file.path(root, raw)
          if (bundled && (!nzchar(local) || !file.exists(local))) add("BUNDLED_SOURCE_MISSING", check_class = "source_inputs", entity_kind = "external_source", entity_id = id, path = raw, expected = "bundled source file", observed = "missing", message = "A source declared as bundled is unavailable.")
          else if (nzchar(local) && file.exists(local) && .wb_validation_nonempty(sha)) { actual <- .wb_prov_sha256_file(local); if (!identical(tolower(actual),tolower(sha))) add("SOURCE_CHECKSUM_MISMATCH", check_class = "source_inputs", entity_kind = "external_source", entity_id = id, path = raw, expected = sha, observed = actual, message = "Locally available immutable source does not match its recorded checksum.") }
          else if (!bundled && (!nzchar(local) || !file.exists(local))) add("EXTERNAL_SOURCE_UNVERIFIABLE", severity = "warning", check_class = "source_inputs", entity_kind = "external_source", entity_id = id, path = raw, observed = "not locally available", message = "External source cannot be verified on this recipient; bundle integrity is not failed.")
        }
      }
    })

    timed("lifecycle", {
      if (.wb_table_exists(con, "entity_lifecycle")) {
        life <- DBI::dbGetQuery(con, "SELECT * FROM entity_lifecycle;"); physical <- .wb_entity_physical_inventory(bundle)
        tomb <- if (.wb_table_exists(con,"entity_tombstones")) DBI::dbGetQuery(con,"SELECT * FROM entity_tombstones;") else data.frame()
        for (i in seq_len(nrow(life))) {
          kind <- as.character(life$entity_kind[i]); id <- as.character(life$entity_id[i]); state <- as.character(life$lifecycle_state[i]); present <- any(physical$entity_kind==kind & physical$entity_id==id)
          if (kind=="model_ref") present <- TRUE
          is_tomb <- nrow(tomb) && any(tomb$entity_kind==kind & tomb$entity_id==id & tomb$tombstone_state==state)
          if (!present && state %in% c("current","superseded")) add("ILLEGAL_HISTORICAL_ENTITY_DELETION", check_class="lifecycle",entity_kind=kind,entity_id=id,table="entity_lifecycle",expected="durable historical payload",observed=state,message="A current or superseded immutable entity is physically missing.")
          if (!present && state %in% c("retracted","rejected") && !is_tomb) add("HISTORICAL_ENTITY_TOMBSTONE_MISSING",check_class="lifecycle",entity_kind=kind,entity_id=id,table="entity_lifecycle",observed=state,message="A missing retracted/rejected entity lacks a matching tombstone.")
        }
        if (.wb_table_exists(con,"entity_supersessions")) {
          sup <- DBI::dbGetQuery(con,"SELECT * FROM entity_supersessions;")
          for (i in seq_len(nrow(sup))) {
            successor <- life$entity_kind==sup$successor_kind[i] & life$entity_id==sup$successor_id[i]; predecessor <- life$entity_kind==sup$predecessor_kind[i] & life$entity_id==sup$predecessor_id[i]
            if (!any(successor) || !any(predecessor) || !identical(as.character(life$lifecycle_state[predecessor][1]),"superseded")) add("SUPERSESSION_STATE_INVALID",check_class="lifecycle",entity_kind=sup$predecessor_kind[i],entity_id=sup$predecessor_id[i],table="entity_supersessions",message="Supersession endpoints or lifecycle transition are invalid.")
          }
        }
      }
    })
  } else {
    for (x in c("sqlite_integrity", "matrix_content", "spaces_and_models", "artifacts", "provenance", "source_inputs", "lifecycle")) skip(x, "content", "requested structural validation does not read or hash payload content")
  }

  pending_paths <- if (dir.exists(root)) list.files(root, recursive = TRUE, full.names = FALSE, all.files = TRUE, no.. = TRUE) else character()
  pending_paths <- pending_paths[grepl("(^|/)\\.pending(/|$)|^\\.manifest[.]json[.](staging|backup)-|INGEST_FAILED[.]json$", pending_paths)]
  if (length(pending_paths)) for (path in pending_paths) {
    if (identical(basename(path),"INGEST_FAILED.json")) add("INGEST_FAILED_INCOMPLETE",check_class="recipient",entity_kind="ingestion",entity_id="failed",path=path,observed="present",message="Bundle ingestion failed/incomplete; see INGEST_FAILED.json marker.")
    else add("PENDING_WORKSPACE_RESIDUE", check_class = "recipient", entity_kind = "pending_publication", entity_id = basename(path), path = path, observed = "present", message = "Incomplete publication/ingestion residue is present.")
  }

  if (has_level("recipient")) timed("recipient", {
    lock <- tryCatch(wb_bundle_writer_lock_info(root), error = function(e) list(locked=FALSE))
    if (isTRUE(lock$locked)) add("ACTIVE_BUNDLE_WRITER", check_class="recipient",entity_kind="writer_lock",entity_id="exclusive",path=.wb_writer_lock_path(root),observed=.wb_writer_lock_diagnostic(lock),message="Recipient validation requires no active bundle writer.")
    if (!is.null(manifest)) {
      db <- file.path(root, as.character(manifest$storage$sqlite$path %||% "")); sidecars <- c(paste0(db,"-wal"),paste0(db,"-shm"),paste0(db,"-journal")); hit <- sidecars[file.exists(sidecars)]
      for (p in hit) add("SQLITE_UNRESOLVED_JOURNAL_STATE",check_class="recipient",entity_kind="sqlite",entity_id="main",path=substring(p,nchar(root)+2L),observed="present",message="Recipient bundle contains unresolved SQLite WAL/SHM/journal state.")
      if (!length(hit) && file.exists(db)) {
        immutable <- tryCatch({
          icon <- DBI::dbConnect(RSQLite::SQLite(), paste0("file:", normalizePath(db,winslash="/",mustWork=TRUE), "?immutable=1"), flags=RSQLite::SQLITE_RO)
          on.exit(DBI::dbDisconnect(icon), add=TRUE)
          DBI::dbGetQuery(icon,"SELECT COUNT(*) AS n FROM sqlite_schema;")
          TRUE
        }, error=function(e) e)
        if (inherits(immutable,"error")) add("SQLITE_IMMUTABLE_OPEN_FAILED",check_class="recipient",entity_kind="sqlite",entity_id="main",path=substring(db,nchar(root)+2L),observed=conditionMessage(immutable),message="Finalized recipient SQLite cannot be opened immutable/read-only.")
      }
    }
  }) else skip("recipient", "recipient", "finalized transfer invariants require level='recipient'")

  if (!is.null(con)) { try(DBI::dbDisconnect(con), silent=TRUE); con <- NULL }
  after_fingerprint <- if (has_level("recipient")) fingerprint() else NA_character_
  if (has_level("recipient") && !identical(before_fingerprint, after_fingerprint)) add("VALIDATION_MUTATED_BUNDLE",check_class="recipient",entity_kind="bundle",entity_id=basename(root),expected=before_fingerprint,observed=after_fingerprint,message="Recipient validation changed the bundle filesystem fingerprint.")

  if (nrow(diagnostics)) diagnostics <- diagnostics[order(diagnostics$severity, diagnostics$code, diagnostics$entity_kind, diagnostics$entity_id, diagnostics$path, na.last=TRUE),,drop=FALSE]
  rownames(diagnostics) <- NULL
  if (nrow(skipped)) skipped <- unique(skipped[order(skipped$check_class),,drop=FALSE])
  timings <- stats::aggregate(elapsed_seconds ~ check_class, timings, sum)
  timings <- timings[order(timings$check_class),,drop=FALSE]; timings$elapsed_seconds <- round(timings$elapsed_seconds, 6)
  errors <- diagnostics$severity == "error"
  finished <- Sys.time(); gc_after <- suppressWarnings(gc())
  peak_memory_mb <- max(c(gc_before[, 6L], gc_after[, 6L]), na.rm = TRUE)
  structure(list(
    schema_version = "scworkbench.bundle_validation_report.v1",
    bundle_path = root,
    bundle_manifest_version = manifest_version,
    requested_level = level,
    completed_levels = .wb_validation_levels()[seq_len(requested_index)],
    ok = !any(errors), status = if (any(errors)) "error" else if (any(diagnostics$severity == "warning")) "ok_with_warnings" else "ok",
    diagnostics = diagnostics, skipped_checks = skipped, elapsed_by_check_class = timings,
    elapsed_seconds = round(as.numeric(difftime(finished, started, units="secs")),6),
    peak_memory_mb = as.numeric(peak_memory_mb),
    started_at = format(started, "%Y-%m-%dT%H:%M:%OS6%z"), finished_at = format(finished, "%Y-%m-%dT%H:%M:%OS6%z"),
    pre_validation_fingerprint = before_fingerprint, post_validation_fingerprint = after_fingerprint
  ), class = c("scworkbench_bundle_validation_report", "list"))
}

#' Validate an scworkbench bundle on disk
#'
#' Preserves the established TRUE-or-error interface. By default it performs
#' content validation; `read_only=TRUE` requests the stronger finalized
#' recipient level. Use [wb_bundle_validation_report()] for structured details.
#'
#' @param bundle_dir Path to bundle directory.
#' @param read_only If `TRUE`, require recipient-transfer invariants in addition
#'   to content integrity.
#' @return `TRUE` if valid, otherwise errors with stable diagnostic codes.
#' @export
wb_validate_bundle <- function(bundle_dir, read_only = FALSE) {
  if (!is.character(bundle_dir) || length(bundle_dir) != 1L || is.na(bundle_dir) || !nzchar(bundle_dir)) {
    stop("wb_validate_bundle(): bundle_dir must be one non-empty path string; pass bundle$dir, not an open scworkbench_bundle handle.", call. = FALSE)
  }
  report <- wb_bundle_validation_report(bundle_dir, level = if (isTRUE(read_only)) "recipient" else "content")
  if (!isTRUE(report$ok)) {
    errors <- report$diagnostics[report$diagnostics$severity == "error",,drop=FALSE]
    detail <- paste0(errors$code, ifelse(is.na(errors$entity_id), "", paste0("[", errors$entity_id, "]")), ": ", errors$message)
    stop("Bundle integrity validation failed (", report$requested_level, "):\n- ", paste(detail, collapse="\n- "), call. = FALSE)
  }
  TRUE
}
