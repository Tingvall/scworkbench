#' Attach primitives to existing cells (matrices/spaces/metadata)
#'
#' Canonical rule: FIRST COLUMN = cell_id, regardless of name.
#' No "cell_id" column semantics anywhere.
#'
#' @param bundle scworkbench_bundle
#' @param matrices Named list. Each entry name is the `matrix_id`. Each entry can be:
#'   - a Matrix-like object (sparse ok) with colnames=cell_id and rownames=feature_id
#'   - OR a list(mat=..., layer=..., feature_type=..., description=...)
#' @param spaces Named list (space_id -> data.frame). Each object must be a data.frame:
#'   - 2D: first col=cell_id, plus x,y
#'   - long: first col=cell_id, plus dim,value
#' @param metadata Optional data.frame: first col=cell_id, rest are metadata cols
#' @param cell_ids Optional character vector: restrict attach to these cells (must exist in bundle)
#' @param source Stored in registries
#' @param created_by Optional (currently unused here; kept for forward compatibility)
#' @return report list
#' @export
wb_attach_to_cells <- function(
    bundle,
    matrices = NULL,
    spaces = NULL,
    metadata = NULL,
    cell_ids = NULL,
    source = "attach",
    created_by = NULL
) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be a scworkbench_bundle")
  con <- bundle$con
  .wb_assert(!is.null(con), "bundle$con is NULL (no DB connection).")

  # Ensure required tables exist
  #.wb_ensure_matrix_fragments_table(con)

  as_chr <- function(x) as.character(x)

  # FIRST COLUMN ONLY = cell_id (name irrelevant)
  .take_first_col_as_cell_id <- function(df, what = "attachment") {
    df <- as.data.frame(df, stringsAsFactors = FALSE, check.names = FALSE)
    .wb_assert(ncol(df) >= 1, paste0(what, " must have at least 1 column (first col = cell_id)."))

    ids <- as_chr(df[[1]])
    .wb_assert(length(ids) == nrow(df), paste0(what, ": first column length mismatch."))
    .wb_assert(!anyNA(ids), paste0(what, ": first column contains NA cell ids."))

    ids <- ids[nzchar(ids)]
    .wb_assert(length(ids) == nrow(df), paste0(what, ": first column contains empty cell ids."))

    payload <- df[, -1, drop = FALSE]
    list(cell_ids = ids, data = payload)
  }

  # ---- infer target cell_ids if NULL ----
  if (is.null(cell_ids)) {
    cands <- character(0)

    # matrices: from colnames
    if (!is.null(matrices) && length(matrices)) {
      for (nm in names(matrices)) {
        x <- matrices[[nm]]
        mat <- if (is.list(x) && !is.null(x$mat)) x$mat else x
        if (!is.null(colnames(mat))) cands <- c(cands, as_chr(colnames(mat)))
      }
    }

    # spaces + metadata: from first column
    if (!is.null(spaces) && length(spaces)) {
      for (sid in names(spaces)) {
        obj <- spaces[[sid]]
        .wb_assert(is.data.frame(obj), paste0("Space '", sid, "' must be a data.frame (first col = cell_id)."))
        cands <- c(cands, as_chr(obj[[1]]))
      }
    }

    if (!is.null(metadata)) {
      .wb_assert(is.data.frame(metadata), "metadata must be a data.frame (first col = cell_id).")
      cands <- c(cands, as_chr(metadata[[1]]))
    }

    cell_ids <- unique(cands[nzchar(cands)])
    .wb_assert(length(cell_ids) > 0, "Could not infer cell_ids from attachments.")
  } else {
    cell_ids <- unique(as_chr(cell_ids))
    cell_ids <- cell_ids[nzchar(cell_ids)]
    .wb_assert(length(cell_ids) > 0, "cell_ids provided but empty after cleaning")
  }

  # ---- restrict to cells that actually exist in bundle ----
  existing <- as_chr(DBI::dbGetQuery(con, "SELECT cell_id FROM cells;")$cell_id)
  keep <- intersect(cell_ids, existing)
  .wb_assert(length(keep) > 0, "None of the provided/inferred cell_ids exist in this bundle.")
  missing <- setdiff(cell_ids, existing)

  report <- list(
    n_target_cells = length(cell_ids),
    n_existing_cells = length(keep),
    n_missing_cells = length(missing),
    missing_cells_head = head(missing, 20),
    matrices = list(),
    spaces = list(),
    metadata = NULL
  )

  # ============================================================
  # 1) METADATA ATTACH (SQLite cells table)
  # ============================================================
  if (!is.null(metadata)) {
    md_res <- .take_first_col_as_cell_id(metadata, what = "metadata")
    md <- md_res$data
    md$cell_id <- md_res$cell_ids

    md <- md[md$cell_id %in% keep, , drop = FALSE]

    if (nrow(md) > 0) {
      existing_cols <- DBI::dbGetQuery(con, "PRAGMA table_info(cells);")$name

      # add columns if needed
      for (nm in setdiff(colnames(md), "cell_id")) {
        if (nm %in% existing_cols) next

        x <- md[[nm]]
        if (is.factor(x)) x <- as.character(x)
        if (is.logical(x)) x <- as.integer(x)

        col_type <- if (is.integer(x)) "INTEGER" else if (is.numeric(x)) "REAL" else "TEXT"
        DBI::dbExecute(con, sprintf('ALTER TABLE cells ADD COLUMN "%s" %s;', nm, col_type))
      }

      # update row-by-row (simple + safe)
      for (nm in setdiff(colnames(md), "cell_id")) {
        vals <- md[[nm]]
        for (i in seq_len(nrow(md))) {
          DBI::dbExecute(
            con,
            sprintf('UPDATE cells SET "%s" = ? WHERE cell_id = ?;', nm),
            params = list(vals[[i]], md$cell_id[[i]])
          )
        }
      }

      report$metadata <- list(n_rows = nrow(md), cols = setdiff(colnames(md), "cell_id"))
    } else {
      report$metadata <- list(n_rows = 0, cols = character(0))
    }
  }

  # ============================================================
  # 2) SPACES ATTACH (SQLite spaces tables)
  # ============================================================
  if (!is.null(spaces) && length(spaces)) {
    for (space_id in names(spaces)) {
      obj <- spaces[[space_id]]
      .wb_assert(is.data.frame(obj), paste0("Space '", space_id, "' must be a data.frame (first col = cell_id)."))

      sp_res <- .take_first_col_as_cell_id(obj, what = paste0("space '", space_id, "'"))
      df <- sp_res$data
      df$cell_id <- sp_res$cell_ids

      df$cell_id <- as_chr(df$cell_id)
      df <- df[df$cell_id %in% keep, , drop = FALSE]

      if (nrow(df) == 0) {
        report$spaces[[space_id]] <- list(type = "empty", n = 0)
        next
      }

      if (all(c("x", "y") %in% colnames(df))) {
        DBI::dbExecute(
          con,
          "INSERT OR IGNORE INTO spaces(space_id, source, dims, storage, description) VALUES(?, ?, ?, ?, ?);",
          params = list(space_id, source, 2L, "wide:space_2d", space_id)
        )

        cells_u <- unique(df$cell_id)
        chunk <- 1000L
        for (s in seq(1, length(cells_u), by = chunk)) {
          sub <- cells_u[s:min(s + chunk - 1, length(cells_u))]
          DBI::dbExecute(
            con,
            "DELETE FROM space_2d
             WHERE space_id = ? AND cell_id IN (SELECT value FROM json_each(?));",
            params = list(space_id, jsonlite::toJSON(as.list(sub), auto_unbox = TRUE))
          )
        }

        DBI::dbWriteTable(
          con, "space_2d",
          data.frame(
            space_id = space_id,
            cell_id = df$cell_id,
            x = as.numeric(df$x),
            y = as.numeric(df$y),
            stringsAsFactors = FALSE
          ),
          append = TRUE
        )

        report$spaces[[space_id]] <- list(type = "2d", n = nrow(df))

      } else if (all(c("dim", "value") %in% colnames(df))) {
        DBI::dbExecute(
          con,
          "INSERT OR IGNORE INTO spaces(space_id, source, dims, storage, description) VALUES(?, ?, ?, ?, ?);",
          params = list(space_id, source, NA_integer_, "long:space_coords", space_id)
        )

        df$dim <- as.integer(df$dim)
        df$value <- as.numeric(df$value)

        cells_u <- unique(df$cell_id)
        chunk <- 1000L
        for (s in seq(1, length(cells_u), by = chunk)) {
          sub <- cells_u[s:min(s + chunk - 1, length(cells_u))]
          DBI::dbExecute(
            con,
            "DELETE FROM space_coords
             WHERE space_id = ? AND cell_id IN (SELECT value FROM json_each(?));",
            params = list(space_id, jsonlite::toJSON(as.list(sub), auto_unbox = TRUE))
          )
        }

        DBI::dbWriteTable(
          con, "space_coords",
          data.frame(
            space_id = space_id,
            cell_id = df$cell_id,
            dim = df$dim,
            value = df$value,
            stringsAsFactors = FALSE
          ),
          append = TRUE
        )

        report$spaces[[space_id]] <- list(type = "long", n = nrow(df))

      } else {
        stop(
          "Space '", space_id, "' must have either columns (x,y) for 2D, or (dim,value) for long. ",
          "Reminder: first column is cell_id and is not part of the payload columns.",
          call. = FALSE
        )
      }
    }
  }

  # ============================================================
  # 3) MATRICES ATTACH (BPCells fragments + registry)
  # ============================================================
  if (!is.null(matrices) && length(matrices)) {
    .wb_require_pkg("BPCells", "matrix attach")
    .wb_require_pkg("Matrix", "matrix attach")

    for (matrix_id in names(matrices)) {
      x <- matrices[[matrix_id]]
      mat <- if (is.list(x) && !is.null(x$mat)) x$mat else x

      layer <- if (is.list(x) && !is.null(x$layer)) x$layer else "counts"
      feature_type <- if (is.list(x) && !is.null(x$feature_type)) x$feature_type else "feature"
      description <- if (is.list(x) && !is.null(x$description)) x$description else NULL

      if (!inherits(mat, "Matrix")) mat <- Matrix::Matrix(mat, sparse = TRUE)

      .wb_assert(!is.null(rownames(mat)), paste0("Matrix ", matrix_id, " missing rownames (feature_ids)"))
      .wb_assert(!is.null(colnames(mat)), paste0("Matrix ", matrix_id, " missing colnames (cell_ids)"))

      feature_ids <- as_chr(rownames(mat))
      col_cells <- as_chr(colnames(mat))

      keep_cols <- intersect(col_cells, keep)
      .wb_assert(length(keep_cols) > 0, paste0("Matrix ", matrix_id, " has no columns matching bundle cells."))

      mat2 <- mat[, match(keep_cols, col_cells), drop = FALSE]
      colnames(mat2) <- keep_cols

      # ensure matrices row exists (create if missing)
      have <- DBI::dbGetQuery(
        con,
        "SELECT matrix_id FROM matrices WHERE matrix_id = ?;",
        params = list(matrix_id)
      )

      if (nrow(have) == 0) {
        DBI::dbWriteTable(
          con, "matrices",
          data.frame(
            matrix_id = matrix_id,
            layer = layer,
            feature_type = feature_type,
            n_features = NA_integer_,
            n_cells = NA_integer_,
            storage = "bpcells",
            path = NA_character_,
            description = description %||% paste0("Created by attach (", source, ")"),
            stringsAsFactors = FALSE
          ),
          append = TRUE
        )
      }

      # write BPCells fragment
      frag_dirname <- paste0("mat_frag_", matrix_id, "_", format(Sys.time(), "%Y%m%d_%H%M%S"))
      rel_path <- file.path("mat", frag_dirname)
      abs_path <- file.path(bundle$dir, rel_path)

      if (dir.exists(abs_path)) unlink(abs_path, recursive = TRUE, force = TRUE)
      BPCells::write_matrix_dir(mat2, abs_path)

      # register fragment (your existing registry is the authority)
      frag_id <- wb_register_matrix_fragment(
        con = con,
        matrix_id = matrix_id,
        path_rel = rel_path,
        feature_ids = feature_ids,
        cell_ids = keep_cols,
        source = source,
        created_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S")
      )

      report$matrices[[matrix_id]] <- list(
        fragment_id = frag_id,
        n_features = length(feature_ids),
        n_cells = length(keep_cols),
        path = rel_path
      )
    }
  }

  report
}
