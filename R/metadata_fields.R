# Canonical cell-metadata identity and bulk-write boundary.

.wb_quote_identifier <- function(con, identifier) {
  .wb_assert(is.character(identifier) && length(identifier) == 1L && !is.na(identifier),
             "SQL identifier must be one non-missing string.")
  raw <- charToRaw(enc2utf8(identifier))
  .wb_assert(!any(raw == as.raw(0L)), "SQL identifiers cannot contain an embedded NUL byte.")
  as.character(DBI::dbQuoteIdentifier(con, identifier))
}

.wb_metadata_core_fields <- function() c("cell_id", "dataset_id")

.wb_ensure_metadata_fields_table <- function(con) {
  DBI::dbExecute(con, paste(
    "CREATE TABLE IF NOT EXISTS metadata_fields (",
    "field_id TEXT PRIMARY KEY,",
    "source_name TEXT NOT NULL,",
    "display_name TEXT NOT NULL,",
    "storage_name TEXT NOT NULL UNIQUE COLLATE NOCASE,",
    "source_position INTEGER NOT NULL,",
    "storage_type TEXT NOT NULL CHECK(storage_type IN ('INTEGER','REAL','TEXT')),",
    "source_type TEXT NOT NULL,",
    "coercion_type TEXT NOT NULL,",
    "collision_status TEXT NOT NULL,",
    "resolution TEXT NOT NULL,",
    "is_core INTEGER NOT NULL DEFAULT 0 CHECK(is_core IN (0,1)),",
    "import_id TEXT,",
    "import_source TEXT,",
    "created_by TEXT,",
    "evidence_json TEXT,",
    "created_at TEXT NOT NULL,",
    "updated_at TEXT NOT NULL",
    ");"
  ))
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_metadata_fields_source ON metadata_fields(source_name);")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_metadata_fields_display ON metadata_fields(display_name);")
  invisible(TRUE)
}

.wb_metadata_backfill_registry <- function(con) {
  .wb_ensure_metadata_fields_table(con)
  info <- DBI::dbGetQuery(con, paste0("PRAGMA table_info(", .wb_quote_identifier(con, "cells"), ");"))
  registered <- DBI::dbGetQuery(con, "SELECT storage_name FROM metadata_fields;")$storage_name
  missing <- info[!(tolower(info$name) %in% tolower(registered)), , drop = FALSE]
  if (!nrow(missing)) return(invisible(TRUE))
  now <- format(Sys.time(), "%Y-%m-%dT%H:%M:%OS6%z")
  next_meta <- sum(!DBI::dbGetQuery(con, "SELECT is_core FROM metadata_fields;")$is_core) + 1L
  for (i in seq_len(nrow(missing))) {
    nm <- as.character(missing$name[[i]])
    core <- nm %in% .wb_metadata_core_fields()
    field_id <- if (core) paste0("core:", nm) else sprintf("meta:%06d", next_meta)
    if (!core) next_meta <- next_meta + 1L
    typ <- toupper(as.character(missing$type[[i]] %||% "TEXT"))
    typ <- if (grepl("INT", typ)) "INTEGER" else if (grepl("REAL|FLOA|DOUB|NUM", typ)) "REAL" else "TEXT"
    DBI::dbExecute(con, paste(
      "INSERT INTO metadata_fields(field_id,source_name,display_name,storage_name,source_position,",
      "storage_type,source_type,coercion_type,collision_status,resolution,is_core,import_id,import_source,created_by,evidence_json,created_at,updated_at)",
      "VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?);"
    ), params = list(
      field_id, nm, nm, nm, as.integer(missing$cid[[i]]) + 1L, typ,
      if (core) "engine" else "legacy", typ, if (core) "reserved_core" else "backfilled",
      if (core) "engine_owned" else "preserved_existing", as.integer(core),
      if (core) "schema" else "migration", "schema_migration", "scworkbench",
      jsonlite::toJSON(list(backfilled = TRUE), auto_unbox = TRUE), now, now
    ))
  }
  invisible(TRUE)
}

.wb_metadata_registry <- function(con) {
  .wb_assert(.wb_table_exists(con, "metadata_fields"),
             "METADATA_FIELD_REGISTRY_MISSING: migrate or recreate this development bundle.")
  DBI::dbGetQuery(con, "SELECT * FROM metadata_fields ORDER BY is_core DESC, rowid;")
}

#' Create an explicit metadata-field reference
#'
#' Use this reference when a metadata field ID must be distinguished from an
#' arbitrary source/display/storage name with the same spelling. The list form
#' is JSON-serializable and is preserved by session provenance and strict replay.
#'
#' @param field_id Stable `field_id` returned by [wb_metadata_fields()].
#' @return A typed metadata-field reference list.
#' @export
wb_ref_metadata_field <- function(field_id) {
  .wb_assert(is.character(field_id) && length(field_id) == 1L && !is.na(field_id) && nzchar(field_id),
             "field_id must be one non-empty stable metadata field identity.")
  list(ref_type = "metadata_field", field_id = field_id)
}

.wb_is_metadata_field_ref <- function(x) {
  is.list(x) && identical(as.character(x$ref_type %||% "")[1L], "metadata_field")
}

.wb_validate_metadata_field_ref <- function(x, label = "metadata field reference") {
  .wb_assert(.wb_is_metadata_field_ref(x), paste0(label, " must be created by wb_ref_metadata_field()."))
  .wb_assert(!is.null(names(x)) && !anyDuplicated(names(x)) &&
               setequal(names(x), c("ref_type", "field_id")),
             paste0(label, " must contain exactly ref_type and field_id."))
  .wb_assert(is.character(x$field_id) && length(x$field_id) == 1L &&
               !is.na(x$field_id) && nzchar(x$field_id),
             paste0(label, "$field_id must be one non-empty string."))
  x
}

.wb_metadata_lookup_items <- function(x) {
  if (is.null(x)) return(list())
  if (.wb_is_metadata_field_ref(x)) return(list(x))
  if (is.character(x)) return(as.list(x))
  .wb_assert(is.list(x), "Metadata fields must be names or wb_ref_metadata_field() references.")
  x
}

.wb_metadata_lookup_plan <- function(bundle, x) {
  items <- .wb_metadata_lookup_items(x)
  if (!length(items)) return(list(refs = list(), aliases = character(), rows = list()))
  rows <- lapply(items, function(item) .wb_metadata_resolve(bundle, item, allow_core = TRUE))
  aliases <- vapply(seq_along(items), function(i) {
    if (.wb_is_metadata_field_ref(items[[i]])) rows[[i]]$field_id[[1L]] else as.character(items[[i]])[1L]
  }, character(1))
  refs <- lapply(rows, function(row) wb_ref_metadata_field(row$field_id[[1L]]))
  .wb_assert(!anyDuplicated(aliases), "Metadata field selection produces duplicate output aliases.")
  list(refs = refs, aliases = aliases, rows = rows)
}

.wb_metadata_resolve <- function(bundle, field, allow_core = TRUE) {
  con <- if (inherits(bundle, "scworkbench_bundle")) bundle$con else bundle
  reg <- .wb_metadata_registry(con)
  if (.wb_is_metadata_field_ref(field)) {
    ref <- .wb_validate_metadata_field_ref(field)
    hit <- which(reg$field_id == ref$field_id)
    label <- ref$field_id
  } else {
    .wb_assert(is.character(field) && length(field) == 1L && !is.na(field) && nzchar(field),
               "Metadata field must be one non-empty name or wb_ref_metadata_field().")
    label <- field
    # The two engine aliases are deliberately stable. Imported fields with
    # these source names remain addressable through their explicit field refs.
    if (isTRUE(allow_core) && field %in% .wb_metadata_core_fields()) {
      hit <- which(reg$field_id == paste0("core:", field))
    } else {
      hit <- unique(which(
        reg$field_id == field | reg$source_name == field |
          reg$display_name == field | reg$storage_name == field
      ))
    }
  }
  if (!isTRUE(allow_core)) hit <- hit[reg$is_core[hit] == 0L]
  if (!length(hit)) {
    stop("Unknown metadata field '", label, "'. Use wb_metadata_fields() to list valid stable identities.", call. = FALSE)
  }
  if (length(hit) != 1L) {
    stop(
      "Ambiguous metadata field '", label, "'. Matching stable identities: ",
      paste(reg$field_id[hit], collapse = ", "),
      ". Select explicitly with wb_ref_metadata_field().", call. = FALSE
    )
  }
  reg[hit, , drop = FALSE]
}

#' List canonical cell-metadata fields
#'
#' Returns the durable mapping between source/display names, stable field IDs,
#' and physical SQLite storage. Use [wb_ref_metadata_field()] whenever a bare
#' name matches more than one namespace.
#'
#' @param bundle Open scworkbench bundle.
#' @param include_core Include engine-owned `cell_id` and `dataset_id` fields.
#' @return A data frame ordered by registry creation order.
#' @export
wb_metadata_fields <- function(bundle, include_core = TRUE) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  out <- .wb_metadata_registry(bundle$con)
  if (!isTRUE(include_core)) out <- out[out$is_core == 0L, , drop = FALSE]
  rownames(out) <- NULL
  out
}

#' Resolve one canonical cell-metadata field
#'
#' @param bundle Open scworkbench bundle.
#' @param field Unambiguous source/display/storage name or a structured
#'   [wb_ref_metadata_field()] reference. A bare stable-ID-shaped string is
#'   rejected when it also names a different field.
#' @param include_core Whether engine-owned fields may resolve.
#' @return The single durable field-mapping row.
#' @export
wb_metadata_field_resolve <- function(bundle, field, include_core = TRUE) {
  .wb_metadata_resolve(bundle, field, allow_core = include_core)
}

.wb_metadata_source_type <- function(x) {
  if (is.factor(x)) return("factor")
  if (is.logical(x)) return("logical")
  if (is.integer(x)) return("integer")
  if (is.double(x)) return("double")
  if (is.character(x)) return("character")
  stop("Unsupported metadata column type: ", paste(class(x), collapse = "/"), call. = FALSE)
}

.wb_metadata_storage_type <- function(x) {
  if (is.factor(x) || is.character(x)) "TEXT" else if (is.logical(x) || is.integer(x)) "INTEGER" else if (is.double(x)) "REAL" else
    stop("Unsupported metadata column type: ", paste(class(x), collapse = "/"), call. = FALSE)
}

.wb_metadata_coerce <- function(x, storage_type, field_label) {
  source_type <- .wb_metadata_source_type(x)
  if (identical(storage_type, "TEXT")) {
    .wb_assert(source_type %in% c("character", "factor"),
               paste0("Incompatible metadata overwrite for '", field_label, "': ", source_type, " cannot safely update TEXT."))
    return(as.character(x))
  }
  if (identical(storage_type, "REAL")) {
    .wb_assert(source_type %in% c("logical", "integer", "double"),
               paste0("Incompatible metadata overwrite for '", field_label, "': ", source_type, " cannot safely update REAL."))
    return(as.numeric(x))
  }
  .wb_assert(source_type %in% c("logical", "integer", "double"),
             paste0("Incompatible metadata overwrite for '", field_label, "': ", source_type, " cannot safely update INTEGER."))
  vals <- as.numeric(x)
  good <- is.na(vals) | (is.finite(vals) & vals == trunc(vals) & vals >= -.Machine$integer.max - 1 & vals <= .Machine$integer.max)
  .wb_assert(all(good), paste0("Lossy metadata coercion rejected for '", field_label, "' (non-integral or out-of-range value)."))
  as.integer(vals)
}

.wb_metadata_writer_hook <- function(event, con = NULL, report = NULL) {
  hook <- getOption("scworkbench.metadata_writer_test_hook")
  if (is.function(hook)) hook(event = event, con = con, report = report)
  invisible(TRUE)
}

.wb_metadata_with_transaction <- function(con, code) {
  if (isTRUE(tryCatch(RSQLite::sqliteIsTransacting(con), error = function(e) FALSE))) return(force(code))
  DBI::dbWithTransaction(con, force(code))
}

.wb_write_cell_metadata <- function(con, metadata, target_cell_ids = NULL,
                                    source = "metadata", created_by = NULL,
                                    field_refs = NULL) {
  .wb_assert(is.data.frame(metadata), "metadata must be a data.frame")
  md <- as.data.frame(metadata, stringsAsFactors = FALSE, check.names = FALSE)
  .wb_assert(ncol(md) >= 1L, "metadata must contain a first cell-id column")
  ids <- as.character(md[[1L]])
  .wb_assert(!anyNA(ids) && all(nzchar(ids)), "metadata contains missing or empty cell IDs")
  .wb_assert(!anyDuplicated(ids), "metadata contains duplicate cell IDs")
  if (!nrow(md)) return(invisible(list(n_rows = 0L, fields = data.frame(), statement_count = 0L)))

  universe <- as.character(DBI::dbGetQuery(con, "SELECT cell_id FROM cells;")$cell_id)
  unknown <- setdiff(ids, universe)
  .wb_assert(!length(unknown), paste0("Unknown metadata cell IDs: ", paste(head(unknown, 10L), collapse = ", ")))
  if (!is.null(target_cell_ids)) {
    outside <- setdiff(ids, as.character(target_cell_ids))
    .wb_assert(!length(outside), paste0("Metadata contains cells outside the declared attachment target: ", paste(head(outside, 10L), collapse = ", ")))
  }
  if (ncol(md) == 1L) return(invisible(list(n_rows = nrow(md), fields = data.frame(), statement_count = 0L)))

  source_names <- names(md)[-1L]
  source_names[is.na(source_names)] <- ""
  n_fields <- length(source_names)
  if (is.null(field_refs)) {
    field_refs <- rep(list(NULL), n_fields)
  } else if (is.character(field_refs)) {
    .wb_assert(length(field_refs) == n_fields,
               "field_refs must have one entry per metadata payload column.")
    field_refs <- lapply(field_refs, function(x) {
      if (is.na(x) || !nzchar(x)) NULL else wb_ref_metadata_field(x)
    })
  } else {
    .wb_assert(is.list(field_refs) && length(field_refs) == n_fields,
               "field_refs must be a list with one entry per metadata payload column.")
  }
  for (j in seq_along(field_refs)) if (!is.null(field_refs[[j]])) {
    field_refs[[j]] <- .wb_validate_metadata_field_ref(field_refs[[j]], paste0("field_refs[[", j, "]]"))
  }
  source_types <- vapply(md[-1L], .wb_metadata_source_type, character(1))
  input_fold <- tolower(enc2utf8(source_names))
  input_ambiguous <- duplicated(input_fold) | duplicated(input_fold, fromLast = TRUE)
  input_reserved_fold <- unique(input_fold[
    nzchar(source_names) & !input_ambiguous &
      !(source_names %in% .wb_metadata_core_fields())
  ])
  import_id <- .wb_allocate_identifier(
    paste0("metadata:", format(Sys.time(), "%Y%m%dT%H%M%OS6"), ":", Sys.getpid(), ":"),
    12L, purpose = "metadata import"
  )
  now <- format(Sys.time(), "%Y-%m-%dT%H:%M:%OS6%z")
  report <- NULL

  .wb_metadata_with_transaction(con, {
    .wb_ensure_metadata_fields_table(con)
    reg <- .wb_metadata_registry(con)
    next_id <- if (any(reg$is_core == 0L)) max(as.integer(sub("^meta:", "", reg$field_id[reg$is_core == 0L]))) + 1L else 1L
    next_id <- if (is.finite(next_id)) next_id else 1L
    mappings <- vector("list", length(source_names))

    for (j in seq_along(source_names)) {
      nm <- source_names[[j]]
      # Payload column names inhabit the source-name namespace only. A spelling
      # that happens to equal another row's field_id/display/storage identity
      # never implies update intent.
      ordinary_hit <- which(reg$source_name == nm & reg$is_core == 0L)
      core_hit <- which(reg$source_name == nm & reg$is_core == 1L)
      explicit <- field_refs[[j]]
      explicit_hit <- if (is.null(explicit)) integer(0) else which(reg$field_id == explicit$field_id)
      if (!is.null(explicit)) {
        .wb_assert(length(explicit_hit) == 1L,
                   paste0("Unknown explicit metadata field_id '", explicit$field_id, "'."))
        .wb_assert(reg$is_core[explicit_hit] == 0L,
                   paste0("Engine-owned field '", explicit$field_id, "' cannot be updated as ordinary metadata."))
      }
      hit <- if (!is.null(explicit)) explicit_hit else if (!input_ambiguous[[j]] && length(ordinary_hit) == 1L) ordinary_hit else integer(0)
      if (is.null(explicit) && !input_ambiguous[[j]] && length(ordinary_hit) > 1L) {
        choices <- unique(reg$field_id[ordinary_hit])
        stop("Ambiguous metadata field '", nm, "'. Use one of the stable identities: ", paste(choices, collapse = ", "), call. = FALSE)
      }

      if (length(hit) == 1L) {
        row <- reg[hit, , drop = FALSE]
        values <- .wb_metadata_coerce(md[[j + 1L]], row$storage_type[[1L]], nm)
        update_evidence <- list(
          action = "compatible_update", field_id = row$field_id[[1L]],
          source_name = nm, source_position = j + 1L,
          previous_source_type = row$source_type[[1L]], source_type = source_types[[j]],
          storage_type = row$storage_type[[1L]], import_id = import_id
        )
        DBI::dbExecute(con, paste(
          "UPDATE metadata_fields SET source_type=?, coercion_type=?, import_id=?, import_source=?,",
          "created_by=?, evidence_json=?, updated_at=? WHERE field_id=?;"
        ), params = list(
          source_types[[j]], row$storage_type[[1L]], import_id, source,
          created_by %||% NA_character_, jsonlite::toJSON(update_evidence, auto_unbox = TRUE),
          now, row$field_id[[1L]]
        ))
        reg <- .wb_metadata_registry(con)
        row <- reg[reg$field_id == row$field_id[[1L]], , drop = FALSE]
        mappings[[j]] <- cbind(row, data.frame(input_position = j + 1L, input_name = nm,
                                                source_type_current = source_types[[j]], stringsAsFactors = FALSE))
        mappings[[j]]$values <- I(list(values))
        next
      }

      field_id <- sprintf("meta:%06d", next_id)
      next_id <- next_id + 1L
      storage_type <- .wb_metadata_storage_type(md[[j + 1L]])
      values <- .wb_metadata_coerce(md[[j + 1L]], storage_type, nm)
      storage_fold <- tolower(enc2utf8(reg$storage_name))
      preservable <- nzchar(nm) && !any(charToRaw(enc2utf8(nm)) == as.raw(0L)) &&
        !(tolower(enc2utf8(nm)) %in% storage_fold) && !input_ambiguous[[j]] && !length(core_hit)
      if (preservable) {
        storage_name <- nm
      } else {
        storage_index <- as.integer(sub("^meta:", "", field_id))
        repeat {
          candidate <- sprintf("__wb_meta_%06d", storage_index)
          if (!(tolower(enc2utf8(candidate)) %in% c(storage_fold, input_reserved_fold))) break
          storage_index <- storage_index + 1L
        }
        storage_name <- candidate
      }
      collision <- if (preservable) "none" else if (!nzchar(nm)) "empty_name" else if (length(core_hit)) "reserved_core" else if (input_ambiguous[[j]]) "duplicate_or_casefold" else "storage_collision"
      resolution <- if (preservable) "preserved_exactly" else "stable_storage_rename"
      display_name <- if (nzchar(nm)) nm else field_id
      evidence <- list(source_name = nm, source_position = j + 1L, collision_status = collision,
                       resolution = resolution, source_type = source_types[[j]], storage_type = storage_type)
      DBI::dbExecute(con, paste(
        "INSERT INTO metadata_fields(field_id,source_name,display_name,storage_name,source_position,storage_type,",
        "source_type,coercion_type,collision_status,resolution,is_core,import_id,import_source,created_by,evidence_json,created_at,updated_at)",
        "VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?);"
      ), params = list(field_id, nm, display_name, storage_name, j + 1L, storage_type,
                       source_types[[j]], storage_type, collision, resolution, 0L, import_id,
                       source, created_by %||% NA_character_, jsonlite::toJSON(evidence, auto_unbox = TRUE), now, now))
      DBI::dbExecute(con, paste0("ALTER TABLE ", .wb_quote_identifier(con, "cells"), " ADD COLUMN ",
                                 .wb_quote_identifier(con, storage_name), " ", storage_type, ";"))
      reg <- .wb_metadata_registry(con)
      row <- reg[reg$field_id == field_id, , drop = FALSE]
      mappings[[j]] <- cbind(row, data.frame(input_position = j + 1L, input_name = nm,
                                              source_type_current = source_types[[j]], stringsAsFactors = FALSE))
      mappings[[j]]$values <- I(list(values))
    }
    .wb_metadata_writer_hook("after_schema_and_registry", con, report)

    tmp <- .wb_allocate_identifier(
      paste0("__wb_metadata_stage_", Sys.getpid(), "_"), 12L,
      purpose = "metadata temporary table"
    )
    tmp_q <- .wb_quote_identifier(con, tmp)
    stage <- data.frame(cell_id = ids, stringsAsFactors = FALSE, check.names = FALSE)
    value_types <- character(length(mappings))
    for (j in seq_along(mappings)) {
      value_name <- sprintf("v%06d", j)
      stage[[value_name]] <- mappings[[j]]$values[[1L]]
      value_types[[j]] <- as.character(mappings[[j]]$storage_type[[1L]])
    }
    stage_columns <- c(
      paste0(.wb_quote_identifier(con, "cell_id"), " TEXT PRIMARY KEY"),
      vapply(seq_along(mappings), function(j) paste0(
        .wb_quote_identifier(con, sprintf("v%06d", j)), " ", value_types[[j]]
      ), character(1))
    )
    DBI::dbExecute(con, paste0("CREATE TEMP TABLE ", tmp_q, " (", paste(stage_columns, collapse = ", "), ");"))
    DBI::dbAppendTable(con, tmp, stage)
    stage_index <- DBI::dbGetQuery(con, paste0("PRAGMA index_list(", tmp_q, ");"))
    .wb_assert(nrow(stage_index) >= 1L && any(as.integer(stage_index$unique) == 1L),
               "Metadata staging table must have a unique cell_id index.")
    .wb_metadata_writer_hook("after_staging", con, report)
    query_plans <- vector("list", length(mappings))
    for (j in seq_along(mappings)) {
      storage_q <- .wb_quote_identifier(con, mappings[[j]]$storage_name[[1L]])
      value_q <- .wb_quote_identifier(con, sprintf("v%06d", j))
      update_sql <- paste0(
        "UPDATE ", .wb_quote_identifier(con, "cells"), " AS c SET ", storage_q,
        " = (SELECT s.", value_q, " FROM ", tmp_q, " AS s WHERE s.cell_id = c.cell_id)",
        " WHERE c.cell_id IN (SELECT cell_id FROM ", tmp_q, ");"
      )
      query_plans[[j]] <- DBI::dbGetQuery(con, paste("EXPLAIN QUERY PLAN", update_sql))
      DBI::dbExecute(con, update_sql)
    }
    .wb_metadata_writer_hook("after_values", con, report)
    DBI::dbExecute(con, paste0("DROP TABLE ", tmp_q, ";"))
    fields <- do.call(rbind, lapply(mappings, function(x) {
      x$values <- NULL
      x
    }))
    report <- list(
      n_rows = nrow(md), fields = fields,
      statement_count = as.integer(3L * sum(fields$created_at == now) +
        2L * sum(fields$created_at != now) + 3L),
      complexity = "O(metadata_rows * metadata_fields * log(bundle_cells))",
      statement_complexity = "O(metadata_fields)",
      staging_index_strategy = "TEMP TABLE cell_id TEXT PRIMARY KEY",
      staging_index_count = nrow(stage_index),
      query_plan = query_plans,
      import_id = import_id
    )
    .wb_metadata_writer_hook("before_commit", con, report)
  })
  invisible(report)
}
