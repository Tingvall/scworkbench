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
  status <- .wb_path_status(root, raw, expected_type = expected_type,
                            must_exist = TRUE, purpose = "validation payload")
  if (isTRUE(status$ok) && dir.exists(status$absolute)) {
    return(.wb_path_tree_status(root, raw, purpose = "validation payload tree"))
  }
  status
}

.wb_validation_json <- function(x) {
  tryCatch(jsonlite::fromJSON(as.character(x)[1], simplifyVector = FALSE), error = function(e) NULL)
}

.wb_validation_model_payload_path <- function(con, model_space_id) {
  id <- as.character(model_space_id %||% "")[1]
  if (.wb_table_exists(con, "artifact_model_ref") &&
      .wb_db_has_column(con, "artifact_model_ref",
        "model_tree_manifest_json")) {
    retained <- DBI::dbGetQuery(con, paste0(
      "SELECT model_path FROM artifact_model_ref ",
      "WHERE model_space_id=? AND model_tree_manifest_json IS NOT NULL ",
      "AND model_tree_manifest_json<>'' ORDER BY artifact_id;"),
      params = list(id))
    paths <- unique(as.character(retained$model_path %||% character()))
    paths <- paths[nzchar(paths)]
    if (length(paths) == 1L) return(paths[[1L]])
  }
  if (.wb_table_exists(con, "space_models")) {
    row <- DBI::dbGetQuery(con,
      "SELECT model_path FROM space_models WHERE space_id=?;",
      params = list(id))
    if (nrow(row) == 1L) return(as.character(row$model_path[[1L]]))
  }
  ""
}

.wb_validation_process_memory <- function() {
  status <- "/proc/self/status"
  if (!file.exists(status)) return(list(rss_mb=NA_real_, peak_rss_mb=NA_real_))
  lines <- readLines(status, warn=FALSE)
  value <- function(key) {
    hit <- grep(paste0("^",key,":"),lines,value=TRUE)
    if (!length(hit)) return(NA_real_)
    as.numeric(sub("^.*:[[:space:]]*([0-9]+)[[:space:]]+kB.*$","\\1",hit[1])) / 1024
  }
  list(rss_mb=value("VmRSS"),peak_rss_mb=value("VmHWM"))
}

#' Describe bundle validation work and scaling
#'
#' @param level Cumulative validation level.
#' @return Data frame describing authoritative check classes and dominant scaling.
#' @export
wb_bundle_validation_plan <- function(level=c("content","structural","recipient")) {
  level <- match.arg(level); n <- match(level,.wb_validation_levels())
  plan <- data.frame(
    level=c("structural","content","content","content","content","recipient"),
    check_class=c("schema_and_registry","matrix_content","artifacts","provenance","content_completeness","recipient"),
    dominant_scaling=c("registry rows","matrix identities plus fragment count","artifact registry and payload identities","provenance rows","durable entities and payload bytes","bundle files and bytes (two fingerprints)"),
    external_files_accessed=FALSE,
    stringsAsFactors=FALSE
  )
  plan[seq_len(c(1L,5L,6L)[n]),,drop=FALSE]
}

.wb_validation_artifact_payload_table <- function(type) {
  switch(as.character(type)[1],
    graph = "artifact_graph_meta",
    cell_vector = "artifact_labels",
    cell_vector_family = "artifact_pseudotime",
    relation_family = "artifact_relation_rows",
    path_2d_family = "artifact_curves_2d",
    space_path_family = "artifact_space_path_rows",
    # space_2d artifacts reference the canonical spaces/space_payloads owner;
    # they never duplicate coordinate rows in an artifact table.
    space_2d = NA_character_,
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
#' commits, registry mutations, materializations, lifecycle history, and tagged
#' content identities. Its `content_coverage` result accounts for every
#' bundle-owned durable payload. Untagged legacy identities and missing
#' baselines remain explicit warnings, never current-scheme proofs. External
#' sources not declared as bundled are reported as uninspected unverifiable
#' warnings and are never accessed. A non-empty active SQLite WAL fails
#' closed before any database connection is opened.
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
#' @param progress `FALSE` for quiet operation, `TRUE` to emit check-class
#'   progress messages, or a function accepting one structured progress event.
#' @return A deterministic named report containing status, stable diagnostics,
#'   skipped checks, durable `content_coverage`, and elapsed time by check class.
#' @export
wb_bundle_validation_report <- function(bundle_dir,
                                        level = c("content", "structural", "recipient"),
                                        progress = FALSE) {
  level <- match.arg(level)
  if (!is.character(bundle_dir) || length(bundle_dir) != 1L || is.na(bundle_dir) || !nzchar(bundle_dir)) {
    stop("wb_bundle_validation_report(): bundle_dir must be one non-empty path string; pass bundle$dir, not an open scworkbench_bundle handle.", call. = FALSE)
  }
  started <- Sys.time()
  gc_before <- suppressWarnings(gc(reset = TRUE))
  diagnostics <- .wb_validation_empty_diagnostics()
  skipped <- .wb_validation_empty_skipped()
  timings <- data.frame(check_class = character(), elapsed_seconds = numeric(), stringsAsFactors = FALSE)
  content_coverage <- data.frame(
    entity_kind=character(),entity_id=character(),baseline_source=character(),
    recorded_scheme=character(),actual_scheme=character(),verification_status=character(),
    stringsAsFactors=FALSE
  )
  resource_samples <- data.frame(event=character(),check_class=character(),elapsed_seconds=numeric(),rss_mb=numeric(),peak_rss_mb=numeric(),stringsAsFactors=FALSE)
  emit_progress <- function(event,check_class) {
    mem <- .wb_validation_process_memory()
    record <- list(event=as.character(event),check_class=as.character(check_class),elapsed_seconds=as.numeric(difftime(Sys.time(),started,units="secs")),rss_mb=mem$rss_mb,peak_rss_mb=mem$peak_rss_mb)
    resource_samples[nrow(resource_samples)+1L,] <<- record
    if (isTRUE(progress)) message("[scworkbench validation] ",event," ",check_class," elapsed=",round(record$elapsed_seconds,3),"s rss=",round(record$rss_mb,1),"MB peak=",round(record$peak_rss_mb,1),"MB")
    else if (is.function(progress)) progress(record)
    invisible(record)
  }
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
  identity_scheme_state <- function(recorded_scheme, actual_scheme, entity_kind, entity_id, table, check_class="provenance") {
    recorded <- as.character(recorded_scheme %||% "")[1]; actual <- as.character(actual_scheme %||% "")[1]
    if (is.na(recorded) || !nzchar(recorded)) {
      add("CONTENT_IDENTITY_SCHEME_LEGACY_UNVERIFIABLE",severity="warning",check_class=check_class,entity_kind=entity_kind,entity_id=entity_id,table=table,expected=actual,observed="untagged",message="Legacy content hash has no identity scheme and is not interpreted as a current-scheme proof.")
      return("legacy")
    }
    supported <- unname(.wb_content_identity_schemes())
    if (!recorded %in% supported) {
      add("CONTENT_IDENTITY_SCHEME_UNSUPPORTED",check_class=check_class,entity_kind=entity_kind,entity_id=entity_id,table=table,expected=paste(supported,collapse=","),observed=recorded,message="Recorded content identity scheme is unsupported.")
      return("unsupported")
    }
    if (.wb_validation_nonempty(actual) && !identical(recorded,actual)) {
      add("CONTENT_IDENTITY_SCHEME_MISMATCH",check_class=check_class,entity_kind=entity_kind,entity_id=entity_id,table=table,expected=actual,observed=recorded,message="Recorded content identity scheme does not match the durable payload class.")
      return("mismatch")
    }
    "current"
  }
  integrity_scheme <- function(value, recorded_scheme, current_scheme, entity_kind, entity_id, table, field) {
    value <- tolower(as.character(value %||% "")[1])
    recorded <- as.character(recorded_scheme %||% "")[1]
    legacy <- unname(.wb_identity_schemes()[["legacy"]])
    if (is.na(recorded) || !nzchar(recorded)) {
      if (grepl("^[0-9a-f]{16}$", value)) recorded <- legacy
      else {
        add("INTEGRITY_IDENTITY_SCHEME_MISSING",check_class="provenance",entity_kind=entity_kind,entity_id=entity_id,table=table,expected=current_scheme,observed="missing",message=paste0(field," has no declared identity scheme."))
        return(NA_character_)
      }
    }
    if (!recorded %in% c(legacy,current_scheme)) {
      add("INTEGRITY_IDENTITY_SCHEME_UNSUPPORTED",check_class="provenance",entity_kind=entity_kind,entity_id=entity_id,table=table,expected=paste(c(legacy,current_scheme),collapse=","),observed=recorded,message=paste0(field," declares an unknown identity scheme."))
      return(NA_character_)
    }
    pattern <- if (identical(recorded,legacy)) "^[0-9a-f]{16}$" else "^[0-9a-f]{64}$"
    if (!grepl(pattern,value)) {
      add("INTEGRITY_DIGEST_SCHEME_CONTRADICTION",check_class="provenance",entity_kind=entity_kind,entity_id=entity_id,table=table,expected=paste0(recorded," digest"),observed=value,message=paste0(field," is malformed for its declared identity scheme."))
      return(NA_character_)
    }
    recorded
  }
  skip <- function(check_class, minimum_level, reason) {
    skipped[nrow(skipped) + 1L, ] <<- list(check_class, minimum_level, reason)
  }
  timed <- function(check_class, code) {
    emit_progress("start",check_class)
    t0 <- proc.time()[["elapsed"]]
    force(code)
    timings[nrow(timings) + 1L, ] <<- list(check_class, proc.time()[["elapsed"]] - t0)
    emit_progress("complete",check_class)
    invisible(TRUE)
  }
  requested_index <- match(level, .wb_validation_levels())
  has_level <- function(x) requested_index >= match(x, .wb_validation_levels())
  root <- normalizePath(bundle_dir, winslash = "/", mustWork = FALSE)
  failed_ingest_marker <- file.path(root, "INGEST_FAILED.json")
  if (file.exists(failed_ingest_marker)) {
    add("INGEST_FAILED_INCOMPLETE", check_class = "structural",
        entity_kind = "ingestion", entity_id = "failed", path = "INGEST_FAILED.json",
        observed = "present",
        message = "Bundle ingestion failed/incomplete; see INGEST_FAILED.json marker.")
  }
  if (has_level("recipient")) emit_progress("start","recipient_fingerprint_before")

  fingerprint <- function() {
    if (!dir.exists(root)) return(NA_character_)
    files <- sort(as.character(fs::dir_ls(root, recurse = TRUE, type = "file", all = TRUE, follow = FALSE)))
    safe <- vapply(files, function(path) {
      rel <- substring(path, nchar(root) + 2L)
      isTRUE(.wb_path_status(root, rel, must_exist = TRUE)$ok)
    }, logical(1))
    files <- files[safe]
    info <- file.info(files)
    .wb_prov_sha256_object(list(
      paths = substring(files, nchar(root) + 2L),
      size = as.numeric(info$size), mode = as.character(info$mode),
      sha256 = vapply(files,.wb_prov_sha256_file,character(1))
    ))
  }
  before_fingerprint <- if (has_level("recipient")) fingerprint() else NA_character_
  if (has_level("recipient")) emit_progress("complete","recipient_fingerprint_before")
  manifest <- NULL
  con <- NULL
  bundle <- NULL
  manifest_version <- NA_character_

  timed("bundle_layout", {
    if (!dir.exists(root)) {
      add("BUNDLE_DIRECTORY_MISSING", path = root, observed = "missing", message = "Bundle directory does not exist.")
    } else {
      manifest_checked <- .wb_validation_path(root,"manifest.json","file")
      if (!isTRUE(manifest_checked$ok)) {
        code <- if (identical(manifest_checked$code,"PAYLOAD_MISSING")) "MANIFEST_MISSING" else manifest_checked$code
        add(code,path="manifest.json",observed=manifest_checked$observed,message=if (identical(code,"MANIFEST_MISSING")) "manifest.json is missing." else "manifest.json is outside the bundle trust boundary.")
      } else {
        manifest <- tryCatch(jsonlite::read_json(manifest_checked$absolute, simplifyVector = TRUE), error = function(e) e)
        if (inherits(manifest, "error")) {
          add("MANIFEST_MALFORMED", path = "manifest.json", observed = conditionMessage(manifest), message = "manifest.json is not valid JSON.")
          manifest <- NULL
        }
      }
    }
  })

  if (!is.null(manifest)) timed("manifest", {
    manifest_version <- as.character(manifest$scworkbench_manifest_version %||% manifest$manifest_version %||% "")[1]
    if (!identical(manifest_version, "2.3.0")) {
      add("SCHEMA_VERSION_UNSUPPORTED", table = "manifest.json", expected = "2.3.0",
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
    } else if (identical(manifest_version, "2.3.0")) {
      add("MANIFEST_CREATION_METADATA_INVALID", entity_kind = "manifest", entity_id = "creation",
          table = "manifest.json", observed = "missing", message = "Manifest 2.3.0 requires immutable creation metadata.")
    }
    if (identical(manifest_version, "2.3.0")) {
      protocol <- as.character(manifest$publication$protocol %||% "")[1]
      state_source <- as.character(manifest$publication$state_source %||% "")[1]
      registry_fingerprint <- as.character(manifest$current_state$fingerprint %||% "")[1]
      if (!identical(protocol, "scworkbench.manifest.atomic.v1") ||
          !identical(state_source, "durable_manifest") ||
          !grepl("^[0-9a-f]{64}$", registry_fingerprint)) {
        add(
          "MANIFEST_PUBLICATION_METADATA_INVALID", check_class = "manifest",
          entity_kind = "manifest", entity_id = "publication", table = "manifest.json",
          expected = "atomic.v1 durable manifest with SHA-256 registry fingerprint",
          observed = paste(protocol, state_source, registry_fingerprint, sep = ";"),
          message = "Manifest publication metadata does not identify a valid authoritative durable snapshot."
        )
      }
    }
    db_rel <- as.character(manifest$storage$sqlite$path %||% "")[1]
    checked <- .wb_validation_path(root, db_rel, "file")
    if (!isTRUE(checked$ok)) {
      add(checked$code, check_class = "paths", entity_kind = "sqlite", entity_id = "main",
          path = db_rel, expected = "contained file", observed = checked$observed,
          message = "The manifest SQLite path is not a contained bundle file.")
    } else {
      # Even a mode=ro SQLite connection takes locks by writing bytes in an
      # existing SHM file. Path-only validation therefore fails closed when a
      # non-empty WAL must be consulted. Finalize the writer or validate an
      # explicitly supported snapshot; never touch supplied runtime sidecars.
      wal_path <- paste0(checked$absolute, "-wal")
      wal_nonempty <- file.exists(wal_path) && isTRUE(file.info(wal_path)$size > 0)
      con <- if (wal_nonempty) {
        add("SQLITE_ACTIVE_WAL_SNAPSHOT_REQUIRED", check_class = "sqlite", entity_kind = "sqlite", entity_id = "main",
            path = substring(wal_path, nchar(root) + 2L), observed = paste0(file.info(wal_path)$size, " bytes"),
            message = "A non-empty WAL cannot be authoritatively validated by path without mutating SHM lock bytes; finalize the bundle or provide a supported immutable snapshot.")
        NULL
      } else tryCatch(DBI::dbConnect(
        RSQLite::SQLite(), paste0("file:", checked$absolute, "?immutable=1"), flags = RSQLite::SQLITE_RO
      ), error = function(e) e)
      if (is.null(con)) {
        bundle <- NULL
      } else if (inherits(con, "error")) {
        add("SQLITE_OPEN_FAILED", check_class = "sqlite", entity_kind = "sqlite", entity_id = "main",
            path = db_rel, observed = conditionMessage(con), message = "SQLite could not be opened read-only.")
        con <- NULL
      } else {
        .wb_sqlite_configure_connection(con, writable = FALSE)
        bundle <- structure(list(dir = root, manifest = manifest, con = con, read_only = TRUE), class = "scworkbench_bundle")
      }
    }
  })
  on.exit(if (!is.null(con)) try(DBI::dbDisconnect(con), silent = TRUE), add = TRUE)

  # Only this fresh recipient report owns these observations. The immutable
  # SQL view and complete before/after filesystem proof remain authoritative;
  # expected provenance/physical claims are NEVER retained as actual evidence.
  table_observations <- list()
  table_report_epoch <- NULL
  table_epoch <- function() tryCatch({
    if (!identical(level, "recipient") || is.null(con) || !DBI::dbIsValid(con) ||
        isTRUE(RSQLite::sqliteIsTransacting(con))) return(NULL)
    if (DBI::dbGetQuery(con, "SELECT EXISTS(SELECT 1 FROM sqlite_temp_schema) AS n")$n[[1L]] ||
        DBI::dbGetQuery(con, paste0("SELECT COUNT(*) AS n FROM pragma_database_list ",
          "WHERE name NOT IN ('main','temp')"))$n[[1L]] != 0L) return(NULL)
    exact <- function(value) {
      text <- as.character(value)
      if (length(text) != 1L || is.na(text) || nchar(text, type = "bytes") > 16L ||
          !grepl("^(0|[1-9][0-9]*)$", text)) return(NULL)
      number <- suppressWarnings(as.numeric(text))
      if (!is.finite(number) || number > 2^53 - 1 ||
          !identical(sprintf("%.0f", number), text)) return(NULL)
      text
    }
    epochs <- list(changes = exact(DBI::dbGetQuery(con,
      "SELECT CAST(total_changes() AS TEXT) AS n")$n),
      data = exact(DBI::dbGetQuery(con, "PRAGMA main.data_version")[[1L]]),
      schema = exact(DBI::dbGetQuery(con, "PRAGMA main.schema_version")[[1L]]))
    if (any(vapply(epochs, is.null, logical(1)))) return(NULL)
    list(connection = con@ref, epochs = epochs)
  }, error = function(e) NULL)
  stored_table_actual_identity <- function(id) {
    complete <- FALSE
    on.exit(if (!complete) table_observations <<- list(), add = TRUE)
    actual <- function() list(content_sha256 = .wb_prov_stored_table_content_sha256(con, id),
      content_identity_scheme = unname(.wb_content_identity_schemes()[["table"]]))
    key <- function() {
      tryCatch({
        epoch <- table_epoch()
        if (is.null(epoch) || is.null(table_report_epoch) ||
            !identical(epoch, table_report_epoch) || length(id) != 1L || is.na(id) ||
            nchar(id, type = "bytes") > 32768) return(NULL)
        # Bound the actual header BEFORE fetching it; oversized metadata still
        # follows the original folding route, without a new artifact rejection.
        header <- DBI::dbGetQuery(con, paste0(
          "SELECT a.type,t.table_type,t.entity_kind,t.meta_json FROM artifacts a ",
          "JOIN artifact_tables t ON t.artifact_id=a.artifact_id WHERE a.artifact_id=? AND ",
          "COALESCE(octet_length(a.type),0)+COALESCE(octet_length(t.table_type),0)+",
          "COALESCE(octet_length(t.entity_kind),0)+COALESCE(octet_length(t.meta_json),0)<=32768 LIMIT 2"),
          params = list(id))
        if (nrow(header) != 1L || !header$type[[1L]] %in% c("feature_table", "obs_table") ||
            !identical(epoch, table_epoch())) return(NULL)
        result <- list(epoch = epoch, artifact_id = id, header = as.list(header))
        if (as.numeric(utils::object.size(result)) > 65536) return(NULL)
        result
      }, error = function(e) NULL)
    }
    before <- key()
    prior <- table_observations[[id]]
    if (!is.null(before) && !is.null(prior) && identical(before, prior$key)) {
      if (identical(before, key())) {
        complete <- TRUE
        return(prior$value)
      }
      table_observations <<- list()
      before <- key()
    } else if (is.null(before)) table_observations <<- list()
    value <- actual()
    if (!is.null(before) && identical(before, key())) {
      entry <- list(key = before, value = value)
      candidate <- table_observations
      candidate[[id]] <- entry
      if (as.numeric(utils::object.size(candidate)) <= 65536) table_observations <<- candidate else {
        candidate <- setNames(list(entry), id)
        table_observations <<- if (as.numeric(utils::object.size(candidate)) <= 65536)
          candidate else list()
      }
    } else table_observations <<- list()
    complete <- TRUE
    value
  }

  if (!is.null(con)) timed("schema_and_registry", {
    tables <- DBI::dbListTables(con)
    schema_status <- .wb_schema_status(con, verify_structure = TRUE)
    if (identical(schema_status$status, "current")) table_report_epoch <- table_epoch()
    if (!identical(schema_status$status, "current")) {
      add(
        "BUNDLE_SCHEMA_UPGRADE_REQUIRED", check_class = "schema",
        entity_kind = "sqlite", entity_id = "main", table = "bundle_schema_migrations",
        expected = paste0("version ", schema_status$current),
        observed = paste0("version ", schema_status$observed),
        message = schema_status$message
      )
    }
    foreign_key_violations <- DBI::dbGetQuery(con, "PRAGMA foreign_key_check;")
    if (nrow(foreign_key_violations)) for (index in seq_len(nrow(foreign_key_violations))) {
      violation <- foreign_key_violations[index, , drop = FALSE]
      add(
        "SQLITE_FOREIGN_KEY_VIOLATION", check_class = "schema",
        entity_kind = "registry_row", entity_id = as.character(violation$rowid[[1L]]),
        table = as.character(violation$table[[1L]]),
        expected = paste0("referenced row in ", violation$parent[[1L]]),
        observed = paste0("foreign-key id ", violation$fkid[[1L]]),
        message = "Durable registry row violates the centrally declared referential-integrity contract."
      )
    }
    required <- c("cells", "metadata_fields", "datasets", "features", "matrices", "spaces", "space_payloads")
    for (table in setdiff(required, tables)) {
      add("REQUIRED_TABLE_MISSING", table = table, observed = "missing", message = paste0("Required table is missing: ", table))
    }
    if (all(c("cells", "datasets", "features", "matrices", "spaces") %in% tables)) {
      counts <- c(
        n_cells = DBI::dbGetQuery(con, "SELECT COUNT(*) n FROM cells;")$n[1],
        n_datasets = DBI::dbGetQuery(con, "SELECT COUNT(*) n FROM datasets;")$n[1],
        n_spaces = DBI::dbGetQuery(con, "SELECT COUNT(*) n FROM spaces;")$n[1],
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
      feature_counts <- .wb_manifest_feature_counts(con)
      cached_feature_records <- suppressWarnings(as.integer(
        manifest$counts$feature_registry_records %||% NA_integer_
      )[1])
      if (!is.null(manifest$counts$n_features) ||
          is.na(cached_feature_records) ||
          cached_feature_records != feature_counts$feature_registry_records) {
        add(
          "MANIFEST_FEATURE_COUNT_SCHEMA_INVALID", check_class = "manifest",
          entity_kind = "registry", entity_id = "feature_registry_records",
          table = "manifest.json", expected = feature_counts$feature_registry_records,
          observed = cached_feature_records,
          message = "Manifest feature records must use the unambiguous 2.3 feature_registry_records field and must not publish counts$n_features."
        )
      }
      cached_by_matrix <- manifest$counts$feature_counts_by_matrix %||% list()
      cached_by_matrix <- if (length(cached_by_matrix)) {
        stats::setNames(
          as.list(suppressWarnings(as.integer(unlist(cached_by_matrix, use.names = FALSE)))),
          names(cached_by_matrix)
        )
      } else list()
      if (!identical(cached_by_matrix, feature_counts$feature_counts_by_matrix)) {
        add(
          "MANIFEST_FEATURE_COUNTS_BY_MATRIX_MISMATCH", check_class = "manifest",
          entity_kind = "registry", entity_id = "feature_counts_by_matrix",
          table = "manifest.json",
          expected = .wb_prov_sha256_object(feature_counts$feature_counts_by_matrix),
          observed = .wb_prov_sha256_object(cached_by_matrix),
          message = "Manifest matrix-scoped feature counts disagree with the authoritative matrix/feature registries."
        )
      }
      unique_count <- manifest$counts$bundle_unique_feature_count %||% list()
      expected_unique_count <- feature_counts$bundle_unique_feature_count
      if (!identical(as.character(unique_count$status %||% "")[1], expected_unique_count$status) ||
          !identical(as.character(unique_count$reason %||% "")[1], expected_unique_count$reason)) {
        add(
          "MANIFEST_BUNDLE_UNIQUE_FEATURE_COUNT_INVALID", check_class = "manifest",
          entity_kind = "registry", entity_id = "bundle_unique_feature_count",
          table = "manifest.json", expected = paste(expected_unique_count$status, expected_unique_count$reason),
          observed = paste(unique_count$status %||% "missing", unique_count$reason %||% "missing"),
          message = "A bundle-level unique feature count is not applicable without declared cross-matrix namespace equivalence."
        )
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
      if (identical(manifest_version, "2.3.0")) {
        authoritative_state <- .wb_manifest_registry_snapshot(con)
        cached_state <- manifest$current_state %||% list()
        cached_tables <- cached_state$tables %||% list()
        for (table in union(names(authoritative_state$tables), names(cached_tables))) {
          expected <- authoritative_state$tables[[table]] %||% list()
          observed <- cached_tables[[table]] %||% list()
          if (!identical(as.integer(expected$row_count %||% NA_integer_),
                         as.integer(observed$row_count %||% NA_integer_)) ||
              !identical(as.character(expected$content_sha256 %||% ""),
                         as.character(observed$content_sha256 %||% ""))) {
            add(
              "MANIFEST_REGISTRY_MISMATCH", check_class = "manifest",
              entity_kind = "registry", entity_id = table, table = "manifest.json",
              expected = paste(expected$row_count %||% "missing", expected$content_sha256 %||% "missing", sep = ":"),
              observed = paste(observed$row_count %||% "missing", observed$content_sha256 %||% "missing", sep = ":"),
              message = paste0("Manifest registry identity disagrees with committed table: ", table)
            )
          }
        }
        if (!identical(as.character(authoritative_state$fingerprint),
                       as.character(cached_state$fingerprint %||% ""))) {
          add(
            "MANIFEST_REGISTRY_MISMATCH", check_class = "manifest",
            entity_kind = "registry", entity_id = "current_state", table = "manifest.json",
            expected = authoritative_state$fingerprint,
            observed = cached_state$fingerprint %||% "missing",
            message = "Manifest current-state fingerprint disagrees with committed registry state."
          )
        }
      }
      cells <- DBI::dbGetQuery(con, "SELECT cell_id, dataset_id FROM cells ORDER BY rowid;")
      if (anyNA(cells$cell_id) || any(!nzchar(as.character(cells$cell_id))) || anyDuplicated(cells$cell_id)) {
        add("CELL_IDENTITY_DUPLICATE_OR_EMPTY", entity_kind = "cell", table = "cells",
            observed = "duplicate, missing, or empty cell_id", message = "Canonical cell identities must be non-empty and unique.")
      }
      if ("metadata_fields" %in% tables) {
        fields <- DBI::dbGetQuery(con, "SELECT * FROM metadata_fields ORDER BY rowid;")
        physical <- DBI::dbGetQuery(con, paste0("PRAGMA table_info(", .wb_quote_identifier(con, "cells"), ");"))
        missing_map <- setdiff(as.character(physical$name), as.character(fields$storage_name))
        dangling_map <- setdiff(as.character(fields$storage_name), as.character(physical$name))
        if (length(missing_map)) add(
          "METADATA_FIELD_MAPPING_MISSING", check_class = "schema", entity_kind = "metadata_field",
          entity_id = paste(missing_map, collapse = ","), table = "metadata_fields",
          observed = "unregistered cells column", message = "Every cells-table column must have one durable metadata-field mapping."
        )
        if (length(dangling_map)) add(
          "METADATA_FIELD_MAPPING_DANGLING", check_class = "schema", entity_kind = "metadata_field",
          entity_id = paste(dangling_map, collapse = ","), table = "metadata_fields",
          observed = "missing cells column", message = "Metadata-field mapping refers to absent physical storage."
        )
        folded <- tolower(enc2utf8(as.character(fields$storage_name)))
        if (anyDuplicated(folded)) add(
          "METADATA_FIELD_STORAGE_CONFLICT", check_class = "schema", entity_kind = "metadata_field",
          table = "metadata_fields", observed = "case-fold collision",
          message = "Physical metadata storage names must be unique under SQLite identifier folding."
        )
        non_resolvable <- is.na(fields$field_id) | !nzchar(as.character(fields$field_id)) |
          is.na(fields$display_name) | !nzchar(as.character(fields$display_name)) |
          is.na(fields$storage_name) | !nzchar(as.character(fields$storage_name)) |
          !(as.character(fields$storage_type) %in% c("INTEGER", "REAL", "TEXT"))
        if (any(non_resolvable)) add(
          "METADATA_FIELD_NON_RESOLVABLE", check_class = "schema", entity_kind = "metadata_field",
          entity_id = paste(which(non_resolvable), collapse = ","), table = "metadata_fields",
          observed = "missing or invalid canonical identity", message = "Every metadata mapping must resolve through a non-empty stable, display, and storage identity."
        )
        core_expected <- paste0("core:", .wb_metadata_core_fields())
        core_observed <- as.character(fields$field_id[fields$is_core == 1L])
        if (!setequal(core_expected, core_observed)) add(
          "METADATA_FIELD_CORE_CONFLICT", check_class = "schema", entity_kind = "metadata_field",
          table = "metadata_fields", expected = paste(core_expected, collapse = ","),
          observed = paste(core_observed, collapse = ","), message = "Engine-owned cells fields are missing or conflicting."
        )
        for (i in seq_len(nrow(fields))) {
          match_type <- physical$type[match(tolower(fields$storage_name[[i]]), tolower(physical$name))]
          canonical_type <- if (!length(match_type) || is.na(match_type)) NA_character_ else if (grepl("INT", toupper(match_type))) "INTEGER" else if (grepl("REAL|FLOA|DOUB|NUM", toupper(match_type))) "REAL" else "TEXT"
          if (is.na(canonical_type) || !identical(canonical_type, as.character(fields$storage_type[[i]]))) add(
            "METADATA_FIELD_TYPE_CONFLICT", check_class = "schema", entity_kind = "metadata_field",
            entity_id = fields$field_id[[i]], table = "metadata_fields",
            expected = canonical_type, observed = fields$storage_type[[i]],
            message = "Metadata field storage type disagrees with physical SQLite storage."
          )
        }
        if ("metadata_field_identities" %in% tables) {
          identities <- DBI::dbGetQuery(con, "SELECT * FROM metadata_field_identities ORDER BY field_id,identity_version;")
          non_core <- as.character(fields$field_id[fields$is_core == 0L])
          for (fid in non_core) {
            current <- identities$identity_id[identities$field_id == fid & identities$is_current == 1L]
            if (length(current) != 1L) add(
              "METADATA_FIELD_CURRENT_IDENTITY_INVALID", check_class = "provenance",
              entity_kind = "metadata_field", entity_id = fid, table = "metadata_field_identities",
              expected = "exactly one", observed = length(current),
              message = "Every non-core metadata field must have one authoritative current identity."
            )
          }
          for (i in seq_len(nrow(identities))) if (identities$is_current[[i]] == 1L) {
            hit <- DBI::dbGetQuery(con, paste(
              "SELECT COUNT(*) AS n FROM prov_run_entity_bindings WHERE snapshot_id=? AND run_id=?",
              "AND entity_kind='metadata_field' AND entity_id=? AND relationship_type IN ('PRODUCES','MATERIALIZES')",
              "AND content_hash=? AND content_identity_scheme=?;"
            ), params = list(identities$snapshot_id[[i]], identities$run_id[[i]], identities$field_id[[i]],
                             identities$content_sha256[[i]], identities$content_identity_scheme[[i]]))$n[[1L]]
            if (is.na(hit) || hit != 1L) add(
              "METADATA_FIELD_PRODUCER_BINDING_INVALID", check_class = "provenance",
              entity_kind = "metadata_field", entity_id = identities$field_id[[i]],
              table = "metadata_field_identities", expected = "one matching current producer", observed = hit,
              message = "Current metadata content identity and producer binding must be published together."
            )
          }
        }
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
      list(table = "space_payloads", id = "space_id", column = "path", type = "file", kind = "space"),
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
    if (.wb_table_exists(con,"prov_run_outputs") && "materialization_path" %in% DBI::dbListFields(con,"prov_run_outputs")) {
      rows <- DBI::dbGetQuery(con,"SELECT run_id,output_name,materialization_path FROM prov_run_outputs WHERE materialization_path IS NOT NULL AND materialization_path <> '' ORDER BY run_id,output_name;")
      if (nrow(rows)) for (i in seq_len(nrow(rows))) {
        raw <- as.character(rows$materialization_path[i])
        checked <- .wb_validation_path(root,raw,"either")
        if (!isTRUE(checked$ok)) add(checked$code,check_class="paths",entity_kind="materialization",entity_id=paste(rows$run_id[i],rows$output_name[i],sep="::"),path=raw,table="prov_run_outputs",expected="contained materialization",observed=checked$observed,message="Invalid durable materialization_path in prov_run_outputs.")
      }
    }
    if (.wb_table_exists(con,"prov_run_entity_bindings")) {
      rows <- DBI::dbGetQuery(con,"SELECT run_id,binding_name,entity_kind,entity_id,path FROM prov_run_entity_bindings WHERE direction='output' AND path IS NOT NULL AND path <> '' ORDER BY run_id,binding_name;")
      if (nrow(rows)) for (i in seq_len(nrow(rows))) {
        raw <- as.character(rows$path[i])
        checked <- .wb_validation_path(root,raw,"either")
        if (!isTRUE(checked$ok)) add(checked$code,check_class="paths",entity_kind=as.character(rows$entity_kind[i]),entity_id=as.character(rows$entity_id[i]),path=raw,table="prov_run_entity_bindings",expected="contained output binding",observed=checked$observed,message="Invalid durable output path in prov_run_entity_bindings.")
      }
    }
  }
  timed("paths", check_paths())

  if (has_level("content") && !is.null(con)) {
    db_path <- .wb_bundle_path_require(root,as.character(manifest$storage$sqlite$path %||% ""),expected_type="file",purpose="manifest SQLite database")
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
        canonical_cells <- as.character(DBI::dbGetQuery(con, "SELECT cell_id FROM cells ORDER BY rowid;")$cell_id)
        for (i in seq_len(nrow(spaces))) {
          id <- as.character(spaces$space_id[i]); dims <- as.integer(spaces$dims[i]); storage <- as.character(spaces$storage[i] %||% "")
          if (identical(storage, .wb_space_payload_storage())) {
            registry <- DBI::dbGetQuery(con, "SELECT * FROM space_payloads WHERE space_id = ?;",
                                        params = list(id))
            if (nrow(registry) != 1L) {
              add("SPACE_PAYLOAD_REGISTRY_MISSING", check_class = "spaces_and_models",
                  entity_kind = "space", entity_id = id, table = "space_payloads",
                  observed = nrow(registry), message = "File-backed space has no unique payload registry row.")
              next
            }
            checked <- .wb_path_status(root, as.character(registry$path[[1L]]), expected_type = "file",
                                       must_exist = TRUE, purpose = "dense-space validation payload")
            if (!isTRUE(checked$ok)) {
              path_code <- if (identical(checked$code, "PAYLOAD_MISSING")) {
                "SPACE_PAYLOAD_MISSING"
              } else if (checked$code %in% c("PATH_ESCAPE", "PATH_SYMLINK_ESCAPE", "PATH_ABSOLUTE", "PATH_TYPE_MISMATCH")) {
                paste0("SPACE_PAYLOAD_", checked$code)
              } else "SPACE_PAYLOAD_PATH_INVALID"
              add(path_code,
                  check_class = "spaces_and_models", entity_kind = "space", entity_id = id,
                  table = "space_payloads", path = as.character(registry$path[[1L]]),
                  observed = checked$code, message = "Dense-space payload path is missing, escaped, or invalid.")
              next
            }
            failure <- tryCatch({
              meta <- .wb_space_payload_validate_file(checked$absolute, expected = registry,
                                                       verify_hash = TRUE, validate_values = TRUE)
              .wb_assert(identical(as.integer(dims), as.integer(meta$n_dims)),
                         "SPACE_PAYLOAD_REGISTRY_MISMATCH: spaces.dims differs from payload.")
              dangling <- setdiff(meta$cell_ids, canonical_cells)
              .wb_assert(!length(dangling),
                         "SPACE_DANGLING_CELL_REFERENCE: payload contains unknown cells.")
              NULL
            }, error = function(e) e)
            if (inherits(failure, "error")) {
              message <- conditionMessage(failure)
              code <- regmatches(message, regexpr("^[A-Z][A-Z0-9_]+", message))
              if (!length(code) || !nzchar(code)) code <- "SPACE_PAYLOAD_CORRUPT"
              add(code, check_class = "spaces_and_models", entity_kind = "space", entity_id = id,
                  table = "space_payloads", path = as.character(registry$path[[1L]]),
                  observed = message, message = "Dense-space payload failed closed validation.")
            }
            next
          } else if (grepl("wide:space_2d", storage, fixed = TRUE) ||
                     (identical(dims, 2L) && .wb_table_exists(con, "space_2d"))) {
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
        for (legacy in intersect(c("space_coords", "space_2d"), DBI::dbListTables(con))) {
          n_legacy <- as.integer(DBI::dbGetQuery(con, paste0("SELECT COUNT(*) AS n FROM ", legacy, ";"))$n[[1L]])
          if (n_legacy > 0L) add("LEGACY_SPACE_COORDINATE_ROWS_PRESENT", check_class = "spaces_and_models",
                                  entity_kind = "registry", entity_id = legacy, table = legacy,
                                  observed = n_legacy,
                                  message = "Coordinate-value rows are forbidden in current dense-space bundles.")
        }
      }
      if (.wb_table_exists(con, "space_models")) {
        models <- DBI::dbGetQuery(con, "SELECT * FROM space_models ORDER BY space_id;")
        spaces_ids <- if (.wb_table_exists(con, "spaces")) DBI::dbGetQuery(con, "SELECT space_id FROM spaces;")$space_id else character()
        for (i in seq_len(nrow(models))) {
          id <- as.character(models$space_id[i])
          if (!id %in% spaces_ids) add("MODEL_DANGLING_OUTPUT_SPACE", check_class = "spaces_and_models", entity_kind = "model", entity_id = id, table = "space_models", observed = id, message = "Model output identity is not a registered durable space.")
          if (!as.character(models$source_space_id[i]) %in% spaces_ids) add("MODEL_DANGLING_SOURCE_SPACE", check_class = "spaces_and_models", entity_kind = "model", entity_id = id, table = "space_models", observed = models$source_space_id[i], message = "Model references an unregistered source space.")
          checked <- .wb_validation_path(root, models$model_path[i], "either")
          if (isTRUE(checked$ok)) {
            life <- if (.wb_table_exists(con, "entity_lifecycle")) wb_entity_lifecycle(bundle, "model", id) else data.frame()
            provenance_bound <- nrow(life) && identical(as.integer(life$provenance_bound[1]), 1L)
            if (!provenance_bound) add("MODEL_DESERIALIZATION_TRUST_REQUIRED", severity = "warning", check_class = "deserialization_trust", entity_kind = "model", entity_id = id, path = models$model_path[i], observed = "contained but not provenance-bound", message = "Serialized model payload was not loaded; explicit opt-in is required because trusted provenance/runtime is absent.")
          }
        }
      }
    })

    timed("normalized_memberships", {
      if (all(c("motif_match_membership", "motif_match_sets", "features") %in% DBI::dbListTables(con))) {
        dangling <- DBI::dbGetQuery(con, "
          SELECT membership.motif_match_set, membership.feature_id, match_set.matrix_id
          FROM motif_match_membership AS membership
          JOIN motif_match_sets AS match_set
            ON match_set.motif_match_set = membership.motif_match_set
          LEFT JOIN features AS feature
            ON feature.matrix_id = match_set.matrix_id
           AND feature.feature_id = membership.feature_id
          WHERE feature.feature_id IS NULL
          ORDER BY membership.motif_match_set, membership.feature_id;
        ")
        if (nrow(dangling)) for (i in seq_len(nrow(dangling))) add(
          "MOTIF_MATCH_DANGLING_MATRIX_FEATURE", check_class = "normalized_memberships",
          entity_kind = "motif_match_set", entity_id = dangling$motif_match_set[i],
          table = "motif_match_membership",
          expected = paste0(dangling$matrix_id[i], "::", dangling$feature_id[i]),
          observed = "feature absent from match-set matrix",
          message = "Motif-match membership references a feature outside its match-set matrix."
        )
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
          if (identical(type, "graph")) {
            verified <- tryCatch({
              .wb_graph_retained_identities(bundle, id)
              .wb_graph_sources_assert(bundle, con, id, .wb_graph_budgets())
              NULL
            }, error = identity)
            if (!is.null(verified)) add("GRAPH_RETAINED_AUTHORITY_INVALID", check_class = "artifacts",
              entity_kind = "artifact", entity_id = id, table = "artifact_graph_meta",
              observed = conditionMessage(verified),
              message = "Graph content, bindings, retained descriptor or required source authority could not be authenticated.")
          }
          if (identical(type, "space_2d")) {
            referenced_space <- as.character(arts$input_space_id[i] %||% "")[1L]
            n_ref <- if (nzchar(referenced_space)) DBI::dbGetQuery(
              con, "SELECT COUNT(*) AS n FROM space_payloads WHERE space_id = ?;",
              params = list(referenced_space)
            )$n[[1L]] else 0L
            if (as.integer(n_ref) != 1L) add(
              "ARTIFACT_SPACE_PAYLOAD_MISSING", check_class = "artifacts",
              entity_kind = "artifact", entity_id = id, table = "space_payloads",
              expected = referenced_space, observed = n_ref,
              message = "space_2d artifact does not reference one durable file-backed space payload."
            )
          }
          if (!is.na(table)) {
            n <- if (.wb_table_exists(con, table)) DBI::dbGetQuery(con, paste0("SELECT COUNT(*) n FROM ", table, " WHERE artifact_id=?;"), params = list(id))$n[1] else 0L
            # Empty tabular artifacts are legitimate but still require their header row.
            if (n < 1L) add("ARTIFACT_PAYLOAD_MISSING", check_class = "artifacts", entity_kind = "artifact", entity_id = id, table = table, expected = ">=1 registry/payload row", observed = n, message = "Artifact has no payload row for its declared primitive type.")
          }
          prov <- tryCatch(jsonlite::fromJSON(as.character(arts$provenance_json[i]), simplifyVector = FALSE), error = function(e) NULL)
          if (is.null(prov)) add("ARTIFACT_PROVENANCE_MALFORMED", check_class = "artifacts", entity_kind = "artifact", entity_id = id, table = "artifacts", observed = "invalid JSON", message = "Artifact provenance_json is malformed.")
        }
        ancestry <- .wb_art_dependency_edges(bundle)
        if (nrow(ancestry)) for (i in seq_len(nrow(ancestry))) {
          parent <- as.character(ancestry$parent_artifact_id[i]); child <- as.character(ancestry$child_artifact_id[i])
          if (!parent %in% known || !child %in% known) add("ARTIFACT_DANGLING_ANCESTRY",check_class="artifacts",entity_kind="artifact",entity_id=child,table="artifacts.provenance_json",expected=parent,observed=if(parent %in% known) "child missing" else "parent missing",message="Persisted artifact ancestry references an artifact that is not durable in the bundle.")
        }
      }
    })

    timed("provenance", {
      tables <- DBI::dbListTables(con)
      has <- function(x) x %in% tables
      runs <- if (has("prov_runs")) DBI::dbGetQuery(con, "SELECT * FROM prov_runs ORDER BY snapshot_id,run_id;") else data.frame(snapshot_id=character(),run_id=character())
      run_key <- paste(runs$snapshot_id, runs$run_id, sep = "\r")
      head_schemas <- if (has("prov_heads")) DBI::dbGetQuery(con,"SELECT snapshot_id,schema_version FROM prov_heads;") else data.frame()
      edges <- if (has("prov_run_edges")) DBI::dbGetQuery(con, "SELECT * FROM prov_run_edges;") else data.frame()
      output_index <- if (has("prov_run_outputs")) DBI::dbGetQuery(con, "SELECT * FROM prov_run_outputs;") else data.frame()
      binding_index <- if (has("prov_run_entity_bindings")) DBI::dbGetQuery(con, "SELECT * FROM prov_run_entity_bindings;") else data.frame()
      artifact_ids <- if (has("artifacts")) as.character(DBI::dbGetQuery(con,"SELECT artifact_id FROM artifacts;")$artifact_id) else character()
      json_fields <- c(
        params_json = "RUN_PARAMS_JSON_MALFORMED",
        inputs_json = "RUN_INPUTS_JSON_MALFORMED",
        symbolic_inputs_json = "RUN_SYMBOLIC_INPUTS_JSON_MALFORMED",
        execution_inputs_json = "RUN_EXECUTION_INPUTS_JSON_MALFORMED",
        runtime_fingerprint_json = "RUN_RUNTIME_FINGERPRINT_JSON_MALFORMED",
        contract_json = "RUN_CONTRACT_JSON_MALFORMED"
      )
      if (nrow(runs)) for (i in seq_len(nrow(runs))) {
        sid <- as.character(runs$snapshot_id[i]); rid <- as.character(runs$run_id[i]); run_entity <- paste(sid,rid,sep="/")
        schema_version <- if (nrow(head_schemas) && any(head_schemas$snapshot_id==sid)) as.character(head_schemas$schema_version[match(sid,head_schemas$snapshot_id)]) else NA_character_
        current_contract <- identical(schema_version,.wb_prov_schema_version())
        typed_contract <- schema_version %in% c("1.7","1.8","1.9","1.10")
        parsed <- list(); malformed <- character()
        for (field in names(json_fields)) {
          txt <- if (field %in% names(runs)) as.character(runs[[field]][i] %||% "")[1] else ""
          required <- field %in% c("params_json","inputs_json") || field %in% names(runs)
          if (!required || is.na(txt) || !nzchar(txt)) {
            if (field %in% c("params_json","inputs_json")) {
              add(json_fields[[field]],check_class="provenance",entity_kind="run",entity_id=run_entity,table="prov_runs",observed="missing",message=paste0(field," is required and must contain a JSON object."))
              malformed <- c(malformed,field)
            }
            next
          }
          value <- tryCatch(jsonlite::fromJSON(txt,simplifyVector=FALSE),error=function(e)e)
          if (inherits(value,"error") || is.null(value) || !is.list(value)) {
            add(json_fields[[field]],check_class="provenance",entity_kind="run",entity_id=run_entity,table="prov_runs",observed=if(inherits(value,"error")) conditionMessage(value) else "not a JSON object",message=paste0(field," is not a valid persisted run-contract object."))
            malformed <- c(malformed,field)
          } else parsed[[field]] <- value
        }
        op_name <- as.character(runs$op_name[i] %||% "")[1]
        op_version <- as.character(runs$op_version[i] %||% "")[1]
        if (!nzchar(op_name)) add("RUN_OPERATION_IDENTITY_INVALID",check_class="provenance",entity_kind="run",entity_id=run_entity,table="prov_runs",observed="empty op_name",message="Persisted run operation identity is empty.")
        if (!nzchar(op_version)) {
          if (typed_contract) add("RUN_OPERATION_VERSION_INVALID",check_class="provenance",entity_kind="run",entity_id=run_entity,table="prov_runs",observed="missing op_version",message="Persisted run operation version is missing.")
          else add("RUN_OPERATION_VERSION_LEGACY_UNVERIFIABLE",severity="warning",check_class="provenance",entity_kind="run",entity_id=run_entity,table="prov_runs",observed="legacy schema without op_version",message="Legacy run predates versioned operation identity and cannot be upgraded during read-only validation.")
        }
        else if (!identical(op_version,"1")) add("RUN_OPERATION_VERSION_UNSUPPORTED",check_class="provenance",entity_kind="run",entity_id=run_entity,table="prov_runs",expected="1",observed=op_version,message="Persisted run operation-contract version is unsupported.")
        if (all(c("params_json","inputs_json","symbolic_inputs_json","execution_inputs_json") %in% names(runs))) {
          observed_run_hash <- as.character(runs$run_hash[i] %||% "")[1]
          observed_run_scheme <- if ("run_hash_scheme" %in% names(runs)) runs$run_hash_scheme[i] else NA_character_
          run_scheme <- integrity_scheme(observed_run_hash,observed_run_scheme,unname(.wb_identity_schemes()[["run"]]),"run",run_entity,"prov_runs","run_hash")
          if (!is.na(run_scheme)) {
            expected_run_hash <- .wb_prov_run_hash(op_name,runs$params_json[i],runs$inputs_json[i],runs$symbolic_inputs_json[i],runs$execution_inputs_json[i],scheme=run_scheme)
            if (!identical(tolower(observed_run_hash),tolower(expected_run_hash))) add("RUN_HASH_MISMATCH",check_class="provenance",entity_kind="run",entity_id=run_entity,table="prov_runs",expected=expected_run_hash,observed=observed_run_hash,message="Persisted run fields no longer match the producer run_hash contract.")
          }
        }
        contract_txt <- as.character(runs$contract_json[i] %||% "")[1]
        contract_hash <- as.character(runs$contract_hash[i] %||% "")[1]
        if (nzchar(contract_txt) && !is.na(contract_txt)) {
          observed_contract_scheme <- if ("contract_hash_scheme" %in% names(runs)) runs$contract_hash_scheme[i] else NA_character_
          contract_scheme <- integrity_scheme(contract_hash,observed_contract_scheme,unname(.wb_identity_schemes()[["contract"]]),"run",run_entity,"prov_runs","contract_hash")
          if (!is.na(contract_scheme)) {
            expected_contract_hash <- .wb_prov_contract_hash(contract_txt,scheme=contract_scheme)
            if (!identical(tolower(contract_hash),tolower(expected_contract_hash))) add("RUN_CONTRACT_HASH_MISMATCH",check_class="provenance",entity_kind="run",entity_id=run_entity,table="prov_runs",expected=expected_contract_hash,observed=contract_hash,message="Persisted operation contract no longer matches contract_hash.")
          }
          contract <- parsed$contract_json
          contract_op <- as.character(contract$interface$op_name %||% "")[1]
          contract_version <- as.character(contract$version %||% "")[1]
          if (!is.null(contract) && (!identical(contract_op,op_name) || !identical(contract_version,op_version))) add("RUN_CONTRACT_IDENTITY_MISMATCH",check_class="provenance",entity_kind="run",entity_id=run_entity,table="prov_runs",expected=paste(op_name,op_version,sep="@"),observed=paste(contract_op,contract_version,sep="@"),message="Recorded contract operation identity/version contradicts the run row.")
          if (current_contract && !is.null(contract) && !is.null(parsed$params_json) && !identical(.wb_prov_sha256_object(contract$parameters %||% list()),.wb_prov_sha256_object(parsed$params_json))) add("RUN_CONTRACT_PARAMETERS_MISMATCH",check_class="provenance",entity_kind="run",entity_id=run_entity,table="prov_runs",message="Recorded contract parameters contradict params_json.")
          if (current_contract && !is.null(contract) && !is.null(parsed$execution_inputs_json) && !identical(.wb_prov_sha256_object(contract$resolved_inputs %||% list()),.wb_prov_sha256_object(parsed$execution_inputs_json))) add("RUN_CONTRACT_EXECUTION_INPUTS_MISMATCH",check_class="provenance",entity_kind="run",entity_id=run_entity,table="prov_runs",message="Recorded contract resolved inputs contradict execution_inputs_json.")
        } else if ("contract_json" %in% names(runs)) add("RUN_CONTRACT_MISSING",severity="warning",check_class="provenance",entity_kind="run",entity_id=run_entity,table="prov_runs",observed="missing",message="Legacy run has no recorded operation contract.")

        expected_bindings <- c(
          .wb_prov_collect_entity_bindings(parsed$execution_inputs_json %||% list(),"resolved"),
          .wb_prov_collect_entity_bindings(parsed$inputs_json$user_inputs %||% list(),"input")
        )
        if (length(expected_bindings)) for (binding in expected_bindings) {
          hit <- nrow(binding_index) && any(binding_index$snapshot_id==sid & binding_index$run_id==rid & binding_index$direction=="input" & binding_index$binding_name==binding$binding_name & binding_index$entity_kind==binding$entity_kind & binding_index$entity_id==binding$entity_id)
          if (!hit) {
            if (typed_contract) add("RUN_TYPED_INPUT_BINDING_MISSING",check_class="provenance",entity_kind=binding$entity_kind,entity_id=binding$entity_id,table="prov_run_entity_bindings",expected=binding$binding_name,observed=run_entity,message="Resolved typed run input lacks its exact persisted entity binding.")
            else add("RUN_TYPED_INPUT_BINDING_LEGACY_UNVERIFIABLE",severity="warning",check_class="provenance",entity_kind=binding$entity_kind,entity_id=binding$entity_id,table="prov_run_entity_bindings",expected=binding$binding_name,observed=run_entity,message="Legacy run predates exact typed input bindings and remains ancestry-unverifiable.")
          }
        }
        if (identical(schema_version, "1.10")) {
          resolutions <- .wb_cell_set_resolution_records(
            parsed$inputs_json$cell_set_resolutions %||% list()
          )
          run_cell_bindings <- if (nrow(binding_index)) binding_index[
            binding_index$snapshot_id==sid & binding_index$run_id==rid &
              binding_index$direction=="input" & binding_index$entity_kind=="cell_set" &
              binding_index$relationship_type=="CONSUMES",,drop=FALSE
          ] else data.frame()
          declared_keys <- character(0)
          if (length(resolutions)) for (resolution in resolutions) {
            role <- as.character(resolution$binding_name %||% "")[1]
            set_id <- as.character(resolution$entity_id %||% "")[1]
            declared_keys <- c(declared_keys,paste(role,set_id,sep="\r"))
            exact <- if (nrow(run_cell_bindings))
              run_cell_bindings$binding_name==role & run_cell_bindings$entity_id==set_id else logical(0)
            same_role <- if (nrow(run_cell_bindings)) run_cell_bindings$binding_name==role else logical(0)
            same_set <- if (nrow(run_cell_bindings)) run_cell_bindings$entity_id==set_id else logical(0)
            if (!any(exact)) {
              if (any(same_set)) add("RUN_NAMED_CELL_SET_BINDING_ROLE_MISMATCH",check_class="provenance",entity_kind="cell_set",entity_id=set_id,table="prov_run_entity_bindings",expected=role,observed=paste(unique(run_cell_bindings$binding_name[same_set]),collapse=","),message="Named cell-set consumption is persisted under the wrong scientific binding role.")
              else if (any(same_role)) add("RUN_NAMED_CELL_SET_BINDING_SET_MISMATCH",check_class="provenance",entity_kind="cell_set",entity_id=set_id,table="prov_run_entity_bindings",expected=set_id,observed=paste(unique(run_cell_bindings$entity_id[same_role]),collapse=","),message="Named cell-set consumption binding identifies the wrong durable set.")
              else add("RUN_NAMED_CELL_SET_BINDING_MISSING",check_class="provenance",entity_kind="cell_set",entity_id=set_id,table="prov_run_entity_bindings",expected=role,observed=run_entity,message="A new typed run resolved a durable named cell set but lacks its exact persisted CONSUMES binding.")
              next
            }
            row <- run_cell_bindings[which(exact)[1],,drop=FALSE]
            expected_source_sha <- as.character(resolution$source_membership_sha256 %||% "")[1]
            expected_effective_sha <- as.character(resolution$effective_membership_sha256 %||% "")[1]
            expected_source_n <- suppressWarnings(as.integer(resolution$source_member_count %||% NA_integer_)[1])
            expected_effective_n <- suppressWarnings(as.integer(resolution$effective_member_count %||% NA_integer_)[1])
            recorded_source_sha <- as.character(row$source_membership_sha256 %||% "")[1]
            recorded_effective_sha <- as.character(row$effective_membership_sha256 %||% "")[1]
            recorded_source_scheme <- as.character(row$source_membership_identity_scheme %||% "")[1]
            recorded_effective_scheme <- as.character(row$effective_membership_identity_scheme %||% "")[1]
            recorded_source_n <- suppressWarnings(as.integer(row$source_member_count %||% NA_integer_)[1])
            recorded_effective_n <- suppressWarnings(as.integer(row$effective_member_count %||% NA_integer_)[1])
            resolution_json <- tryCatch(jsonlite::fromJSON(as.character(row$resolution_json %||% ""),simplifyVector=FALSE),error=function(e) NULL)
            record_matches <- identical(as.character(resolution$schema %||% "")[1],.wb_cell_set_resolution_schema()) &&
              grepl("^[0-9a-f]{64}$",expected_source_sha) && grepl("^[0-9a-f]{64}$",expected_effective_sha) &&
              identical(tolower(expected_source_sha),tolower(recorded_source_sha)) &&
              identical(tolower(expected_effective_sha),tolower(recorded_effective_sha)) &&
              identical(recorded_source_scheme,.wb_cell_set_membership_scheme()) &&
              identical(recorded_effective_scheme,.wb_cell_set_membership_scheme()) &&
              identical(expected_source_n,recorded_source_n) && identical(expected_effective_n,recorded_effective_n) &&
              !is.null(resolution_json) && identical(.wb_prov_sha256_object(resolution_json),.wb_prov_sha256_object(resolution))
            if (!record_matches) add("RUN_NAMED_CELL_SET_MEMBERSHIP_IDENTITY_MISMATCH",check_class="provenance",entity_kind="cell_set",entity_id=set_id,table="prov_run_entity_bindings",expected=paste(expected_source_sha,expected_source_n,expected_effective_sha,expected_effective_n,sep="/"),observed=paste(recorded_source_sha,recorded_source_n,recorded_effective_sha,recorded_effective_n,sep="/"),message="Named cell-set binding does not authenticate the persisted source and effective membership resolution.")
            present <- has("cell_set_membership") && nrow(DBI::dbGetQuery(con,"SELECT 1 FROM cell_set_membership WHERE cell_set=? LIMIT 1;",params=list(set_id)))==1L
            if (!present) {
              add("RUN_NAMED_CELL_SET_BINDING_DANGLING",check_class="provenance",entity_kind="cell_set",entity_id=set_id,table="cell_set_membership",expected=role,observed="membership absent",message="Named cell-set consumption points to a missing or fabricated durable membership.")
            } else {
              observed_cells <- DBI::dbGetQuery(
                con,"SELECT cell_id FROM cell_set_membership WHERE cell_set=? ORDER BY cell_id;",
                params=list(set_id)
              )$cell_id
              observed_membership <- .wb_cell_set_membership_identity(observed_cells)
              if (!identical(tolower(expected_source_sha),tolower(observed_membership$content_sha256)) || !identical(expected_source_n,observed_membership$count)) add("RUN_NAMED_CELL_SET_MEMBERSHIP_CONTENT_MISMATCH",check_class="provenance",entity_kind="cell_set",entity_id=set_id,table="cell_set_membership",expected=paste(expected_source_sha,expected_source_n,sep="/"),observed=paste(observed_membership$content_sha256,observed_membership$count,sep="/"),message="Durable named-set membership no longer matches the exact source membership consumed by the run.")
              expected_entity_hash <- as.character(resolution$entity_content_sha256 %||% "")[1]
              observed_entity_hash <- tryCatch(.wb_registry_entity_content_hash(bundle,"cell_set",set_id),error=function(e) NA_character_)
              bound_entity_hash <- as.character(row$content_hash %||% "")[1]
              if (.wb_validation_nonempty(expected_entity_hash) && .wb_validation_nonempty(observed_entity_hash) &&
                  (!identical(tolower(expected_entity_hash),tolower(observed_entity_hash)) ||
                   !identical(tolower(expected_entity_hash),tolower(bound_entity_hash)))) add("RUN_NAMED_CELL_SET_STALE_RESOLUTION",check_class="provenance",entity_kind="cell_set",entity_id=set_id,table="prov_run_entity_bindings",expected=expected_entity_hash,observed=paste(bound_entity_hash,observed_entity_hash,sep="/"),message="A current or replacement set was incorrectly attributed to a historical named-set resolution.")
            }
          }
          if (nrow(run_cell_bindings)) {
            actual_keys <- paste(run_cell_bindings$binding_name,run_cell_bindings$entity_id,sep="\r")
            fabricated <- !(actual_keys %in% declared_keys)
            if (any(fabricated)) for (j in which(fabricated)) add("RUN_NAMED_CELL_SET_BINDING_FABRICATED",check_class="provenance",entity_kind="cell_set",entity_id=as.character(run_cell_bindings$entity_id[j]),table="prov_run_entity_bindings",expected="binding declared by run resolution record",observed=as.character(run_cell_bindings$binding_name[j]),message="Cell-set CONSUMES binding has no matching typed resolution record in the run contract.")
          }
        }
        parents <- unique(as.character(parsed$inputs_json$parents %||% character()))
        parents <- parents[!is.na(parents)&nzchar(parents)]
        if (length(parents)) for (parent in parents) {
          parent_exists <- paste(sid,parent,sep="\r") %in% run_key
          edge_exists <- nrow(edges) && any(edges$snapshot_id==sid & edges$parent_run_id==parent & edges$child_run_id==rid & edges$edge_type=="depends_on_run")
          if (!parent_exists || !edge_exists) add("RUN_INPUT_ANCESTRY_MISSING",check_class="provenance",entity_kind="run",entity_id=run_entity,table="prov_run_edges",expected=parent,observed=if(parent_exists) "edge missing" else "parent run missing",message="Declared run parent is not represented by complete persisted ancestry.")
        }
        refs <- .wb_dag_collect_refs(list(symbolic=parsed$symbolic_inputs_json %||% list(),inputs=parsed$inputs_json %||% list()),path="run_contract")
        if (nrow(refs)) for (j in seq_len(nrow(refs))) {
          if (identical(as.character(refs$ref_type[j]),"run")) {
            parent <- as.character(refs$run_id[j]); output_name <- as.character(refs$output[j] %||% "")[1]
            if (!.wb_validation_nonempty(parent) || !.wb_validation_nonempty(output_name)) next
            output_exists <- nrow(output_index) && any(output_index$snapshot_id==sid & output_index$run_id==parent & output_index$output_name==output_name)
            edge_exists <- nrow(edges) && any(edges$snapshot_id==sid & edges$parent_run_id==parent & edges$child_run_id==rid & edges$edge_type=="input_run_ref")
            if (!output_exists || !edge_exists) add("RUN_SYMBOLIC_INPUT_ANCESTRY_MISSING",check_class="provenance",entity_kind="run",entity_id=run_entity,table="prov_run_edges",expected=paste(parent,output_name,sep="::"),observed=if(output_exists) "edge missing" else "run output missing",message="Symbolic run input is not backed by its output and ancestry edge.")
          } else if (identical(as.character(refs$ref_type[j]),"artifact")) {
            aid <- as.character(refs$artifact_id[j] %||% "")[1]
            if (!.wb_validation_nonempty(aid)) next
            bound <- nrow(binding_index) && any(binding_index$snapshot_id==sid & binding_index$run_id==rid & binding_index$direction=="input" & binding_index$entity_kind=="artifact" & binding_index$entity_id==aid)
            if (!aid %in% artifact_ids || !bound) {
              if (typed_contract || !aid %in% artifact_ids) add("RUN_ARTIFACT_INPUT_ANCESTRY_MISSING",check_class="provenance",entity_kind="artifact",entity_id=aid,table="prov_run_entity_bindings",expected=run_entity,observed=if(aid %in% artifact_ids) "binding missing" else "artifact missing",message="Symbolic artifact input is not backed by a durable artifact and typed input binding.")
              else add("RUN_ARTIFACT_INPUT_ANCESTRY_LEGACY_UNVERIFIABLE",severity="warning",check_class="provenance",entity_kind="artifact",entity_id=aid,table="prov_run_entity_bindings",expected=run_entity,observed="legacy binding missing",message="Legacy run references a durable artifact but predates exact typed artifact-input bindings.")
            }
          }
        }
      }
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
          actual_identity <- tryCatch({
            atype <- DBI::dbGetQuery(con,"SELECT type FROM artifacts WHERE artifact_id=?;",params=list(aid))$type[1]
            if (as.character(atype) %in% c("feature_table","obs_table")) stored_table_actual_identity(aid) else if (as.character(atype) == "model_ref") {
              mr <- DBI::dbGetQuery(con,"SELECT model_path FROM artifact_model_ref WHERE artifact_id=?;",params=list(aid)); checked <- if(nrow(mr)) .wb_validation_path(root,mr$model_path[1],"either") else list(ok=FALSE); if(isTRUE(checked$ok)) .wb_prov_path_identity(checked$absolute) else NULL
            } else {
              prim <- wb_art_load(bundle, aid); .wb_prov_payload_identity(bundle, prim)
            }
          }, error = function(e) NULL)
          if (!is.null(actual_identity)) {
            scheme <- if ("content_identity_scheme" %in% names(outputs)) outputs$content_identity_scheme[i] else NA_character_
            scheme_state <- identity_scheme_state(scheme,actual_identity$content_identity_scheme,"artifact",aid,"prov_run_outputs")
            actual <- as.character(actual_identity$content_sha256 %||% "")[1]
            if (identical(scheme_state,"current") && nzchar(actual) && !identical(tolower(actual), tolower(sha))) add("ARTIFACT_CONTENT_IDENTITY_MISMATCH", check_class = "provenance", entity_kind = "artifact", entity_id = aid, table = "prov_run_outputs", expected = sha, observed = actual, message = "Artifact payload no longer matches its recorded content identity.")
          }
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
            external_model_input <- identical(as.character(bindings$direction[i]),"input") && .wb_validation_nonempty(bound_path) && .wb_path_is_absolute(bound_path)
            if (external_model_input) add("LEGACY_EXTERNAL_MODEL_REFERENCE", severity="warning", check_class="deserialization_trust", entity_kind="model_ref", entity_id=id, path=bound_path, observed="nonportable external path not inspected", message="External model input is explicit legacy state; recipient validation did not access or deserialize it.")
            resolved_model <- if (external_model_input) NULL else
              .wb_model_ref_physical_presence(bundle, id, allow_pending = FALSE)
            present <- if (external_model_input) TRUE else isTRUE(resolved_model$present)
          }
          if (!present && kind != "registry") add("PROVENANCE_DANGLING_ENTITY_BINDING", check_class = "provenance", entity_kind = kind, entity_id = id, table = "prov_run_entity_bindings", observed = "durable entity missing", message = "Provenance binding has no durable payload; ordinary retraction/rejection tombstones do not authorize deletion.")
          recorded_hash <- as.character(bindings$content_hash[i] %||% "")[1]
          if (present && .wb_validation_nonempty(recorded_hash) && grepl("^[A-Fa-f0-9]{64}$", recorded_hash)) {
            actual_identity <- tryCatch({
              if (kind == "matrix") {
                .wb_prov_payload_identity(bundle, wb_prim_matrix(id))
              } else if (kind == "space") {
                sr <- DBI::dbGetQuery(con, "SELECT dims FROM spaces WHERE space_id=?;", params=list(id))
                prims <- if (nrow(sr) && identical(as.integer(sr$dims[1]), 2L)) list(wb_prim_space(id), wb_prim_space_2d(id)) else list(wb_prim_space(id))
                identities <- lapply(prims, function(prim) .wb_prov_payload_identity(bundle, prim))
                hashes <- vapply(identities, function(x) as.character(x$content_sha256), character(1))
                hit <- which(tolower(hashes) == tolower(recorded_hash))
                identities[[if(length(hit)) hit[1] else 1L]]
              } else if (kind %in% c("model", "model_ref")) {
                candidate <- ""
                if (kind == "model_ref") {
                  resolved <- .wb_model_ref_physical_presence(bundle, id, allow_pending = FALSE)
                  if (isTRUE(resolved$present)) candidate <- as.character(resolved$model_path)
                }
                if (!.wb_validation_nonempty(candidate) && kind == "model")
                  candidate <- .wb_validation_model_payload_path(con, id)
                if (!.wb_validation_nonempty(candidate)) candidate <- bound_path
                checked <- if (.wb_path_is_absolute(candidate)) list(ok=FALSE,absolute=NA_character_) else .wb_validation_path(root, candidate, "either")
                if (isTRUE(checked$ok)) .wb_prov_path_identity(checked$absolute) else NULL
              } else if (kind == "artifact") {
                atype <- DBI::dbGetQuery(con,"SELECT type FROM artifacts WHERE artifact_id=?;",params=list(id))$type[1]
                if (as.character(atype) %in% c("feature_table","obs_table")) stored_table_actual_identity(id) else if (as.character(atype) == "model_ref") {
                  mr <- DBI::dbGetQuery(con,"SELECT model_path FROM artifact_model_ref WHERE artifact_id=?;",params=list(id)); checked <- if(nrow(mr)) .wb_validation_path(root,mr$model_path[1],"either") else list(ok=FALSE); if(isTRUE(checked$ok)) .wb_prov_path_identity(checked$absolute) else NULL
                } else .wb_prov_payload_identity(bundle,wb_art_load(bundle,id))
              } else if (kind %in% c("cell_set","feature_set")) {
                list(content_sha256=.wb_registry_entity_content_hash(bundle,kind,id),content_identity_scheme=unname(.wb_content_identity_schemes()[["registry"]]))
              } else if (kind == "external_source") {
                list(content_sha256=recorded_hash,content_identity_scheme=unname(.wb_content_identity_schemes()[["raw_file"]]))
              } else NULL
            }, error=function(e) NULL)
            if (!is.null(actual_identity)) {
              recorded_scheme <- if ("content_identity_scheme" %in% names(bindings)) bindings$content_identity_scheme[i] else NA_character_
              scheme_state <- identity_scheme_state(recorded_scheme,actual_identity$content_identity_scheme,kind,id,"prov_run_entity_bindings")
              actual_hash <- as.character(actual_identity$content_sha256 %||% "")[1]
            } else { scheme_state <- "unavailable"; actual_hash <- NA_character_ }
            if (identical(scheme_state,"current") && .wb_validation_nonempty(actual_hash) && !identical(tolower(actual_hash),tolower(recorded_hash))) {
              code <- switch(kind, matrix="MATRIX_CONTENT_IDENTITY_MISMATCH", space="SPACE_CONTENT_IDENTITY_MISMATCH", model="MODEL_CONTENT_IDENTITY_MISMATCH", model_ref="MODEL_CONTENT_IDENTITY_MISMATCH", "ENTITY_CONTENT_IDENTITY_MISMATCH")
              add(code,check_class="provenance",entity_kind=kind,entity_id=id,table="prov_run_entity_bindings",expected=recorded_hash,observed=actual_hash,message="Durable entity payload no longer matches its provenance-bound content identity.")
            }
          }
        }
      }
      if (nrow(output_index)) for (i in seq_len(nrow(output_index))) {
        id <- paste(output_index$snapshot_id[i],output_index$run_id[i],output_index$output_name[i],sep="/")
        output_hash <- as.character(output_index$output_hash[i] %||% "")[1]
        output_scheme <- if ("output_hash_scheme" %in% names(output_index)) output_index$output_hash_scheme[i] else NA_character_
        structural <- if ("structural_fingerprint" %in% names(output_index) && .wb_validation_nonempty(output_index$structural_fingerprint[i])) as.character(output_index$structural_fingerprint[i])[1] else output_hash
        structural_scheme <- if ("structural_fingerprint_scheme" %in% names(output_index)) output_index$structural_fingerprint_scheme[i] else NA_character_
        resolved_output_scheme <- integrity_scheme(output_hash,output_scheme,unname(.wb_identity_schemes()[["structural"]]),"run_output",id,"prov_run_outputs","output_hash")
        resolved_structural_scheme <- integrity_scheme(structural,structural_scheme,unname(.wb_identity_schemes()[["structural"]]),"run_output",id,"prov_run_outputs","structural_fingerprint")
        if (!is.na(resolved_output_scheme) && !is.na(resolved_structural_scheme) &&
            (!identical(resolved_output_scheme,resolved_structural_scheme) || !identical(tolower(output_hash),tolower(structural)))) {
          add("RUN_OUTPUT_STRUCTURAL_IDENTITY_CONTRADICTION",check_class="provenance",entity_kind="run_output",entity_id=id,table="prov_run_outputs",expected=paste(resolved_structural_scheme,structural),observed=paste(resolved_output_scheme,output_hash),message="Compatibility output_hash contradicts the declared structural fingerprint identity.")
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
          materialization_hash <- as.character(mats$output_hash[i] %||% "")[1]
          materialization_scheme <- integrity_scheme(materialization_hash,if("output_hash_scheme" %in% names(mats)) mats$output_hash_scheme[i] else NA_character_,unname(.wb_identity_schemes()[["materialization"]]),"materialization",id,"prov_materializations","output_hash")
          if (isTRUE(checked$ok) && !is.na(materialization_scheme) && file.exists(checked$absolute) && !dir.exists(checked$absolute)) {
            prim <- tryCatch(readRDS(checked$absolute),error=function(e)e)
            if (inherits(prim,"error")) add("MATERIALIZATION_PAYLOAD_UNREADABLE",check_class="provenance",entity_kind="materialization",entity_id=id,path=mats$path[i],observed=conditionMessage(prim),message="Materialization payload cannot be read for identity validation.")
            else {
              expected_materialization_hash <- if (identical(materialization_scheme,unname(.wb_identity_schemes()[["legacy"]]))) .wb_hash_text_legacy_v1(serialize(prim,NULL,version=3)) else .wb_prov_materialization_hash(prim)
              if (!identical(tolower(materialization_hash),tolower(expected_materialization_hash))) add("MATERIALIZATION_OUTPUT_HASH_MISMATCH",check_class="provenance",entity_kind="materialization",entity_id=id,path=mats$path[i],expected=expected_materialization_hash,observed=materialization_hash,message="Materialization payload contradicts its declared output identity.")
            }
          }
          if (isTRUE(checked$ok) && "content_sha256" %in% names(mats)) {
            sha <- as.character(mats$content_sha256[i] %||% "")[1]
            if (.wb_validation_nonempty(sha)) {
              actual_identity <- .wb_prov_path_identity(checked$absolute)
              scheme <- if ("content_identity_scheme" %in% names(mats)) mats$content_identity_scheme[i] else NA_character_
              scheme_state <- identity_scheme_state(scheme,actual_identity$content_identity_scheme,"materialization",id,"prov_materializations")
              actual <- actual_identity$content_sha256
              if (identical(scheme_state,"current") && !identical(tolower(actual), tolower(sha))) add("MATERIALIZATION_CONTENT_IDENTITY_MISMATCH", check_class = "provenance", entity_kind = "materialization", entity_id = id, path = mats$path[i], expected = sha, observed = actual, message = "Materialization payload no longer matches its content identity.")
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
          if (.wb_validation_nonempty(sha)) identity_scheme_state(if("content_identity_scheme" %in% names(reg)) reg$content_identity_scheme[i] else NA_character_,unname(.wb_content_identity_schemes()[["registry"]]),"registry_mutation",reg$event_id[i],"prov_registry_mutations")
        }
        entity_ids <- vapply(entities,function(x) if(is.null(x)) "" else paste(x$kind,x$id,sep="\r"),character(1))
        for (entity_key in unique(entity_ids[nzchar(entity_ids)])) {
          index <- utils::tail(which(entity_ids==entity_key),1L); entity <- entities[[index]]; expected_hash <- as.character(reg$content_hash[index] %||% "")[1]
          scheme <- if("content_identity_scheme" %in% names(reg)) reg$content_identity_scheme[index] else NA_character_
          if (.wb_validation_nonempty(expected_hash) && identical(identity_scheme_state(scheme,unname(.wb_content_identity_schemes()[["registry"]]),entity$kind,entity$id,"prov_registry_mutations"),"current")) {
            actual_hash <- tryCatch(.wb_registry_entity_content_hash(bundle,entity$kind,entity$id),error=function(e) NA_character_)
            if (.wb_validation_nonempty(actual_hash) && !identical(tolower(actual_hash),tolower(expected_hash))) add("REGISTRY_MUTATION_CONTENT_IDENTITY_MISMATCH",check_class="provenance",entity_kind=entity$kind,entity_id=entity$id,table="prov_registry_mutations",expected=expected_hash,observed=actual_hash,message="Current durable registry entity disagrees with the latest recorded mutation identity.")
          }
        }
      }
      if (has("prov_replay_equivalence_results")) {
        replay_results <- DBI::dbGetQuery(con, "SELECT * FROM prov_replay_equivalence_results ORDER BY result_id;")
        for (i in seq_len(nrow(replay_results))) {
          id <- as.character(replay_results$result_id[i])
          original_hash <- as.character(replay_results$original_content_sha256[i] %||% "")[1]
          replayed_hash <- as.character(replay_results$replayed_content_sha256[i] %||% "")[1]
          original_scheme <- if ("original_content_identity_scheme" %in% names(replay_results)) replay_results$original_content_identity_scheme[i] else NA_character_
          replayed_scheme <- if ("replayed_content_identity_scheme" %in% names(replay_results)) replay_results$replayed_content_identity_scheme[i] else NA_character_
          if (.wb_validation_nonempty(original_hash)) identity_scheme_state(original_scheme,replayed_scheme,"replay_equivalence",id,"prov_replay_equivalence_results")
          if (.wb_validation_nonempty(replayed_hash)) identity_scheme_state(replayed_scheme,original_scheme,"replay_equivalence",id,"prov_replay_equivalence_results")
          claimed_identical <- identical(as.integer(replay_results$payload_identical[i]),1L)
          actually_identical <- .wb_validation_nonempty(original_hash) && .wb_validation_nonempty(replayed_hash) &&
            .wb_validation_nonempty(original_scheme) && .wb_validation_nonempty(replayed_scheme) &&
            identical(as.character(original_scheme),as.character(replayed_scheme)) &&
            identical(tolower(original_hash),tolower(replayed_hash))
          if (claimed_identical && !actually_identical) add("REPLAY_CONTENT_IDENTITY_CONTRADICTION",check_class="provenance",entity_kind="replay_equivalence",entity_id=id,table="prov_replay_equivalence_results",expected="equal tagged scheme and hash",observed="payload_identical=1 with unequal or untagged identities",message="Replay result claims payload identity without an equal tagged content-identity contract.")
        }
      }
    })

    timed("source_inputs", {
      if (.wb_table_exists(con, "prov_source_inputs")) {
        src <- DBI::dbGetQuery(con, "SELECT * FROM prov_source_inputs ORDER BY snapshot_id,run_id,source_id;")
        runs <- if (.wb_table_exists(con, "prov_runs")) DBI::dbGetQuery(con, "SELECT snapshot_id,run_id FROM prov_runs;") else data.frame()
        add_source_coverage <- function(id, recorded_scheme=NA_character_, actual_scheme=NA_character_, status="structurally_checked_only") {
          content_coverage[nrow(content_coverage)+1L,] <<- list("external_source",id,"prov_source_inputs",recorded_scheme,actual_scheme,status)
        }
        for (i in seq_len(nrow(src))) {
          source_id <- as.character(src$source_id[i]); id <- paste(src$snapshot_id[i],src$run_id[i],source_id,sep="/"); x <- .wb_validation_json(src$source_json[i])
          if (is.null(x)) { add("SOURCE_IDENTITY_MALFORMED", check_class = "source_inputs", entity_kind = "external_source", entity_id = id, table = "prov_source_inputs", observed = "invalid JSON", message = "Source input declaration is malformed."); add_source_coverage(id); next }
          if (!paste(src$snapshot_id[i],src$run_id[i],sep="\r") %in% paste(runs$snapshot_id,runs$run_id,sep="\r")) add("SOURCE_INPUT_DANGLING_RUN", check_class = "source_inputs", entity_kind = "external_source", entity_id = id, table = "prov_source_inputs", message = "Source input references a missing run.")
          scope <- as.character(x$scope %||% x$source_scope %||% "legacy_external")[1]
          entity_kind <- if (identical(scope,"in_memory")) "in_memory_source" else "external_source"
          if (.wb_validation_nonempty(x$sha256) && .wb_validation_nonempty(x$checksum) && !identical(tolower(as.character(x$sha256)[1]),tolower(as.character(x$checksum)[1]))) add("SOURCE_CHECKSUM_ALIASES_CONFLICT",check_class="source_inputs",entity_kind=entity_kind,entity_id=id,table="prov_source_inputs",expected=as.character(x$sha256)[1],observed=as.character(x$checksum)[1],message="Persisted checksum aliases disagree.")
          alg <- tolower(as.character(x$checksum_algorithm %||% if (!is.null(x$sha256)) "sha256" else "")[1]); sha <- as.character(x$sha256 %||% x$checksum %||% "")[1]
          valid_sha <- .wb_validation_nonempty(sha) && identical(alg,"sha256") && grepl("^[A-Fa-f0-9]{64}$", sha)
          if (.wb_validation_nonempty(sha) && !valid_sha) { add("SOURCE_CHECKSUM_MALFORMED", check_class = "source_inputs", entity_kind = "external_source", entity_id = id, table = "prov_source_inputs", expected = "sha256 plus 64 hexadecimal characters", observed = paste(alg,sha), message = "Source checksum syntax is invalid."); add_source_coverage(id); next }
          raw <- as.character(x$path %||% "")[1]; bundled <- isTRUE(x$bundled %||% x$bundle_owned %||% FALSE)
          source_status <- "structurally_checked_only"; actual_scheme <- NA_character_; recorded_scheme <- if(valid_sha) unname(.wb_content_identity_schemes()[["raw_file"]]) else NA_character_
          checked_source <- if (bundled) .wb_validation_path(root, raw, "file") else NULL
          if (bundled && !isTRUE(checked_source$ok)) add(if(identical(checked_source$code,"PAYLOAD_MISSING")) "BUNDLED_SOURCE_MISSING" else checked_source$code, check_class = "source_inputs", entity_kind = "external_source", entity_id = id, path = raw, expected = "contained bundled source file", observed = checked_source$observed, message = "A bundled source path is unavailable or outside the bundle.")
          else if (bundled && isTRUE(checked_source$ok) && valid_sha) { actual <- .wb_prov_sha256_file(checked_source$absolute); actual_scheme <- unname(.wb_content_identity_schemes()[["raw_file"]]); source_status <- if(identical(tolower(actual),tolower(sha))) "content_verified" else "content_mismatch"; if (!identical(tolower(actual),tolower(sha))) add("SOURCE_CHECKSUM_MISMATCH", check_class = "source_inputs", entity_kind = "external_source", entity_id = id, path = raw, expected = sha, observed = actual, message = "Bundled immutable source does not match its recorded checksum.") }
          else if (!bundled && scope %in% c("public_file","external_file","legacy_external")) { source_status <- "external_uninspected"; add("EXTERNAL_SOURCE_UNVERIFIABLE", severity = "warning", check_class = "source_inputs", entity_kind = entity_kind, entity_id = id, path = raw, observed = "external path deliberately not accessed", message = "External source is outside the recipient trust boundary and was not inspected.") }
          else if (identical(scope,"in_memory")) source_status <- "nonportable_in_memory_boundary"
          add_source_coverage(id,recorded_scheme,actual_scheme,source_status)
        }
        parsed_sources <- lapply(src$source_json, .wb_validation_json)
        for (i in seq_len(nrow(src))) {
          x <- parsed_sources[[i]] %||% list()
          parent_id <- as.character(x$parent_source_id %||% "")[1]
          relation <- as.character(x$source_relation %||% "")[1]
          if (!nzchar(parent_id) && !nzchar(relation)) next
          id <- paste(src$snapshot_id[i], src$run_id[i], src$source_id[i], sep = "/")
          same_run <- as.character(src$snapshot_id) == as.character(src$snapshot_id[i]) &
            as.character(src$run_id) == as.character(src$run_id[i]) &
            as.character(src$source_id) == parent_id
          if (sum(same_run) != 1L) {
            add("SOURCE_NESTED_PARENT_MISSING", check_class="source_inputs", entity_kind="in_memory_source", entity_id=id, table="prov_source_inputs", expected="one parent source in the same ingestion run", observed=as.character(sum(same_run)), message="Nested conversion source does not resolve one declared parent in the same run.")
            next
          }
          parent <- parsed_sources[[which(same_run)[[1L]]]] %||% list()
          parent_scope <- as.character(parent$scope %||% parent$source_scope %||% "")[1]
          if (!identical(relation, "CONVERTS_TO") ||
              !identical(as.character(x$scope %||% x$source_scope %||% "")[1], "in_memory") ||
              !parent_scope %in% c("public_file", "external_file")) {
            add("SOURCE_NESTED_RELATION_INVALID", check_class="source_inputs", entity_kind="in_memory_source", entity_id=id, table="prov_source_inputs", expected="checksummed external parent CONVERTS_TO in-memory child", observed=paste(parent_scope, relation, as.character(x$scope %||% "")), message="Nested conversion relationship is forged or ambiguous.")
          }
        }
      }
      if (.wb_table_exists(con,"prov_source_identities")) {
        identities <- DBI::dbGetQuery(con,"SELECT * FROM prov_source_identities ORDER BY snapshot_id,run_id,matrix_id;")
        source_runs <- if (.wb_table_exists(con,"prov_runs")) DBI::dbGetQuery(con,"SELECT snapshot_id,run_id FROM prov_runs;") else data.frame()
        run_keys <- if (nrow(source_runs)) paste(source_runs$snapshot_id,source_runs$run_id,sep="\r") else character()
        matrices <- if (.wb_table_exists(con,"matrices")) as.character(DBI::dbGetQuery(con,"SELECT matrix_id FROM matrices;")$matrix_id) else character()
        for (i in seq_len(nrow(identities))) {
          sid <- as.character(identities$snapshot_id[i]); rid <- as.character(identities$run_id[i]); mid <- as.character(identities$matrix_id[i]); id <- paste(sid,rid,mid,sep="/")
          parsed <- tryCatch(jsonlite::fromJSON(as.character(identities$source_identity_json[i]),simplifyVector=FALSE),error=function(e)e)
          valid <- if (inherits(parsed,"error")) parsed else tryCatch(.wb_prov_source_identity_validate(parsed),error=function(e)e)
          if (inherits(valid,"error") || is.null(valid)) add("SOURCE_IDENTITY_MALFORMED",check_class="source_inputs",entity_kind="source_identity",entity_id=id,table="prov_source_identities",observed=if(inherits(valid,"error")) conditionMessage(valid) else "invalid declaration",message="Persisted source identity is not syntactically valid.")
          if (!paste(sid,rid,sep="\r") %in% run_keys) add("SOURCE_IDENTITY_DANGLING_RUN",check_class="source_inputs",entity_kind="source_identity",entity_id=id,table="prov_source_identities",observed=rid,message="Source identity references a missing run.")
          if (!mid %in% matrices) add("SOURCE_IDENTITY_DANGLING_MATRIX",check_class="source_inputs",entity_kind="source_identity",entity_id=id,table="prov_source_identities",observed=mid,message="Source identity references a missing matrix.")
          nested <- if (!inherits(valid, "error") && !is.null(valid)) valid$nested_ingestion %||% NULL else NULL
          if (!is.null(nested)) {
            required_ids <- c(
              as.character(nested$authoritative_source_id %||% "")[1],
              as.character(nested$conversion_source_id %||% "")[1]
            )
            linked <- if (.wb_table_exists(con, "prov_source_inputs")) DBI::dbGetQuery(
              con,
              "SELECT source_id FROM prov_source_inputs WHERE snapshot_id=? AND run_id=? AND source_id IN (?,?);",
              params = list(sid, rid, required_ids[[1L]], required_ids[[2L]])
            ) else data.frame(source_id = character())
            observed_ids <- as.character(linked$source_id %||% character())
            if (!setequal(observed_ids, required_ids) || nrow(linked) != 2L) add(
              "SOURCE_NESTED_ANCESTRY_MISSING", check_class="source_inputs",
              entity_kind="matrix", entity_id=mid, table="prov_source_inputs",
              expected=paste(required_ids, collapse=","), observed=paste(observed_ids, collapse=","),
              message="Imported matrix does not retain one complete authoritative external-to-conversion source chain."
            )
          }
        }
      }
    })

    timed("lifecycle", {
      if (.wb_table_exists(con, "entity_lifecycle")) {
        life <- DBI::dbGetQuery(con, "SELECT * FROM entity_lifecycle;"); physical <- .wb_entity_physical_inventory(bundle)
        tomb <- if (.wb_table_exists(con,"entity_tombstones")) DBI::dbGetQuery(con,"SELECT * FROM entity_tombstones;") else data.frame()
        for (i in seq_len(nrow(life))) {
          kind <- as.character(life$entity_kind[i]); id <- as.character(life$entity_id[i]); state <- as.character(life$lifecycle_state[i]); present <- any(physical$entity_kind==kind & physical$entity_id==id); bound <- identical(as.integer(life$provenance_bound[i]),1L)
          if (kind=="model_ref") {
            resolved_model <- .wb_model_ref_physical_presence(bundle, id, allow_pending = FALSE)
            present <- isTRUE(resolved_model$present)
            if (!present && bound) add(
              resolved_model$code, check_class="lifecycle", entity_kind=kind,
              entity_id=id, path=resolved_model$model_path,
              table=if(identical(resolved_model$storage,"space_models")) "space_models" else "artifact_model_ref",
              expected="storage-aware model_ref owner, payload, and provenance",
              observed=resolved_model$message,
              message=resolved_model$message
            )
          }
          is_tomb <- nrow(tomb) && any(tomb$entity_kind==kind & tomb$entity_id==id & tomb$tombstone_state==state)
          if (!present && bound && state %in% c("current","superseded","retracted","rejected")) add("ILLEGAL_HISTORICAL_ENTITY_DELETION", check_class="lifecycle",entity_kind=kind,entity_id=id,table="entity_lifecycle",expected="provenance-bound durable historical payload",observed=state,message="A provenance-bound immutable entity payload is physically missing; retraction/rejection tombstones do not authorize deletion.")
          if (state %in% c("retracted","rejected") && !is_tomb) add("HISTORICAL_ENTITY_TOMBSTONE_MISSING",check_class="lifecycle",entity_kind=kind,entity_id=id,table="entity_lifecycle",observed=state,message="A retracted/rejected entity lacks a matching ordinary tombstone.")
        }
        if (nrow(tomb)) for (i in seq_len(nrow(tomb))) {
          hit <- life$entity_kind==tomb$entity_kind[i] & life$entity_id==tomb$entity_id[i]
          if (!any(hit) || !identical(as.character(life$lifecycle_state[hit][1]),as.character(tomb$tombstone_state[i]))) add("HISTORICAL_TOMBSTONE_STATE_INVALID",check_class="lifecycle",entity_kind=tomb$entity_kind[i],entity_id=tomb$entity_id[i],table="entity_tombstones",expected=tomb$tombstone_state[i],observed=if(any(hit)) life$lifecycle_state[hit][1] else "lifecycle row missing",message="Tombstone and lifecycle state are inconsistent.")
          if (any(hit) && "identity_scheme" %in% names(tomb) && "identity_scheme" %in% names(life)) {
            tomb_hash <- as.character(tomb$identity_hash[i] %||% "")[1]
            life_hash <- as.character(life$identity_hash[hit][1] %||% "")[1]
            tomb_scheme <- as.character(tomb$identity_scheme[i] %||% "")[1]
            life_scheme <- as.character(life$identity_scheme[hit][1] %||% "")[1]
            if (.wb_validation_nonempty(tomb_hash) && (!identical(tomb_hash, life_hash) || !identical(tomb_scheme, life_scheme))) {
              add("HISTORICAL_TOMBSTONE_IDENTITY_MISMATCH",check_class="lifecycle",entity_kind=tomb$entity_kind[i],entity_id=tomb$entity_id[i],table="entity_tombstones",expected=paste(life_scheme,life_hash,sep=":"),observed=paste(tomb_scheme,tomb_hash,sep=":"),message="Tombstone identity does not preserve the lifecycle content-identity contract.")
            }
          }
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
    timed("content_completeness", {
      physical <- .wb_entity_physical_inventory(bundle)
      if (nrow(physical)) {
        life <- if (.wb_table_exists(con,"entity_lifecycle")) DBI::dbGetQuery(con,"SELECT * FROM entity_lifecycle;") else data.frame()
        keep <- physical$entity_kind %in% c("matrix","space","model","artifact","metadata_field")
        if (nrow(life)) keep <- keep | vapply(seq_len(nrow(physical)),function(i) any(life$entity_kind==physical$entity_kind[i] & life$entity_id==physical$entity_id[i] & life$provenance_bound==1L),logical(1))
        keep <- keep & !physical$entity_kind %in% c("external_source", "in_memory_source")
        physical <- unique(physical[keep,,drop=FALSE])
        bindings <- if (.wb_table_exists(con,"prov_run_entity_bindings")) DBI::dbGetQuery(con,"SELECT * FROM prov_run_entity_bindings;") else data.frame()
        outputs_all <- if (.wb_table_exists(con,"prov_run_outputs")) DBI::dbGetQuery(con,"SELECT * FROM prov_run_outputs;") else data.frame()
        registry <- if (.wb_table_exists(con,"prov_registry_mutations")) DBI::dbGetQuery(con,"SELECT * FROM prov_registry_mutations ORDER BY rowid;") else data.frame()
        baseline_rows <- function(kind,id) {
          rows <- list(); n <- 0L
          if (nrow(bindings)) {
            hit <- bindings$entity_kind==kind & bindings$entity_id==id
            if (kind=="model") hit <- hit | (bindings$entity_kind=="model_ref" & vapply(strsplit(as.character(bindings$entity_id),"|",fixed=TRUE),function(x) length(x)>=2L && identical(x[2],id),logical(1)))
            if (any(hit)) { n<-n+1L; rows[[n]]<-data.frame(hash=as.character(bindings$content_hash[hit]),scheme=if("content_identity_scheme" %in% names(bindings)) as.character(bindings$content_identity_scheme[hit]) else NA_character_,source="prov_run_entity_bindings",stringsAsFactors=FALSE) }
          }
          if (kind=="artifact" && nrow(outputs_all) && "content_sha256" %in% names(outputs_all)) {
            hit <- !is.na(outputs_all$artifact_id) & outputs_all$artifact_id==id
            if (any(hit)) { n<-n+1L; rows[[n]]<-data.frame(hash=as.character(outputs_all$content_sha256[hit]),scheme=if("content_identity_scheme" %in% names(outputs_all)) as.character(outputs_all$content_identity_scheme[hit]) else NA_character_,source="prov_run_outputs",stringsAsFactors=FALSE) }
          }
          if (kind %in% c("cell_set","feature_set") && nrow(registry) && "content_hash" %in% names(registry)) {
            entities <- lapply(seq_len(nrow(registry)),function(i){ key<-.wb_validation_json(registry$registry_key_json[i]); if(is.null(key)) NULL else .wb_registry_event_entity(as.character(registry$registry_type[i]),key) })
            hit <- vapply(entities,function(x)!is.null(x)&&identical(x$kind,kind)&&identical(x$id,id),logical(1))
            if(any(hit)){ n<-n+1L; rows[[n]]<-data.frame(hash=as.character(registry$content_hash[hit]),scheme=if("content_identity_scheme" %in% names(registry)) as.character(registry$content_identity_scheme[hit]) else NA_character_,source="prov_registry_mutations",stringsAsFactors=FALSE) }
          }
          if (kind == "metadata_field" && .wb_table_exists(con, "metadata_field_identities")) {
            mi <- DBI::dbGetQuery(con, "SELECT content_sha256,content_identity_scheme FROM metadata_field_identities WHERE field_id=? AND is_current=1;", params=list(id))
            if (nrow(mi)) { n<-n+1L; rows[[n]]<-data.frame(hash=as.character(mi$content_sha256),scheme=as.character(mi$content_identity_scheme),source="metadata_field_identities",stringsAsFactors=FALSE) }
          }
          if (nrow(life) && all(c("identity_hash","identity_scheme") %in% names(life))) {
            hit <- life$entity_kind==kind & life$entity_id==id
            if (any(hit)) { n<-n+1L; rows[[n]]<-data.frame(hash=as.character(life$identity_hash[hit]),scheme=as.character(life$identity_scheme[hit]),source="entity_lifecycle",stringsAsFactors=FALSE) }
          }
          if(!length(rows)) return(data.frame(hash=character(),scheme=character(),source=character(),stringsAsFactors=FALSE))
          out<-do.call(rbind,rows); out[!is.na(out$hash)&grepl("^[A-Fa-f0-9]{64}$",out$hash),,drop=FALSE]
        }
        actual_rows <- function(kind,id) {
          identities <- tryCatch({
            if(kind=="matrix") list(.wb_prov_payload_identity(bundle,wb_prim_matrix(id)))
            else if(kind=="space") { sr<-DBI::dbGetQuery(con,"SELECT dims FROM spaces WHERE space_id=?;",params=list(id)); if(nrow(sr)&&identical(as.integer(sr$dims[1]),2L)) list(.wb_prov_payload_identity(bundle,wb_prim_space(id)),.wb_prov_payload_identity(bundle,wb_prim_space_2d(id))) else list(.wb_prov_payload_identity(bundle,wb_prim_space(id))) }
            else if(kind=="model") { model_path<-.wb_validation_model_payload_path(con,id); if(nzchar(model_path)){ checked<-.wb_validation_path(root,model_path,"either"); if(isTRUE(checked$ok)) list(.wb_prov_path_identity(checked$absolute)) else list() } else list() }
            else if(kind=="artifact") { at<-DBI::dbGetQuery(con,"SELECT type FROM artifacts WHERE artifact_id=?;",params=list(id))$type[1]; if(as.character(at)%in%c("feature_table","obs_table")) list(stored_table_actual_identity(id)) else if(as.character(at)=="model_ref") { mr<-DBI::dbGetQuery(con,"SELECT model_path FROM artifact_model_ref WHERE artifact_id=?;",params=list(id)); checked<-if(nrow(mr)) .wb_validation_path(root,mr$model_path[1],"either") else list(ok=FALSE); if(isTRUE(checked$ok)) list(.wb_prov_path_identity(checked$absolute)) else list() } else list(.wb_prov_payload_identity(bundle,wb_art_load(bundle,id))) }
            else if(kind%in%c("cell_set","feature_set")) list(list(content_sha256=.wb_registry_entity_content_hash(bundle,kind,id),content_identity_scheme=unname(.wb_content_identity_schemes()[["registry"]])))
            else if(kind=="metadata_field") list(.wb_metadata_field_content_identity(con,id))
            else list()
          },error=function(e)list())
          if(!length(identities)) return(data.frame(hash=character(),scheme=character(),stringsAsFactors=FALSE))
          do.call(rbind,lapply(identities,function(x)data.frame(hash=as.character(x$content_sha256%||%NA_character_),scheme=as.character(x$content_identity_scheme%||%NA_character_),stringsAsFactors=FALSE)))
        }
        for(i in seq_len(nrow(physical))){
          kind<-as.character(physical$entity_kind[i]); id<-as.character(physical$entity_id[i]); base<-baseline_rows(kind,id)
          tagged_baseline <- base[!is.na(base$scheme)&nzchar(base$scheme)&base$scheme%in%unname(.wb_content_identity_schemes()),,drop=FALSE]
          actual<-if(nrow(tagged_baseline)) actual_rows(kind,id) else data.frame(hash=character(),scheme=character(),stringsAsFactors=FALSE)
          status<-"structurally_checked_only"; recorded_scheme<-NA_character_; actual_scheme<-if(nrow(actual)) paste(sort(unique(actual$scheme)),collapse=",") else NA_character_; source<-if(nrow(base)) paste(sort(unique(base$source)),collapse=",") else NA_character_
          if(!nrow(base)) add("DURABLE_CONTENT_IDENTITY_MISSING",severity="warning",check_class="content_completeness",entity_kind=kind,entity_id=id,observed="no recorded baseline",message="Bundle-owned durable payload has no recorded content identity and cannot be proved unchanged.")
          else {
            tagged<-base[!is.na(base$scheme)&nzchar(base$scheme),,drop=FALSE]
            if(!nrow(tagged)){ status<-"legacy_unverifiable"; add("DURABLE_CONTENT_IDENTITY_LEGACY_UNVERIFIABLE",severity="warning",check_class="content_completeness",entity_kind=kind,entity_id=id,observed="untagged baseline",message="Durable payload has only untagged legacy hashes and is not claimed content-verified.") }
            else {
              recorded_scheme<-paste(sort(unique(tagged$scheme)),collapse=",")
              supported<-tagged$scheme%in%unname(.wb_content_identity_schemes())
              if(any(supported)&&nrow(actual)&&any(vapply(seq_len(nrow(tagged[supported,,drop=FALSE])),function(j) any(actual$scheme==tagged$scheme[supported][j]&tolower(actual$hash)==tolower(tagged$hash[supported][j]),na.rm=TRUE),logical(1)))) status<-"content_verified"
              else if(any(supported)&&nrow(actual)){ status<-"content_mismatch"; add("DURABLE_CONTENT_IDENTITY_MISMATCH",check_class="content_completeness",entity_kind=kind,entity_id=id,expected=paste(tagged$hash[supported],collapse=","),observed=paste(actual$hash,collapse=","),message="No tagged durable content baseline matches the current payload.") }
              else status<-"legacy_unverifiable"
            }
          }
          content_coverage[nrow(content_coverage)+1L,] <- list(kind,id,source,recorded_scheme,actual_scheme,status)
        }
      }
    })
  } else {
    for (x in c("sqlite_integrity", "matrix_content", "spaces_and_models", "artifacts", "provenance", "source_inputs", "lifecycle")) skip(x, "content", "requested structural validation does not read or hash payload content")
  }

  if (!is.null(con) && .wb_table_exists(con,"analysis_capsules")) timed("analysis_capsules", {
    .wb_validate_analysis_capsules(root,con,add,content=has_level("content"))
  })

  if (has_level("recipient")) timed("recipient", {
    pending_abs <- if (dir.exists(root)) {
      as.character(fs::dir_ls(root, recurse = TRUE, type = "any", all = TRUE, follow = FALSE))
    } else character()
    pending_paths <- substring(pending_abs, nchar(root) + 2L)
    pending_paths <- pending_paths[grepl("(^|/)\\.pending(/|$)|(^|/)\\.pending-[^/]+(/|$)|^\\.manifest[.]json[.](staging|backup)-|INGEST_FAILED[.]json$", pending_paths)]
    # The empty, pre-created .pending container is part of the normal bundle
    # layout. Only entries beneath it represent unfinished publication work.
    pending_paths <- pending_paths[!grepl("(^|/)\\.pending$", pending_paths)]
    if (length(pending_paths)) for (path in pending_paths) {
      if (identical(basename(path),"INGEST_FAILED.json")) {
        if (!"INGEST_FAILED_INCOMPLETE" %in% diagnostics$code) add("INGEST_FAILED_INCOMPLETE",check_class="recipient",entity_kind="ingestion",entity_id="failed",path=path,observed="present",message="Bundle ingestion failed/incomplete; see INGEST_FAILED.json marker.")
      }
      else add("PENDING_WORKSPACE_RESIDUE", check_class = "recipient", entity_kind = "pending_publication", entity_id = basename(path), path = path, observed = "present", message = "Incomplete publication/ingestion residue is present.")
    }
    lock <- tryCatch(wb_bundle_writer_lock_info(root), error = function(e) list(locked=FALSE))
    if (isTRUE(lock$locked)) add("ACTIVE_BUNDLE_WRITER", check_class="recipient",entity_kind="writer_lock",entity_id="exclusive",path=.wb_writer_lock_path(root),observed=.wb_writer_lock_diagnostic(lock),message="Recipient validation requires no active bundle writer.")
    if (!is.null(manifest)) {
      db_checked <- .wb_validation_path(root, as.character(manifest$storage$sqlite$path %||% ""), "file")
      db <- if (isTRUE(db_checked$ok)) db_checked$absolute else ""; sidecars <- if(nzchar(db)) c(paste0(db,"-wal"),paste0(db,"-shm"),paste0(db,"-journal")) else character(); hit <- sidecars[file.exists(sidecars)]
      for (p in hit) add("SQLITE_UNRESOLVED_JOURNAL_STATE",check_class="recipient",entity_kind="sqlite",entity_id="main",path=substring(p,nchar(root)+2L),observed="present",message="Recipient bundle contains unresolved SQLite WAL/SHM/journal state.")
      if (!length(hit) && file.exists(db)) {
        immutable <- tryCatch({
          icon <- DBI::dbConnect(RSQLite::SQLite(), paste0("file:", normalizePath(db,winslash="/",mustWork=TRUE), "?immutable=1"), flags=RSQLite::SQLITE_RO)
          on.exit(DBI::dbDisconnect(icon), add=TRUE)
          .wb_sqlite_configure_connection(icon, writable = FALSE)
          DBI::dbGetQuery(icon,"SELECT COUNT(*) AS n FROM sqlite_schema;")
          TRUE
        }, error=function(e) e)
        if (inherits(immutable,"error")) add("SQLITE_IMMUTABLE_OPEN_FAILED",check_class="recipient",entity_kind="sqlite",entity_id="main",path=substring(db,nchar(root)+2L),observed=conditionMessage(immutable),message="Finalized recipient SQLite cannot be opened immutable/read-only.")
      }
    }
    v2_result <- tryCatch({
      .wb_operation_pack_v2_assert_recipient(structure(
        list(dir = root, manifest = manifest, con = con, read_only = TRUE),
        class = "scworkbench_bundle"))
      TRUE
    }, error = identity)
    if (inherits(v2_result, "error")) add(
      "OPERATION_PACK_V2_RECIPIENT_INVALID", check_class = "recipient",
      entity_kind = "operation_pack_transition", entity_id = "v2",
      path = "operation_pack_v2", observed = conditionMessage(v2_result),
      message = "A finalized ABI v2 transition failed pack-free recipient validation."
    )
  }) else skip("recipient", "recipient", "finalized transfer invariants require level='recipient'")

  if (!is.null(con)) { try(DBI::dbDisconnect(con), silent=TRUE); con <- NULL }
  after_fingerprint <- if (has_level("recipient")) fingerprint() else NA_character_
  if (has_level("recipient")) emit_progress("complete","recipient_fingerprint_after")
  if (has_level("recipient") && !identical(before_fingerprint, after_fingerprint)) add("VALIDATION_MUTATED_BUNDLE",check_class="recipient",entity_kind="bundle",entity_id=basename(root),expected=before_fingerprint,observed=after_fingerprint,message="Recipient validation changed the bundle filesystem fingerprint.")

  if (nrow(diagnostics)) diagnostics <- diagnostics[order(diagnostics$severity, diagnostics$code, diagnostics$entity_kind, diagnostics$entity_id, diagnostics$path, na.last=TRUE),,drop=FALSE]
  rownames(diagnostics) <- NULL
  if (nrow(skipped)) skipped <- unique(skipped[order(skipped$check_class),,drop=FALSE])
  if (nrow(content_coverage)) { content_coverage <- content_coverage[order(content_coverage$entity_kind,content_coverage$entity_id),,drop=FALSE]; rownames(content_coverage)<-NULL }
  timings <- stats::aggregate(elapsed_seconds ~ check_class, timings, sum)
  timings <- timings[order(timings$check_class),,drop=FALSE]; timings$elapsed_seconds <- round(timings$elapsed_seconds, 6)
  errors <- diagnostics$severity == "error"
  finished <- Sys.time(); gc_after <- suppressWarnings(gc())
  peak_memory_mb <- max(c(gc_before[, 6L], gc_after[, 6L]), na.rm = TRUE)
  process_peak_rss_mb <- suppressWarnings(max(resource_samples$peak_rss_mb,na.rm=TRUE)); if (!is.finite(process_peak_rss_mb)) process_peak_rss_mb <- NA_real_
  structure(list(
    schema_version = "scworkbench.bundle_validation_report.v1",
    path_contract = list(
      version = .wb_bundle_path_contract_version(),
      durable_paths = "bundle_relative_contained",
      external_paths = "declared_nonportable_uninspected",
      serialized_payloads = "not_loaded_by_validation",
      unsafe_payloads_loaded = FALSE
    ),
    bundle_path = root,
    bundle_manifest_version = manifest_version,
    requested_level = level,
    completed_levels = .wb_validation_levels()[seq_len(requested_index)],
    ok = !any(errors), status = if (any(errors)) "error" else if (any(diagnostics$severity == "warning")) "ok_with_warnings" else "ok",
    diagnostics = diagnostics, skipped_checks = skipped, content_coverage = content_coverage, elapsed_by_check_class = timings,
    elapsed_seconds = round(as.numeric(difftime(finished, started, units="secs")),6),
    peak_memory_mb = as.numeric(peak_memory_mb), process_peak_rss_mb=process_peak_rss_mb, resource_samples=resource_samples,
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
