# Checksummed, source-aware cell-metadata table ingestion.

.wb_metadata_import_abort <- function(code, message, evidence = list()) {
  stop(structure(
    c(list(message = paste0(code, ": ", message), call = NULL, code = code), evidence),
    class = c("scworkbench_metadata_import_error", "scworkbench_error", "error", "condition")
  ))
}

.wb_metadata_import_fault <- function(event, ...) {
  hook <- getOption("scworkbench.metadata_import_test_hook")
  if (is.function(hook)) hook(event = event, ...)
  invisible(TRUE)
}

.wb_metadata_import_format <- function(path) {
  ext <- tolower(tools::file_ext(path))
  if (identical(ext, "csv")) return(list(format = "csv", delimiter = ","))
  if (ext %in% c("tsv", "tab")) return(list(format = "tsv", delimiter = "\t"))
  .wb_metadata_import_abort(
    "METADATA_IMPORT_FORMAT_UNSUPPORTED",
    "input must have a .csv, .tsv, or .tab extension."
  )
}

.wb_metadata_import_parse <- function(path, parser) {
  tryCatch(
    utils::read.table(
      path, header = TRUE, sep = parser$delimiter, quote = "\"",
      comment.char = "", stringsAsFactors = FALSE, check.names = FALSE,
      na.strings = c("", "NA"), fill = FALSE, strip.white = FALSE,
      numerals = "no.loss"
    ),
    error = function(e) .wb_metadata_import_abort(
      "METADATA_IMPORT_PARSE_FAILED", conditionMessage(e)
    )
  )
}

.wb_metadata_import_source <- function(input, source_identity, parser) {
  identity <- source_identity
  if (is.list(identity) && !is.null(identity$scope) && is.null(identity$inputs)) {
    identity <- list(schema = "scworkbench.source_identity.v2", inputs = list(identity))
  }
  checked <- tryCatch(
    wb_source_preflight(identity, verify_files = TRUE, strict = TRUE),
    error = function(e) .wb_metadata_import_abort(
      "METADATA_IMPORT_SOURCE_INVALID", conditionMessage(e)
    )
  )
  sources <- checked$source_identity$inputs %||% list()
  if (length(sources) != 1L) {
    .wb_metadata_import_abort(
      "METADATA_IMPORT_SOURCE_CARDINALITY",
      "source_identity must declare exactly one checksummed file input."
    )
  }
  source <- sources[[1L]]
  scope <- as.character(source$scope %||% "")[1L]
  if (!scope %in% c("public_file", "external_file")) {
    .wb_metadata_import_abort(
      "METADATA_IMPORT_SOURCE_SCOPE",
      "source_identity must use public_file or external_file scope."
    )
  }
  declared_format <- tolower(as.character(source$format %||% "")[1L])
  compatible <- if (identical(parser$format, "csv")) c("csv", "text/csv") else
    c("tsv", "tab", "text/tab-separated-values", "text/tsv")
  if (!declared_format %in% compatible) {
    .wb_metadata_import_abort(
      "METADATA_IMPORT_FORMAT_CONTRADICTION",
      paste0("source format '", declared_format, "' contradicts the ", parser$format, " input extension.")
    )
  }
  actual <- wb_source_sha256(input)
  expected <- tolower(as.character(source$sha256 %||% source$checksum %||% "")[1L])
  if (!identical(actual, expected)) {
    .wb_metadata_import_abort(
      "METADATA_IMPORT_CHECKSUM_MISMATCH",
      paste0("input SHA-256 ", actual, " does not equal declared SHA-256 ", expected, ".")
    )
  }
  declared_path <- as.character(source$path %||% "")[1L]
  if (nzchar(declared_path) && file.exists(declared_path)) {
    same <- identical(
      normalizePath(declared_path, winslash = "/", mustWork = TRUE),
      normalizePath(input, winslash = "/", mustWork = TRUE)
    )
    if (!same) .wb_metadata_import_abort(
      "METADATA_IMPORT_SOURCE_PATH_MISMATCH",
      "the local file verified by source_identity is not the input file."
    )
  }
  uri <- as.character(source$uri %||% "")[1L]
  if (nzchar(uri) && grepl("^file:", uri, ignore.case = TRUE)) {
    .wb_metadata_import_abort(
      "METADATA_IMPORT_HOST_PATH_URI",
      "file: URIs are not portable source identities; use a public URI or accession."
    )
  }
  portable <- source
  portable$path <- if (nzchar(declared_path)) basename(declared_path) else basename(input)
  portable$local_path <- NULL
  portable$bundled <- FALSE
  portable$sha256 <- actual
  portable$checksum <- actual
  portable$checksum_algorithm <- "sha256"
  list(
    actual_sha256 = actual,
    source_id = as.character(source$source_id)[1L],
    source_identity = list(
      schema = as.character(checked$source_identity$schema %||% "scworkbench.source_identity.v2")[1L],
      inputs = list(portable)
    )
  )
}

.wb_metadata_import_field_refs <- function(field_refs, n_fields) {
  if (is.null(field_refs)) return(rep(list(NULL), n_fields))
  if (is.character(field_refs)) {
    if (length(field_refs) != n_fields) .wb_metadata_import_abort(
      "METADATA_IMPORT_FIELD_REFS_LENGTH",
      "field_refs must have one position-aligned entry per selected metadata field."
    )
    field_refs <- lapply(field_refs, function(x) {
      if (is.na(x) || !nzchar(x)) NULL else wb_ref_metadata_field(x)
    })
  }
  if (!is.list(field_refs) || length(field_refs) != n_fields) {
    .wb_metadata_import_abort(
      "METADATA_IMPORT_FIELD_REFS_LENGTH",
      "field_refs must be a position-aligned list with one entry per selected metadata field."
    )
  }
  lapply(seq_along(field_refs), function(i) {
    if (is.null(field_refs[[i]])) NULL else
      .wb_validate_metadata_field_ref(field_refs[[i]], paste0("field_refs[[", i, "]]"))
  })
}

.wb_metadata_import_field_plan <- function(bundle, payload, field_refs) {
  reg <- .wb_metadata_registry(bundle$con)
  source_names <- names(payload)[-1L]
  source_types <- vapply(payload[-1L], .wb_metadata_source_type, character(1))
  fold <- tolower(enc2utf8(source_names))
  ambiguous <- duplicated(fold) | duplicated(fold, fromLast = TRUE)
  reserved <- unique(fold[nzchar(source_names) & !ambiguous &
                            !(source_names %in% .wb_metadata_core_fields())])
  next_id <- if (any(reg$is_core == 0L)) {
    suppressWarnings(max(as.integer(sub("^meta:", "", reg$field_id[reg$is_core == 0L])), na.rm = TRUE) + 1L)
  } else 1L
  if (!is.finite(next_id)) next_id <- 1L
  rows <- vector("list", length(source_names))
  for (j in seq_along(source_names)) {
    nm <- source_names[[j]]
    ordinary <- which(reg$source_name == nm & reg$is_core == 0L)
    core <- which(reg$source_name == nm & reg$is_core == 1L)
    explicit <- field_refs[[j]]
    hit <- integer()
    if (!is.null(explicit)) {
      hit <- which(reg$field_id == explicit$field_id)
      if (length(hit) != 1L) .wb_metadata_import_abort(
        "METADATA_IMPORT_FIELD_REF_UNKNOWN",
        paste0("unknown explicit metadata field_id '", explicit$field_id, "'.")
      )
      if (reg$is_core[hit] == 1L) .wb_metadata_import_abort(
        "METADATA_IMPORT_FIELD_REF_CORE",
        paste0("engine-owned field '", explicit$field_id, "' cannot be updated.")
      )
    } else if (!ambiguous[[j]] && length(ordinary) == 1L) {
      hit <- ordinary
    } else if (!ambiguous[[j]] && length(ordinary) > 1L) {
      .wb_metadata_import_abort(
        "METADATA_IMPORT_FIELD_AMBIGUOUS",
        paste0("metadata field '", nm, "' matches multiple identities; use field_refs.")
      )
    }
    if (length(hit)) {
      row <- reg[hit, , drop = FALSE]
      .wb_metadata_coerce(payload[[j + 1L]], row$storage_type[[1L]], nm)
      rows[[j]] <- data.frame(
        field_id = row$field_id, source_name = nm, display_name = row$display_name,
        storage_name = row$storage_name, source_type = source_types[[j]],
        storage_type = row$storage_type, action = "compatible_update",
        missing_count = as.integer(sum(is.na(payload[[j + 1L]]))),
        stringsAsFactors = FALSE, check.names = FALSE
      )
      next
    }
    field_id <- sprintf("meta:%06d", next_id); next_id <- next_id + 1L
    storage_type <- .wb_metadata_storage_type(payload[[j + 1L]])
    .wb_metadata_coerce(payload[[j + 1L]], storage_type, nm)
    storage_fold <- tolower(enc2utf8(reg$storage_name))
    preservable <- nzchar(nm) && !any(charToRaw(enc2utf8(nm)) == as.raw(0L)) &&
      !(tolower(enc2utf8(nm)) %in% storage_fold) && !ambiguous[[j]] && !length(core)
    if (preservable) storage_name <- nm else {
      storage_index <- as.integer(sub("^meta:", "", field_id))
      repeat {
        candidate <- sprintf("__wb_meta_%06d", storage_index)
        if (!(tolower(enc2utf8(candidate)) %in% c(storage_fold, reserved))) break
        storage_index <- storage_index + 1L
      }
      storage_name <- candidate
    }
    rows[[j]] <- data.frame(
      field_id = field_id, source_name = nm,
      display_name = if (nzchar(nm)) nm else field_id,
      storage_name = storage_name, source_type = source_types[[j]],
      storage_type = storage_type, action = "create",
      missing_count = as.integer(sum(is.na(payload[[j + 1L]]))),
      stringsAsFactors = FALSE, check.names = FALSE
    )
    reg <- rbind(reg, data.frame(
      field_id = field_id, source_name = nm,
      display_name = if (nzchar(nm)) nm else field_id,
      storage_name = storage_name, source_position = j + 1L,
      storage_type = storage_type, source_type = source_types[[j]],
      coercion_type = storage_type, collision_status = if (preservable) "none" else "stable_storage_rename",
      resolution = if (preservable) "preserved_exactly" else "stable_storage_rename",
      is_core = 0L, import_id = NA_character_, import_source = NA_character_,
      created_by = NA_character_, evidence_json = NA_character_,
      created_at = NA_character_, updated_at = NA_character_, stringsAsFactors = FALSE
    ))
  }
  out <- if (length(rows)) do.call(rbind, rows) else data.frame(
    field_id=character(), source_name=character(), display_name=character(),
    storage_name=character(), source_type=character(), storage_type=character(),
    action=character(), missing_count=integer(), stringsAsFactors=FALSE
  )
  rownames(out) <- NULL
  out
}

.wb_metadata_import_plan <- function(bundle, input, cell_id_col, source_identity,
                                     fields, field_refs, unknown_cell_policy) {
  if (!is.character(input) || length(input) != 1L || is.na(input) || !nzchar(input) ||
      !file.exists(input) || dir.exists(input)) {
    .wb_metadata_import_abort("METADATA_IMPORT_INPUT_MISSING", "input must be one existing text file.")
  }
  parser <- .wb_metadata_import_format(input)
  source <- .wb_metadata_import_source(input, source_identity, parser)
  table <- .wb_metadata_import_parse(input, parser)
  if (!is.character(cell_id_col) || length(cell_id_col) != 1L || is.na(cell_id_col) || !nzchar(cell_id_col)) {
    .wb_metadata_import_abort("METADATA_IMPORT_CELL_ID_COLUMN_INVALID", "cell_id_col must be one explicit non-empty column name.")
  }
  id_hits <- which(names(table) == cell_id_col)
  if (length(id_hits) != 1L) .wb_metadata_import_abort(
    if (!length(id_hits)) "METADATA_IMPORT_CELL_ID_COLUMN_MISSING" else "METADATA_IMPORT_CELL_ID_COLUMN_DUPLICATED",
    paste0("cell_id_col '", cell_id_col, "' must identify exactly one source column.")
  )
  ids <- as.character(table[[id_hits]])
  if (anyNA(ids) || any(!nzchar(ids))) .wb_metadata_import_abort(
    "METADATA_IMPORT_CELL_ID_EMPTY", "imported cell IDs may not be missing or empty."
  )
  if (anyDuplicated(ids)) .wb_metadata_import_abort(
    "METADATA_IMPORT_CELL_ID_DUPLICATED", "imported cell IDs must be unique."
  )
  available <- names(table)[-id_hits]
  selected <- if (is.null(fields)) available else {
    if (!is.character(fields) || anyNA(fields) || any(!nzchar(fields))) .wb_metadata_import_abort(
      "METADATA_IMPORT_FIELDS_INVALID", "fields must be non-empty source column names."
    )
    if (anyDuplicated(fields)) .wb_metadata_import_abort(
      "METADATA_IMPORT_FIELDS_DUPLICATED", "requested fields must not be duplicated."
    )
    missing_fields <- fields[!fields %in% available]
    if (length(missing_fields)) .wb_metadata_import_abort(
      "METADATA_IMPORT_FIELDS_MISSING",
      paste0("requested fields are absent: ", paste(missing_fields, collapse = ", "), ".")
    )
    duplicated_source <- fields[vapply(fields, function(x) sum(available == x) != 1L, logical(1))]
    if (length(duplicated_source)) .wb_metadata_import_abort(
      "METADATA_IMPORT_FIELDS_AMBIGUOUS",
      paste0("requested fields do not identify exactly one source column: ", paste(unique(duplicated_source), collapse = ", "), ".")
    )
    fields
  }
  if (!length(selected)) .wb_metadata_import_abort(
    "METADATA_IMPORT_NO_FIELDS", "the import must select at least one non-ID metadata field."
  )
  selected_idx <- vapply(selected, function(x) which(names(table) == x)[1L], integer(1))
  payload <- table[c(id_hits, selected_idx)]
  names(payload)[1L] <- cell_id_col
  refs <- .wb_metadata_import_field_refs(field_refs, length(selected))
  universe <- as.character(DBI::dbGetQuery(bundle$con, "SELECT cell_id FROM cells ORDER BY cell_id;")$cell_id)
  unknown <- ids[!ids %in% universe]
  if (length(unknown) && identical(unknown_cell_policy, "error")) .wb_metadata_import_abort(
    "METADATA_IMPORT_UNKNOWN_CELLS",
    paste0(length(unknown), " imported cell IDs are not in the bundle; examples: ",
           paste(head(unknown, 10L), collapse = ", "), "."),
    list(unknown_cell_ids = head(unknown, 100L))
  )
  keep <- ids %in% universe
  accepted <- payload[keep, , drop = FALSE]
  if (!nrow(accepted)) .wb_metadata_import_abort(
    "METADATA_IMPORT_NO_MATCHED_CELLS", "no imported rows match the bundle cell universe."
  )
  plan_fields <- .wb_metadata_import_field_plan(bundle, accepted, refs)
  list(
    schema = "scworkbench.metadata_import.plan.v1",
    valid = TRUE, input = input, parser = parser,
    source = source, cell_id_col = cell_id_col, selected_fields = selected,
    unknown_cell_policy = unknown_cell_policy, payload = accepted, field_refs = refs,
    fields = plan_fields,
    counts = list(
      supplied = as.integer(nrow(table)), matched = as.integer(sum(keep)),
      unknown = as.integer(length(unknown)), rejected = as.integer(length(unknown)),
      unsupplied_known = as.integer(length(setdiff(universe, ids[keep])))
    ),
    rejected = data.frame(
      row_number = as.integer(which(!keep)), cell_id = as.character(ids[!keep]),
      reason = rep("unknown_bundle_cell", sum(!keep)), stringsAsFactors = FALSE
    )
  )
}

.wb_metadata_import_report <- function(plan, description) {
  fields <- plan$fields
  field_rows <- data.frame(
    record_type = rep("field", nrow(fields)), source_name = fields$source_name,
    field_id = fields$field_id, storage_type = fields$storage_type,
    source_type = fields$source_type, action = fields$action,
    missing_count = fields$missing_count, row_number = NA_integer_,
    cell_id = NA_character_, reason = NA_character_, stringsAsFactors = FALSE
  )
  rejected <- head(plan$rejected, 100L)
  rejected_rows <- data.frame(
    record_type = rep("rejected_row", nrow(rejected)), source_name = rep(NA_character_, nrow(rejected)),
    field_id = rep(NA_character_, nrow(rejected)), storage_type = rep(NA_character_, nrow(rejected)), source_type = rep(NA_character_, nrow(rejected)),
    action = rep(NA_character_, nrow(rejected)), missing_count = rep(NA_integer_, nrow(rejected)), row_number = rejected$row_number,
    cell_id = rejected$cell_id, reason = rejected$reason, stringsAsFactors = FALSE
  )
  table <- rbind(field_rows, rejected_rows)
  limitation <- paste(
    "Values are externally supplied. scworkbench verified the imported file, alignment,",
    "field identities, and downstream filtering; upstream metadata derivation was not engine-observed."
  )
  wb_prim_obs_table(
    table, table_type = "cell_metadata_import_evidence", entity_kind = "metadata_import",
    meta = list(
      schema = "scworkbench.metadata_import.evidence.v1",
      source_identity = plan$source$source_identity,
      checksum_status = "verified_sha256", source_sha256 = plan$source$actual_sha256,
      parser = plan$parser$format, delimiter = plan$parser$delimiter,
      cell_id_col = plan$cell_id_col, selected_fields = as.list(plan$selected_fields),
      unknown_cell_policy = plan$unknown_cell_policy, counts = plan$counts,
      rejected_evidence = list(total = plan$counts$rejected, retained = nrow(rejected), limit = 100L),
      description = description, assurance = list(
        values = "externally_supplied", upstream_derivation = "not_engine_observed",
        limitation = limitation
      )
    )
  )
}

#' Import a checksummed cell-metadata table
#'
#' Imports selected columns from a CSV or TSV into the existing canonical cell
#' metadata registry and scalable set-based writer. The source file is verified
#' against an explicit immutable SHA-256 declaration before mutation.
#'
#' scworkbench preserves lineage from declared bundle inputs onward. It verifies
#' the imported metadata file, alignment, field identities, and downstream
#' filtering, but does not claim to have executed the external process that
#' produced the metadata values.
#'
#' @param bundle Open writable bundle.
#' @param input Existing `.csv`, `.tsv`, or `.tab` file.
#' @param cell_id_col Exact source column containing bundle cell IDs.
#' @param source_identity One strict file declaration from [wb_source_input()]
#'   or a full declaration accepted by [wb_source_preflight()].
#' @param fields Optional ordered character vector of non-ID columns. `NULL`
#'   selects all non-ID columns.
#' @param field_refs Optional position-aligned stable field references. Use these
#'   to declare compatible updates unambiguously.
#' @param unknown_cell_policy Reject unknown imported IDs by default. Explicit
#'   `"warn_drop"` retains bounded rejected-row evidence and emits a warning.
#' @param validate_only Return the complete parse/alignment/field plan without
#'   acquiring a writer lock or changing bundle, SQLite, WAL, or filesystem state.
#' @param created_by Optional importing actor.
#' @param description Optional evidence description.
#' @return A metadata-import plan when `validate_only=TRUE`; otherwise a durable
#'   result containing field rows, provenance/run IDs, report artifact ID, and counts.
#' @export
wb_metadata_import <- function(bundle, input, cell_id_col, source_identity,
                               fields = NULL, field_refs = NULL,
                               unknown_cell_policy = c("error", "warn_drop"),
                               validate_only = FALSE, created_by = NULL,
                               description = NULL) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert_bundle_writable(bundle, "cell metadata import")
  unknown_cell_policy <- match.arg(unknown_cell_policy)
  plan <- .wb_metadata_import_plan(
    bundle, input, cell_id_col, source_identity, fields, field_refs,
    unknown_cell_policy
  )
  public_plan <- plan
  public_plan$input <- basename(plan$input)
  public_plan$payload <- NULL
  public_plan$field_refs <- NULL
  public_plan$source <- plan$source$source_identity
  class(public_plan) <- c("wb_metadata_import_plan", "list")
  if (isTRUE(validate_only)) return(public_plan)
  if (length(plan$rejected$row_number)) warning(
    "METADATA_IMPORT_UNKNOWN_CELLS_DROPPED: ", nrow(plan$rejected),
    " unknown imported rows were rejected and recorded.", call. = FALSE
  )

  result <- .wb_with_mutation_context(bundle = bundle, route = "ingestion", code = {
    .wb_with_bundle_writer_lock(bundle, operation = "cell metadata import", code = {
      # Re-preflight under the lock so checksum, alignment, and update intent
      # cannot become stale between planning and publication.
      locked <- .wb_metadata_import_plan(
        bundle, input, cell_id_col, source_identity, fields, field_refs,
        unknown_cell_policy
      )
      .wb_metadata_import_fault("after_staging", plan = public_plan)
      out <- DBI::dbWithTransaction(bundle$con, {
        report <- .wb_write_cell_metadata(
          bundle$con, locked$payload,
          target_cell_ids = as.character(locked$payload[[1L]]),
          source = paste0("metadata_import:", locked$source$source_id),
          created_by = created_by, field_refs = locked$field_refs
        )
        actual_fields <- report$fields
        ordered <- match(locked$fields$field_id, actual_fields$field_id)
        .wb_assert(!anyNA(ordered), "METADATA_IMPORT_FIELD_PLAN_DRIFT: writer result differs from the accepted plan.")
        evidence <- .wb_metadata_import_report(locked, description)
        run <- wb_new_run(
          op_name = "metadata_import",
          inputs = list(
            cell_set = "all", parents = character(), provenance_refs = list(),
            user_inputs = list(
              source_id = locked$source$source_id,
              cell_id_col = locked$cell_id_col,
              fields = as.list(locked$selected_fields),
              unknown_cell_policy = locked$unknown_cell_policy
            )
          ),
          params = list(
            parser = locked$parser$format, delimiter = locked$parser$delimiter,
            counts = locked$counts,
            assurance = list(values = "externally_supplied", upstream_derivation = "not_engine_observed")
          ),
          outputs = list(import_evidence = evidence),
          notes = description %||% "Checksummed external cell-metadata import"
        )
        artifact_id <- .wb_promote_obs_table(
          bundle, run, "import_evidence", evidence,
          name = paste0("metadata_import__", locked$source$source_id),
          description = description %||% "Checksummed external cell-metadata import evidence",
          created_by = created_by
        )
        .wb_metadata_import_fault("before_provenance_publication", run_id = run$run_id)
        snapshot_id <- .wb_prov_record_ingestion(
          bundle, run, artifact_id = artifact_id, matrix_ids = character(),
          created_by = created_by, transaction_open = TRUE,
          source_identity = locked$source$source_identity
        )
        commit_id <- DBI::dbGetQuery(
          bundle$con, "SELECT commit_id FROM prov_heads WHERE snapshot_id=?;",
          params = list(snapshot_id)
        )$commit_id[[1L]]
        for (i in seq_len(nrow(locked$fields))) .wb_prov_insert_entity_binding(
          bundle$con, snapshot_id, commit_id, run$run_id,
          "output", paste0("metadata_field.", i), "metadata_field",
          locked$fields$field_id[[i]], "PRODUCES", source = "metadata_import"
        )
        .wb_metadata_import_fault("before_commit", run_id = run$run_id)
        list(
          schema = "scworkbench.metadata_import.result.v1", imported = TRUE,
          run_id = run$run_id, snapshot_id = snapshot_id,
          report_artifact_id = artifact_id, source_id = locked$source$source_id,
          source_sha256 = locked$source$actual_sha256,
          counts = locked$counts, fields = locked$fields,
          assurance = list(values = "externally_supplied", upstream_derivation = "not_engine_observed")
        )
      })
      .wb_refresh_manifest_committed(bundle)
      out
    })
  })
  class(result) <- c("wb_metadata_import_result", "list")
  result
}
