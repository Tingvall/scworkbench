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

.wb_art_parse_prov_json <- function(provenance_json) {
  txt <- as.character(provenance_json %||% "")[1]
  if (!nzchar(txt)) return(NULL)
  if (!requireNamespace("jsonlite", quietly = TRUE)) return(NULL)
  obj <- try(jsonlite::fromJSON(txt, simplifyVector = FALSE), silent = TRUE)
  if (inherits(obj, "try-error")) return(NULL)
  obj
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
    if (.wb_table_exists(con, "artifact_space_2d")) {
      DBI::dbExecute(con, "DELETE FROM artifact_space_2d WHERE artifact_id = ?;", params = list(artifact_id))
    }
  } else if (identical(type, "umap_model")) {
    row <- DBI::dbGetQuery(
      con,
      "SELECT model_path FROM artifact_umap_model WHERE artifact_id = ?;",
      params = list(artifact_id)
    )
    stored_model_path <- NA_character_
    if (nrow(row) == 1) {
      stored_model_path <- as.character(row$model_path[1] %||% NA_character_)
      model_path <- stored_model_path
    }
    DBI::dbExecute(con, "DELETE FROM artifact_umap_model WHERE artifact_id = ?;", params = list(artifact_id))

    checked_model <- if (!is.null(bundle) && !is.na(stored_model_path) && nzchar(stored_model_path)) {
      .wb_path_status(bundle$dir, stored_model_path, expected_type="either", must_exist=TRUE,
                      purpose="UMAP artifact model deletion")
    } else list(ok=FALSE)
    if (isTRUE(remove_model_file) && isTRUE(checked_model$ok)) {
      model_path <- checked_model$absolute
      can_remove <- TRUE
      if (isTRUE(model_file_only_if_unique)) {
        n_other <- DBI::dbGetQuery(
          con,
          "SELECT COUNT(*) AS n FROM artifact_umap_model WHERE model_path = ?;",
          params = list(stored_model_path)
        )$n[[1]] %||% 0L
        can_remove <- as.integer(n_other) == 0L
      }
      if (can_remove) {
        if (dir.exists(model_path)) {
          unlink(model_path, recursive=TRUE, force=TRUE)
          model_removed <- !dir.exists(model_path) && !file.exists(model_path)
        } else model_removed <- isTRUE(file.remove(model_path))
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

    checked_model <- if (!is.null(bundle) && !is.na(stored_model_path) && nzchar(stored_model_path)) {
      .wb_path_status(bundle$dir, stored_model_path, expected_type="either", must_exist=TRUE,
                      purpose="model_ref artifact deletion")
    } else list(ok=FALSE)
    if (isTRUE(remove_model_file) && isTRUE(checked_model$ok)) {
      model_path <- checked_model$absolute
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
        if (dir.exists(model_path)) {
          unlink(model_path, recursive=TRUE, force=TRUE)
          model_removed <- !dir.exists(model_path) && !file.exists(model_path)
        } else model_removed <- isTRUE(file.remove(model_path))
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
