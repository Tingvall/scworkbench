# R/artifacts_load.R
# Load a promoted artifact back into a wb_primitive (kind-safe),
# using the *existing* migrate schema (no payload_json column needed).

# ---- Main loader ----
#' Load a Promoted Artifact as a Primitive
#'
#' Reconstructs a typed primitive from the bundle-owned artifact registry and
#' payload tables. Consumers should use this function rather than reading
#' artifact payload tables directly.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param artifact_id Promoted artifact identifier.
#' @param expected_kind Optional expected primitive kind. When supplied, loading
#'   fails if the stored artifact has another kind.
#'
#' @param allow_untrusted_deserialization Explicitly allow R deserialization of
#'   a contained model payload that is not provenance-bound. This never permits
#'   an external, traversing, or symlink-escaping path.
#' @return A `wb_primitive` reconstructed from the promoted payload.
#' @export
wb_art_load <- function(bundle, artifact_id, expected_kind = NULL,
                        allow_untrusted_deserialization = FALSE) {
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
  if (nrow(art) != 1L) {
    # A session overlay is a point-in-time SQLite copy. Resolve only against
    # its explicitly recorded source bundle when a promoted artifact was
    # created after the overlay began; never search arbitrary paths.
    source_dir <- as.character(bundle$staging_source_dir %||% "")[1]
    if (nzchar(source_dir) && dir.exists(source_dir) &&
        !identical(normalizePath(source_dir, winslash = "/", mustWork = TRUE),
                   normalizePath(bundle$dir, winslash = "/", mustWork = TRUE))) {
      source_bundle <- wb_open_bundle(source_dir, validate = FALSE)
      on.exit(wb_close_bundle(source_bundle), add = TRUE)
      return(wb_art_load(source_bundle, artifact_id = artifact_id, expected_kind = expected_kind,
                         allow_untrusted_deserialization = allow_untrusted_deserialization))
    }
  }
  .wb_assert(nrow(art) == 1, paste0("wb_art_load(): artifact not found: ", artifact_id))

  type <- as.character(art$type[[1]])

  # Reconstruct primitive by type
  prim <- switch(
    type,

    # ---- cell_vector stored as artifact_labels (cell_id, label) ----
    "cell_vector" = {
      has_value_type <- .wb_db_has_column(con, "artifact_labels", "value_type")
      has_value_num  <- .wb_db_has_column(con, "artifact_labels", "value_num")
      q <- if (has_value_type || has_value_num) {
        paste0(
          "SELECT cell_id, label, ",
          if (has_value_type) "value_type" else "NULL AS value_type", ", ",
          if (has_value_num) "value_num" else "NULL AS value_num", "
           FROM artifact_labels
           WHERE artifact_id = ?;"
        )
      } else {
        "SELECT cell_id, label, NULL AS value_type, NULL AS value_num
         FROM artifact_labels
         WHERE artifact_id = ?;"
      }
      df <- DBI::dbGetQuery(con, q, params = list(artifact_id))
      .wb_assert(nrow(df) > 0, paste0("wb_art_load(): no rows in artifact_labels for ", artifact_id))

      vt <- unique(as.character(stats::na.omit(df$value_type %||% character(0))))
      inferred_type <- if ("continuous" %in% vt) "continuous" else "categorical"
      if (identical(inferred_type, "continuous") && "value_num" %in% names(df)) {
        v <- suppressWarnings(as.numeric(df$value_num))
        bad <- is.na(v) & !is.na(df$label) & nzchar(as.character(df$label))
        if (any(bad)) v[bad] <- suppressWarnings(as.numeric(df$label[bad]))
      } else {
        v <- as.character(df$label)
      }
      names(v) <- as.character(df$cell_id)
      wb_prim_cell_vector(v, value_type = inferred_type)
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

    # ---- relation_family stored as artifact_relation_rows ----
    "relation_family" = {
      df <- DBI::dbGetQuery(
        con,
        "SELECT relation_key, cell_id, weight, value, distance
         FROM artifact_relation_rows
         WHERE artifact_id = ?
         ORDER BY relation_key, cell_id;",
        params = list(artifact_id)
      )
      .wb_assert(nrow(df) > 0, paste0("wb_art_load(): no rows in artifact_relation_rows for ", artifact_id))

      # Preserve optional columns semantically: all-NA columns become NULL.
      all_na <- function(x) all(is.na(x))
      wb_prim_relation_family(
        key = df$relation_key,
        cell_id = df$cell_id,
        weight = if (all_na(df$weight)) NULL else df$weight,
        value = if (all_na(df$value)) NULL else df$value,
        distance = if (all_na(df$distance)) NULL else df$distance
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

    # ---- space_path_family stored as artifact_space_path_rows/meta ----
    "space_path_family" = {
      df <- DBI::dbGetQuery(
        con,
        "SELECT space_id, path_id, point, dim, value
         FROM artifact_space_path_rows
         WHERE artifact_id = ?
         ORDER BY path_id, point, dim;",
        params = list(artifact_id)
      )
      .wb_assert(nrow(df) > 0, paste0("wb_art_load(): no rows in artifact_space_path_rows for ", artifact_id))

      meta_info <- DBI::dbGetQuery(
        con,
        "SELECT meta_json
         FROM artifact_space_path_meta
         WHERE artifact_id = ?;",
        params = list(artifact_id)
      )
      meta <- list()
      if (nrow(meta_info) == 1L) {
        mj <- as.character(meta_info$meta_json[[1]] %||% "")
        if (nzchar(mj) && !identical(mj, "null")) {
          meta <- tryCatch(jsonlite::fromJSON(mj, simplifyVector = FALSE), error = function(e) list())
        }
      }

      wb_prim_space_path_family(
        space_id = df$space_id,
        path_id = df$path_id,
        point = df$point,
        dim = df$dim,
        value = df$value,
        meta = meta
      )
    },

    # ---- space_2d: durable reference to the canonical file-backed payload ----
    "space_2d" = {
      space_id <- as.character(art$input_space_id[[1]])
      .wb_assert(nzchar(space_id), "wb_art_load(): space_2d artifact missing input_space_id.")

      p <- wb_prim_space_2d(space_id)
      p$df <- .wb_space_2d_safe(bundle, space_id)
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

    # ---- generic model_ref artifacts (engine-tagged, e.g. slingshot/uwot) ----
    "model_ref" = {
      df <- DBI::dbGetQuery(
        con,
        "SELECT engine, model_space_id, in_space_id, model_type, model_path
         FROM artifact_model_ref
         WHERE artifact_id = ?;",
        params = list(artifact_id)
      )
      .wb_assert(nrow(df) == 1, paste0("wb_art_load(): no row in artifact_model_ref for ", artifact_id))

      engine <- as.character(df$engine[[1]] %||% "uwot")
      stored_model_path <- as.character(df$model_path[[1]] %||% "")
      model_path <- tryCatch(
        .wb_resolve_model_ref_path(bundle, stored_model_path),
        error = function(e) {
          stop(
            paste0(
              "wb_art_load(): model file missing for engine='", engine, "': ",
              stored_model_path, ". ", conditionMessage(e)
            ),
            call. = FALSE
          )
        }
      )
      p <- wb_prim_model_ref(
        model_space_id = as.character(df$model_space_id[[1]]),
        in_space_id = as.character(df$in_space_id[[1]] %||% ""),
        engine = engine,
        artifact_id = artifact_id
      )
      p$model_type <- as.character(df$model_type[[1]] %||% engine)
      p$model_path <- model_path
      lifecycle <- if (.wb_table_exists(con, "entity_lifecycle")) {
        wb_entity_lifecycle(bundle, "artifact", artifact_id)
      } else data.frame()
      provenance_bound <- nrow(lifecycle) && identical(as.integer(lifecycle$provenance_bound[1] %||% 0L), 1L)
      trust <- .wb_model_deserialization_status(bundle, stored_model_path,
                                                provenance_bound = provenance_bound)
      p$deserialization_trust <- trust$trust

      # Load in-memory object for engines with project/continue ops that require the model object.
      if (engine %in% c("slingshot", "monocle3")) {
        .wb_assert(
          isTRUE(trust$deserialization_allowed) || isTRUE(allow_untrusted_deserialization),
          "MODEL_DESERIALIZATION_TRUST_REQUIRED: loading serialized model state requires trusted provenance/runtime or allow_untrusted_deserialization=TRUE."
        )
        p$model_obj <- readRDS(model_path)
      }
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
        .wb_art_table_rows_to_df(rows)
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
        .wb_art_table_rows_to_df(rows)
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

  prim <- .wb_trajectory_hydrate_primitive_meta(bundle, artifact_id, prim)

  # Kind-safety
  if (!is.null(expected_kind)) {
    .wb_assert_kind(prim, expected_kind, where = paste0(" (artifact_id=", artifact_id, ")"))
  }

  prim
}
