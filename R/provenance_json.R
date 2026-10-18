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
.wb_prov_json <- function(run, parent_artifacts, primitive_payload = NULL) {
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
  if (!is.null(primitive_payload)) prov$primitive_payload <- primitive_payload

  jsonlite::toJSON(.wb_json_sanitize(prov), auto_unbox = TRUE, null = "null")
}

.wb_object_primitive_kinds <- function() {
  c("cell_vector", "cell_vector_family", "relation_family", "path_2d_family", "space_path_family")
}

.wb_object_primitive_row_keys <- function(prim) {
  kind <- as.character(prim$kind)[1L]
  switch(
    kind,
    cell_vector = data.frame(cell_id = as.character(prim$cell_id), stringsAsFactors = FALSE),
    cell_vector_family = data.frame(key = as.character(prim$key), cell_id = as.character(prim$cell_id), stringsAsFactors = FALSE),
    relation_family = data.frame(key = as.character(prim$key), cell_id = as.character(prim$cell_id), stringsAsFactors = FALSE),
    path_2d_family = data.frame(key = as.character(prim$key), point = as.integer(prim$point), stringsAsFactors = FALSE),
    space_path_family = data.frame(space_id = as.character(prim$space_id), path_id = as.character(prim$path_id), point = as.integer(prim$point), dim = as.integer(prim$dim), stringsAsFactors = FALSE),
    stop("Unsupported object primitive kind: ", kind, call. = FALSE)
  )
}

.wb_object_row_key_tokens <- function(keys) {
  if (!nrow(keys)) return(character())
  vapply(seq_len(nrow(keys)), function(i) {
    jsonlite::serializeJSON(as.list(keys[i, , drop = FALSE]), digits = NA)
  }, character(1))
}

# This is equality of already loaded ordered scientific keys, not construction
# of a retained identity. Keep the original typed comparator for nonordinary
# columns; descriptors still serialize every row with the original function.
.wb_object_row_keys_identical <- function(left, right) {
  ordinary <- function(keys) is.data.frame(keys) && nrow(keys) > 0L &&
    all(vapply(keys, function(column) is.character(column) &&
      is.null(attributes(column)) && {
        converted <- tryCatch(iconv(column, from = "", to = "UTF-8", sub = NA_character_),
          error = function(error) NULL)
        !is.null(converted) && !any(!is.na(column) & is.na(converted))
      }, logical(1)))
  if (ordinary(left) && ordinary(right))
    return(identical(names(left), names(right)) &&
      identical(as.list(left), as.list(right)))
  identical(.wb_object_row_key_tokens(left), .wb_object_row_key_tokens(right))
}

.wb_object_primitive_payload_descriptor <- function(prim,
    sealed_content_identity = FALSE) {
  kind <- as.character(prim$kind)[1L]
  .wb_assert(kind %in% .wb_object_primitive_kinds(),
             paste0("Unsupported durable object primitive kind: ", kind))
  descriptor <- list(
    schema = "scworkbench.artifact.object-payload.v1",
    kind = kind,
    row_order = as.list(.wb_object_row_key_tokens(.wb_object_primitive_row_keys(prim))),
    meta_present = "meta" %in% names(unclass(prim))
  )
  if (isTRUE(descriptor$meta_present)) {
    descriptor$meta_r_json <- jsonlite::serializeJSON(prim$meta, digits = NA)
  }
  if (kind %in% c("cell_vector", "cell_vector_family")) {
    descriptor$value_type <- as.character(prim$value_type %||% "categorical")
  }
  if (identical(kind, "relation_family")) {
    descriptor$fields_present <- intersect(
      c("weight", "value", "distance"),
      names(unclass(prim))[vapply(unclass(prim), Negate(is.null), logical(1))]
    )
    if (isTRUE(sealed_content_identity))
      descriptor$content_identity <- .wb_operation_pack_v2_identity_plain(
        "scworkbench.relation_family.content.v1", unclass(prim))
  }
  descriptor
}

.wb_object_primitive_meta_from_descriptor <- function(descriptor) {
  if (is.null(descriptor) || !isTRUE(descriptor$meta_present)) return(NULL)
  text <- as.character(descriptor$meta_r_json %||% "")[1L]
  .wb_assert(nzchar(text), "Durable object primitive metadata descriptor is empty.")
  jsonlite::unserializeJSON(text)
}

.wb_artifact_object_descriptor <- function(provenance_json, expected_kind, artifact_id) {
  provenance <- tryCatch(
    jsonlite::fromJSON(as.character(provenance_json), simplifyVector = FALSE),
    error = function(e) NULL
  )
  descriptor <- provenance$primitive_payload %||% NULL
  if (is.null(descriptor)) return(NULL)
  .wb_assert(
    identical(as.character(descriptor$schema %||% ""),
              "scworkbench.artifact.object-payload.v1") &&
      identical(as.character(descriptor$kind %||% ""), as.character(expected_kind)),
    paste0("wb_art_load(): invalid durable ", expected_kind,
           " payload descriptor for ", artifact_id)
  )
  descriptor
}

.wb_artifact_restore_object_row_order <- function(df, descriptor, kind, artifact_id) {
  if (is.null(descriptor)) return(df)
  keys <- switch(
    kind,
    cell_vector = data.frame(cell_id = as.character(df$cell_id), stringsAsFactors = FALSE),
    cell_vector_family = data.frame(key = as.character(df$lineage_id), cell_id = as.character(df$cell_id), stringsAsFactors = FALSE),
    relation_family = data.frame(key = as.character(df$relation_key), cell_id = as.character(df$cell_id), stringsAsFactors = FALSE),
    path_2d_family = data.frame(key = as.character(df$lineage_id), point = as.integer(df$point), stringsAsFactors = FALSE),
    space_path_family = data.frame(space_id = as.character(df$space_id), path_id = as.character(df$path_id), point = as.integer(df$point), dim = as.integer(df$dim), stringsAsFactors = FALSE),
    stop("Unsupported durable object primitive kind: ", kind, call. = FALSE)
  )
  observed <- .wb_object_row_key_tokens(keys)
  expected <- as.character(unlist(descriptor$row_order %||% list(), use.names = FALSE))
  .wb_assert(
    length(expected) == nrow(df) && !anyDuplicated(expected) &&
      !anyDuplicated(observed) && setequal(expected, observed),
    paste0("wb_art_load(): durable ", kind,
           " row order does not match payload rows for ", artifact_id)
  )
  df[match(expected, observed), , drop = FALSE]
}
