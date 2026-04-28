#' Ingest new cells into an existing bundle as a named membership-based cell set
#'
#' - Inserts new rows into `cells` (cell_id + dataset_id)
#' - Writes membership rows into `cell_set_membership` for set:<set_name>
#' - Optionally ingests metadata and spaces for those cells
#' - Optionally ingests matrices via wb_attach_to_cells() (recommended canonical path)
#'
#' NOTE: dev-mode, fresh bundles only: we do NOT use legacy `cells.cell_set`.
#'
#' @param bundle scworkbench bundle handle (opened)
#' @param set_name Name of ingested set (stored in membership as cell_set = "set:<name>")
#' @param cell_ids Character vector of new cell IDs
#' @param metadata Optional data.frame. First column treated as cell_id if no "cell_id" column.
#' @param spaces Optional named list of spaces. Each entry can be:
#'   - 2D wide df: first col cell_id, next cols x,y (no colnames required)
#'   - high-D wide matrix/df: rownames=cell_id OR first col cell_id
#'   - long df: first col cell_id, second col dim, third col value (no colnames required)
#' @param matrices Optional named list passed to wb_attach_to_cells(matrices=...)
#' @param overwrite If TRUE, allow re-ingesting existing cell_ids (NOT implemented yet)
#' @param source Provenance string stored in membership rows / space registry
#' @param created_by Optional provenance
#' @export
wb_ingest_cells <- function(
    bundle,
    set_name,
    cell_ids,
    metadata = NULL,
    spaces = list(),
    matrices = list(),
    overwrite = FALSE,
    source = "ingest",
    created_by = NULL
) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be a scworkbench_bundle handle")
  .wb_assert(is.character(set_name) && length(set_name) == 1 && nzchar(set_name),
             "set_name must be a non-empty string")
  .wb_assert(is.character(cell_ids) && length(cell_ids) > 0,
             "cell_ids must be a non-empty character vector")

  con <- bundle$con
  cell_ids <- unique(as.character(cell_ids))
  cell_ids <- cell_ids[nzchar(cell_ids)]
  .wb_assert(length(cell_ids) > 0, "cell_ids empty after cleaning")

  cell_set <- paste0("set:", set_name)

  # Ensure schema primitives exist

  .wb_ensure_cell_set_membership_table(con)

  # -------------------------
  # 1) Validate non-existence (dev safety)
  # -------------------------
  cl <- .wb_sql_in_json(cell_ids)
  existing <- DBI::dbGetQuery(
    con,
    paste0("SELECT cell_id FROM cells WHERE cell_id IN ", cl$sql, ";"),
    params = cl$params
  )$cell_id
  existing <- as.character(existing)

  if (length(existing) > 0) {
    if (!isTRUE(overwrite)) {
      stop(
        "Some cell_ids already exist in bundle (overwrite=FALSE). First few: ",
        paste(head(existing, 10), collapse = ", "),
        call. = FALSE
      )
    }
    stop("overwrite=TRUE not implemented yet for safety.", call. = FALSE)
  }

  # -------------------------
  # 2) Insert into cells table (NO cell_set column used)
  # -------------------------
  # minimal row: cell_id + dataset_id. (dataset_id can be set_name for now.)
  new_cells_df <- data.frame(
    cell_id    = cell_ids,
    dataset_id = set_name,
    stringsAsFactors = FALSE
  )

  DBI::dbWriteTable(con, "cells", new_cells_df, append = TRUE)

  # -------------------------
  # 3) Add membership rows for this set
  # -------------------------
  created_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  ins <- data.frame(
    cell_set    = cell_set,
    cell_id     = cell_ids,
    source      = source,
    created_at  = created_at,
    created_by  = created_by %||% NA_character_,
    description = paste0("ingested cells for ", cell_set),
    stringsAsFactors = FALSE
  )
  DBI::dbWriteTable(con, "cell_set_membership", ins, append = TRUE)

  # -------------------------
  # 4) Metadata (optional) into cells table columns
  # -------------------------
  if (!is.null(metadata)) {
    .wb_ingest_cell_metadata(con, cell_ids, metadata)
  }

  # -------------------------
  # 5) Spaces (optional)
  # -------------------------
  if (length(spaces)) {
    for (space_id in names(spaces)) {
      coords <- spaces[[space_id]]
      .wb_ingest_space_coords(
        con        = con,
        bundle_dir = bundle$dir,
        space_id   = space_id,
        coords     = coords,
        cell_ids   = cell_ids,
        source     = source
      )
    }
  }

  # -------------------------
  # 6) Matrices (optional) — canonical path: attach fragments to THESE new cells
  # -------------------------
  if (length(matrices)) {
    wb_attach_to_cells(
      bundle   = bundle,
      matrices = matrices,
      cell_ids = cell_ids,     # restrict to these new cells
      source   = source,
      created_by = created_by
    )
  }

  invisible(list(
    set_name     = set_name,
    cell_set     = cell_set,
    n_ingested   = length(cell_ids),
    n_spaces     = length(spaces),
    n_matrices   = length(matrices)
  ))
}


# -------------------------
# Metadata ingestion (first column == cell_id if no explicit column)
# -------------------------
.wb_ingest_cell_metadata <- function(con, cell_ids, metadata) {
  .wb_assert(is.data.frame(metadata), "metadata must be a data.frame")

  md <- as.data.frame(metadata, stringsAsFactors = FALSE, check.names = FALSE)

  # first column is cell_id unless explicit "cell_id" exists
  if (!("cell_id" %in% colnames(md))) {
    .wb_assert(ncol(md) >= 1, "metadata must have at least 1 column")
    md$cell_id <- as.character(md[[1]])
  } else {
    md$cell_id <- as.character(md$cell_id)
  }

  md$cell_id <- as.character(md$cell_id)
  md <- md[md$cell_id %in% cell_ids, , drop = FALSE]
  if (!nrow(md)) return(invisible(TRUE))

  # Convert factor/logical
  for (nm in setdiff(colnames(md), "cell_id")) {
    x <- md[[nm]]
    if (is.factor(x))  x <- as.character(x)
    if (is.logical(x)) x <- as.integer(x)
    md[[nm]] <- x
  }

  # Add missing columns
  existing_cols <- DBI::dbListFields(con, "cells")
  new_cols <- setdiff(colnames(md), existing_cols)

  for (nm in new_cols) {
    x <- md[[nm]]
    col_type <- if (is.numeric(x)) "REAL" else "TEXT"
    if (is.integer(x)) col_type <- "INTEGER"
    DBI::dbExecute(con, sprintf('ALTER TABLE cells ADD COLUMN "%s" %s;', nm, col_type))
  }

  cols_to_write <- setdiff(colnames(md), "cell_id")
  if (length(cols_to_write)) {
    tmp_name <- paste0("tmp_cell_metadata_", as.integer(Sys.time()), "_", paste(sample(c(letters, 0:9), 6, replace = TRUE), collapse = ""))
    DBI::dbWriteTable(
      con,
      tmp_name,
      md[, c("cell_id", cols_to_write), drop = FALSE],
      temporary = TRUE,
      overwrite = TRUE
    )

    quoted_cols <- vapply(cols_to_write, DBI::dbQuoteIdentifier, character(1), conn = con)
    set_sql <- paste(
      sprintf(
        "%s = (SELECT t.%s FROM %s t WHERE t.cell_id = cells.cell_id)",
        quoted_cols,
        quoted_cols,
        tmp_name
      ),
      collapse = ", "
    )

    DBI::dbExecute(
      con,
      sprintf(
        "UPDATE cells
            SET %s
          WHERE cell_id IN (SELECT cell_id FROM %s);",
        set_sql,
        tmp_name
      )
    )
    DBI::dbExecute(con, sprintf("DROP TABLE IF EXISTS %s;", tmp_name))
  }

  invisible(TRUE)
}


# -------------------------
# Space ingestion (2D wide -> space_2d ; otherwise -> long space_coords)
# First column ALWAYS treated as cell_id, no explicit names required.
# -------------------------
.wb_ingest_space_coords <- function(con, bundle_dir, space_id, coords, cell_ids, source = "ingest") {
  .wb_assert(is.character(space_id) && length(space_id) == 1 && nzchar(space_id), "space_id invalid")

  # Helper: normalize df where first col is cell_id
  normalize_df_first_col_id <- function(df) {
    df <- as.data.frame(df, stringsAsFactors = FALSE, check.names = FALSE)
    .wb_assert(ncol(df) >= 1, "coords data.frame must have at least 1 column")
    cell <- as.character(df[[1]])
    .wb_assert(all(nzchar(cell)), "coords first column (cell_id) has empty values")
    df$..cell_id <- cell
    df
  }

  # -------------------------
  # Case 1: data.frame with >= 3 columns could be:
  #   - 2D wide: [cell_id, x, y]
  #   - long:    [cell_id, dim, value]
  # We decide by column 2 type: if integer-ish and column3 numeric -> long.
  # Otherwise treat as 2D if exactly 3 columns, else treat as wide high-D.
  # -------------------------
  if (is.data.frame(coords)) {
    df <- normalize_df_first_col_id(coords)
    df <- df[df$..cell_id %in% cell_ids, , drop = FALSE]
    if (!nrow(df)) return(invisible(TRUE))

    if (ncol(df) >= 3) {
      v2 <- df[[2]]
      v3 <- df[[3]]

      looks_long <- (is.numeric(v2) || is.integer(v2)) && (is.numeric(v3) || is.integer(v3))
      if (isTRUE(looks_long)) {
        # interpret as long: [cell_id, dim, value]
        out <- data.frame(
          space_id = space_id,
          cell_id  = as.character(df$..cell_id),
          dim      = as.integer(df[[2]]),
          value    = as.numeric(df[[3]]),
          stringsAsFactors = FALSE
        )

        .wb_ensure_space_registered(
          con, space_id,
          dims = max(out$dim, na.rm = TRUE),
          storage = "long:space_coords",
          source = source,
          description = space_id
        )

        DBI::dbWriteTable(con, "space_coords", out, append = TRUE)
        return(invisible(TRUE))
      }

      # If exactly 3 cols -> treat as 2D wide [cell_id, x, y]
      if (ncol(df) == 3) {
        out <- data.frame(
          space_id = space_id,
          cell_id  = as.character(df$..cell_id),
          x        = as.numeric(df[[2]]),
          y        = as.numeric(df[[3]]),
          stringsAsFactors = FALSE
        )

        .wb_ensure_space_registered(
          con, space_id,
          dims = 2L,
          storage = "wide:space_2d",
          source = source,
          description = space_id
        )

        DBI::dbWriteTable(con, "space_2d", out, append = TRUE)
        return(invisible(TRUE))
      }

      # Otherwise: wide high-D stored in remaining columns 2:n
      m <- as.matrix(df[, 2:(ncol(df)-1), drop = FALSE])  # exclude ..cell_id tail
      rownames(m) <- as.character(df$..cell_id)
      return(.wb_ingest_space_matrix_long(con, space_id, m, source = source))
    }

    stop("coords data.frame must have at least 3 columns: [cell_id,x,y] or [cell_id,dim,value].", call. = FALSE)
  }

  # -------------------------
  # Case 2: matrix-like high-D (rownames = cell_id OR first col is cell_id)
  # -------------------------
  m <- coords
  if (is.data.frame(m)) m <- as.matrix(m)
  .wb_assert(is.matrix(m), "space coords must be a data.frame or matrix-like object")

  if (is.null(rownames(m)) || !all(nzchar(rownames(m)))) {
    stop("High-D coords matrix must have rownames=cell_id (or provide as data.frame with first col=cell_id).",
         call. = FALSE)
  }

  m <- m[intersect(cell_ids, rownames(m)), , drop = FALSE]
  if (!nrow(m)) return(invisible(TRUE))

  .wb_ingest_space_matrix_long(con, space_id, m, source = source)
}


# Write a wide matrix (cells x dims) into space_coords long format
.wb_ingest_space_matrix_long <- function(con, space_id, m, source = "ingest") {
  if (is.data.frame(m)) m <- as.matrix(m)
  .wb_assert(is.matrix(m), "m must be a matrix")
  .wb_assert(!is.null(rownames(m)) && all(nzchar(rownames(m))), "m must have rownames (cell_id)")

  dims <- ncol(m)
  .wb_assert(dims >= 1, "m has 0 columns")

  .wb_ensure_space_registered(
    con, space_id,
    dims = dims,
    storage = "long:space_coords",
    source = source,
    description = space_id
  )

  # Chunk by cells (safe, simple)
  chunk <- 2000L
  r <- seq_len(nrow(m))
  for (s in seq(1, length(r), by = chunk)) {
    ii <- r[s:min(s + chunk - 1L, length(r))]
    sub <- m[ii, , drop = FALSE]

    df_long <- do.call(rbind, lapply(seq_len(dims), function(d) {
      data.frame(
        space_id = space_id,
        cell_id  = rownames(sub),
        dim      = d,
        value    = as.numeric(sub[, d]),
        stringsAsFactors = FALSE
      )
    }))

    DBI::dbWriteTable(con, "space_coords", df_long, append = TRUE)
  }

  invisible(TRUE)
}


# Register space in `spaces` if missing
.wb_ensure_space_registered <- function(con, space_id, dims, storage, source, description) {
  exists <- DBI::dbGetQuery(con, "SELECT space_id FROM spaces WHERE space_id = ?;", params = list(space_id))
  if (!nrow(exists)) {
    DBI::dbWriteTable(con, "spaces", data.frame(
      space_id = space_id,
      source = source,
      dims = as.integer(dims),
      storage = storage,
      description = description,
      stringsAsFactors = FALSE
    ), append = TRUE)
  } else {
    # keep existing, but ensure dims/storage are not empty
    DBI::dbExecute(con, "
      UPDATE spaces
      SET dims = COALESCE(dims, ?),
          storage = COALESCE(storage, ?),
          source = COALESCE(source, ?),
          description = COALESCE(description, ?)
      WHERE space_id = ?;",
                   params = list(as.integer(dims), storage, source, description, space_id)
    )
  }
  invisible(TRUE)
}
