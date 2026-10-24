#' Attach a legacy numeric scalar cell vector to a bundle
#'
#' This API stores a numeric scalar per cell in the legacy `cell_vectors` and
#' `cell_vector_values` tables. It is separate from promoted artifact-backed
#' `cell_vector` primitives. New analysis outputs should normally be promoted
#' artifacts; this helper remains for bundle metadata and compatibility inputs.
#'
#' @param bundle A scworkbench bundle.
#' @param vector_id Unique legacy vector identifier.
#' @param values Named numeric vector (`names` are cell IDs) or a data frame
#'   with `cell_id` and numeric `value` columns.
#' @param overwrite If `TRUE`, replace all stored values for `vector_id`. If
#'   `FALSE`, replace only values supplied for the matching cell IDs.
#' @return Invisibly, a list with `vector_id` and number of written values.
#' @export
wb_attach_cell_vector <- function(bundle, vector_id, values, overwrite = TRUE) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert(is.character(vector_id) && length(vector_id) == 1L && nzchar(vector_id), "vector_id invalid")
  .wb_assert(is.logical(overwrite) && length(overwrite) == 1L && !is.na(overwrite), "overwrite must be TRUE or FALSE")

  .wb_with_mutation_context(bundle = bundle, route = "ingestion", code = {
  if (is.data.frame(values)) {
    .wb_assert(all(c("cell_id", "value") %in% names(values)), "values data frame must contain cell_id and value")
    input <- values[, c("cell_id", "value"), drop = FALSE]
  } else {
    .wb_assert(is.atomic(values) && !is.null(names(values)), "values must be a named numeric vector or data frame")
    input <- data.frame(cell_id = names(values), value = values, stringsAsFactors = FALSE)
  }
  .wb_assert(!anyDuplicated(as.character(input$cell_id)), "values contains duplicate cell_id entries")
  input$value <- suppressWarnings(as.numeric(input$value))
  .wb_assert(all(is.finite(input$value)), "legacy cell-vector values must be finite numeric values")

  con <- bundle$con
  .wb_ensure_cell_vectors_tables(con)
  DBI::dbWithTransaction(con, {
  registered <- DBI::dbGetQuery(con, "SELECT vector_id FROM cell_vectors WHERE vector_id = ?;", params = list(vector_id))
  if (!nrow(registered)) wb_register_cell_vector(bundle, vector_id = vector_id, value_type = "numeric")

  n <- wb_write_cell_vector(bundle, vector_id = vector_id, values = input, overwrite = overwrite)
  vals <- as.numeric(input$value)
  names(vals) <- as.character(input$cell_id)
  .wb_record_declared_ingestion(
    bundle = bundle, transaction_name = "attach_cell_vector",
    source = "legacy_cell_vector_attachment",
    additional_outputs = list(cell_vector = wb_prim_cell_vector(vals, value_type = "continuous")),
    transaction_open = TRUE
  )
  invisible(list(vector_id = vector_id, n = as.integer(n)))
  })
  })
}

#' Read a cell_vector (scalar per cell) for a set of cells
#'
#' Supports two backends:
#' 1) artifact-backed vectors: vector_id = "artifact:<artifact_id>"
#'    - loads via wb_art_load() and subsets to cell_ids
#' 2) legacy DB vectors: vector_id = "<vector_id>"
#'    - reads from cell_vector_values (numeric)
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param vector_id Artifact-backed (`"artifact:<id>"`) or legacy vector id.
#' @param cell_ids Requested cell ids and output order.
#'
#' @return Named numeric or character vector aligned to `cell_ids`, with
#'   `NA` for unavailable values.
#' @export
wb_read_cell_vector <- function(bundle, vector_id, cell_ids) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert(is.character(vector_id) && length(vector_id) == 1 && nzchar(vector_id), "vector_id invalid")
  .wb_assert(is.character(cell_ids) && length(cell_ids) > 0, "cell_ids invalid")
  con <- bundle$con
  .wb_assert(!is.null(con), "bundle$con is NULL")

  cell_ids <- as.character(cell_ids)

  # -------------------------
  # 1) Artifact-backed
  # -------------------------
  if (startsWith(vector_id, "artifact:")) {
    artifact_id <- sub("^artifact:", "", vector_id)
    prim <- wb_art_load(bundle, artifact_id = artifact_id)

    .wb_assert(inherits(prim, "wb_primitive"), "wb_art_load() did not return a wb_primitive")
    .wb_assert(identical(prim$kind, "cell_vector") || identical(prim$kind, "cell_vector_family"),
               "artifact must be of kind 'cell_vector' or 'cell_vector_family'")

    if (identical(prim$kind, "cell_vector_family")) {
      stop(
        "wb_read_cell_vector(): '", vector_id, "' is a cell_vector_family. ",
        "Use wb_read_cell_vector_family(bundle, vector_id, key=, cell_ids=) instead.",
        call. = FALSE
      )
    }

    # Build full named vector
    v <- prim$value
    names(v) <- prim$cell_id

    # Subset (preserve order, return NA for missing)
    out <- rep(NA_character_, length(cell_ids))
    names(out) <- cell_ids
    hit <- intersect(cell_ids, names(v))
    out[hit] <- as.character(v[hit])

    # Optional: if value_type looks numeric, coerce
    if (!is.null(prim$value_type) && identical(prim$value_type, "continuous")) {
      out_num <- suppressWarnings(as.numeric(out))
      names(out_num) <- names(out)
      return(out_num)
    }

    return(out)
  }

  # -------------------------
  # 2) Legacy DB-backed numeric vectors
  # -------------------------
  .wb_ensure_cell_vectors_tables(con)

  out <- rep(NA_real_, length(cell_ids))
  names(out) <- cell_ids

  cl <- .wb_sql_in_json(cell_ids)
  df <- DBI::dbGetQuery(
    con,
    paste0(
      "SELECT cell_id, value FROM cell_vector_values
       WHERE vector_id = ? AND cell_id IN ", cl$sql, ";"
    ),
    params = c(list(vector_id), cl$params)
  )

  if (nrow(df) == 0) return(out)
  out[df$cell_id] <- as.numeric(df$value)
  out
}


#' Read one member of a cell_vector_family (e.g. pseudotime for a given lineage)
#'
#' vector_id must be artifact-backed: "artifact:<artifact_id>"
#' key selects which family member (e.g. "L1")
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param vector_id Artifact-backed vector-family id.
#' @param key Family member key, for example lineage `"L1"`.
#' @param cell_ids Requested cell ids and output order.
#'
#' @return Named numeric vector aligned to `cell_ids`, with `NA` where the
#'   selected family member is unavailable.
#' @export
wb_read_cell_vector_family <- function(bundle, vector_id, key, cell_ids) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert(is.character(vector_id) && length(vector_id) == 1 && nzchar(vector_id), "vector_id invalid")
  .wb_assert(is.character(key) && length(key) == 1 && nzchar(key), "key invalid (e.g. 'L1')")
  .wb_assert(is.character(cell_ids) && length(cell_ids) > 0, "cell_ids invalid")

  .wb_assert(startsWith(vector_id, "artifact:"),
             "wb_read_cell_vector_family(): only supports artifact-backed families: vector_id='artifact:<artifact_id>'")
  artifact_id <- sub("^artifact:", "", vector_id)

  prim <- wb_art_load(bundle, artifact_id = artifact_id, expected_kind = "cell_vector_family")

  # prim: (key, cell_id, value) triplets
  key <- as.character(key)
  keep <- prim$key == key

  out <- rep(NA_real_, length(cell_ids))
  names(out) <- as.character(cell_ids)

  if (!any(keep)) return(out)

  df_cell <- prim$cell_id[keep]
  df_val  <- prim$value[keep]
  names(df_val) <- df_cell

  hit <- intersect(names(out), names(df_val))
  out[hit] <- as.numeric(df_val[hit])
  out
}




#' List available cell vectors (artifacts + optional session outputs)
#'
#' Source of truth:
#' - Bundle: artifacts table (type == cell_vector / cell_vector_family)
#' - Session (optional): session$runs outputs (kind == cell_vector / cell_vector_family)
#'
#' Returns a lightweight index for UX/plotting/selectors. It does NOT return payloads.
#'
#' Columns:
#' - vector_id: stable id for loading (artifact:<artifact_id> or session:<run_id>:<output>)
#' - kind: cell_vector | cell_vector_family
#' - name: human label
#' - source: artifact | session
#' - created_at, created_by, op_name, run_id (when available)
#' - artifact_id (when artifact)
#'
#' @param bundle An open scworkbench bundle.
#' @param session Optional `wb_session` whose unpromoted outputs are included.
#' @param include_session Whether to include compatible session outputs.
#' @return A data frame indexing vector-like sources without loading payloads.
#' @export
wb_list_cell_vectors <- function(bundle, session = NULL, include_session = !is.null(session)) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  con <- bundle$con

  # ---- 1) artifact-backed vectors ----
  arts <- DBI::dbGetQuery(
    con,
    "SELECT artifact_id, type, name, created_at, created_by, source_op
     FROM artifacts
     WHERE type IN ('cell_vector','cell_vector_family')
     ORDER BY created_at DESC;"
  )

  if (nrow(arts) > 0) {
    arts$vector_id <- paste0("artifact:", arts$artifact_id)
    arts$kind      <- as.character(arts$type)
    arts$source    <- "artifact"
    arts$op_name   <- as.character(arts$source_op)
    arts$run_id    <- NA_character_
    arts$artifact_id <- as.character(arts$artifact_id)
    arts$name      <- as.character(arts$name %||% arts$artifact_id)
    arts$created_at <- as.character(arts$created_at)
    arts$created_by <- as.character(arts$created_by)

    arts <- arts[, c("vector_id","kind","name","source","created_at","created_by","op_name","run_id","artifact_id"), drop = FALSE]
  } else {
    arts <- data.frame(
      vector_id = character(0),
      kind = character(0),
      name = character(0),
      source = character(0),
      created_at = character(0),
      created_by = character(0),
      op_name = character(0),
      run_id = character(0),
      artifact_id = character(0),
      stringsAsFactors = FALSE
    )
  }

  # ---- 2) session-backed vectors (optional) ----
  sess_df <- NULL
  if (isTRUE(include_session)) {
    .wb_assert(is.list(session), "session must be a list-like wb_session object")
    runs <- session$runs %||% list()

    rows <- list()
    k <- 0L

    for (rid in names(runs)) {
      run <- runs[[rid]]
      outs <- run$outputs %||% list()
      if (!length(outs)) next

      for (out_name in names(outs)) {
        prim <- outs[[out_name]]
        if (!is.list(prim) || is.null(prim$kind)) next
        if (!prim$kind %in% c("cell_vector","cell_vector_family")) next

        k <- k + 1L
        k_name <- paste0("session:", rid, ":", out_name)

        rows[[k]] <- data.frame(
          vector_id   = k_name,
          kind        = as.character(prim$kind),
          name        = paste0(run$op_name %||% "op", "::", out_name),
          source      = "session",
          created_at  = as.character(run$created_at %||% NA_character_),
          created_by  = as.character(run$created_by %||% NA_character_),
          op_name     = as.character(run$op_name %||% NA_character_),
          run_id      = as.character(rid),
          artifact_id = NA_character_,
          stringsAsFactors = FALSE
        )
      }
    }

    sess_df <- if (length(rows)) do.call(rbind, rows) else arts[0, ]
  } else {
    sess_df <- arts[0, ]
  }

  out <- rbind(arts, sess_df)

  # optional: prefer session rows at the top if the same “name/kind” appears
  out <- out[order(out$source, out$created_at, decreasing = TRUE), , drop = FALSE]

  rownames(out) <- NULL
  out
}



wb_register_cell_vector <- function(
    bundle,
    vector_id,
    name = vector_id,
    description = NULL,
    value_type = "numeric",
    source = NULL,
    created_by = NULL,
    provenance = NULL
) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert_mutation_context(bundle = bundle, action = "Legacy cell-vector registry mutation",
    allowed = c("assembly", "ingestion"),
    replacement = "wb_attach_cell_vector() within declared assembly, or a promoted cell_vector primitive")
  con <- bundle$con

  .wb_ensure_cell_vectors_tables(con)

  # coerce optionals to scalar strings (NO NULLs!)
  description <- if (is.null(description)) NA_character_ else as.character(description)
  source      <- if (is.null(source))      NA_character_ else as.character(source)
  created_by  <- if (is.null(created_by))  NA_character_ else as.character(created_by)

  prov_json <- if (is.null(provenance)) {
    NA_character_
  } else {
    as.character(jsonlite::toJSON(provenance, auto_unbox = TRUE))
  }

  created_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")

  # upsert-ish: delete then insert (simple + safe for v1)
  DBI::dbExecute(con, "DELETE FROM cell_vectors WHERE vector_id = ?;", params = list(vector_id))

  DBI::dbWriteTable(
    con,
    "cell_vectors",
    data.frame(
      vector_id = as.character(vector_id),
      name = as.character(name),
      description = description,
      value_type = as.character(value_type),
      source = source,
      created_at = as.character(created_at),
      created_by = created_by,
      provenance_json = prov_json,
      stringsAsFactors = FALSE
    ),
    append = TRUE
  )

  invisible(vector_id)
}

#' Load a Cell Vector Primitive
#'
#' Resolve an artifact-backed or session-backed vector reference to a typed
#' primitive. This is a compatibility helper for vector-oriented consumers.
#'
#' @param bundle Open `scworkbench_bundle`.
#' @param session Optional `wb_session` used to resolve `session:*:*` ids.
#' @param vector_id Exact vector reference from [wb_list_cell_vectors()]:
#'   `artifact:<artifact_id>` or `session:<run_id>:<output>`. A metadata field
#'   name or bare artifact ID is not a vector reference.
#' @param expected_kind Optional expected primitive kind.
#'
#' @return A `cell_vector` or `cell_vector_family` primitive.
#' @export
wb_cell_vector_load <- function(bundle, session = NULL, vector_id, expected_kind = NULL) {
  .wb_assert(is.character(vector_id) && length(vector_id) == 1 && nzchar(vector_id), "vector_id invalid")

  if (startsWith(vector_id, "artifact:")) {
    artifact_id <- sub("^artifact:", "", vector_id)
    return(wb_art_load(bundle, artifact_id = artifact_id, expected_kind = expected_kind))
  }

  if (startsWith(vector_id, "session:")) {
    .wb_assert(!is.null(session), "vector_id is session:* but session is NULL.")
    parts <- strsplit(vector_id, ":", fixed = TRUE)[[1]]
    .wb_assert(length(parts) >= 3, "session vector_id must be session:<run_id>:<output>")

    run_id <- parts[[2]]
    out_nm <- paste(parts[3:length(parts)], collapse=":") # tolerate ':' in output names

    run <- session$runs[[run_id]]
    .wb_assert(!is.null(run), paste0("No such run_id in session: ", run_id))
    prim <- run$outputs[[out_nm]]
    .wb_assert(!is.null(prim), paste0("Run ", run_id, " has no output '", out_nm, "'"))

    if (!is.null(expected_kind)) .wb_assert_kind(prim, expected_kind, where = paste0(" (", vector_id, ")"))
    return(prim)
  }

  stop("Unknown vector_id scheme: ", vector_id,
    ". Use wb_list_cell_vectors()$vector_id: artifact:<artifact_id> or session:<run_id>:<output>. ",
    "Read metadata fields with wb_meta(bundle, cols=...), or create a typed vector with metadata_cell_vector.",
    call. = FALSE)
}


wb_write_cell_vector <- function(
    bundle,
    vector_id,
    values,
    subset_cell_ids = NULL,
    overwrite = TRUE
) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert_mutation_context(bundle = bundle, action = "Legacy cell-vector payload mutation",
    allowed = c("assembly", "ingestion"),
    replacement = "wb_attach_cell_vector() within declared assembly, or a promoted cell_vector primitive")
  .wb_assert(is.character(vector_id) && length(vector_id) == 1 && nzchar(vector_id), "vector_id invalid")
  con <- bundle$con
  .wb_ensure_cell_vectors_tables(con)

  # normalize -> df(cell_id,value)
  df <- NULL
  if (is.data.frame(values)) {
    .wb_assert(all(c("cell_id","value") %in% colnames(values)), "values df must have cell_id,value")
    df <- values[, c("cell_id","value")]
  } else {
    .wb_assert(is.atomic(values), "values must be atomic or data.frame")
    .wb_assert(!is.null(names(values)) && all(nzchar(names(values))), "named vector required (names=cell_id)")
    df <- data.frame(cell_id = names(values), value = as.numeric(values), stringsAsFactors = FALSE)
  }

  df$cell_id <- as.character(df$cell_id)
  df$value <- as.numeric(df$value)

  if (!is.null(subset_cell_ids)) {
    subset_cell_ids <- as.character(subset_cell_ids)
    df <- df[df$cell_id %in% subset_cell_ids, , drop = FALSE]
  }

  # drop NA values => sparse storage
  df <- df[!is.na(df$value) & nzchar(df$cell_id), , drop = FALSE]
  if (nrow(df) == 0) return(invisible(0L))

  # optional: validate cells exist
  have <- DBI::dbGetQuery(
    con,
    "SELECT cell_id FROM cells WHERE cell_id IN (SELECT value FROM json_each(?));",
    params = list(jsonlite::toJSON(as.list(unique(df$cell_id)), auto_unbox = TRUE))
  )$cell_id
  df <- df[df$cell_id %in% have, , drop = FALSE]
  if (nrow(df) == 0) return(invisible(0L))

  if (isTRUE(overwrite)) {
    DBI::dbExecute(con, "DELETE FROM cell_vector_values WHERE vector_id = ?;", params = list(vector_id))
  } else {
    # keep existing; we'll insert/replace per key
    DBI::dbExecute(con, "DELETE FROM cell_vector_values WHERE vector_id = ? AND cell_id IN (SELECT value FROM json_each(?));",
                   params = list(vector_id, jsonlite::toJSON(as.list(unique(df$cell_id)), auto_unbox = TRUE))
    )
  }

  df$vector_id <- vector_id
  df <- df[, c("vector_id","cell_id","value")]
  DBI::dbWriteTable(con, "cell_vector_values", df, append = TRUE)

  invisible(nrow(df))
}

wb_vector_choices <- function(bundle) {
  df <- wb_list_cell_vectors(bundle)
  if (!nrow(df)) return(character(0))
  paste0("vec:", df$vector_id)
}
