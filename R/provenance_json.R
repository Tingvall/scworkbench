# R/provenance_json.R  (or wherever .wb_prov_json lives)
.wb_prim_summary <- function(p) {
  .wb_assert(inherits(p, "wb_primitive"), "Expected wb_primitive.")
  kind <- p$kind %||% "unknown"

  if (identical(kind, "cell_vector")) {
    return(list(
      kind = "cell_vector",
      value_type = p$value_type %||% NA_character_,
      n = length(p$cell_id %||% character(0)),
      meta = p$meta %||% NULL
    ))
  }

  if (identical(kind, "cell_vector_family")) {
    return(list(
      kind = "cell_vector_family",
      value_type = p$value_type %||% NA_character_,
      n = length(p$cell_id %||% character(0)),
      n_keys = length(unique(p$key %||% character(0)))
    ))
  }

  if (identical(kind, "relation_family")) {
    return(list(
      kind = "relation_family",
      n = length(p$cell_id %||% character(0)),
      n_keys = length(unique(p$key %||% character(0))),
      has_weight = !is.null(p$weight),
      has_value = !is.null(p$value),
      has_distance = !is.null(p$distance)
    ))
  }

  if (identical(kind, "path_2d_family")) {
    return(list(
      kind = "path_2d_family",
      n = length(p$point %||% integer(0)),
      n_keys = length(unique(p$key %||% character(0)))
    ))
  }

  if (identical(kind, "space_path_family")) {
    return(list(
      kind = "space_path_family",
      n = length(p$point %||% integer(0)),
      n_paths = length(unique(p$path_id %||% character(0))),
      n_dims = length(unique(p$dim %||% integer(0))),
      space_id = unique(as.character(p$space_id %||% NA_character_))[1]
    ))
  }

  if (identical(kind, "space_2d")) {
    return(list(
      kind = "space_2d",
      space_id = p$space_id %||% NA_character_
    ))
  }


  if (identical(kind, "space")) {
    return(list(kind = "space", space_id = p$space_id %||% NA_character_))
  }

  if (identical(kind, "matrix")) {
    return(list(kind = "matrix", matrix_id = p$matrix_id %||% NA_character_))
  }

  if (identical(kind, "model_ref")) {
    return(list(
      kind = "model_ref",
      engine = p$engine %||% NA_character_,
      model_space_id = p$model_space_id %||% p$space_id %||% NA_character_,
      in_space_id = p$in_space_id %||% NA_character_,
      model_type = p$model_type %||% NA_character_,
      model_path = p$model_path %||% NA_character_
    ))
  }

  if (identical(kind, "feature_table")) {
    tbl <- p$table
    return(list(
      kind = "feature_table",
      table_type = p$table_type %||% "generic",
      n_rows = if (is.data.frame(tbl)) nrow(tbl) else NA_integer_,
      n_cols = if (is.data.frame(tbl)) ncol(tbl) else NA_integer_
    ))
  }

  if (identical(kind, "obs_table")) {
    tbl <- p$table
    return(list(
      kind = "obs_table",
      table_type = p$table_type %||% "generic",
      entity_kind = p$entity_kind %||% "generic",
      n_rows = if (is.data.frame(tbl)) nrow(tbl) else NA_integer_,
      n_cols = if (is.data.frame(tbl)) ncol(tbl) else NA_integer_
    ))
  }

  # fallback
  list(kind = kind)
}

.wb_json_sanitize <- function(x) {
  # primitives -> summary
  if (inherits(x, "wb_primitive")) return(.wb_prim_summary(x))

  # basic types are fine
  if (is.null(x) || is.atomic(x) || is.data.frame(x)) return(x)

  # lists -> recurse
  if (is.list(x)) {
    out <- lapply(x, .wb_json_sanitize)
    if (!is.null(names(x))) names(out) <- names(x)
    return(out)
  }

  # everything else -> string fallback
  as.character(x)
}

# ---- REPLACEMENT ----
.wb_prov_json <- function(run, parent_artifacts) {
  .wb_require_pkg("jsonlite", "provenance json")

  prov <- list(
    run_id = run$run_id,
    op_name = run$op_name,
    created_at = run$created_at %||% NA_character_,

    # key point: sanitize these
    inputs = run$inputs %||% list(),
    params = run$params %||% list(),

    notes  = run$notes %||% NULL,
    parent_artifacts = parent_artifacts %||% list()
  )

  jsonlite::toJSON(.wb_json_sanitize(prov), auto_unbox = TRUE, null = "null")
}
