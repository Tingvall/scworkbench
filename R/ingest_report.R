# Ingest report artifact accessors

#' List ingest report artifacts
#'
#' Returns artifact metadata for ingest reports emitted by `wb_ingest_apply(..., emit_report_artifact=TRUE)`.
#'
#' @param bundle scworkbench bundle
#' @param set_name Optional set name filter (matches report `set_name` or `cell_set` suffix)
#' @param limit Optional max number of rows
#' @return data.frame of ingest report artifact metadata
#' @export
wb_ingest_reports <- function(bundle, set_name = NULL, limit = NULL) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  con <- bundle$con
  wb_migrate_artifacts(bundle)

  q <- paste(
    "SELECT a.artifact_id, a.name, a.description, a.created_at, a.created_by,",
    "a.source_op, a.cell_set, t.table_type, t.entity_kind, t.meta_json",
    "FROM artifacts a",
    "JOIN artifact_tables t ON t.artifact_id = a.artifact_id",
    "WHERE a.type = 'obs_table' AND t.table_type = 'ingest_report'"
  )
  params <- list()

  if (!is.null(set_name) && nzchar(as.character(set_name)[1])) {
    sn <- as.character(set_name)[1]
    q <- paste0(
      q,
      " AND (a.cell_set = ? OR a.cell_set = ? OR a.name LIKE ?)"
    )
    params <- c(params, list(sn, paste0("set:", sn), paste0("%", sn, "%")))
  }

  q <- paste0(q, " ORDER BY a.created_at DESC")
  if (!is.null(limit)) {
    lim <- as.integer(limit)[1]
    if (!is.na(lim) && lim > 0L) {
      q <- paste0(q, " LIMIT ", lim)
    }
  }

  out <- if (length(params)) DBI::dbGetQuery(con, q, params = params) else DBI::dbGetQuery(con, q)
  if (!is.data.frame(out)) {
    out <- data.frame(
      artifact_id = character(0),
      name = character(0),
      description = character(0),
      created_at = character(0),
      created_by = character(0),
      source_op = character(0),
      cell_set = character(0),
      table_type = character(0),
      entity_kind = character(0),
      meta_json = character(0),
      stringsAsFactors = FALSE
    )
  }
  out
}

#' Load one ingest report artifact
#'
#' @param bundle scworkbench bundle
#' @param artifact_id ingest report artifact id
#' @param parse_json If TRUE, parse JSON payload columns in the report row
#' @return list(metadata, table)
#' @export
wb_ingest_report <- function(bundle, artifact_id, parse_json = TRUE) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  aid <- as.character(artifact_id)[1]
  .wb_assert(nzchar(aid), "artifact_id must be non-empty")

  meta <- wb_ingest_reports(bundle)
  meta <- meta[as.character(meta$artifact_id) == aid, , drop = FALSE]
  .wb_assert(nrow(meta) == 1, paste0("Ingest report artifact not found: ", aid))

  prim <- wb_art_load(bundle, artifact_id = aid, expected_kind = "obs_table")
  .wb_assert(identical(as.character(prim$table_type %||% "")[1], "ingest_report"),
             paste0("Artifact is not ingest_report: ", aid))

  tbl <- prim$table
  if (isTRUE(parse_json) && is.data.frame(tbl) && nrow(tbl) >= 1 && requireNamespace("jsonlite", quietly = TRUE)) {
    parse_col <- function(col) {
      lapply(as.character(col %||% ""), function(x) {
        if (!nzchar(x)) return(NULL)
        tryCatch(jsonlite::fromJSON(x, simplifyVector = FALSE), error = function(e) NULL)
      })
    }
    if ("errors_json" %in% names(tbl)) tbl$errors <- parse_col(tbl$errors_json)
    if ("warnings_json" %in% names(tbl)) tbl$warnings <- parse_col(tbl$warnings_json)
    if ("validation_json" %in% names(tbl)) tbl$validation <- parse_col(tbl$validation_json)
    if ("normalization_json" %in% names(tbl)) tbl$normalization <- parse_col(tbl$normalization_json)
    if ("result_json" %in% names(tbl)) tbl$result <- parse_col(tbl$result_json)
  }

  list(metadata = meta, table = tbl)
}
