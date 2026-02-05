# R/artifacts_load.R
# Load a promoted artifact back into a wb_primitive (kind-safe),
# using the *existing* migrate schema (no payload_json column needed).

`%||%` <- function(x, y) if (is.null(x)) y else x

.wb_assert <- function(ok, msg) {
  if (!isTRUE(ok)) stop(msg, call. = FALSE)
  invisible(TRUE)
}

# Optional: if you already have these, remove duplicates.
.wb_is_primitive <- function(x) inherits(x, "wb_primitive")
.wb_assert_kind <- function(x, expected_kind, where = "") {
  .wb_assert(.wb_is_primitive(x), paste0("Expected primitive object", where, "."))
  .wb_assert(identical(as.character(x$kind), as.character(expected_kind)),
             paste0("Expected kind '", expected_kind, "'", where, ", got '", x$kind, "'."))
  invisible(TRUE)
}

# ---- Your primitive constructors (use yours if already defined) ----
wb_prim_cell_vector <- function(x, value_type = "categorical") {
  stopifnot(is.atomic(x), !is.null(names(x)))
  structure(
    list(kind = "cell_vector",
         cell_id = as.character(names(x)),
         value = as.character(x),
         value_type = as.character(value_type)),
    class = "wb_primitive"
  )
}

wb_prim_cell_vector_family <- function(key, cell_id, value, value_type = "continuous") {
  structure(
    list(kind = "cell_vector_family",
         key = as.character(key),
         cell_id = as.character(cell_id),
         value = as.numeric(value),
         value_type = as.character(value_type)),
    class = "wb_primitive"
  )
}

wb_prim_path_2d_family <- function(key, point, x, y) {
  structure(
    list(kind = "path_2d_family",
         key = as.character(key),
         point = as.integer(point),
         x = as.numeric(x),
         y = as.numeric(y)),
    class = "wb_primitive"
  )
}

wb_prim_space_2d <- function(space_id) {
  structure(list(kind = "space_2d", space_id = as.character(space_id)),
            class = "wb_primitive")
}

wb_prim_model_ref <- function(space_id, model_path = NULL) {
  structure(list(kind = "model_ref",
                 space_id = as.character(space_id),
                 model_path = if (is.null(model_path)) NULL else as.character(model_path)),
            class = "wb_primitive")
}

# ---- Main loader ----
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
      wb_prim_model_ref(space_id = df$space_id[[1]], model_path = df$model_path[[1]])
    },

    stop("wb_art_load(): Unsupported artifact type: ", type, call. = FALSE)
  )

  # Kind-safety
  if (!is.null(expected_kind)) {
    .wb_assert_kind(prim, expected_kind, where = paste0(" (artifact_id=", artifact_id, ")"))
  }

  prim
}
