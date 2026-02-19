# R/artifacts_load.R
# Load a promoted artifact back into a wb_primitive (kind-safe),
# using the *existing* migrate schema (no payload_json column needed).

# ---- Main loader ----
#' Load a promoted artifact as a primitive
#' @export
wb_art_load <- function(bundle, artifact_id, expected_kind = NULL) {
  con <- bundle$con
  .wb_assert(!is.null(con), "wb_art_load(): bundle$con is NULL (no DB connection).")
  artifact_id <- as.character(artifact_id)
  .wb_assert(nzchar(artifact_id), "wb_art_load(): artifact_id must be a non-empty string.")

  art <- DBI::dbGetQuery(
    con,
    "SELECT artifact_id, type, name, source_op, input_space_id, input_matrix_id,
            cell_set, provenance_json
     FROM artifacts
     WHERE artifact_id = ?;",
    params = list(artifact_id)
  )
  .wb_assert(nrow(art) == 1, paste0("wb_art_load(): artifact not found: ", artifact_id))

  type <- as.character(art$type[[1]])

  # Reconstruct primitive by type
  prim <- switch(
    type,

    # ---- cell_vector stored as artifact_labels (cell_id, label) ----
    "cell_vector" = {
      df <- DBI::dbGetQuery(
        con,
        "SELECT cell_id, label
         FROM artifact_labels
         WHERE artifact_id = ?;",
        params = list(artifact_id)
      )
      .wb_assert(nrow(df) > 0, paste0("wb_art_load(): no rows in artifact_labels for ", artifact_id))

      v <- as.character(df$label)
      names(v) <- as.character(df$cell_id)
      wb_prim_cell_vector(v, value_type = "categorical")
    },

    # ---- cell_vector_family stored as artifact_pseudotime (cell_id, lineage_id, pseudotime) ----
    "cell_vector_family" = {
      df <- DBI::dbGetQuery(
        con,
        "SELECT cell_id, lineage_id, pseudotime
         FROM artifact_pseudotime
         WHERE artifact_id = ?;",
        params = list(artifact_id)
      )
      .wb_assert(nrow(df) > 0, paste0("wb_art_load(): no rows in artifact_pseudotime for ", artifact_id))

      wb_prim_cell_vector_family(
        key = df$lineage_id,
        cell_id = df$cell_id,
        value = df$pseudotime,
        value_type = "continuous"
      )
    },

    # ---- path_2d_family stored as artifact_curves_2d (lineage_id, point, x, y) ----
    "path_2d_family" = {
      df <- DBI::dbGetQuery(
        con,
        "SELECT lineage_id, point, x, y
         FROM artifact_curves_2d
         WHERE artifact_id = ?
         ORDER BY lineage_id, point;",
        params = list(artifact_id)
      )
      .wb_assert(nrow(df) > 0, paste0("wb_art_load(): no rows in artifact_curves_2d for ", artifact_id))

      wb_prim_path_2d_family(
        key = df$lineage_id,
        point = df$point,
        x = df$x,
        y = df$y
      )
    },

    # ---- space_2d: minimum ref is space_id; coords live in artifact_space_2d ----
    "space_2d" = {
      space_id <- as.character(art$input_space_id[[1]])
      .wb_assert(nzchar(space_id), "wb_art_load(): space_2d artifact missing input_space_id.")

      # If you want the coords too, you can attach them as meta/df.
      coords <- DBI::dbGetQuery(
        con,
        "SELECT cell_id, x, y
         FROM artifact_space_2d
         WHERE artifact_id = ?;",
        params = list(artifact_id)
      )

      p <- wb_prim_space_2d(space_id)
      if (nrow(coords) > 0) p$df <- coords
      p
    },

    # ---- umap_model / model_ref stored as artifact_umap_model ----
    "umap_model" = {
      df <- DBI::dbGetQuery(
        con,
        "SELECT space_id, model_path
         FROM artifact_umap_model
         WHERE artifact_id = ?;",
        params = list(artifact_id)
      )
      .wb_assert(nrow(df) == 1, paste0("wb_art_load(): no row in artifact_umap_model for ", artifact_id))
      p <- wb_prim_model_ref(
        model_space_id = as.character(df$space_id[[1]]),
        in_space_id = if (is.null(art$input_space_id[[1]])) "" else as.character(art$input_space_id[[1]]),
        engine = "uwot",
        artifact_id = artifact_id
      )
      p$model_path <- as.character(df$model_path[[1]])
      p
    },

    "feature_table" = {
      info <- DBI::dbGetQuery(
        con,
        "SELECT table_type, entity_kind, meta_json
         FROM artifact_tables
         WHERE artifact_id = ?;",
        params = list(artifact_id)
      )
      .wb_assert(nrow(info) == 1, paste0("wb_art_load(): no row in artifact_tables for ", artifact_id))

      rows <- DBI::dbGetQuery(
        con,
        "SELECT row_json
         FROM artifact_table_rows
         WHERE artifact_id = ?
         ORDER BY row_idx ASC;",
        params = list(artifact_id)
      )
      .wb_assert(nrow(rows) >= 0, paste0("wb_art_load(): failed reading table rows for ", artifact_id))

      tbl <- if (nrow(rows) == 0) {
        data.frame(stringsAsFactors = FALSE)
      } else {
        rr <- lapply(rows$row_json, jsonlite::fromJSON)
        rr <- lapply(rr, as.data.frame, stringsAsFactors = FALSE)
        out <- do.call(rbind, rr)
        rownames(out) <- NULL
        out
      }
      meta <- if (!is.null(info$meta_json[[1]]) && nzchar(as.character(info$meta_json[[1]]))) {
        jsonlite::fromJSON(as.character(info$meta_json[[1]]), simplifyVector = TRUE)
      } else {
        list()
      }

      wb_prim_feature_table(
        table = tbl,
        table_type = as.character(info$table_type[[1]] %||% "generic"),
        meta = meta
      )
    },

    "obs_table" = {
      info <- DBI::dbGetQuery(
        con,
        "SELECT table_type, entity_kind, meta_json
         FROM artifact_tables
         WHERE artifact_id = ?;",
        params = list(artifact_id)
      )
      .wb_assert(nrow(info) == 1, paste0("wb_art_load(): no row in artifact_tables for ", artifact_id))

      rows <- DBI::dbGetQuery(
        con,
        "SELECT row_json
         FROM artifact_table_rows
         WHERE artifact_id = ?
         ORDER BY row_idx ASC;",
        params = list(artifact_id)
      )
      tbl <- if (nrow(rows) == 0) {
        data.frame(stringsAsFactors = FALSE)
      } else {
        rr <- lapply(rows$row_json, jsonlite::fromJSON)
        rr <- lapply(rr, as.data.frame, stringsAsFactors = FALSE)
        out <- do.call(rbind, rr)
        rownames(out) <- NULL
        out
      }
      meta <- if (!is.null(info$meta_json[[1]]) && nzchar(as.character(info$meta_json[[1]]))) {
        jsonlite::fromJSON(as.character(info$meta_json[[1]]), simplifyVector = TRUE)
      } else {
        list()
      }

      wb_prim_obs_table(
        table = tbl,
        table_type = as.character(info$table_type[[1]] %||% "generic"),
        entity_kind = as.character(info$entity_kind[[1]] %||% "generic"),
        meta = meta
      )
    },

    stop("wb_art_load(): Unsupported artifact type: ", type, call. = FALSE)
  )

  # Kind-safety
  if (!is.null(expected_kind)) {
    .wb_assert_kind(prim, expected_kind, where = paste0(" (artifact_id=", artifact_id, ")"))
  }

  prim
}
