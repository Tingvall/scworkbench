# Read-only reporting contracts for thin clients (Shiny, agents, notebooks).

.wb_empty_df <- function(cols) {
  out <- as.data.frame(stats::setNames(rep(list(character(0)), length(cols)), cols), stringsAsFactors = FALSE)
  rownames(out) <- NULL
  out
}

.wb_json_compact <- function(x) {
  if (is.null(x)) return(NA_character_)
  out <- try(jsonlite::toJSON(.wb_json_sanitize(x), auto_unbox = TRUE, null = "null"), silent = TRUE)
  if (inherits(out, "try-error")) return(NA_character_)
  as.character(out)
}

.wb_collapse_chr <- function(x) {
  x <- unique(as.character(x %||% character(0)))
  x <- x[!is.na(x) & nzchar(x)]
  if (!length(x)) return(NA_character_)
  paste(x, collapse = ";")
}

.wb_count_table <- function(x, name_col = "key") {
  x <- as.character(x %||% character(0))
  x <- x[!is.na(x) & nzchar(x)]
  if (!length(x)) {
    return(data.frame(
      stringsAsFactors = FALSE
    )[0, , drop = FALSE])
  }
  tab <- sort(table(x), decreasing = TRUE)
  out <- data.frame(
    key = as.character(names(tab)),
    n = as.integer(tab),
    stringsAsFactors = FALSE
  )
  stats::setNames(out, c(name_col, "n"))
}

.wb_safe_df <- function(expr, cols = character(0)) {
  out <- try(expr, silent = TRUE)
  if (inherits(out, "try-error") || is.null(out)) return(.wb_empty_df(cols))
  if (is.vector(out) && !is.list(out)) return(data.frame(value = as.character(out), stringsAsFactors = FALSE))
  if (is.data.frame(out)) return(out)
  .wb_empty_df(cols)
}

#' Inspect cell metadata columns
#'
#' Returns a stable column inventory for `cells` metadata so clients do not need
#' direct SQLite `PRAGMA` calls.
#'
#' @param bundle Open scworkbench bundle.
#' @param summarize If `TRUE`, compute missingness and distinct counts.
#' @param max_distinct_for_grouping Columns with distinct count at or below this
#'   value are marked useful for grouping.
#' @return Data frame with one row per metadata column.
#' @export
wb_cell_metadata_columns <- function(bundle,
                                     summarize = TRUE,
                                     max_distinct_for_grouping = 100L) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  con <- bundle$con
  .wb_assert(.wb_db_has_table(con, "cells"), "cells table missing.")

  fields <- wb_metadata_fields(bundle, include_core = TRUE)
  if (!nrow(fields)) {
    return(data.frame(
      column_name = character(0),
      storage_type = character(0),
      display_label = character(0),
      r_class = character(0),
      n_missing = integer(0),
      n_distinct = integer(0),
      missing_fraction = numeric(0),
      useful_for_coloring = logical(0),
      useful_for_grouping = logical(0),
      stringsAsFactors = FALSE
    ))
  }

  n_rows <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM cells;")$n[[1]] %||% 0L
  n_rows <- as.integer(n_rows)

  out <- lapply(seq_len(nrow(fields)), function(i) {
    nm <- as.character(fields$storage_name[[i]])
    storage_type <- as.character(fields$storage_type[[i]] %||% "")
    quoted <- .wb_quote_identifier(con, nm)

    n_missing <- NA_integer_
    n_distinct <- NA_integer_
    if (isTRUE(summarize)) {
      n_missing <- DBI::dbGetQuery(con, paste0(
        "SELECT SUM(CASE WHEN ", quoted, " IS NULL OR ", quoted, " = '' THEN 1 ELSE 0 END) AS n FROM cells;"
      ))$n[[1]] %||% 0L
      n_distinct <- DBI::dbGetQuery(con, paste0(
        "SELECT COUNT(DISTINCT ", quoted, ") AS n FROM cells WHERE ", quoted, " IS NOT NULL AND ", quoted, " <> '';"
      ))$n[[1]] %||% 0L
      n_missing <- as.integer(n_missing)
      n_distinct <- as.integer(n_distinct)
    }

    storage_upper <- toupper(storage_type)
    r_class <- if (grepl("INT", storage_upper)) {
      "integer"
    } else if (grepl("REAL|FLOA|DOUB|NUM", storage_upper)) {
      "numeric"
    } else {
      "character"
    }
    useful_for_coloring <- !isTRUE(fields$is_core[[i]] == 1L && identical(nm, "cell_id"))
    useful_for_grouping <- isTRUE(useful_for_coloring) &&
      isTRUE(is.finite(n_distinct)) &&
      n_distinct > 0L &&
      n_distinct <= as.integer(max_distinct_for_grouping)

    data.frame(
      column_name = as.character(fields$display_name[[i]]),
      field_id = as.character(fields$field_id[[i]]),
      source_name = as.character(fields$source_name[[i]]),
      display_name = as.character(fields$display_name[[i]]),
      storage_name = nm,
      source_position = as.integer(fields$source_position[[i]]),
      storage_type = storage_type,
      source_type = as.character(fields$source_type[[i]]),
      coercion_type = as.character(fields$coercion_type[[i]]),
      collision_status = as.character(fields$collision_status[[i]]),
      resolution = as.character(fields$resolution[[i]]),
      is_core = as.logical(fields$is_core[[i]]),
      import_id = as.character(fields$import_id[[i]]),
      import_source = as.character(fields$import_source[[i]]),
      created_by = as.character(fields$created_by[[i]]),
      evidence_json = as.character(fields$evidence_json[[i]]),
      display_label = as.character(fields$display_name[[i]]),
      r_class = r_class,
      n_missing = n_missing,
      n_distinct = n_distinct,
      missing_fraction = if (isTRUE(summarize) && n_rows > 0L) n_missing / n_rows else NA_real_,
      useful_for_coloring = useful_for_coloring,
      useful_for_grouping = useful_for_grouping,
      stringsAsFactors = FALSE
    )
  })

  out <- do.call(rbind, out)
  rownames(out) <- NULL
  out
}

#' Bundle overview for read-only clients
#'
#' Summarizes bundle identity, validation state, registries, artifact counts,
#' and provenance heads without requiring clients to know SQLite internals.
#'
#' @param bundle Open scworkbench bundle.
#' @param validate If `TRUE`, run `wb_validate_bundle()` and report status.
#'   Defaults to `FALSE` because full validation may open large matrices.
#' @return Named list of overview tables and status fields.
#' @export
wb_bundle_overview <- function(bundle, validate = FALSE) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  con <- bundle$con
  .wb_assert(!is.null(con), "bundle$con is NULL.")

  manifest <- tryCatch(wb_manifest(bundle), error = function(e) list(error = conditionMessage(e)))
  validation <- list(checked = isTRUE(validate), ok = NA, warnings = character(0), error = NA_character_)
  if (isTRUE(validate)) {
    validation <- tryCatch(
      {
        ok <- isTRUE(wb_validate_bundle(bundle$dir))
        list(checked = TRUE, ok = ok, warnings = character(0), error = NA_character_)
      },
      error = function(e) list(checked = TRUE, ok = FALSE, warnings = character(0), error = conditionMessage(e))
    )
  }

  matrices <- .wb_safe_df(wb_matrices(bundle))
  spaces <- .wb_safe_df(wb_spaces(bundle))
  cell_sets_vec <- tryCatch(wb_cell_sets(bundle), error = function(e) character(0))
  cell_sets <- if (length(cell_sets_vec)) {
    data.frame(
      cell_set = as.character(cell_sets_vec),
      n_cells = vapply(cell_sets_vec, function(cs) length(tryCatch(wb_cells(bundle, cell_set = cs), error = function(e) character(0))), integer(1)),
      stringsAsFactors = FALSE
    )
  } else {
    data.frame(cell_set = character(0), n_cells = integer(0), stringsAsFactors = FALSE)
  }
  feature_sets <- .wb_safe_df(wb_feature_sets(bundle))
  artifacts <- .wb_safe_df(wb_art_list(bundle))
  provenance_heads <- .wb_safe_df(wb_prov_list_heads(bundle))

  artifact_counts_by_type <- if (nrow(artifacts) && "type" %in% names(artifacts)) .wb_count_table(artifacts$type, "type") else data.frame(type = character(0), n = integer(0), stringsAsFactors = FALSE)
  artifact_counts_by_source_op <- if (nrow(artifacts) && "source_op" %in% names(artifacts)) .wb_count_table(artifacts$source_op, "source_op") else data.frame(source_op = character(0), n = integer(0), stringsAsFactors = FALSE)
  feature_set_summary <- if (nrow(feature_sets)) {
    stats::aggregate(
      list(n_feature_sets = rep(1L, nrow(feature_sets)), n_features_total = as.integer(feature_sets$n_features %||% 0L)),
      by = list(
        matrix_id = as.character(feature_sets$matrix_id %||% NA_character_),
        namespace = as.character(feature_sets$namespace %||% NA_character_)
      ),
      FUN = sum,
      na.rm = TRUE
    )
  } else {
    data.frame(matrix_id = character(0), namespace = character(0), n_feature_sets = integer(0), n_features_total = integer(0), stringsAsFactors = FALSE)
  }

  list(
    schema = "bundle_overview_v1",
    bundle = list(
      path = normalizePath(bundle$dir, winslash = "/", mustWork = FALSE),
      bundle_id = as.character(manifest$bundle_id %||% bundle$manifest$bundle_id %||% NA_character_)[1],
      bundle_name = as.character(manifest$bundle_name %||% bundle$manifest$bundle_name %||% NA_character_)[1],
      manifest_version = as.character(manifest$scworkbench_manifest_version %||% manifest$manifest_version %||% NA_character_)[1]
    ),
    manifest = manifest,
    validation = validation,
    counts = list(
      n_cells = if (.wb_db_has_table(con, "cells")) as.integer(DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM cells;")$n[[1]]) else NA_integer_,
      n_matrices = nrow(matrices),
      feature_registry_records = as.integer(manifest$counts$feature_registry_records %||% NA_integer_)[1],
      feature_counts_by_matrix = manifest$counts$feature_counts_by_matrix %||% list(),
      bundle_unique_feature_count = manifest$counts$bundle_unique_feature_count %||% list(),
      n_spaces = nrow(spaces),
      n_cell_sets = nrow(cell_sets),
      n_feature_sets = nrow(feature_sets),
      n_artifacts = nrow(artifacts),
      n_provenance_heads = nrow(provenance_heads)
    ),
    matrices = matrices,
    spaces = spaces,
    cell_sets = cell_sets,
    feature_set_summary = feature_set_summary,
    artifact_counts_by_type = artifact_counts_by_type,
    artifact_counts_by_source_op = artifact_counts_by_source_op,
    provenance_heads = provenance_heads,
    warnings = character(0)
  )
}

#' List trajectory model artifacts
#'
#' Returns promoted `model_ref` artifacts with trajectory-relevant metadata and,
#' when requested, lineage/pseudotime coverage derived by loading the model.
#'
#' @param bundle Open scworkbench bundle.
#' @param inspect_payload If `TRUE`, load each model and summarize lineage
#'   pseudotime coverage. Failures are recorded in `warnings`.
#' @return Data frame, one row per model_ref artifact.
#' @export
wb_list_trajectory_models <- function(bundle, inspect_payload = TRUE) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  con <- bundle$con
  wb_migrate_artifacts(bundle)

  if (!.wb_db_has_table(con, "artifact_model_ref")) {
    return(.wb_empty_df(c(
      "artifact_id", "name", "model_type", "engine", "source_op", "cell_set", "input_matrix_id",
      "input_space_id", "model_space_id", "in_space_id", "fitted_cell_count", "n_lineages",
      "lineage_ids", "finite_pseudotime_cells", "pseudotime_min", "pseudotime_max",
      "root_label", "end_label", "run_id", "snapshot_id", "lineage_status", "warnings"
    )))
  }

  rows <- DBI::dbGetQuery(con, "
    SELECT a.artifact_id, a.name, a.type, a.source_op, a.input_space_id, a.input_matrix_id,
           a.cell_set, a.provenance_snapshot_id, a.lineage_status, a.provenance_json,
           m.engine, m.model_space_id, m.in_space_id, m.model_type, m.model_path
    FROM artifacts a
    JOIN artifact_model_ref m ON m.artifact_id = a.artifact_id
    WHERE a.type = 'model_ref'
    ORDER BY a.created_at DESC, a.artifact_id;
  ")
  if (!nrow(rows)) {
    return(.wb_empty_df(c(
      "artifact_id", "name", "model_type", "engine", "source_op", "cell_set", "input_matrix_id",
      "input_space_id", "model_space_id", "in_space_id", "fitted_cell_count", "n_lineages",
      "lineage_ids", "finite_pseudotime_cells", "pseudotime_min", "pseudotime_max",
      "root_label", "end_label", "run_id", "snapshot_id", "lineage_status", "warnings"
    )))
  }

  out <- lapply(seq_len(nrow(rows)), function(i) {
    r <- rows[i, , drop = FALSE]
    prov <- .wb_art_parse_provenance_json(r$provenance_json[[1]] %||% "")
    params <- prov$params %||% list()
    exec <- prov$inputs$execution_inputs %||% list()
    fitted_cell_count <- suppressWarnings(as.integer(
      params$cells_fit %||% params$n_cells_fit %||% exec$effective_n %||% NA_integer_
    ))
    n_lineages <- suppressWarnings(as.integer(params$n_lineages %||% NA_integer_))
    lineage_ids <- NA_character_
    finite_cells <- NA_integer_
    pt_min <- NA_real_
    pt_max <- NA_real_
    warnings <- character(0)

    if (isTRUE(inspect_payload)) {
      loaded <- tryCatch(wb_art_load(bundle, as.character(r$artifact_id[[1]]), expected_kind = "model_ref"), error = function(e) e)
      if (inherits(loaded, "error")) {
        warnings <- c(warnings, conditionMessage(loaded))
      } else {
        lin <- tryCatch(.wb_trajectory_smooth_resolve_lineages(model = loaded, lineage = NULL, cells = NULL), error = function(e) e)
        if (inherits(lin, "error")) {
          warnings <- c(warnings, conditionMessage(lin))
        } else {
          lineage_ids <- .wb_collapse_chr(names(lin))
          n_lineages <- length(lin)
          finite_by_lin <- vapply(lin, function(d) sum(is.finite(suppressWarnings(as.numeric(d$pseudotime)))), integer(1))
          finite_cells <- as.integer(sum(finite_by_lin))
          pts <- unlist(lapply(lin, function(d) suppressWarnings(as.numeric(d$pseudotime))), use.names = FALSE)
          pts <- pts[is.finite(pts)]
          if (length(pts)) {
            pt_min <- min(pts)
            pt_max <- max(pts)
          }
        }
      }
    }

    data.frame(
      artifact_id = as.character(r$artifact_id[[1]]),
      name = as.character(r$name[[1]] %||% NA_character_),
      model_type = as.character(r$model_type[[1]] %||% NA_character_),
      engine = as.character(r$engine[[1]] %||% NA_character_),
      source_op = as.character(r$source_op[[1]] %||% NA_character_),
      cell_set = as.character(r$cell_set[[1]] %||% NA_character_),
      input_matrix_id = as.character(r$input_matrix_id[[1]] %||% NA_character_),
      input_space_id = as.character(r$input_space_id[[1]] %||% NA_character_),
      model_space_id = as.character(r$model_space_id[[1]] %||% NA_character_),
      in_space_id = as.character(r$in_space_id[[1]] %||% NA_character_),
      fitted_cell_count = fitted_cell_count,
      n_lineages = n_lineages,
      lineage_ids = lineage_ids,
      finite_pseudotime_cells = finite_cells,
      pseudotime_min = pt_min,
      pseudotime_max = pt_max,
      root_label = as.character(params$start_label %||% params$root_label %||% NA_character_)[1],
      end_label = as.character(params$end_label %||% NA_character_)[1],
      run_id = as.character(prov$run_id %||% NA_character_)[1],
      snapshot_id = as.character(r$provenance_snapshot_id[[1]] %||% NA_character_),
      lineage_status = as.character(r$lineage_status[[1]] %||% NA_character_),
      warnings = .wb_collapse_chr(warnings),
      stringsAsFactors = FALSE
    )
  })

  out <- do.call(rbind, out)
  rownames(out) <- NULL
  out
}

#' Flatten persisted provenance run history
#'
#' Returns a chronological table of persisted runs. Complex inputs/params remain
#' compact JSON strings; use `wb_prov_run_details()` for exact nested payloads.
#'
#' @param bundle Open scworkbench bundle.
#' @param snapshot_id Optional snapshot id. If `NULL`, all snapshots are used.
#' @return Data frame with one row per persisted run per snapshot.
#' @export
wb_run_history <- function(bundle, snapshot_id = NULL) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  con <- bundle$con
  .wb_migrate_provenance_tables(con)

  base_cols <- c(
    "snapshot_id", "run_id", "op_name", "created_at", "notes", "params_json", "inputs_json",
    "symbolic_inputs_json", "execution_inputs_json", "output_names", "output_kinds",
    "promoted_artifact_ids", "parent_count", "child_count", "lineage_statuses",
    "warnings", "errors"
  )

  where <- ""
  params <- list()
  if (!is.null(snapshot_id)) {
    where <- " WHERE snapshot_id = ?"
    params <- list(as.character(snapshot_id)[1])
  }
  run_query <- paste0(
    "SELECT snapshot_id, run_id, op_name, created_at, notes, params_json, inputs_json, ",
    if (.wb_db_has_column(con, "prov_runs", "symbolic_inputs_json")) "symbolic_inputs_json" else "NULL AS symbolic_inputs_json",
    ", ",
    if (.wb_db_has_column(con, "prov_runs", "execution_inputs_json")) "execution_inputs_json" else "NULL AS execution_inputs_json",
    " FROM prov_runs", where, " ORDER BY created_at, snapshot_id, run_id;"
  )
  runs <- if (length(params)) {
    DBI::dbGetQuery(con, run_query, params = params)
  } else {
    DBI::dbGetQuery(con, run_query)
  }
  if (!nrow(runs)) return(.wb_empty_df(base_cols))

  out <- lapply(seq_len(nrow(runs)), function(i) {
    sid <- as.character(runs$snapshot_id[[i]])
    rid <- as.character(runs$run_id[[i]])
    outs <- DBI::dbGetQuery(
      con,
      "SELECT output_name, primitive_kind, artifact_id
       FROM prov_run_outputs
       WHERE snapshot_id = ? AND run_id = ?
       ORDER BY output_name;",
      params = list(sid, rid)
    )
    parents <- DBI::dbGetQuery(
      con,
      "SELECT COUNT(DISTINCT parent_run_id) AS n
       FROM prov_run_edges
       WHERE snapshot_id = ? AND child_run_id = ?;",
      params = list(sid, rid)
    )$n[[1]] %||% 0L
    children <- DBI::dbGetQuery(
      con,
      "SELECT COUNT(DISTINCT child_run_id) AS n
       FROM prov_run_edges
       WHERE snapshot_id = ? AND parent_run_id = ?;",
      params = list(sid, rid)
    )$n[[1]] %||% 0L
    art_ids <- unique(as.character(outs$artifact_id %||% character(0)))
    art_ids <- art_ids[!is.na(art_ids) & nzchar(art_ids)]
    statuses <- character(0)
    if (length(art_ids) && .wb_db_has_table(con, "artifacts")) {
      q <- paste0("SELECT lineage_status FROM artifacts WHERE artifact_id IN (", paste(rep("?", length(art_ids)), collapse = ","), ");")
      statuses <- DBI::dbGetQuery(con, q, params = as.list(art_ids))$lineage_status
    }
    data.frame(
      snapshot_id = sid,
      run_id = rid,
      op_name = as.character(runs$op_name[[i]] %||% NA_character_),
      created_at = as.character(runs$created_at[[i]] %||% NA_character_),
      notes = as.character(runs$notes[[i]] %||% NA_character_),
      params_json = as.character(runs$params_json[[i]] %||% NA_character_),
      inputs_json = as.character(runs$inputs_json[[i]] %||% NA_character_),
      symbolic_inputs_json = as.character(runs$symbolic_inputs_json[[i]] %||% NA_character_),
      execution_inputs_json = as.character(runs$execution_inputs_json[[i]] %||% NA_character_),
      output_names = .wb_collapse_chr(outs$output_name),
      output_kinds = .wb_collapse_chr(outs$primitive_kind),
      promoted_artifact_ids = .wb_collapse_chr(art_ids),
      parent_count = as.integer(parents),
      child_count = as.integer(children),
      lineage_statuses = .wb_collapse_chr(statuses),
      warnings = NA_character_,
      errors = NA_character_,
      stringsAsFactors = FALSE
    )
  })

  out <- do.call(rbind, out)
  rownames(out) <- NULL
  out <- out[, base_cols, drop = FALSE]
  out
}
