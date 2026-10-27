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

# New execution-setting records use ordinary JSON numbers with enough digits
# for IEEE-754 round-trip. Keep double tokens decimal so 1.0 and signed zero
# retain their numeric type in standard R/Python readers. Identity helpers and
# historical stored JSON are deliberately not re-encoded by this writer.
.wb_execution_settings_encoding <- function() "scworkbench.execution-settings.json.v1"

.wb_execution_settings_json <- function(x) {
  jsonlite::toJSON(x, auto_unbox = TRUE, null = "null",
    digits = 17, always_decimal = TRUE)
}

.wb_prov_json <- function(run, parent_artifacts, primitive_payload = NULL) {
  .wb_require_pkg("jsonlite", "provenance json")

  prov <- list(
    run_id = run$run_id,
    op_name = run$op_name,
    created_at = run$created_at %||% NA_character_,
    execution_settings_encoding = .wb_execution_settings_encoding(),

    # key point: sanitize these
    inputs = run$inputs %||% list(),
    params = run$params %||% list(),

    notes  = run$notes %||% NULL,
    parent_artifacts = parent_artifacts %||% list()
  )
  if (!is.null(primitive_payload)) prov$primitive_payload <- primitive_payload

  .wb_execution_settings_json(.wb_json_sanitize(prov))
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

.wb_object_row_key_tokens_template <- function(keys) tryCatch(withCallingHandlers({
  if (!is.data.frame(keys) || !identical(class(keys), "data.frame") ||
      !identical(as.character(getRversion()), "4.4.1") ||
      !identical(as.character(getNamespaceVersion("jsonlite")), "1.8.8")) return(NULL)
  n <- nrow(keys); width <- ncol(keys)
  if (n <= 1L || width < 1L || width > 4L) return(NULL)
  guard <- getOption("scworkbench.max_dense_materialize_mb", 256)
  if (is.object(guard) || !is.null(attributes(guard)) || !is.numeric(guard) ||
      length(guard) != 1L || is.na(guard) || !is.finite(guard) || guard <= 0) return(NULL)
  allowance <- min(32 * 1024^2, guard * 1024^2 / 4)
  metadata <- 65536 + 1024 * width
  if (metadata + 64 * n >= allowance) return(NULL)
  if (!setequal(names(attributes(keys)), c("names", "row.names", "class"))) return(NULL)
  fields <- names(keys)
  field_bytes <- sum(nchar(fields, type = "bytes"))
  metadata <- metadata + 8 * field_bytes
  if (!is.finite(metadata) || metadata + 64 * n >= allowance || anyNA(fields) ||
      any(!nzchar(fields)) || anyDuplicated(fields) ||
      !identical(fields, make.names(fields, unique = TRUE))) return(NULL)
  columns <- as.list(keys)
  if (!all(vapply(columns, function(column) is.character(column) &&
      is.null(attributes(column)) && length(column) == n, logical(1)))) return(NULL)

  # Compile ONLY the original typed-list serializer's constant framing. Each
  # raw marker must occur once in the ENTIRE template, including names metadata.
  # No substitution ever runs over a token containing actual source values.
  markers <- paste0("__scwb_row_key_template_", seq_len(width), "__")
  template <- as.character(jsonlite::serializeJSON(setNames(as.list(markers), fields), digits = NA))
  positions <- numeric(width)
  for (j in seq_len(width)) {
    at <- gregexpr(markers[[j]], template, fixed = TRUE)[[1L]]
    quoted <- gregexpr(paste0('"', markers[[j]], '"'), template, fixed = TRUE)[[1L]]
    if (length(at) != 1L || at[[1L]] < 1L || length(quoted) != 1L || quoted[[1L]] < 1L) return(NULL)
    positions[[j]] <- at[[1L]]
  }
  if (is.unsorted(positions, strictly = TRUE)) return(NULL)
  pieces <- character(width + 1L); cursor <- 1
  for (j in seq_len(width)) {
    pieces[[j]] <- substring(template, cursor, positions[[j]] - 1)
    cursor <- positions[[j]] + nchar(markers[[j]])
  }
  pieces[[width + 1L]] <- substring(template, cursor)
  fixed_bytes <- nchar(template, type = "bytes") - sum(nchar(markers, type = "bytes"))
  metadata <- metadata + 8 * nchar(template, type = "bytes")
  # First pass validates ALL actual values before any successful result. Only
  # <=1000-row scratch, scalar totals and a <=4-column reference list survive.
  initial_batch <- min(1000, floor((allowance - metadata - 64 * n) / (512 * width + 1024)))
  if (!is.finite(initial_batch) || initial_batch < 1) return(NULL)
  total_bytes <- as.double(n) * fixed_bytes; maximum_row_bytes <- as.double(fixed_bytes)
  start <- 1
  while (start <= n) {
    end <- min(n, start + initial_batch - 1); indices <- seq.int(start, end)
    row_bytes <- rep.int(fixed_bytes, length(indices))
    for (column in columns) {
      value <- column[indices]
      if (anyNA(value) || any(Encoding(value) != "unknown") ||
          !all(grepl("\\A[A-Za-z0-9_.:-]*\\z", value, perl = TRUE, useBytes = TRUE))) return(NULL)
      bytes <- nchar(value, type = "bytes")
      if (anyNA(bytes)) return(NULL)
      row_bytes <- row_bytes + bytes
    }
    total_bytes <- total_bytes + sum(row_bytes) - length(indices) * fixed_bytes
    maximum_row_bytes <- max(maximum_row_bytes, row_bytes)
    if (!is.finite(total_bytes) || metadata + 64 * n + 2 * total_bytes >= allowance) return(NULL)
    start <- end + 1
  }
  rm(column, value, bytes, row_bytes, indices)
  # Returned strings/vector PLUS copy margin, then all live batch carriers and
  # intermediate paste strings. The old materialized API remains the fallback
  # if its complete token result cannot fit this narrow optimization allowance.
  retained <- metadata + 64 * n + 2 * total_bytes
  batch <- min(initial_batch, floor((allowance - retained) /
    (256 * width + 8 * maximum_row_bytes + 256)))
  if (!is.finite(batch) || batch < 1) return(NULL)
  out <- character(n); observed_bytes <- 0; start <- 1
  while (start <= n) {
    end <- min(n, start + batch - 1); indices <- seq.int(start, end)
    assembled <- rep.int(pieces[[1L]], length(indices))
    row_bytes <- rep.int(fixed_bytes, length(indices))
    for (j in seq_len(width)) {
      value <- columns[[j]][indices]
      if (anyNA(value) || any(Encoding(value) != "unknown") ||
          !all(grepl("\\A[A-Za-z0-9_.:-]*\\z", value, perl = TRUE, useBytes = TRUE))) return(NULL)
      bytes <- nchar(value, type = "bytes"); row_bytes <- row_bytes + bytes
      if (anyNA(bytes) || any(row_bytes > maximum_row_bytes)) return(NULL)
      assembled <- paste0(assembled, value, pieces[[j + 1L]])
    }
    observed_bytes <- observed_bytes + sum(row_bytes)
    if (observed_bytes > total_bytes) return(NULL)
    out[indices] <- assembled
    rm(value, bytes, assembled, row_bytes, indices)
    start <- end + 1
  }
  if (!identical(observed_bytes, total_bytes)) return(NULL)
  out
}, warning = function(w) stop("Original row-key serialization fallback.", call. = FALSE)),
  error = function(e) NULL)

.wb_object_row_key_tokens <- function(keys) {
  if (!nrow(keys)) return(character())
  if (nrow(keys) > 1L) {
    tokens <- .wb_object_row_key_tokens_template(keys)
    if (!is.null(tokens)) return(tokens)
  }
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
