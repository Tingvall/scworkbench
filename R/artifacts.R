#' List Promoted Artifacts
#'
#' Return artifact registry rows from the bundle, optionally restricted to a
#' single promoted artifact type.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param type Optional artifact type filter such as `"feature_table"` or
#'   `"obs_table"`.
#' @param include_history If `FALSE`, omit ephemeral, superseded, rejected, and retracted
#'   artifacts. Historical evidence remains loadable by id.
#'
#' @return A data frame of artifact registry rows ordered by `created_at`
#'   descending.
#'
# pybench-parity: yes
# pybench-counterpart: pybench.getters.art_list
# contract-note: artifact registry rows ordered by created_at DESC
#' @export
wb_art_list <- function(bundle, type = NULL, include_history = FALSE) {
  con <- bundle$con
  if (!isTRUE(bundle$read_only)) .wb_entity_lifecycle_migrate(bundle)
  has_lifecycle <- .wb_table_exists(con, "entity_lifecycle")
  select <- if (has_lifecycle) {
    "SELECT a.*, COALESCE(el.lifecycle_state, 'current') AS lifecycle_state, COALESCE(el.provenance_bound, 0) AS provenance_bound FROM artifacts a LEFT JOIN entity_lifecycle el ON el.entity_kind = 'artifact' AND el.entity_id = a.artifact_id"
  } else "SELECT a.*, 'current' AS lifecycle_state, 0 AS provenance_bound FROM artifacts a"
  where <- character(0); params <- list()
  if (!is.null(type)) { where <- c(where, "a.type = ?"); params <- c(params, list(type)) }
  if (!isTRUE(include_history) && has_lifecycle) where <- c(where, "COALESCE(el.lifecycle_state, 'current') = 'current'")
  sql <- paste0(select, if (length(where)) paste0(" WHERE ", paste(where, collapse = " AND ")) else "", " ORDER BY a.created_at DESC;")
  if (length(params)) DBI::dbGetQuery(con, sql, params = params) else DBI::dbGetQuery(con, sql)
}

.wb_art_table_json_path <- function(column) {
  col <- as.character(column %||% "")[1]
  .wb_assert(grepl("^[A-Za-z][A-Za-z0-9_]*$", col),
             paste0("Invalid JSON column for artifact table query: ", col))
  paste0("$.", col)
}

.wb_art_table_filters_sql <- function(filters) {
  ff <- filters %||% list()
  if (!is.list(ff) || !length(ff)) {
    return(list(sql = character(0), params = list()))
  }

  clauses <- character(0)
  params <- list()
  for (nm in names(ff)) {
    vals <- ff[[nm]]
    if (is.null(vals)) next
    vals <- as.vector(vals)
    vals <- vals[!is.na(vals)]
    if (!length(vals)) next
    qmarks <- paste(rep("?", length(vals)), collapse = ", ")
    clauses <- c(
      clauses,
      paste0("json_extract(row_json, '", .wb_art_table_json_path(nm), "') IN (", qmarks, ")")
    )
    params <- c(params, as.list(vals))
  }
  list(sql = clauses, params = params)
}

.wb_art_table_rows_to_df <- function(rows) {
  if (!is.data.frame(rows) || !nrow(rows)) {
    return(data.frame(stringsAsFactors = FALSE))
  }
  rr <- lapply(rows$row_json, jsonlite::fromJSON, simplifyVector = FALSE)
  rr <- lapply(rr, function(x) {
    if (is.list(x) && length(x)) {
      is_null <- vapply(x, is.null, logical(1))
      if (any(is_null)) {
        for (nm in names(x)[is_null]) x[[nm]] <- NA
      }
    }
    x
  })
  rr <- lapply(rr, as.data.frame, stringsAsFactors = FALSE)
  out <- do.call(rbind, rr)
  rownames(out) <- NULL
  out
}

.wb_art_parse_provenance_json <- function(x) {
  txt <- as.character(x %||% "")[1]
  if (!nzchar(txt)) return(list())
  out <- try(jsonlite::fromJSON(txt, simplifyVector = TRUE), silent = TRUE)
  if (inherits(out, "try-error") || !is.list(out)) return(list())
  out
}

.wb_art_trajectory_model_signature <- function(info_row, prov = NULL) {
  prov <- prov %||% .wb_art_parse_provenance_json(info_row$provenance_json[1] %||% "")
  cand <- c(
    as.character(prov$inputs$user_inputs$model$model_path %||% "")[1],
    as.character(prov$inputs$execution_inputs$resolved$model$model_path %||% "")[1],
    as.character(prov$inputs$symbolic_inputs$model$model_path %||% "")[1]
  )
  cand <- cand[nzchar(cand)]
  if (length(cand)) return(cand[1])
  paste(
    as.character(prov$params$model_engine %||% prov$inputs$execution_inputs$resolved$model$engine %||% "")[1],
    as.character(prov$inputs$execution_inputs$resolved$model$model_space_id %||% "")[1],
    as.character(prov$inputs$execution_inputs$resolved$model$in_space_id %||% "")[1],
    sep = "::"
  )
}

.wb_art_trajectory_model_fields <- function(info_row, prov = NULL) {
  prov <- prov %||% .wb_art_parse_provenance_json(info_row$provenance_json[1] %||% "")
  resolved <- prov$inputs$execution_inputs$resolved$model %||% list()
  user_model <- prov$inputs$user_inputs$model %||% list()
  list(
    engine = as.character(resolved$engine %||% prov$params$model_engine %||% user_model$engine %||% "")[1],
    model_space_id = as.character(resolved$model_space_id %||% user_model$model_space_id %||% "")[1],
    in_space_id = as.character(resolved$in_space_id %||% user_model$in_space_id %||% "")[1],
    model_path = as.character(resolved$model_path %||% user_model$model_path %||% "")[1],
    feature_set = as.character(prov$params$feature_set %||% prov$inputs$symbolic_inputs$feature_set %||% "")[1]
  )
}

#' Read Table Artifact Metadata
#'
#' Fetch registry and table-contract metadata for a promoted table artifact.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param artifact_id Artifact id for a promoted `feature_table` or `obs_table`.
#'
#' @return A one-row data frame including artifact registry fields plus
#'   `table_type`, `entity_kind`, and `meta_json`.
#'
#' @export
wb_art_table_info <- function(bundle, artifact_id) {
  con <- bundle$con
  aid <- as.character(artifact_id %||% "")[1]
  .wb_assert(nzchar(aid), "artifact_id must be non-empty")

  info <- DBI::dbGetQuery(
    con,
    "SELECT a.*, t.table_type, t.entity_kind, t.meta_json
     FROM artifacts a
     JOIN artifact_tables t ON t.artifact_id = a.artifact_id
     WHERE a.artifact_id = ?;",
    params = list(aid)
  )
  .wb_assert(nrow(info) == 1L, paste0("Table artifact not found: ", aid))
  info
}

#' List Distinct Values From A Table Artifact Column
#'
#' Query distinct values for one JSON-backed table column without loading the
#' full artifact payload.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param artifact_id Artifact id for a promoted `feature_table` or `obs_table`.
#' @param column Column name to extract from `row_json`.
#' @param filters Optional named list of equality filters applied before taking
#'   distinct values.
#' @param limit Optional limit on the number of returned values.
#'
#' @return Character vector of distinct non-empty values.
#'
#' @export
wb_art_table_distinct <- function(bundle, artifact_id, column, filters = NULL, limit = NULL) {
  info <- wb_art_table_info(bundle, artifact_id)
  .wb_assert(as.character(info$type[1] %||% "")[1] %in% c("obs_table", "feature_table"),
             "wb_art_table_distinct() supports obs_table and feature_table artifacts.")

  aid <- as.character(artifact_id)[1]
  lim <- suppressWarnings(as.integer(limit %||% NA_integer_))
  filt <- .wb_art_table_filters_sql(filters)
  where_bits <- c("artifact_id = ?", filt$sql)
  sql <- paste0(
    "SELECT DISTINCT json_extract(row_json, '", .wb_art_table_json_path(column), "') AS value
     FROM artifact_table_rows
     WHERE ", paste(where_bits, collapse = " AND "),
    " ORDER BY value",
    if (is.finite(lim) && lim > 0L) paste0(" LIMIT ", lim) else "",
    ";"
  )
  vals <- DBI::dbGetQuery(bundle$con, sql, params = c(list(aid), filt$params))
  if (!is.data.frame(vals) || !nrow(vals) || !("value" %in% names(vals))) return(character(0))
  out <- as.character(vals$value)
  out <- out[!is.na(out) & nzchar(out)]
  unique(out)
}

#' Slice Rows From A Table Artifact Without Full Load
#'
#' Read a bounded row slice from a promoted `feature_table` or `obs_table`
#' artifact by filtering directly against the JSON-backed row store.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param artifact_id Artifact id for a promoted `feature_table` or `obs_table`.
#' @param filters Optional named list of equality filters applied to row JSON.
#' @param limit Optional limit on the number of rows returned.
#'
#' @return A data frame reconstructed from the matching `artifact_table_rows`.
#'
#' @export
wb_art_table_slice <- function(bundle, artifact_id, filters = NULL, limit = NULL) {
  info <- wb_art_table_info(bundle, artifact_id)
  .wb_assert(as.character(info$type[1] %||% "")[1] %in% c("obs_table", "feature_table"),
             "wb_art_table_slice() supports obs_table and feature_table artifacts.")

  aid <- as.character(artifact_id)[1]
  lim <- suppressWarnings(as.integer(limit %||% NA_integer_))
  filt <- .wb_art_table_filters_sql(filters)
  where_bits <- c("artifact_id = ?", filt$sql)
  sql <- paste0(
    "SELECT row_json
     FROM artifact_table_rows
     WHERE ", paste(where_bits, collapse = " AND "),
    " ORDER BY row_idx ASC",
    if (is.finite(lim) && lim > 0L) paste0(" LIMIT ", lim) else "",
    ";"
  )
  rows <- DBI::dbGetQuery(bundle$con, sql, params = c(list(aid), filt$params))
  .wb_art_table_rows_to_df(rows)
}

#' Summarize A Promoted `trajectory_smooth` Artifact
#'
#' Read the lightweight overview needed to browse a promoted
#' `trajectory_smooth` artifact without materializing the full trend table.
#' This includes lineage/route coverage, feature-set context, paired summary
#' artifact information, and related trajectory artifacts. `trajectory_route_smooth`
#' artifacts are accepted and surfaced through the same overview shape with
#' route keys exposed via the `lineages` field for client compatibility.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param artifact_id Artifact id for an `obs_table` with
#'   `table_type = "trajectory_smooth"` or `"trajectory_route_smooth"`.
#'
#' @return A named list with overview fields such as `lineages`, `feature_ids`,
#'   `feature_set`, `matrix_id`, `summary_artifact_id`, and `related`.
#'
#' @export
wb_art_trajectory_smooth_overview <- function(bundle, artifact_id) {
  info <- wb_art_table_info(bundle, artifact_id)
  .wb_assert(identical(as.character(info$type[1] %||% "")[1], "obs_table"),
             "wb_art_trajectory_smooth_overview() requires an obs_table artifact.")
  table_type <- as.character(info$table_type[1] %||% "")[1]
  .wb_assert(table_type %in% c("trajectory_smooth", "trajectory_route_smooth"),
             "wb_art_trajectory_smooth_overview() requires table_type='trajectory_smooth' or 'trajectory_route_smooth'.")

  prov_json <- as.character(info$provenance_json[1] %||% "")[1]
  prov <- if (nzchar(prov_json)) jsonlite::fromJSON(prov_json, simplifyVector = TRUE) else list()
  run_id <- as.character(prov$run_id %||% "")[1]
  params <- prov$params %||% list()
  matrix_id <- as.character(params$matrix_id %||% info$input_matrix_id[1] %||% "")[1]
  feature_set <- as.character(params$feature_set %||% "")[1]
  model_signature <- .wb_art_trajectory_model_signature(info, prov = prov)

  arts <- wb_art_list(bundle, type = "obs_table")
  summary_artifact_id <- NA_character_
  summary_tbl <- data.frame(stringsAsFactors = FALSE)
  if (is.data.frame(arts) && nrow(arts)) {
    tt <- DBI::dbGetQuery(
      bundle$con,
      "SELECT artifact_id, table_type
       FROM artifact_tables
       WHERE artifact_id IN (SELECT artifact_id FROM artifacts WHERE type = 'obs_table');"
    )
    arts2 <- merge(arts, tt, by = "artifact_id", all.x = TRUE, sort = FALSE)
    if (nrow(arts2)) {
      run_ids <- vapply(seq_len(nrow(arts2)), function(i) {
        pj <- as.character(arts2$provenance_json[i] %||% "")[1]
        if (!nzchar(pj)) return("")
        out <- try(jsonlite::fromJSON(pj, simplifyVector = TRUE), silent = TRUE)
        if (inherits(out, "try-error")) return("")
        as.character(out$run_id %||% "")[1]
      }, character(1))
      summary_type <- if (identical(table_type, "trajectory_route_smooth")) "trajectory_route_smooth_summary" else "trajectory_smooth_summary"
      summary_source <- if (identical(table_type, "trajectory_route_smooth")) "trajectory_route_smooth" else "trajectory_smooth"
      hits <- arts2[
        as.character(arts2$table_type %||% "") == summary_type &
          as.character(arts2$source_op %||% "") == summary_source &
          nzchar(run_id) & run_ids == run_id,
        ,
        drop = FALSE
      ]
      if (nrow(hits)) {
        summary_artifact_id <- as.character(hits$artifact_id[1])
        summary_prim <- wb_art_load(bundle, summary_artifact_id, expected_kind = "obs_table")
        summary_tbl <- summary_prim$table %||% data.frame(stringsAsFactors = FALSE)
      }
    }
  }

  lineages <- if (is.data.frame(summary_tbl) && "lineage_id" %in% names(summary_tbl)) {
    unique(as.character(summary_tbl$lineage_id))
  } else if (is.data.frame(summary_tbl) && "route_key" %in% names(summary_tbl)) {
    unique(as.character(summary_tbl$route_key))
  } else {
    key_col <- if (identical(table_type, "trajectory_route_smooth")) "route_key" else "lineage_id"
    wb_art_table_distinct(bundle, artifact_id, key_col)
  }
  lineages <- lineages[!is.na(lineages) & nzchar(lineages)]

  feature_ids <- character(0)
  if (nzchar(feature_set) && nzchar(matrix_id)) {
    feature_ids <- try(wb_feature_set_get(bundle, feature_set = feature_set, matrix_id = matrix_id), silent = TRUE)
    if (inherits(feature_ids, "try-error")) feature_ids <- character(0)
  }
  feature_ids <- unique(as.character(feature_ids %||% character(0)))
  feature_ids <- feature_ids[nzchar(feature_ids)]

  related <- try(wb_art_trajectory_related(bundle, artifact_id), silent = TRUE)
  if (inherits(related, "try-error") || !is.list(related)) related <- list()

  list(
    artifact_id = as.character(artifact_id)[1],
    run_id = run_id,
    summary_artifact_id = summary_artifact_id,
    summary_table = summary_tbl,
    lineages = lineages,
    matrix_id = matrix_id,
    feature_set = feature_set,
    feature_ids = feature_ids,
    model_signature = model_signature,
    related = related,
    n_features_input = suppressWarnings(as.integer(params$n_features_input %||% length(feature_ids))),
    n_lineages = suppressWarnings(as.integer(params$n_lineages %||% length(lineages))),
    n_bins = suppressWarnings(as.integer(params$n_bins %||% NA_integer_))
  )
}

#' Find Related Trajectory Artifacts
#'
#' Match promoted trajectory artifacts that belong to the same analysis context.
#' Matching is based on matrix, cell set, and trajectory model signature so
#' clients can discover valid follow-up workflows without reimplementing these
#' compatibility rules.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param artifact_id Artifact id for a promoted trajectory artifact.
#'
#' @return A named list of data frames. Current slots are `trajectory_de`,
#'   `trajectory_smooth`, and `trajectory_signature_smooth`.
#'
#' @export
wb_art_trajectory_related <- function(bundle, artifact_id) {
  info <- wb_art_table_info(bundle, artifact_id)
  prov <- .wb_art_parse_provenance_json(info$provenance_json[1] %||% "")
  matrix_id <- as.character(info$input_matrix_id[1] %||% prov$params$matrix_id %||% "")[1]
  cell_set <- as.character(info$cell_set[1] %||% prov$inputs$cell_set %||% "")[1]
  model_sig <- .wb_art_trajectory_model_signature(info, prov = prov)
  model_fields <- .wb_art_trajectory_model_fields(info, prov = prov)

  arts <- wb_art_list(bundle)
  if (!is.data.frame(arts) || !nrow(arts)) {
    empty_df <- data.frame(stringsAsFactors = FALSE)
    return(list(
      trajectory_de = empty_df,
      trajectory_smooth = empty_df,
      trajectory_signature_smooth = empty_df
    ))
  }

  tt <- DBI::dbGetQuery(
    bundle$con,
    "SELECT artifact_id, table_type
     FROM artifact_tables
     WHERE artifact_id IN (SELECT artifact_id FROM artifacts WHERE type IN ('obs_table', 'feature_table'));"
  )
  arts2 <- merge(arts, tt, by = "artifact_id", all.x = TRUE, sort = FALSE)
  if (!nrow(arts2)) {
    empty_df <- data.frame(stringsAsFactors = FALSE)
    return(list(
      trajectory_de = empty_df,
      trajectory_smooth = empty_df,
      trajectory_signature_smooth = empty_df
    ))
  }

  provs <- lapply(arts2$provenance_json, .wb_art_parse_provenance_json)
  model_sigs <- vapply(seq_len(nrow(arts2)), function(i) .wb_art_trajectory_model_signature(arts2[i, , drop = FALSE], prov = provs[[i]]), character(1))
  model_fields_all <- lapply(seq_len(nrow(arts2)), function(i) .wb_art_trajectory_model_fields(arts2[i, , drop = FALSE], prov = provs[[i]]))
  model_compatible <- vapply(seq_len(nrow(arts2)), function(i) {
    mf <- model_fields_all[[i]]
    exact_sig <- nzchar(model_sig) && identical(model_sigs[[i]], model_sig)
    exact_path <- nzchar(model_fields$model_path) && nzchar(mf$model_path) && identical(as.character(mf$model_path), as.character(model_fields$model_path))
    coarse <- nzchar(model_fields$engine) &&
      identical(as.character(mf$engine), as.character(model_fields$engine)) &&
      identical(as.character(mf$model_space_id), as.character(model_fields$model_space_id)) &&
      identical(as.character(mf$in_space_id), as.character(model_fields$in_space_id))
    exact_sig || exact_path || coarse
  }, logical(1))
  base_ok <- as.character(arts2$input_matrix_id %||% "") == matrix_id &
    as.character(arts2$cell_set %||% "") == cell_set &
    model_compatible

  ok_de <- as.character(arts2$source_op %||% "") == "trajectory_de" &
    as.character(arts2$type %||% "") == "feature_table" &
    base_ok

  ok_smooth <- as.character(arts2$source_op %||% "") == "trajectory_smooth" &
    as.character(arts2$type %||% "") == "obs_table" &
    as.character(arts2$table_type %||% "") == "trajectory_smooth" &
    base_ok

  ok_sig <- as.character(arts2$source_op %||% "") == "trajectory_signature_smooth" &
    as.character(arts2$type %||% "") == "obs_table" &
    as.character(arts2$table_type %||% "") == "trajectory_signature_smooth" &
    as.character(arts2$input_matrix_id %||% "") == matrix_id &
    as.character(arts2$cell_set %||% "") == cell_set &
    model_compatible &
    vapply(model_fields_all, function(mf) {
      fs_self <- as.character(model_fields$feature_set %||% "")[1]
      fs_other <- as.character(mf$feature_set %||% "")[1]
      if (!nzchar(fs_self) || !nzchar(fs_other)) return(TRUE)
      identical(fs_self, fs_other)
    }, logical(1))

  keep_cols <- c("artifact_id", "name", "description", "created_at", "input_matrix_id", "cell_set", "source_op", "table_type")
  rel_de <- arts2[ok_de, keep_cols, drop = FALSE]
  rownames(rel_de) <- NULL
  rel_smooth <- arts2[ok_smooth, keep_cols, drop = FALSE]
  rownames(rel_smooth) <- NULL
  rel_sig <- arts2[ok_sig, keep_cols, drop = FALSE]
  rownames(rel_sig) <- NULL
  list(
    trajectory_de = rel_de,
    trajectory_smooth = rel_smooth,
    trajectory_signature_smooth = rel_sig
  )
}

#' Get Top-Ranked `trajectory_de` Rows For One Lineage
#'
#' Convenience wrapper around [wb_art_trajectory_de_ranked()] for the common
#' case of "top genes for this lineage" using the default trajectory DE ranking
#' policy.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param artifact_id Artifact id for a `feature_table` with
#'   `table_type = "trajectory_de"`.
#' @param lineage_id Lineage to rank within.
#' @param limit Maximum number of rows to return.
#'
#' @return A ranked data frame slice from the promoted `trajectory_de` table.
#'
#' @export
wb_art_trajectory_de_top <- function(bundle, artifact_id, lineage_id, limit = 50L) {
  wb_art_trajectory_de_ranked(
    bundle = bundle,
    artifact_id = artifact_id,
    lineage_id = lineage_id,
    limit = limit,
    direction = "any",
    order_by = "abs_rho",
    search = NULL
  )
}

#' Rank `trajectory_de` Rows Within One Lineage
#'
#' Slice a promoted `trajectory_de` artifact to one lineage and apply a stable
#' ranking/filtering policy suitable for browsers, pickers, and bounded plotting
#' surfaces.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param artifact_id Artifact id for a `feature_table` with
#'   `table_type = "trajectory_de"`.
#' @param lineage_id Lineage to rank within.
#' @param limit Maximum number of rows to return after filtering and ranking.
#' @param direction Direction filter: any, up, or down.
#' @param order_by Ranking rule to apply.
#' @param search Optional case-insensitive substring filter over `feature_id`.
#'
#' @return A filtered and ranked data frame containing trajectory DE rows for
#'   the requested lineage.
#'
#' @export
wb_art_trajectory_de_ranked <- function(bundle,
                                        artifact_id,
                                        lineage_id,
                                        limit = 50L,
                                        direction = c("any", "up", "down"),
                                        order_by = c("abs_rho", "rho_desc", "rho_asc", "p_adj"),
                                        search = NULL) {
  info <- wb_art_table_info(bundle, artifact_id)
  .wb_assert(identical(as.character(info$type[1] %||% "")[1], "feature_table"),
             "wb_art_trajectory_de_ranked() requires a feature_table artifact.")
  .wb_assert(identical(as.character(info$table_type[1] %||% "")[1], "trajectory_de"),
             "wb_art_trajectory_de_ranked() requires table_type='trajectory_de'.")
  lin <- as.character(lineage_id %||% "")[1]
  .wb_assert(nzchar(lin), "lineage_id must be non-empty")

  n <- suppressWarnings(as.integer(limit %||% 50L))
  if (!is.finite(n) || n < 1L) n <- 50L
  dir_mode <- match.arg(direction)
  ord_mode <- match.arg(order_by)
  q <- trimws(as.character(search %||% "")[1])

  tbl <- wb_art_table_slice(bundle, artifact_id, filters = list(lineage_id = lin))
  if (!is.data.frame(tbl) || !nrow(tbl)) return(data.frame(stringsAsFactors = FALSE))
  if ("feature_id" %in% names(tbl)) tbl$feature_id <- as.character(tbl$feature_id)
  if ("direction" %in% names(tbl)) tbl$direction <- as.character(tbl$direction)
  if ("rho" %in% names(tbl)) tbl$rho <- suppressWarnings(as.numeric(tbl$rho))
  if ("abs_rho" %in% names(tbl)) tbl$abs_rho <- suppressWarnings(as.numeric(tbl$abs_rho))
  if ("p_val_adj" %in% names(tbl)) tbl$p_val_adj <- suppressWarnings(as.numeric(tbl$p_val_adj))

  if (identical(dir_mode, "up") && "direction" %in% names(tbl)) {
    tbl <- tbl[as.character(tbl$direction) == "up", , drop = FALSE]
  } else if (identical(dir_mode, "down") && "direction" %in% names(tbl)) {
    tbl <- tbl[as.character(tbl$direction) == "down", , drop = FALSE]
  }
  if (nzchar(q) && "feature_id" %in% names(tbl)) {
    keep <- grepl(tolower(q), tolower(as.character(tbl$feature_id)), fixed = TRUE)
    tbl <- tbl[keep, , drop = FALSE]
  }
  if (!nrow(tbl)) return(tbl)

  ord <- switch(
    ord_mode,
    abs_rho = order(suppressWarnings(-abs(as.numeric(tbl$rho %||% tbl$abs_rho))), as.character(tbl$feature_id), na.last = TRUE),
    rho_desc = order(suppressWarnings(-as.numeric(tbl$rho)), as.character(tbl$feature_id), na.last = TRUE),
    rho_asc = order(suppressWarnings(as.numeric(tbl$rho)), as.character(tbl$feature_id), na.last = TRUE),
    p_adj = order(suppressWarnings(as.numeric(tbl$p_val_adj)), suppressWarnings(-abs(as.numeric(tbl$rho %||% tbl$abs_rho))), na.last = TRUE)
  )
  if (is.null(ord)) ord <- seq_len(nrow(tbl))
  tbl <- tbl[ord, , drop = FALSE]
  if (nrow(tbl) > n) tbl <- tbl[seq_len(n), , drop = FALSE]
  rownames(tbl) <- NULL
  tbl
}

#' Summarize A Promoted `trajectory_de` Artifact
#'
#' Read lightweight overview metadata for a promoted `trajectory_de` artifact,
#' including lineage coverage, paired summary artifact information, input
#' feature-set context, test settings, and related trajectory artifacts.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param artifact_id Artifact id for a `feature_table` with
#'   `table_type = "trajectory_de"`.
#'
#' @return A named list with overview fields such as `lineages`, `feature_ids`,
#'   `summary_artifact_id`, `test`, thresholds, and `related`.
#'
#' @export
wb_art_trajectory_de_overview <- function(bundle, artifact_id) {
  info <- wb_art_table_info(bundle, artifact_id)
  .wb_assert(identical(as.character(info$type[1] %||% "")[1], "feature_table"),
             "wb_art_trajectory_de_overview() requires a feature_table artifact.")
  .wb_assert(identical(as.character(info$table_type[1] %||% "")[1], "trajectory_de"),
             "wb_art_trajectory_de_overview() requires table_type='trajectory_de'.")

  prov_json <- as.character(info$provenance_json[1] %||% "")[1]
  prov <- if (nzchar(prov_json)) jsonlite::fromJSON(prov_json, simplifyVector = TRUE) else list()
  run_id <- as.character(prov$run_id %||% "")[1]
  params <- prov$params %||% list()
  matrix_id <- as.character(params$matrix_id %||% info$input_matrix_id[1] %||% "")[1]
  feature_set <- as.character(params$feature_set %||% "")[1]
  model_signature <- .wb_art_trajectory_model_signature(info, prov = prov)

  arts <- wb_art_list(bundle, type = "obs_table")
  summary_artifact_id <- NA_character_
  summary_tbl <- data.frame(stringsAsFactors = FALSE)
  if (is.data.frame(arts) && nrow(arts)) {
    tt <- DBI::dbGetQuery(
      bundle$con,
      "SELECT artifact_id, table_type
       FROM artifact_tables
       WHERE artifact_id IN (SELECT artifact_id FROM artifacts WHERE type = 'obs_table');"
    )
    arts2 <- merge(arts, tt, by = "artifact_id", all.x = TRUE, sort = FALSE)
    if (nrow(arts2)) {
      run_ids <- vapply(seq_len(nrow(arts2)), function(i) {
        pj <- as.character(arts2$provenance_json[i] %||% "")[1]
        if (!nzchar(pj)) return("")
        out <- try(jsonlite::fromJSON(pj, simplifyVector = TRUE), silent = TRUE)
        if (inherits(out, "try-error")) return("")
        as.character(out$run_id %||% "")[1]
      }, character(1))
      hits <- arts2[
        as.character(arts2$table_type %||% "") == "trajectory_de_summary" &
          as.character(arts2$source_op %||% "") == "trajectory_de" &
          nzchar(run_id) & run_ids == run_id,
        ,
        drop = FALSE
      ]
      if (nrow(hits)) {
        summary_artifact_id <- as.character(hits$artifact_id[1])
        summary_prim <- wb_art_load(bundle, summary_artifact_id, expected_kind = "obs_table")
        summary_tbl <- summary_prim$table %||% data.frame(stringsAsFactors = FALSE)
      }
    }
  }

  lineages <- if (is.data.frame(summary_tbl) && "lineage_id" %in% names(summary_tbl)) {
    unique(as.character(summary_tbl$lineage_id))
  } else {
    wb_art_table_distinct(bundle, artifact_id, "lineage_id")
  }
  lineages <- lineages[!is.na(lineages) & nzchar(lineages)]

  feature_ids <- character(0)
  if (nzchar(feature_set) && nzchar(matrix_id)) {
    feature_ids <- try(wb_feature_set_get(bundle, feature_set = feature_set, matrix_id = matrix_id), silent = TRUE)
    if (inherits(feature_ids, "try-error")) feature_ids <- character(0)
  }
  if (!length(feature_ids)) {
    feature_ids <- wb_art_table_distinct(bundle, artifact_id, "feature_id")
  }
  feature_ids <- unique(as.character(feature_ids %||% character(0)))
  feature_ids <- feature_ids[nzchar(feature_ids)]

  related <- try(wb_art_trajectory_related(bundle, artifact_id), silent = TRUE)
  if (inherits(related, "try-error") || !is.list(related)) related <- list()

  list(
    artifact_id = as.character(artifact_id)[1],
    run_id = run_id,
    summary_artifact_id = summary_artifact_id,
    summary_table = summary_tbl,
    lineages = lineages,
    matrix_id = matrix_id,
    feature_set = feature_set,
    feature_ids = feature_ids,
    model_signature = model_signature,
    related = related,
    n_features_input = suppressWarnings(as.integer(params$n_features_input %||% length(feature_ids))),
    n_features_tested = suppressWarnings(as.integer(params$n_features_tested %||% NA_integer_)),
    n_lineages = suppressWarnings(as.integer(params$n_lineages_tested %||% params$n_lineages_input %||% length(lineages))),
    test = as.character(params$test %||% "spearman")[1],
    min_pct_nonzero = suppressWarnings(as.numeric(params$min_pct_nonzero %||% NA_real_)),
    min_sd = suppressWarnings(as.numeric(params$min_sd %||% NA_real_))
  )
}

#' Slice A `trajectory_de` Artifact Into A `feature_table` Primitive
#'
#' Materialize a bounded lineage-specific slice from a promoted `trajectory_de`
#' artifact and wrap it as a canonical `feature_table` primitive. This is the
#' preferred engine path for downstream plotting and browser views that should
#' not load the full artifact.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param artifact_id Artifact id for a `feature_table` with
#'   `table_type = "trajectory_de"`.
#' @param lineage_id Lineage to slice.
#' @param feature_ids Optional feature ids to keep.
#' @param limit Optional row limit passed to the underlying table slice.
#'
#' @return A `wb_primitive` of kind `feature_table` with `table_type =
#'   "trajectory_de"`.
#'
#' @export
wb_art_trajectory_de_slice_primitive <- function(bundle, artifact_id, lineage_id, feature_ids = NULL, limit = NULL) {
  info <- wb_art_table_info(bundle, artifact_id)
  .wb_assert(identical(as.character(info$type[1] %||% "")[1], "feature_table"),
             "wb_art_trajectory_de_slice_primitive() requires a feature_table artifact.")
  .wb_assert(identical(as.character(info$table_type[1] %||% "")[1], "trajectory_de"),
             "wb_art_trajectory_de_slice_primitive() requires table_type='trajectory_de'.")
  lin <- as.character(lineage_id %||% "")[1]
  .wb_assert(nzchar(lin), "lineage_id must be non-empty")

  fids <- unique(as.character(feature_ids %||% character(0)))
  fids <- fids[nzchar(fids)]
  filters <- list(lineage_id = lin)
  if (length(fids)) filters$feature_id <- fids
  tbl <- wb_art_table_slice(bundle, artifact_id, filters = filters, limit = limit)
  if (!is.data.frame(tbl)) tbl <- data.frame(stringsAsFactors = FALSE)
  rownames(tbl) <- NULL

  meta <- list()
  meta_json <- as.character(info$meta_json[1] %||% "")[1]
  if (nzchar(meta_json)) {
    parsed <- try(jsonlite::fromJSON(meta_json, simplifyVector = TRUE), silent = TRUE)
    if (!inherits(parsed, "try-error") && is.list(parsed)) meta <- parsed
  }
  meta$lineage_id <- lin
  meta$slice_n_rows <- nrow(tbl)
  if (length(fids)) meta$feature_ids <- fids
  wb_prim_feature_table(
    table = tbl,
    table_type = "trajectory_de",
    meta = meta
  )
}

#' Build A Ranked Plotting Slice For `trajectory_de`
#'
#' Compose [wb_art_trajectory_de_ranked()] and
#' [wb_art_trajectory_de_slice_primitive()] to return a bounded, lineage-specific
#' `feature_table` primitive suitable for plotting.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param artifact_id Artifact id for a `feature_table` with
#'   `table_type = "trajectory_de"`.
#' @param lineage_id Lineage to plot.
#' @param top_n Number of ranked features to include.
#' @param search Optional case-insensitive substring filter over `feature_id`.
#' @param direction Direction filter: any, up, or down.
#' @param order_by Ranking rule to apply before slicing.
#'
#' @return A `wb_primitive` of kind `feature_table` with a bounded
#'   lineage-specific trajectory DE slice.
#'
#' @export
wb_art_trajectory_de_plot_slice <- function(bundle,
                                            artifact_id,
                                            lineage_id,
                                            top_n = 50L,
                                            search = NULL,
                                            direction = c("any", "up", "down"),
                                            order_by = c("abs_rho", "rho_desc", "rho_asc", "p_adj")) {
  ranked <- wb_art_trajectory_de_ranked(
    bundle = bundle,
    artifact_id = artifact_id,
    lineage_id = lineage_id,
    limit = top_n,
    direction = direction,
    order_by = order_by,
    search = search
  )
  fids <- if (is.data.frame(ranked) && "feature_id" %in% names(ranked)) as.character(ranked$feature_id) else character(0)
  fids <- unique(fids[nzchar(fids)])
  wb_art_trajectory_de_slice_primitive(
    bundle = bundle,
    artifact_id = artifact_id,
    lineage_id = lineage_id,
    feature_ids = fids,
    limit = length(fids)
  )
}

#' Read label rows for a label-like artifact
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param artifact_id Promoted label-like artifact identifier.
#'
#' @return A data frame with `cell_id` and `label`, ordered by cell id.
#' @export
wb_art_get_labels <- function(bundle, artifact_id) {
  con <- bundle$con
  DBI::dbGetQuery(con, "SELECT cell_id, label FROM artifact_labels WHERE artifact_id = ? ORDER BY cell_id;", params = list(artifact_id))
}

.wb_idcard_compact_ref_rows <- function(df, n = 5L) {
  if (!is.data.frame(df) || !nrow(df)) return(data.frame(
    artifact_id = character(0), type = character(0), name = character(0), source_op = character(0),
    stringsAsFactors = FALSE
  ))
  keep <- intersect(c("artifact_id", "type", "name", "source_op"), colnames(df))
  out <- df[, keep, drop = FALSE]
  if (nrow(out) > n) out <- out[seq_len(n), , drop = FALSE]
  rownames(out) <- NULL
  out
}

.wb_idcard_null_if_empty_chr <- function(x) {
  x <- as.character(x %||% "")[1]
  if (!nzchar(x) || identical(x, "NA")) return(NULL)
  x
}

.wb_idcard_scalar <- function(x) {
  if (is.null(x)) return(NULL)
  if (is.atomic(x) && length(x) >= 1L) return(x[[1]])
  x
}

.wb_idcard_group_input_summary <- function(x, preview_n = 4L) {
  if (is.null(x)) return(NULL)

  # Common case: named set selectors should be shown verbatim.
  if (is.character(x)) {
    vals <- as.character(x)
    vals <- vals[!is.na(vals) & nzchar(vals)]
    if (!length(vals)) return(NULL)

    if (length(vals) == 1L) {
      token <- vals[[1]]
      if (startsWith(token, "set:") || token %in% c("core", "all")) {
        return(list(
          display = token,
          chip = token,
          mode = "set",
          n = NA_integer_,
          preview = token
        ))
      }
      # Single literal cell id.
      return(list(
        display = token,
        chip = "literal[1]",
        mode = "literal_ids",
        n = 1L,
        preview = token
      ))
    }

    prev <- utils::head(vals, as.integer(preview_n))
    prev_txt <- paste(prev, collapse = ", ")
    if (length(vals) > length(prev)) prev_txt <- paste0(prev_txt, ", ...")
    return(list(
      display = paste0(length(vals), " literal cell IDs (", prev_txt, ")"),
      chip = paste0("literal[", length(vals), "]"),
      mode = "literal_ids",
      n = as.integer(length(vals)),
      preview = prev_txt
    ))
  }

  # Fallback: compact scalar/list representation for unexpected shapes.
  sx <- .wb_idcard_scalar(x)
  txt <- paste(utils::capture.output(str(sx, give.attr = FALSE, vec.len = 3L)), collapse = " ")
  txt <- gsub("\\s+", " ", txt)
  if (nchar(txt) > 120L) txt <- paste0(substr(txt, 1L, 117L), "...")
  list(
    display = txt,
    chip = "group:<complex>",
    mode = "complex",
    n = NA_integer_,
    preview = txt
  )
}

.wb_idcard_pick_params <- function(params, keys) {
  p <- params %||% list()
  if (!is.list(p) || !length(p)) return(list())
  out <- list()
  for (k in as.character(keys)) {
    if (is.null(p[[k]])) next
    out[[k]] <- .wb_idcard_scalar(p[[k]])
  }
  out
}

.wb_idcard_infer_input_feature_table <- function(rd) {
  rd <- rd %||% list()
  x <- rd$run %||% list()
  sy <- x$symbolic_inputs %||% list()
  ex <- x$execution_inputs %||% list()
  inp <- x$inputs %||% list()

  cand <- list(
    sy$feature_table, sy$feature_table_ref, sy$de_table, sy$table,
    ex$resolved$feature_table, ex$feature_table,
    inp$user_inputs$feature_table, inp$user_inputs$feature_table_ref, inp$user_inputs$de_table
  )
  for (v in cand) {
    if (is.null(v)) next
    if (is.character(v) && length(v) == 1L && nzchar(v)) return(as.character(v))
    if (is.list(v) && identical(as.character(v$ref_type %||% "")[1], "artifact")) {
      aid <- as.character(v$artifact_id %||% "")[1]
      if (nzchar(aid)) return(paste0("artifact:", aid))
    }
  }
  NULL
}

.wb_idcard_infer_input_ref <- function(rd, input_name) {
  rd <- rd %||% list()
  x <- rd$run %||% list()
  sy <- x$symbolic_inputs %||% list()
  ex <- x$execution_inputs %||% list()
  inp <- x$inputs %||% list()

  cand <- list(
    sy[[input_name]],
    sy[[paste0(input_name, "_ref")]],
    inp$user_inputs[[input_name]],
    inp$user_inputs[[paste0(input_name, "_ref")]],
    ex$resolved[[input_name]],
    ex[[input_name]]
  )

  for (v in cand) {
    if (is.null(v)) next
    if (is.character(v) && length(v) == 1L && nzchar(v)) return(as.character(v))
    if (is.list(v) && identical(as.character(v$ref_type %||% "")[1], "artifact")) {
      aid <- as.character(v$artifact_id %||% "")[1]
      out <- as.character(v$output %||% input_name)[1]
      if (nzchar(aid)) return(paste0("artifact:", aid, ":", out))
    }
    if (is.list(v) && identical(as.character(v$ref_type %||% "")[1], "run")) {
      rid <- as.character(v$run_id %||% "")[1]
      out <- as.character(v$output %||% input_name)[1]
      if (nzchar(rid)) return(paste0("session:", rid, ":", out))
    }
    # resolved primitive -> compact summary by kind
    if (is.list(v) && identical(as.character(v$kind %||% "")[1], "model_ref")) {
      eng <- as.character(v$engine %||% "")[1]
      ms <- as.character(v$model_space_id %||% v$space_id %||% "")[1]
      if (nzchar(ms)) return(paste0("model_ref(", if (nzchar(eng)) paste0(eng, ":") else "", ms, ")"))
    }
    if (is.list(v) && identical(as.character(v$kind %||% "")[1], "cell_vector")) {
      n <- length(as.character(v$cell_id %||% character(0)))
      return(paste0("cell_vector", if (!is.na(n)) paste0("[", n, "]") else ""))
    }
  }
  NULL
}

.wb_art_identity_card_default_issuer <- function(bc) {
  id <- bc$identity %||% list()
  rd <- bc$persisted_provenance$run_details %||% NULL
  run_obj <- rd$run %||% list()
  params <- run_obj$params %||% bc$inline_provenance$parsed$params %||% list()

  issuer_fields <- list(
    matrix_id = .wb_idcard_null_if_empty_chr(id$input_matrix_id),
    space_id = .wb_idcard_null_if_empty_chr(id$input_space_id),
    cell_set = .wb_idcard_null_if_empty_chr(id$cell_set)
  )
  issuer_fields <- issuer_fields[!vapply(issuer_fields, is.null, logical(1))]

  chips <- c(
    if (nzchar(as.character(id$type %||% "")[1])) paste0("type:", as.character(id$type)[1]) else NULL,
    if (nzchar(as.character(id$source_op %||% "")[1])) paste0("op:", as.character(id$source_op)[1]) else NULL,
    if (nzchar(as.character(id$input_matrix_id %||% "")[1])) paste0("matrix:", as.character(id$input_matrix_id)[1]) else NULL,
    if (nzchar(as.character(id$input_space_id %||% "")[1])) paste0("space:", as.character(id$input_space_id)[1]) else NULL
  )

  pnames <- names(params %||% list())
  pnames <- pnames[nzchar(pnames)]
  pshow <- utils::head(sort(unique(pnames)), 8L)
  summary_lines <- c(
    paste0("Artifact: ", as.character(id$name %||% id$artifact_id %||% "")),
    paste0("Source op: ", as.character(id$source_op %||% "<unknown>")),
    if (length(pshow)) paste0("Params: ", paste(pshow, collapse = ", ")) else NULL
  )

  list(
    agency = "default",
    issuer_fields = issuer_fields,
    key_params = list(),
    chips = unique(chips[nzchar(chips)]),
    summary_lines = summary_lines
  )
}

.wb_art_identity_card_issuer_pathway_enrich <- function(bc) {
  rd <- bc$persisted_provenance$run_details %||% NULL
  run_obj <- rd$run %||% list()
  params <- run_obj$params %||% bc$inline_provenance$parsed$params %||% list()

  key_params <- .wb_idcard_pick_params(params, c(
    "namespace", "direction", "p_adj_max", "lfc_col", "lfc_min", "lfc_min_abs",
    "min_set_size", "max_set_size", "p_adjust_method", "matrix_id",
    "n_query", "n_universe", "n_pathways"
  ))
  key_params$input_feature_table <- .wb_idcard_infer_input_feature_table(rd)

  chips <- c(
    if (!is.null(key_params$namespace)) paste0("namespace:", key_params$namespace) else NULL,
    if (!is.null(key_params$direction)) paste0("direction:", key_params$direction) else NULL,
    if (!is.null(key_params$matrix_id)) paste0("matrix:", key_params$matrix_id) else NULL
  )

  summary_lines <- c(
    if (!is.null(key_params$namespace)) paste0("Gene-set namespace: ", key_params$namespace) else NULL,
    if (!is.null(key_params$direction)) paste0("Direction filter: ", key_params$direction) else NULL,
    if (!is.null(key_params$p_adj_max)) paste0("Query filter p_adj <= ", key_params$p_adj_max) else NULL,
    if (!is.null(key_params$input_feature_table)) paste0("Input feature table: ", key_params$input_feature_table) else NULL,
    if (!is.null(key_params$n_pathways)) paste0("Pathways tested: ", key_params$n_pathways) else NULL
  )

  list(
    agency = "pathway_enrich",
    issuer_fields = list(namespace = key_params$namespace %||% NULL),
    key_params = key_params,
    chips = unique(as.character(chips[nzchar(as.character(chips))])),
    summary_lines = summary_lines
  )
}

.wb_art_identity_card_issuer_de_wilcox <- function(bc) {
  rd <- bc$persisted_provenance$run_details %||% NULL
  run_obj <- rd$run %||% list()
  params <- run_obj$params %||% bc$inline_provenance$parsed$params %||% list()
  sym <- run_obj$symbolic_inputs %||% list()
  in_all <- run_obj$inputs %||% list()

  group_a <- params$group_a %||% sym$group_a %||% in_all$user_inputs$group_a %||% NULL
  group_b <- params$group_b %||% sym$group_b %||% in_all$user_inputs$group_b %||% NULL

  key_params <- .wb_idcard_pick_params(params, c("matrix_id", "min_pct", "p_adjust_method"))
  ga <- .wb_idcard_group_input_summary(group_a)
  gb <- .wb_idcard_group_input_summary(group_b)
  key_params$group_a <- ga$display %||% NULL
  key_params$group_b <- gb$display %||% NULL
  key_params$group_a_mode <- ga$mode %||% NULL
  key_params$group_b_mode <- gb$mode %||% NULL
  key_params$group_a_n <- ga$n %||% NULL
  key_params$group_b_n <- gb$n %||% NULL

  chips <- c(
    if (!is.null(key_params$matrix_id)) paste0("matrix:", key_params$matrix_id) else NULL,
    if (!is.null(ga$chip)) paste0("A:", as.character(ga$chip)) else NULL,
    if (!is.null(gb$chip)) paste0("B:", as.character(gb$chip)) else NULL
  )

  summary_lines <- c(
    if (!is.null(ga$display)) paste0("Group A: ", as.character(ga$display)) else NULL,
    if (!is.null(gb$display)) paste0("Group B: ", as.character(gb$display)) else NULL,
    if (!is.null(key_params$min_pct)) paste0("min_pct: ", key_params$min_pct) else NULL,
    if (!is.null(key_params$p_adjust_method)) paste0("p.adjust: ", key_params$p_adjust_method) else NULL
  )

  list(
    agency = "de_wilcox",
    issuer_fields = list(),
    key_params = key_params,
    chips = unique(as.character(chips[nzchar(as.character(chips))])),
    summary_lines = summary_lines
  )
}

.wb_idcard_trajectory_summary_artifact <- function(bundle, run_id, table_type) {
  if (is.null(bundle) || is.null(bundle$con) || !nzchar(as.character(run_id %||% "")[1])) return(NULL)
  arts <- try(wb_art_list(bundle), silent = TRUE)
  if (inherits(arts, "try-error") || !is.data.frame(arts) || !nrow(arts)) return(NULL)
  tt <- try(DBI::dbGetQuery(
    bundle$con,
    "SELECT artifact_id, table_type
     FROM artifact_tables
     WHERE artifact_id IN (SELECT artifact_id FROM artifacts WHERE type = 'obs_table');"
  ), silent = TRUE)
  if (inherits(tt, "try-error") || !is.data.frame(tt) || !nrow(tt)) return(NULL)
  arts2 <- merge(arts, tt, by = "artifact_id", all.x = TRUE, sort = FALSE)
  if (!nrow(arts2)) return(NULL)
  run_ids <- vapply(seq_len(nrow(arts2)), function(i) {
    pj <- as.character(arts2$provenance_json[i] %||% "")[1]
    if (!nzchar(pj)) return("")
    out <- try(jsonlite::fromJSON(pj, simplifyVector = TRUE), silent = TRUE)
    if (inherits(out, "try-error") || !is.list(out)) return("")
    as.character(out$run_id %||% "")[1]
  }, character(1))
  hit <- arts2[
    as.character(arts2$table_type %||% "") == as.character(table_type)[1] &
      run_ids == as.character(run_id)[1],
    ,
    drop = FALSE
  ]
  if (!nrow(hit)) return(NULL)
  as.character(hit$artifact_id[1])
}

.wb_art_identity_card_issuer_trajectory_de <- function(bc) {
  id <- bc$identity %||% list()
  rd <- bc$persisted_provenance$run_details %||% list()
  run_obj <- rd$run %||% list()
  params <- run_obj$params %||% bc$inline_provenance$parsed$params %||% list()
  bundle <- bc$bundle %||% NULL
  rid <- as.character(run_obj$run_id %||% bc$inline_provenance$parsed$run_id %||% "")[1]

  n_rows <- as.integer(params$n_features_tested %||% NA_integer_)
  n_lin <- as.integer(params$n_lineages_tested %||% params$n_lineages_input %||% NA_integer_)
  n_feat_input <- NA_integer_
  sum_aid <- .wb_idcard_trajectory_summary_artifact(bundle, rid, "trajectory_de_summary")
  if (nzchar(as.character(sum_aid %||% "")[1])) {
    sum_prim <- try(wb_art_load(bundle, sum_aid, expected_kind = "obs_table"), silent = TRUE)
    if (!inherits(sum_prim, "try-error") && is.list(sum_prim) && is.data.frame(sum_prim$table) && nrow(sum_prim$table)) {
      st <- sum_prim$table
      if ("n_features_input" %in% names(st)) {
        n_feat_input <- suppressWarnings(as.integer(max(st$n_features_input, na.rm = TRUE)))
      }
      if ("lineage_id" %in% names(st)) {
        n_lin <- length(unique(as.character(st$lineage_id)))
      }
    }
  }
  if (!is.finite(n_feat_input) || is.na(n_feat_input)) {
    n_feat_input <- suppressWarnings(as.integer(params$feature_set_n %||% NA_integer_))
  }

  avg_rows <- if (is.finite(n_rows) && is.finite(n_lin) && n_lin > 0L) round(n_rows / n_lin, 1) else NA_real_
  key_params <- .wb_idcard_pick_params(params, c("matrix_id", "feature_set", "model_engine", "test", "min_pct_nonzero", "min_sd", "p_adjust_method"))
  key_params$n_lineages <- n_lin
  key_params$n_features_input <- n_feat_input
  key_params$n_rows <- n_rows

  chips <- c(
    if (!is.null(key_params$matrix_id)) paste0("matrix:", key_params$matrix_id) else NULL,
    if (is.finite(n_lin)) paste0("lineages:", n_lin) else NULL,
    if (is.finite(n_feat_input)) paste0("features:", n_feat_input) else NULL
  )

  summary_lines <- c(
    "Per-lineage feature trend table against trajectory pseudotime.",
    if (!is.null(key_params$feature_set) && nzchar(as.character(key_params$feature_set))) paste0("Feature set: ", key_params$feature_set) else NULL,
    if (is.finite(n_lin) && is.finite(n_feat_input)) paste0("Input scope: ", n_feat_input, " features across ", n_lin, " lineages.") else NULL,
    if (is.finite(n_rows)) paste0("Lineage-feature rows: ", n_rows, if (is.finite(avg_rows)) paste0(" (avg ", avg_rows, " per lineage).") else "") else NULL,
    if (!is.null(key_params$test)) paste0("Trend test: ", key_params$test) else NULL
  )

  list(
    agency = "trajectory_de",
    issuer_fields = list(
      matrix_id = key_params$matrix_id %||% NULL,
      feature_set = key_params$feature_set %||% NULL
    ),
    key_params = key_params,
    chips = unique(as.character(chips[nzchar(as.character(chips))])),
    summary_lines = summary_lines
  )
}

.wb_art_identity_card_issuer_trajectory_smooth <- function(bc) {
  id <- bc$identity %||% list()
  rd <- bc$persisted_provenance$run_details %||% list()
  run_obj <- rd$run %||% list()
  params <- run_obj$params %||% bc$inline_provenance$parsed$params %||% list()
  bundle <- bc$bundle %||% NULL
  rid <- as.character(run_obj$run_id %||% bc$inline_provenance$parsed$run_id %||% "")[1]

  key_params <- .wb_idcard_pick_params(params, c("matrix_id", "feature_set", "n_bins", "summary_fun", "min_cells_per_bin"))
  n_rows <- NA_integer_
  n_lin <- as.integer(params$n_lineages %||% NA_integer_)
  n_feat_input <- as.integer(params$n_features_input %||% NA_integer_)
  sum_aid <- .wb_idcard_trajectory_summary_artifact(bundle, rid, "trajectory_smooth_summary")
  if (nzchar(as.character(sum_aid %||% "")[1])) {
    sum_prim <- try(wb_art_load(bundle, sum_aid, expected_kind = "obs_table"), silent = TRUE)
    if (!inherits(sum_prim, "try-error") && is.list(sum_prim) && is.data.frame(sum_prim$table) && nrow(sum_prim$table)) {
      st <- sum_prim$table
      if ("n_rows" %in% names(st)) n_rows <- suppressWarnings(as.integer(sum(st$n_rows, na.rm = TRUE)))
      if ("lineage_id" %in% names(st)) n_lin <- length(unique(as.character(st$lineage_id)))
      if ("n_features_input" %in% names(st)) n_feat_input <- suppressWarnings(as.integer(max(st$n_features_input, na.rm = TRUE)))
    }
  }

  chips <- c(
    if (!is.null(key_params$matrix_id)) paste0("matrix:", key_params$matrix_id) else NULL,
    if (is.finite(n_lin)) paste0("lineages:", n_lin) else NULL,
    if (is.finite(n_feat_input)) paste0("features:", n_feat_input) else NULL,
    if (!is.null(key_params$n_bins)) paste0("bins:", key_params$n_bins) else NULL
  )
  summary_lines <- c(
    "Per-lineage binned expression trends along trajectory pseudotime.",
    if (!is.null(key_params$feature_set) && nzchar(as.character(key_params$feature_set))) paste0("Feature set: ", key_params$feature_set) else NULL,
    if (is.finite(n_feat_input) && is.finite(n_lin)) paste0("Input scope: ", n_feat_input, " features across ", n_lin, " lineages.") else NULL,
    if (is.finite(n_rows)) paste0("Trend rows: ", n_rows) else NULL,
    if (!is.null(key_params$summary_fun) && !is.null(key_params$n_bins)) paste0("Binning: ", key_params$n_bins, " bins, ", key_params$summary_fun, " per bin.") else NULL
  )

  list(
    agency = "trajectory_smooth",
    issuer_fields = list(
      matrix_id = key_params$matrix_id %||% NULL,
      feature_set = key_params$feature_set %||% NULL
    ),
    key_params = key_params,
    chips = unique(as.character(chips[nzchar(as.character(chips))])),
    summary_lines = summary_lines
  )
}

.wb_art_identity_card_issuer_trajectory_signature_smooth <- function(bc) {
  rd <- bc$persisted_provenance$run_details %||% list()
  run_obj <- rd$run %||% list()
  params <- run_obj$params %||% bc$inline_provenance$parsed$params %||% list()
  key_params <- .wb_idcard_pick_params(params, c("matrix_id", "feature_set", "score_method", "n_bins", "summary_fun", "min_cells_per_bin", "n_lineages", "n_features"))
  chips <- c(
    if (!is.null(key_params$matrix_id)) paste0("matrix:", key_params$matrix_id) else NULL,
    if (!is.null(key_params$feature_set)) paste0("feature_set:", key_params$feature_set) else NULL,
    if (!is.null(key_params$n_lineages)) paste0("lineages:", key_params$n_lineages) else NULL
  )
  summary_lines <- c(
    "Per-lineage feature-set signature trends along trajectory pseudotime.",
    if (!is.null(key_params$feature_set)) paste0("Feature set: ", key_params$feature_set) else NULL,
    if (!is.null(key_params$n_features) && !is.null(key_params$n_lineages)) paste0("Input scope: ", key_params$n_features, " features across ", key_params$n_lineages, " lineages.") else NULL,
    if (!is.null(key_params$score_method)) paste0("Signature score: ", key_params$score_method) else NULL,
    if (!is.null(key_params$n_bins) && !is.null(key_params$summary_fun)) paste0("Binning: ", key_params$n_bins, " bins, ", key_params$summary_fun, " per bin.") else NULL
  )
  list(
    agency = "trajectory_signature_smooth",
    issuer_fields = list(
      matrix_id = key_params$matrix_id %||% NULL,
      feature_set = key_params$feature_set %||% NULL
    ),
    key_params = key_params,
    chips = unique(as.character(chips[nzchar(as.character(chips))])),
    summary_lines = summary_lines
  )
}

.wb_art_identity_card_issuer_monocle3_fit <- function(bc) {
  rd <- bc$persisted_provenance$run_details %||% list()
  run_obj <- rd$run %||% list()
  params <- run_obj$params %||% bc$inline_provenance$parsed$params %||% list()
  key_params <- .wb_idcard_pick_params(params, c("fit_space_id", "cells_fit", "root_pr_nodes", "cluster_method", "k", "n_lineages"))
  chips <- c(
    "engine:monocle3",
    if (!is.null(key_params$fit_space_id)) paste0("fit_space:", key_params$fit_space_id) else NULL,
    if (!is.null(key_params$n_lineages)) paste0("lineages:", key_params$n_lineages) else NULL
  )
  summary_lines <- c(
    "Monocle3 trajectory fit model and derived pseudotime/branch membership.",
    if (!is.null(key_params$fit_space_id)) paste0("Fit space: ", key_params$fit_space_id) else NULL,
    if (!is.null(key_params$root_pr_nodes)) paste0("Root principal node: ", key_params$root_pr_nodes) else NULL,
    if (!is.null(key_params$cells_fit)) paste0("Cells fit: ", key_params$cells_fit) else NULL,
    if (!is.null(key_params$n_lineages)) paste0("Derived lineages: ", key_params$n_lineages) else NULL
  )
  list(
    agency = "monocle3_fit",
    issuer_fields = list(fit_space_id = key_params$fit_space_id %||% NULL),
    key_params = key_params,
    chips = unique(as.character(chips[nzchar(as.character(chips))])),
    summary_lines = summary_lines
  )
}

.wb_art_identity_card_issuer_monocle3_project <- function(bc) {
  rd <- bc$persisted_provenance$run_details %||% list()
  run_obj <- rd$run %||% list()
  params <- run_obj$params %||% bc$inline_provenance$parsed$params %||% list()
  key_params <- .wb_idcard_pick_params(params, c("fit_space_id", "plot_space_id", "cells_projected", "n_lineages", "approx_points"))
  chips <- c(
    "engine:monocle3",
    if (!is.null(key_params$plot_space_id)) paste0("plot_space:", key_params$plot_space_id) else NULL,
    if (!is.null(key_params$n_lineages)) paste0("lineages:", key_params$n_lineages) else NULL
  )
  summary_lines <- c(
    "Projected monocle3 lineage curves into a 2D display space.",
    if (!is.null(key_params$plot_space_id)) paste0("Display space: ", key_params$plot_space_id) else NULL,
    if (!is.null(key_params$fit_space_id)) paste0("Source fit space: ", key_params$fit_space_id) else NULL,
    if (!is.null(key_params$cells_projected)) paste0("Cells projected: ", key_params$cells_projected) else NULL,
    if (!is.null(key_params$approx_points)) paste0("Curve compaction target: ", key_params$approx_points, " points per lineage.") else NULL
  )
  list(
    agency = "monocle3_project",
    issuer_fields = list(plot_space_id = key_params$plot_space_id %||% NULL),
    key_params = key_params,
    chips = unique(as.character(chips[nzchar(as.character(chips))])),
    summary_lines = summary_lines
  )
}

.wb_art_identity_card_issuer_slingshot_fit <- function(bc) {
  rd <- bc$persisted_provenance$run_details %||% NULL
  run_obj <- rd$run %||% list()
  params <- run_obj$params %||% bc$inline_provenance$parsed$params %||% list()

  key_params <- .wb_idcard_pick_params(params, c(
    "fit_space_id", "start.clus", "stretch", "reweight", "shrink", "maxit",
    "n_lineages", "cells_in", "cells_after_exclude_cells", "cells_after_cluster_filter"
  ))
  # end.clus may be vector; keep as compact string if present.
  end_cl <- params$end.clus %||% NULL
  if (!is.null(end_cl)) {
    end_cl <- as.character(end_cl)
    end_cl <- end_cl[nzchar(end_cl)]
    if (length(end_cl)) key_params$end.clus <- paste(end_cl, collapse = ", ")
  }
  clusters_ref <- .wb_idcard_infer_input_ref(rd, "clusters")
  if (!is.null(clusters_ref)) key_params$clusters <- clusters_ref

  chips <- c(
    if (!is.null(key_params$fit_space_id)) paste0("fit_space:", key_params$fit_space_id) else NULL,
    if (!is.null(key_params$n_lineages)) paste0("lineages:", key_params$n_lineages) else NULL,
    if (!is.null(key_params$clusters)) "clusters:input" else NULL
  )

  summary_lines <- c(
    if (!is.null(key_params$fit_space_id)) paste0("Fit space: ", key_params$fit_space_id) else NULL,
    if (!is.null(key_params$clusters)) paste0("Clusters input: ", key_params$clusters) else NULL,
    if (!is.null(key_params$start.clus)) paste0("Start cluster: ", key_params$start.clus) else NULL,
    if (!is.null(key_params$end.clus)) paste0("End cluster(s): ", key_params$end.clus) else NULL,
    if (!is.null(key_params$n_lineages)) paste0("Lineages inferred: ", key_params$n_lineages) else NULL,
    if (!is.null(key_params$cells_after_cluster_filter)) paste0("Cells used: ", key_params$cells_after_cluster_filter) else NULL
  )

  list(
    agency = "slingshot_fit",
    issuer_fields = list(
      fit_space_id = key_params$fit_space_id %||% NULL,
      n_lineages = key_params$n_lineages %||% NULL
    ),
    key_params = key_params,
    chips = unique(as.character(chips[nzchar(as.character(chips))])),
    summary_lines = summary_lines
  )
}

.wb_art_identity_card_issuer_slingshot_project <- function(bc) {
  rd <- bc$persisted_provenance$run_details %||% NULL
  run_obj <- rd$run %||% list()
  params <- run_obj$params %||% bc$inline_provenance$parsed$params %||% list()

  key_params <- .wb_idcard_pick_params(params, c(
    "fit_space_id", "plot_space_id", "cells_projected", "n_lineages",
    "stretch", "shrink", "approx_points"
  ))
  model_ref <- .wb_idcard_infer_input_ref(rd, "model")
  if (!is.null(model_ref)) key_params$model <- model_ref

  chips <- c(
    if (!is.null(key_params$fit_space_id)) paste0("fit_space:", key_params$fit_space_id) else NULL,
    if (!is.null(key_params$plot_space_id)) paste0("plot_space:", key_params$plot_space_id) else NULL,
    if (!is.null(key_params$n_lineages)) paste0("lineages:", key_params$n_lineages) else NULL
  )

  summary_lines <- c(
    if (!is.null(key_params$model)) paste0("Model input: ", key_params$model) else NULL,
    if (!is.null(key_params$fit_space_id)) paste0("Fit space (from model): ", key_params$fit_space_id) else NULL,
    if (!is.null(key_params$plot_space_id)) paste0("Projected to 2D space: ", key_params$plot_space_id) else NULL,
    if (!is.null(key_params$cells_projected)) paste0("Cells projected: ", key_params$cells_projected) else NULL,
    if (!is.null(key_params$n_lineages)) paste0("Lineages projected: ", key_params$n_lineages) else NULL
  )

  list(
    agency = "slingshot_project",
    issuer_fields = list(
      fit_space_id = key_params$fit_space_id %||% NULL,
      plot_space_id = key_params$plot_space_id %||% NULL
    ),
    key_params = key_params,
    chips = unique(as.character(chips[nzchar(as.character(chips))])),
    summary_lines = summary_lines
  )
}

.wb_idcard_art_row_title <- function(row) {
  if (!is.data.frame(row) || !nrow(row)) return(NULL)
  nm <- as.character(row$name[1] %||% "")[1]
  aid <- as.character(row$artifact_id[1] %||% "")[1]
  ty <- as.character(row$type[1] %||% "")[1]
  sop <- as.character(row$source_op[1] %||% "")[1]
  title <- if (nzchar(nm)) nm else aid
  if (nzchar(ty)) title <- paste0(title, " [", ty, "]")
  if (nzchar(sop)) title <- paste0(title, " <", sop, ">")
  title
}

.wb_idcard_augment_slingshot_project_lineage <- function(bundle, bc, issued) {
  parents <- bc$parent_artifacts %||% NULL
  if (!is.data.frame(parents) || !nrow(parents)) return(issued)

  fit_rows <- parents[as.character(parents$source_op %||% "") == "slingshot_fit", , drop = FALSE]
  if (!nrow(fit_rows)) {
    # fallback: model artifact parent by type if source_op is missing/legacy
    fit_rows <- parents[as.character(parents$type %||% "") == "model_ref", , drop = FALSE]
  }
  if (!nrow(fit_rows)) return(issued)

  fit_row <- fit_rows[1, , drop = FALSE]
  fit_aid <- as.character(fit_row$artifact_id[1] %||% "")[1]
  fit_title <- .wb_idcard_art_row_title(fit_row)

  extra_lines <- character(0)
  extra_chips <- character(0)
  if (nzchar(fit_title %||% "")) {
    extra_lines <- c(extra_lines, paste0("Upstream slingshot fit artifact: ", fit_title))
    extra_chips <- c(extra_chips, "fit_artifact:yes")
  }

  # Optional second-hop lineage highlight: clustering artifact used by slingshot_fit (often leiden).
  if (nzchar(fit_aid)) {
    fit_bc <- try(
      wb_art_birth_certificate(
        bundle = bundle,
        artifact_id = fit_aid,
        include_parents = TRUE,
        include_children = FALSE,
        include_snapshot_run = TRUE
      ),
      silent = TRUE
    )
    if (!inherits(fit_bc, "try-error") && is.list(fit_bc)) {
      fit_par <- fit_bc$parent_artifacts %||% NULL
      if (is.data.frame(fit_par) && nrow(fit_par)) {
        cl_rows <- fit_par[as.character(fit_par$type %||% "") == "cell_vector", , drop = FALSE]
        if (nrow(cl_rows)) {
          # Prefer Leiden if present because that is the common trajectory clustering source.
          leid <- cl_rows[as.character(cl_rows$source_op %||% "") == "leiden", , drop = FALSE]
          cl_row <- if (nrow(leid)) leid[1, , drop = FALSE] else cl_rows[1, , drop = FALSE]
          cl_title <- .wb_idcard_art_row_title(cl_row)
          if (nzchar(cl_title %||% "")) {
            extra_lines <- c(extra_lines, paste0("Upstream clustering artifact: ", cl_title))
            cl_op <- as.character(cl_row$source_op[1] %||% "")[1]
            if (nzchar(cl_op)) extra_chips <- c(extra_chips, paste0("clusters_from:", cl_op))
          }
        }
      }
    }
  }

  if (length(extra_lines)) {
    issued$summary_lines <- unique(c(as.character(issued$summary_lines %||% character(0)), extra_lines))
  }
  if (length(extra_chips)) {
    issued$chips <- unique(c(as.character(issued$chips %||% character(0)), extra_chips))
  }
  issued
}

.wb_art_identity_card_issuers <- function() {
  list(
    pathway_enrich = .wb_art_identity_card_issuer_pathway_enrich,
    de_wilcox = .wb_art_identity_card_issuer_de_wilcox,
    trajectory_de = .wb_art_identity_card_issuer_trajectory_de,
    trajectory_smooth = .wb_art_identity_card_issuer_trajectory_smooth,
    trajectory_signature_smooth = .wb_art_identity_card_issuer_trajectory_signature_smooth,
    monocle3_fit = .wb_art_identity_card_issuer_monocle3_fit,
    monocle3_project = .wb_art_identity_card_issuer_monocle3_project,
    slingshot_fit = .wb_art_identity_card_issuer_slingshot_fit,
    slingshot_project = .wb_art_identity_card_issuer_slingshot_project
  )
}

#' Artifact Identity Card (Compact Provenance View)
#'
#' Builds a compact, human-facing identity card from `wb_art_birth_certificate()`.
#' Uses registry-based issuer dispatch by `source_op`, with a default fallback.
#'
#' @param bundle scworkbench bundle handle
#' @param artifact_id artifact id
#' @param include_birth_certificate If TRUE, attach full birth certificate under `birth_certificate`
#' @return named list identity card payload
#' @export
wb_art_identity_card <- function(bundle,
                                 artifact_id,
                                 include_birth_certificate = FALSE) {
  bc <- wb_art_birth_certificate(
    bundle = bundle,
    artifact_id = artifact_id,
    include_parents = TRUE,
    include_children = FALSE,
    include_snapshot_run = TRUE
  )

  id <- bc$identity %||% list()
  rd <- bc$persisted_provenance$run_details %||% NULL
  sel_link <- bc$persisted_provenance$selected_link %||% NULL
  op_name <- as.character(id$source_op %||% "")[1]
  issuers <- .wb_art_identity_card_issuers()
  issuer_fn <- issuers[[op_name]] %||% .wb_art_identity_card_default_issuer
  issued <- try(issuer_fn(bc), silent = TRUE)
  if (inherits(issued, "try-error") || !is.list(issued)) {
    issued <- .wb_art_identity_card_default_issuer(bc)
    bc$warnings <- unique(c(as.character(bc$warnings %||% character(0)), paste0("Identity-card issuer failed for op: ", op_name)))
  }
  if (identical(op_name, "slingshot_project")) {
    issued2 <- try(.wb_idcard_augment_slingshot_project_lineage(bundle, bc, issued), silent = TRUE)
    if (!inherits(issued2, "try-error") && is.list(issued2)) {
      issued <- issued2
    } else {
      bc$warnings <- unique(c(as.character(bc$warnings %||% character(0)), "Slingshot lineage highlight augmentation failed."))
    }
  }

  upstream_rows <- .wb_idcard_compact_ref_rows(bc$parent_artifacts %||% NULL, n = 8L)

  core <- list(
    artifact_id = as.character(id$artifact_id %||% "")[1],
    name = as.character(id$name %||% "")[1],
    type = as.character(id$type %||% "")[1],
    source_op = as.character(id$source_op %||% "")[1],
    created_at = as.character(id$created_at %||% "")[1],
    created_by = as.character(id$created_by %||% "")[1],
    input_matrix_id = .wb_idcard_null_if_empty_chr(id$input_matrix_id),
    input_space_id = .wb_idcard_null_if_empty_chr(id$input_space_id),
    cell_set = .wb_idcard_null_if_empty_chr(id$cell_set),
    lineage_status = .wb_idcard_null_if_empty_chr(id$lineage_status),
    run_id = if (is.list(rd)) as.character(rd$run$run_id %||% "")[1] else .wb_idcard_null_if_empty_chr(bc$inline_provenance$parsed$run_id %||% NULL),
    snapshot_id = if (is.data.frame(sel_link) && nrow(sel_link)) as.character(sel_link$snapshot_id[1]) else .wb_idcard_null_if_empty_chr(id$provenance_snapshot_id),
    output_name = if (is.data.frame(sel_link) && nrow(sel_link)) as.character(sel_link$output_name[1]) else NULL
  )

  title <- if (nzchar(core$name %||% "")) core$name else core$artifact_id
  subtitle_bits <- c(core$type, core$source_op, core$created_at)
  subtitle_bits <- subtitle_bits[vapply(subtitle_bits, function(z) !is.null(z) && nzchar(as.character(z)[1]), logical(1))]
  display <- list(
    title = title,
    subtitle = paste(subtitle_bits, collapse = " | "),
    chips = unique(as.character(c(
      issued$chips %||% character(0),
      if (nzchar(as.character(core$lineage_status %||% "")[1])) paste0("lineage:", as.character(core$lineage_status)[1]) else NULL
    ))),
    summary_lines = as.character(issued$summary_lines %||% character(0))
  )

  out <- list(
    schema = "artifact_identity_card_v1",
    core = core,
    issuer = list(
      agency = as.character(issued$agency %||% "default")[1],
      issuer_fields = issued$issuer_fields %||% list(),
      key_params = issued$key_params %||% list()
    ),
    upstream = list(
      n = if (is.data.frame(bc$parent_artifacts)) nrow(bc$parent_artifacts) else 0L,
      artifacts = upstream_rows
    ),
    display = display,
    warnings = unique(as.character(c(bc$warnings %||% character(0), issued$warnings %||% character(0))))
  )
  if (isTRUE(include_birth_certificate)) out$birth_certificate <- bc
  out
}

.wb_art_parse_prov_json <- function(provenance_json) {
  txt <- as.character(provenance_json %||% "")[1]
  if (!nzchar(txt)) return(NULL)
  if (!requireNamespace("jsonlite", quietly = TRUE)) return(NULL)
  obj <- try(jsonlite::fromJSON(txt, simplifyVector = FALSE), silent = TRUE)
  if (inherits(obj, "try-error")) return(NULL)
  obj
}

.wb_art_row_one <- function(bundle, artifact_id) {
  arts <- wb_art_list(bundle, include_history = TRUE)
  if (!is.data.frame(arts) || !nrow(arts)) return(arts[0, , drop = FALSE])
  hit <- arts[as.character(arts$artifact_id) == as.character(artifact_id)[1], , drop = FALSE]
  if (nrow(hit) > 1L) hit <- hit[1, , drop = FALSE]
  rownames(hit) <- NULL
  hit
}

#' Artifact Birth Certificate (Full Provenance Record)
#'
#' Returns a reconstruction-oriented provenance record for one promoted artifact.
#' This is the engine-side "birth certificate" that clients can render as a compact
#' identity card or detailed provenance view.
#'
#' The function reuses inline `artifacts.provenance_json` and, when available,
#' links to persisted provenance snapshots (`prov_*` tables) to recover richer
#' run details (`symbolic_inputs`, `execution_inputs`, outputs).
#'
#' @param bundle scworkbench bundle handle
#' @param artifact_id artifact id
#' @param include_parents If TRUE, attach upstream artifact rows
#' @param include_children If TRUE, attach downstream artifact rows
#' @param include_snapshot_run If TRUE, attach persisted provenance run details when available
#' @return named list birth certificate payload
#' @export
wb_art_birth_certificate <- function(bundle,
                                     artifact_id,
                                     include_parents = TRUE,
                                     include_children = FALSE,
                                     include_snapshot_run = TRUE) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  aid <- as.character(artifact_id)[1]
  .wb_assert(nzchar(aid), "artifact_id must be a non-empty string")

  wb_migrate_artifacts(bundle)
  con <- bundle$con
  art <- .wb_art_row_one(bundle, aid)
  .wb_assert(is.data.frame(art) && nrow(art) == 1L, paste0("Artifact not found: ", aid))

  prov_obj <- .wb_art_parse_prov_json(art$provenance_json[1] %||% "")
  parent_ids <- .wb_art_refs_from_prov_json(art$provenance_json[1] %||% "")
  parent_ids <- unique(as.character(parent_ids[parent_ids != aid]))

  parents_df <- data.frame(stringsAsFactors = FALSE)
  if (isTRUE(include_parents) && length(parent_ids)) {
    arts <- wb_art_list(bundle, include_history = TRUE)
    parents_df <- arts[match(parent_ids, as.character(arts$artifact_id)), , drop = FALSE]
    parents_df <- parents_df[!is.na(parents_df$artifact_id), , drop = FALSE]
    rownames(parents_df) <- NULL
  } else if (isTRUE(include_parents)) {
    parents_df <- art[0, , drop = FALSE]
  }

  children_df <- data.frame(stringsAsFactors = FALSE)
  if (isTRUE(include_children)) {
    kids <- wb_art_dependencies(bundle, artifact_id = aid, direction = "children", recursive = FALSE)
    if (is.data.frame(kids) && nrow(kids)) {
      arts <- wb_art_list(bundle, include_history = TRUE)
      children_df <- arts[match(as.character(kids$artifact_id), as.character(arts$artifact_id)), , drop = FALSE]
      children_df <- children_df[!is.na(children_df$artifact_id), , drop = FALSE]
      rownames(children_df) <- NULL
    } else {
      children_df <- art[0, , drop = FALSE]
    }
  }

  # Try to link artifact -> persisted provenance run/output (if snapshot tables exist).
  prov_link_rows <- data.frame(
    snapshot_id = character(0),
    run_id = character(0),
    output_name = character(0),
    primitive_kind = character(0),
    output_hash = character(0), structural_fingerprint = character(0), content_sha256 = character(0), verification_level = character(0), verification_status = character(0),
    op_name = character(0),
    created_at = character(0),
    stringsAsFactors = FALSE
  )
  source_run_details <- NULL
  source_run_pick <- NULL
  warnings <- character(0)

  if (isTRUE(include_snapshot_run) && .wb_table_exists(con, "prov_run_outputs")) {
    .wb_migrate_provenance_tables(con)

    has_runs <- .wb_table_exists(con, "prov_runs")
    if (isTRUE(has_runs)) {
      prov_link_rows <- DBI::dbGetQuery(
        con,
        paste0("SELECT o.snapshot_id, o.run_id, o.output_name, o.primitive_kind, o.output_hash, ",
               .wb_prov_output_identity_select(con, "o"), ", r.op_name, r.created_at FROM prov_run_outputs o LEFT JOIN prov_runs r ON r.snapshot_id = o.snapshot_id AND r.run_id = o.run_id WHERE o.artifact_id = ? ORDER BY r.created_at DESC, o.snapshot_id DESC, o.run_id DESC, o.output_name ASC;"),
        params = list(aid)
      )
    }

    if (nrow(prov_link_rows)) {
      inline_run_id <- as.character(prov_obj$run_id %||% "")[1]
      inline_op_name <- as.character(prov_obj$op_name %||% "")[1]

      pick_idx <- seq_len(nrow(prov_link_rows))
      if (nzchar(inline_run_id)) {
        hit <- which(as.character(prov_link_rows$run_id) == inline_run_id)
        if (length(hit)) pick_idx <- hit
      }
      if (nzchar(inline_op_name) && length(pick_idx) > 1L) {
        hit2 <- pick_idx[as.character(prov_link_rows$op_name[pick_idx]) == inline_op_name]
        if (length(hit2)) pick_idx <- hit2
      }
      pick <- pick_idx[1]
      source_run_pick <- prov_link_rows[pick, , drop = FALSE]

      det <- try(
        wb_prov_run_details(
          bundle,
          run_id = as.character(source_run_pick$run_id[1]),
          snapshot_id = as.character(source_run_pick$snapshot_id[1])
        ),
        silent = TRUE
      )
      if (!inherits(det, "try-error")) {
        source_run_details <- det
      } else {
        warnings <- c(warnings, paste0("Failed to load persisted run details for artifact ", aid, "."))
      }
    }
  }

  lifecycle <- wb_entity_lifecycle(bundle, entity_kind = "artifact", entity_id = aid)
  supersessions <- wb_entity_supersessions(bundle)
  if (is.data.frame(supersessions) && nrow(supersessions)) {
    supersessions <- supersessions[
      (supersessions$successor_kind == "artifact" & supersessions$successor_id == aid) |
        (supersessions$predecessor_kind == "artifact" & supersessions$predecessor_id == aid),
      , drop = FALSE
    ]
  }

  list(
    schema = "artifact_birth_certificate_v1",
    artifact = art[1, , drop = FALSE],
    identity = list(
      artifact_id = as.character(art$artifact_id[1]),
      name = as.character(art$name[1] %||% ""),
      type = as.character(art$type[1] %||% ""),
      source_op = as.character(art$source_op[1] %||% ""),
      created_at = as.character(art$created_at[1] %||% ""),
      created_by = as.character(art$created_by[1] %||% ""),
      input_matrix_id = as.character(art$input_matrix_id[1] %||% ""),
      input_space_id = as.character(art$input_space_id[1] %||% ""),
      cell_set = as.character(art$cell_set[1] %||% ""),
      provenance_snapshot_id = as.character(art$provenance_snapshot_id[1] %||% ""),
      lineage_status = as.character(art$lineage_status[1] %||% "")
    ),
    lifecycle = list(
      state = as.character(lifecycle$lifecycle_state[1] %||% "current"),
      provenance_bound = as.integer(lifecycle$provenance_bound[1] %||% 0L),
      record = lifecycle,
      supersessions = supersessions
    ),
    inline_provenance = list(
      parsed = prov_obj,
      parent_artifact_ids = parent_ids
    ),
    parent_artifacts = if (isTRUE(include_parents)) parents_df else NULL,
    child_artifacts = if (isTRUE(include_children)) children_df else NULL,
    persisted_provenance = list(
      links = prov_link_rows,
      selected_link = source_run_pick,
      run_details = source_run_details
    ),
    warnings = unique(warnings)
  )
}

.wb_art_refs_from_prov_json <- function(provenance_json) {
  txt <- as.character(provenance_json %||% "")[1]
  if (!nzchar(txt)) return(character(0))
  if (!requireNamespace("jsonlite", quietly = TRUE)) return(character(0))

  obj <- try(jsonlite::fromJSON(txt, simplifyVector = FALSE), silent = TRUE)
  if (inherits(obj, "try-error")) return(character(0))

  refs <- character(0)
  rec_refs <- function(x, allow_plain = FALSE) {
    if (is.null(x)) return(invisible(NULL))

    if (is.character(x) && isTRUE(allow_plain)) {
      vals <- as.character(x)
      refs <<- c(refs, vals[nzchar(vals)])
      return(invisible(NULL))
    }

    if (!is.list(x)) return(invisible(NULL))

    rt <- as.character(x$ref_type %||% "")[1]
    aid <- as.character(x$artifact_id %||% "")[1]
    if ((identical(rt, "artifact") || !nzchar(rt)) && nzchar(aid)) {
      refs <<- c(refs, aid)
      return(invisible(NULL))
    }

    if (length(x)) {
      child_plain <- is.null(names(x)) || !any(nzchar(names(x)))
      for (i in seq_along(x)) rec_refs(x[[i]], allow_plain = child_plain)
    }
    invisible(NULL)
  }

  if (!is.null(obj$parent_artifacts)) rec_refs(obj$parent_artifacts, allow_plain = TRUE)
  if (!is.null(obj$inputs$provenance_refs)) rec_refs(obj$inputs$provenance_refs, allow_plain = TRUE)
  unique(refs[nzchar(refs)])
}

.wb_art_dependency_edges <- function(bundle) {
  arts <- wb_art_list(bundle, include_history = TRUE)
  if (!is.data.frame(arts) || nrow(arts) == 0) {
    return(data.frame(
      parent_artifact_id = character(0),
      child_artifact_id = character(0),
      stringsAsFactors = FALSE
    ))
  }

  out <- list()
  k <- 0L
  for (i in seq_len(nrow(arts))) {
    child <- as.character(arts$artifact_id[i])
    parents <- .wb_art_refs_from_prov_json(arts$provenance_json[i] %||% "")
    if (!length(parents)) next
    for (p in parents) {
      k <- k + 1L
      out[[k]] <- data.frame(
        parent_artifact_id = as.character(p),
        child_artifact_id = child,
        stringsAsFactors = FALSE
      )
    }
  }

  if (!length(out)) {
    return(data.frame(
      parent_artifact_id = character(0),
      child_artifact_id = character(0),
      stringsAsFactors = FALSE
    ))
  }

  unique(do.call(rbind, out))
}

.wb_art_neighbors <- function(edges, artifact_id, direction = c("children", "parents")) {
  direction <- match.arg(direction)
  artifact_id <- as.character(artifact_id)[1]
  if (!nrow(edges) || !nzchar(artifact_id)) return(character(0))
  if (identical(direction, "children")) {
    return(unique(as.character(edges$child_artifact_id[edges$parent_artifact_id == artifact_id])))
  }
  unique(as.character(edges$parent_artifact_id[edges$child_artifact_id == artifact_id]))
}

#' Get artifact dependencies
#'
#' Returns artifacts connected to `artifact_id` in the provenance dependency graph.
#'
#' @param bundle scworkbench bundle handle
#' @param artifact_id root artifact id
#' @param direction dependency direction: `children` (dependents) or `parents` (upstream refs)
#' @param recursive if TRUE, returns transitive closure; otherwise direct neighbors only
#' @return data.frame with columns root_artifact_id, artifact_id, type, distance, direction
#' @export
wb_art_dependencies <- function(bundle,
                                artifact_id,
                                direction = c("children", "parents"),
                                recursive = TRUE) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  artifact_id <- as.character(artifact_id)[1]
  .wb_assert(nzchar(artifact_id), "artifact_id must be a non-empty string")

  direction <- match.arg(direction)
  wb_migrate_artifacts(bundle)

  arts <- wb_art_list(bundle, include_history = TRUE)
  hit <- arts[arts$artifact_id == artifact_id, , drop = FALSE]
  .wb_assert(nrow(hit) == 1, paste0("Artifact not found: ", artifact_id))

  edges <- .wb_art_dependency_edges(bundle)
  neigh <- function(aid) .wb_art_neighbors(edges, aid, direction = direction)
  type_of <- function(ids) {
    idx <- match(ids, as.character(arts$artifact_id))
    out <- as.character(arts$type[idx])
    out[is.na(out)] <- NA_character_
    out
  }

  if (!isTRUE(recursive)) {
    deps <- neigh(artifact_id)
    if (!length(deps)) {
      return(data.frame(
        root_artifact_id = character(0),
        artifact_id = character(0),
        type = character(0),
        distance = integer(0),
        direction = character(0),
        stringsAsFactors = FALSE
      ))
    }
    return(data.frame(
      root_artifact_id = rep(artifact_id, length(deps)),
      artifact_id = deps,
      type = type_of(deps),
      distance = rep(1L, length(deps)),
      direction = rep(direction, length(deps)),
      stringsAsFactors = FALSE
    ))
  }

  seen <- setNames(logical(0), character(0))
  queue_id <- character(0)
  queue_dist <- integer(0)
  out <- list()
  k <- 0L

  seed <- neigh(artifact_id)
  if (length(seed)) {
    queue_id <- seed
    queue_dist <- rep.int(1L, length(seed))
  }

  while (length(queue_id) > 0) {
    cur <- queue_id[[1]]
    d <- queue_dist[[1]]
    queue_id <- queue_id[-1]
    queue_dist <- queue_dist[-1]
    if (cur %in% names(seen) && isTRUE(seen[[cur]])) next
    seen[cur] <- TRUE

    k <- k + 1L
    out[[k]] <- data.frame(
      root_artifact_id = artifact_id,
      artifact_id = cur,
      type = type_of(cur),
      distance = as.integer(d),
      direction = direction,
      stringsAsFactors = FALSE
    )

    nxt <- neigh(cur)
    if (length(nxt)) {
      nxt <- nxt[!vapply(nxt, function(z) z %in% names(seen) && isTRUE(seen[[z]]), logical(1))]
      if (length(nxt)) {
        queue_id <- c(queue_id, nxt)
        queue_dist <- c(queue_dist, rep.int(as.integer(d + 1L), length(nxt)))
      }
    }
  }

  if (!length(out)) {
    return(data.frame(
      root_artifact_id = character(0),
      artifact_id = character(0),
      type = character(0),
      distance = integer(0),
      direction = character(0),
      stringsAsFactors = FALSE
    ))
  }
  do.call(rbind, out)
}

#' Build artifact retraction plan
#'
#' Computes what `wb_art_delete()` will tombstone without deleting evidence.
#'
#' @param bundle scworkbench bundle handle
#' @param artifact_id root artifact id
#' @param recursive if TRUE, includes dependent artifacts in delete order
#' @return list with fields: `plan` (data.frame), `blocked_by` (data.frame), and
#'   compatibility field `can_delete` (always `TRUE`; no physical deletion occurs).
#' @export
wb_art_delete_plan <- function(bundle, artifact_id, recursive = FALSE) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  artifact_id <- as.character(artifact_id)[1]
  .wb_assert(nzchar(artifact_id), "artifact_id must be a non-empty string")

  wb_migrate_artifacts(bundle)
  arts <- wb_art_list(bundle, include_history = TRUE)
  hit <- arts[arts$artifact_id == artifact_id, , drop = FALSE]
  .wb_assert(nrow(hit) == 1, paste0("Artifact not found: ", artifact_id))

  direct_children <- wb_art_dependencies(
    bundle = bundle,
    artifact_id = artifact_id,
    direction = "children",
    recursive = FALSE
  )

  blocked <- if (nrow(direct_children)) direct_children else direct_children[0, , drop = FALSE]
  can_delete <- TRUE

  edges <- .wb_art_dependency_edges(bundle)
  children_of <- function(aid) .wb_art_neighbors(edges, aid, direction = "children")
  type_of <- function(ids) {
    idx <- match(ids, as.character(arts$artifact_id))
    out <- as.character(arts$type[idx])
    out[is.na(out)] <- NA_character_
    out
  }

  order <- character(0)
  depth <- integer(0)
  seen <- new.env(parent = emptyenv())
  visit <- function(aid, d = 0L) {
    aid <- as.character(aid)[1]
    if (!nzchar(aid)) return(invisible(NULL))
    if (exists(aid, envir = seen, inherits = FALSE)) return(invisible(NULL))
    assign(aid, TRUE, envir = seen)
    if (isTRUE(recursive)) {
      kids <- children_of(aid)
      for (k in kids) visit(k, d + 1L)
    }
    order <<- c(order, aid)
    depth <<- c(depth, as.integer(d))
    invisible(NULL)
  }
  visit(artifact_id, 0L)

  plan <- data.frame(
    artifact_id = order,
    type = type_of(order),
    depth = depth,
    delete_order = seq_along(order),
    requested = order == artifact_id,
    action = "retract",
    stringsAsFactors = FALSE
  )

  list(
    artifact_id = artifact_id,
    recursive = isTRUE(recursive),
    can_delete = can_delete,
    blocked_by = blocked,
    plan = plan
  )
}

.wb_art_delete_payload <- function(con, artifact_id, type, remove_model_file = FALSE, model_file_only_if_unique = TRUE, bundle = NULL) {
  artifact_id <- as.character(artifact_id)[1]
  type <- as.character(type)[1]
  model_path <- NA_character_
  model_removed <- FALSE

  if (identical(type, "cell_vector")) {
    DBI::dbExecute(con, "DELETE FROM artifact_labels WHERE artifact_id = ?;", params = list(artifact_id))
  } else if (identical(type, "cell_vector_family")) {
    DBI::dbExecute(con, "DELETE FROM artifact_pseudotime WHERE artifact_id = ?;", params = list(artifact_id))
  } else if (identical(type, "path_2d_family")) {
    DBI::dbExecute(con, "DELETE FROM artifact_curves_2d WHERE artifact_id = ?;", params = list(artifact_id))
  } else if (identical(type, "space_path_family")) {
    DBI::dbExecute(con, "DELETE FROM artifact_space_path_rows WHERE artifact_id = ?;", params = list(artifact_id))
    DBI::dbExecute(con, "DELETE FROM artifact_space_path_meta WHERE artifact_id = ?;", params = list(artifact_id))
  } else if (identical(type, "space_2d")) {
    DBI::dbExecute(con, "DELETE FROM artifact_space_2d WHERE artifact_id = ?;", params = list(artifact_id))
  } else if (identical(type, "umap_model")) {
    row <- DBI::dbGetQuery(
      con,
      "SELECT model_path FROM artifact_umap_model WHERE artifact_id = ?;",
      params = list(artifact_id)
    )
    if (nrow(row) == 1) model_path <- as.character(row$model_path[1] %||% NA_character_)
    DBI::dbExecute(con, "DELETE FROM artifact_umap_model WHERE artifact_id = ?;", params = list(artifact_id))

    if (isTRUE(remove_model_file) && !is.na(model_path) && nzchar(model_path) && file.exists(model_path)) {
      can_remove <- TRUE
      if (isTRUE(model_file_only_if_unique)) {
        n_other <- DBI::dbGetQuery(
          con,
          "SELECT COUNT(*) AS n FROM artifact_umap_model WHERE model_path = ?;",
          params = list(model_path)
        )$n[[1]] %||% 0L
        can_remove <- as.integer(n_other) == 0L
      }
      if (can_remove) {
        model_removed <- isTRUE(file.remove(model_path))
      }
    }
  } else if (identical(type, "model_ref")) {
    row <- DBI::dbGetQuery(
      con,
      "SELECT model_path FROM artifact_model_ref WHERE artifact_id = ?;",
      params = list(artifact_id)
    )
    stored_model_path <- NA_character_
    if (nrow(row) == 1) {
      stored_model_path <- as.character(row$model_path[1] %||% NA_character_)
      model_path <- stored_model_path
      if (!is.null(bundle) && !is.na(stored_model_path) && nzchar(stored_model_path)) {
        model_path <- tryCatch(.wb_resolve_model_ref_path(bundle, stored_model_path), error = function(e) stored_model_path)
      }
    }
    DBI::dbExecute(con, "DELETE FROM artifact_model_ref WHERE artifact_id = ?;", params = list(artifact_id))

    if (isTRUE(remove_model_file) && !is.na(model_path) && nzchar(model_path) && file.exists(model_path)) {
      can_remove <- TRUE
      if (isTRUE(model_file_only_if_unique)) {
        candidate_paths <- unique(c(
          stored_model_path,
          if (!is.null(bundle) && !is.na(model_path) && nzchar(model_path)) .wb_model_ref_bundle_relative_path(bundle, model_path) else NA_character_,
          model_path
        ))
        candidate_paths <- candidate_paths[!is.na(candidate_paths) & nzchar(candidate_paths)]
        n_other <- DBI::dbGetQuery(
          con,
          paste0(
            "SELECT COUNT(*) AS n FROM artifact_model_ref WHERE model_path IN (",
            paste(rep("?", length(candidate_paths)), collapse = ","),
            ");"
          ),
          params = as.list(candidate_paths)
        )$n[[1]] %||% 0L
        can_remove <- as.integer(n_other) == 0L
      }
      if (can_remove) {
        model_removed <- isTRUE(file.remove(model_path))
      }
    }
  } else if (type %in% c("feature_table", "obs_table")) {
    DBI::dbExecute(con, "DELETE FROM artifact_table_rows WHERE artifact_id = ?;", params = list(artifact_id))
    DBI::dbExecute(con, "DELETE FROM artifact_tables WHERE artifact_id = ?;", params = list(artifact_id))
  }

  DBI::dbExecute(con, "DELETE FROM artifacts WHERE artifact_id = ?;", params = list(artifact_id))

  list(model_path = model_path, model_file_removed = isTRUE(model_removed))
}

#' Retract promoted artifact(s)
#'
#' Compatibility wrapper for the former destructive deletion API. It now writes
#' lifecycle tombstones and retains every payload, birth certificate, and
#' provenance link. `recursive=TRUE` retracts dependent artifacts too.
#'
#' @param bundle scworkbench bundle handle
#' @param artifact_id artifact id to delete
#' @param recursive if TRUE, also delete artifacts that depend on this one
#' @param force Deprecated destructive-delete flag. `TRUE` is rejected.
#' @param remove_model_file Deprecated destructive-delete flag. `TRUE` is rejected.
#' @param model_file_only_if_unique Retained for signature compatibility; no
#'   model file is removed.
#' @return data.frame summary of retracted artifacts in dependency order
#' @export
wb_art_delete <- function(bundle,
                          artifact_id,
                          recursive = FALSE,
                          force = FALSE,
                          remove_model_file = FALSE,
                          model_file_only_if_unique = TRUE) {
  .wb_assert_bundle_writable(bundle, "artifact retraction")
  .wb_with_bundle_writer_lock(bundle, operation = "artifact retraction", code = {
    .wb_art_delete_locked(
      bundle, artifact_id, recursive = recursive, force = force,
      remove_model_file = remove_model_file,
      model_file_only_if_unique = model_file_only_if_unique
    )
  })
}

.wb_art_delete_locked <- function(bundle,
                                  artifact_id,
                                  recursive = FALSE,
                                  force = FALSE,
                                  remove_model_file = FALSE,
                                  model_file_only_if_unique = TRUE) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  artifact_id <- as.character(artifact_id)[1]
  .wb_assert(nzchar(artifact_id), "artifact_id must be a non-empty string")
  .wb_assert(!isTRUE(force), "force=TRUE physical artifact deletion was removed. Retract normally, or use the verified unsafe ephemeral purge API.")
  .wb_assert(!isTRUE(remove_model_file), "remove_model_file=TRUE was removed because promoted model evidence is immutable.")

  wb_migrate_artifacts(bundle)
  plan <- wb_art_delete_plan(bundle, artifact_id = artifact_id, recursive = isTRUE(recursive))

  order <- as.character(plan$plan$artifact_id %||% character(0))
  if (!isTRUE(recursive)) order <- order[seq_len(min(length(order), 1L))]
  arts <- wb_art_list(bundle, include_history = TRUE)
  rows <- list()
  old_transaction <- getOption("scworkbench.registry_replay_transaction_open")
  options(scworkbench.registry_replay_transaction_open = TRUE)
  on.exit(options(scworkbench.registry_replay_transaction_open = old_transaction), add = TRUE)
  DBI::dbWithTransaction(bundle$con, {
    rows <- lapply(order, function(aid) {
      row <- arts[arts$artifact_id == aid, , drop = FALSE]
      if (!nrow(row)) return(NULL)
      state <- as.character(row$lifecycle_state[1] %||% "current")
      if (state %in% c("superseded", "retracted", "rejected")) {
        return(data.frame(artifact_id = aid, type = as.character(row$type[1]), action = paste0("already_", state),
          model_path = NA_character_, model_file_removed = FALSE, stringsAsFactors = FALSE))
      }
      wb_entity_retract(bundle, "artifact", aid, reason = "Retracted through wb_art_delete() compatibility API.")
      data.frame(artifact_id = aid, type = as.character(row$type[1]), action = "retracted",
        model_path = NA_character_, model_file_removed = FALSE, stringsAsFactors = FALSE)
    })
  })
  rows <- Filter(Negate(is.null), rows)
  if (!length(rows)) return(data.frame(artifact_id = character(), type = character(), action = character(),
    model_path = character(), model_file_removed = logical(), stringsAsFactors = FALSE))
  out <- do.call(rbind, rows); rownames(out) <- NULL; out
}
