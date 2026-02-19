# R/getters.R
# scworkbench v1 getters: small but exhaustive read API over SQLite + BPCells
#
# Public contract (exported):
# - wb_open_bundle(), wb_close_bundle(), wb_manifest(), wb_list()
# - wb_cells(), wb_meta()
# - wb_features(), wb_feature_ids()
# - wb_space_info(), wb_space()
# - wb_matrix_info(), wb_matrix()
# - wb_slice(), wb_vector()
#
# Internal helpers are prefixed with . (not exported).

.wb_nonempty_or <- function(a, b) {
  if (!is.null(a) && length(a) > 0 && nzchar(as.character(a[1]))) a else b
}


.wb_as_sparse <- function(x) {
  # 1) Already a Matrix?
  if (inherits(x, "Matrix")) return(x)

  # 2) Try S4 coercion to dgCMatrix
  if (methods::is(x, "S4")) {
    y <- try(methods::as(x, "dgCMatrix"), silent = TRUE)
    if (!inherits(y, "try-error") && inherits(y, "dgCMatrix")) return(y)
  }

  # 3) Try BPCells helper functions if present (API varies by version)
  if (requireNamespace("BPCells", quietly = TRUE)) {
    ns <- asNamespace("BPCells")

    # common-ish names across versions / forks
    for (fname in c("as_sparse_matrix", "as_sparse", "to_sparse", "convert_to_sparse")) {
      if (exists(fname, where = ns, mode = "function")) {
        f <- get(fname, envir = ns)
        y <- try(f(x), silent = TRUE)
        if (!inherits(y, "try-error") && inherits(y, "Matrix")) return(y)
      }
    }
  }

  # 4) Last resort: materialize only small dense matrices, otherwise fail fast.
  # This prevents accidental sparse->dense explosions on large pulls.
  d <- try(dim(x), silent = TRUE)
  if (!inherits(d, "try-error") && length(d) == 2 && all(is.finite(d))) {
    n <- as.numeric(d[1]) * as.numeric(d[2])
    est_mb <- (n * 8) / (1024^2)
    limit_mb <- getOption("scworkbench.max_dense_materialize_mb", 256)
    if (is.finite(est_mb) && est_mb > as.numeric(limit_mb)) {
      stop(
        paste0(
          "Refusing sparse->dense materialization of ~", round(est_mb, 1),
          " MB (limit=", limit_mb, " MB). ",
          "Requested slice is too large for fallback coercion. ",
          "Reduce features/cells or use a sparse-compatible matrix backend."
        ),
        call. = FALSE
      )
    }
  }

  y <- try(as.matrix(x), silent = TRUE)
  if (inherits(y, "try-error")) {
    stop("Could not coerce BPCells slice to a sparse Matrix. Try updating BPCells or reduce slice size.", call. = FALSE)
  }
  Matrix::Matrix(y, sparse = TRUE)
}

.wb_as_numeric <- function(x) {
  # Plain numeric already?
  if (is.numeric(x)) return(as.numeric(x))

  # Many S4 objects can be coerced via as.vector or as.numeric methods,
  # but if not, try as.matrix/as.array as a fallback for small objects.
  y <- try(as.numeric(x), silent = TRUE)
  if (!inherits(y, "try-error")) return(y)

  y <- try(as.vector(x), silent = TRUE)
  if (!inherits(y, "try-error") && is.numeric(y)) return(as.numeric(y))

  # BPCells sometimes yields a 1 x n or n x 1 matrix-like object.
  y <- try(as.matrix(x), silent = TRUE)
  if (!inherits(y, "try-error")) return(as.numeric(y))

  y <- try(as.array(x), silent = TRUE)
  if (!inherits(y, "try-error")) return(as.numeric(y))

  stop("Could not coerce BPCells result to numeric vector.", call. = FALSE)
}



.wb_sqlite_quote_vec <- function(x) {
  # Quote strings for an IN (...) clause (for small vectors).
  # We use DBI quoting to be safe; for large vectors, prefer joins/temp tables later.
  if (length(x) == 0) return("(NULL)")
  paste0("(", paste(DBI::dbQuoteString(RSQLite::SQLite(), as.character(x)), collapse = ","), ")")
}

.wb_table_exists <- function(con, tbl) {
  tbl %in% DBI::dbListTables(con)
}

.wb_get_matrices_row <- function(con, matrix_id) {
  row <- DBI::dbGetQuery(con, "SELECT * FROM matrices WHERE matrix_id = ?;", params = list(matrix_id))
  .wb_assert(nrow(row) == 1, paste0("Matrix not found: ", matrix_id))
  row
}

.wb_get_spaces_row <- function(con, space_id) {
  row <- DBI::dbGetQuery(con, "SELECT * FROM spaces WHERE space_id = ?;", params = list(space_id))
  .wb_assert(nrow(row) == 1, paste0("Space not found: ", space_id))
  row
}

.wb_sql_in_placeholders <- function(n) {
  .wb_assert(n >= 1, "Need at least one placeholder")
  paste0("(", paste(rep("?", n), collapse = ","), ")")
}


.wb_bp_open_matrix_dir <- function(path) {
  .wb_assert(requireNamespace("BPCells", quietly = TRUE),
             "BPCells not installed. Install it to access matrices.")
  if (exists("open_matrix_dir", where = asNamespace("BPCells"), mode = "function")) {
    return(BPCells::open_matrix_dir(path))
  }
  if (exists("open_matrix", where = asNamespace("BPCells"), mode = "function")) {
    return(BPCells::open_matrix(path))
  }
  stop("No supported BPCells open function found (expected open_matrix_dir or open_matrix).", call. = FALSE)
}

#' Get the manifest from an scworkbench bundle
#'
#' @param bundle Bundle handle from `wb_open_bundle()`
#' @return Parsed manifest list
#' @export
wb_manifest <- function(bundle) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be a scworkbench_bundle handle")
  bundle$manifest
}

#' List registry tables in the bundle
#'
#' Convenience entry point to list key registries from SQLite.
#'
#' @param bundle Bundle handle from `wb_open_bundle()`
#' @param what One of: "matrices", "features", "spaces", "datasets"
#' @return A data.frame
#' @export
wb_list <- function(bundle, what = c("matrices", "features", "spaces", "datasets")) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be a scworkbench_bundle handle")
  what <- match.arg(what)
  con <- bundle$con
  .wb_assert(.wb_table_exists(con, what), paste0("Table not found in SQLite: ", what))
  DBI::dbReadTable(con, what)
}

#' List cell IDs in canonical bundle order
#'
#' @param bundle scworkbench bundle handle
#' @param dataset_id Optional dataset filter
#' @param cell_set Which cell set to use: "core" (default), "all", or "set:<name>"
#' @export
wb_cells <- function(bundle, cell_set = "core", dataset_id = NULL) {
  con <- bundle$con
  .wb_ensure_cell_set_membership_table(con)

  if (identical(cell_set, "all")) {
    if (is.null(dataset_id)) return(DBI::dbGetQuery(con, "SELECT cell_id FROM cells ORDER BY rowid;")$cell_id)
    return(DBI::dbGetQuery(con, "SELECT cell_id FROM cells WHERE dataset_id=? ORDER BY rowid;", params=list(dataset_id))$cell_id)
  }

  # membership query
  if (is.null(dataset_id)) {
    return(DBI::dbGetQuery(con, "
      SELECT c.cell_id
      FROM cell_set_membership m
      JOIN cells c ON c.cell_id = m.cell_id
      WHERE m.cell_set = ?
      ORDER BY c.rowid;", params = list(cell_set))$cell_id)
  }

  DBI::dbGetQuery(con, "
    SELECT c.cell_id
    FROM cell_set_membership m
    JOIN cells c ON c.cell_id = m.cell_id
    WHERE m.cell_set = ? AND c.dataset_id = ?
    ORDER BY c.rowid;",
                  params = list(cell_set, dataset_id)
  )$cell_id
}


#' Get cell metadata
#'
#' Returns metadata rows aligned to the requested `cells` vector if provided.
#'
#' @param bundle Bundle handle from `wb_open_bundle()`
#' @param cells Optional cell_ids to subset/align (order preserved)
#' @param cols Optional metadata columns to select (default all columns)
#' @param dataset_id Optional dataset filter applied before `cells` alignment
#' @return A data.frame
#' @export
wb_meta <- function(bundle, cells = NULL, cols = NULL, dataset_id = NULL) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be a scworkbench_bundle handle")
  con <- bundle$con

  all_cols <- DBI::dbListFields(con, "cells")
  .wb_assert("cell_id" %in% all_cols, "cells table missing cell_id column")

  if (is.null(cols)) {
    cols <- all_cols
  } else {
    missing <- setdiff(cols, all_cols)
    .wb_assert(length(missing) == 0, paste0("Unknown cells columns: ", paste(missing, collapse = ", ")))
  }

  sel <- paste(sprintf('"%s"', cols), collapse = ", ")
  q <- paste0("SELECT ", sel, " FROM cells")
  params <- list()

  if (!is.null(dataset_id)) {
    q <- paste0(q, " WHERE dataset_id = ?")
    params <- c(params, list(dataset_id))
  }

  df <- if (length(params) == 0) DBI::dbGetQuery(con, q) else DBI::dbGetQuery(con, q, params = params)

  if (!is.null(cells)) {
    ii <- match(cells, df$cell_id)
    .wb_assert(!anyNA(ii), "Some requested cells not found in cells table.")
    df <- df[ii, , drop = FALSE]
  }

  df
}

#' Get features registry
#'
#' Returns the registered features for a matrix (matrix_id-first world).
#'
#' @param bundle Bundle handle from `wb_bundle_open()`.
#' @param matrix_id Optional matrix identifier (exact match). If NULL, returns all features.
#' @param feature_type Optional feature_type filter (e.g. "gene", "peak").
#'
#' @return A data.frame with columns:
#'   matrix_id, feature_id, feature_type, chr, start, end
#' @export
wb_features <- function(bundle, matrix_id = NULL, feature_type = NULL) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"),
             "bundle must be a scworkbench_bundle handle")

  con <- bundle$con
  .wb_assert(!is.null(con), "bundle$con is NULL (no DB connection).")
  .wb_assert(.wb_table_exists(con, "features"),
             "features table not found in SQLite")

  # hard requirement in the new world
  flds <- DBI::dbListFields(con, "features")
  .wb_assert("matrix_id" %in% flds,
             "features table must contain column 'matrix_id' (matrix_id-first bundles only).")

  q <- "SELECT matrix_id, feature_id, feature_type, chr, start, end FROM features"
  where <- character(0)
  params <- list()

  if (!is.null(matrix_id)) {
    .wb_assert(is.character(matrix_id) && length(matrix_id) == 1 && nzchar(matrix_id),
               "matrix_id must be a length-1 non-empty string")
    where <- c(where, "matrix_id = ?")
    params <- c(params, list(matrix_id))
  }

  if (!is.null(feature_type)) {
    .wb_assert(is.character(feature_type) && length(feature_type) == 1 && nzchar(feature_type),
               "feature_type must be a length-1 non-empty string")
    where <- c(where, "feature_type = ?")
    params <- c(params, list(feature_type))
  }

  if (length(where) > 0) q <- paste0(q, " WHERE ", paste(where, collapse = " AND "))
  q <- paste0(q, " ORDER BY matrix_id, rowid;")  # rowid = publish insertion order

  if (length(params) == 0) DBI::dbGetQuery(con, q) else DBI::dbGetQuery(con, q, params = params)
}



#' Get feature IDs in canonical order for a matrix
#'
#' Important: this defines the row order for matrices for that `matrix_id`.
#' The canonical order is the insertion order during bundle publish (SQLite `rowid`).
#'
#' @param bundle Bundle handle from `wb_bundle_open()`.
#' @param matrix_id Matrix ID (exact match), e.g. "RNA_counts" or "ATAC_counts".
#' @param feature_type Optional filter (e.g. "gene", "peak"). If provided, only
#'   returns features of that type within the matrix.
#'
#' @return Character vector of `feature_id`s in canonical row order.
#' @export
wb_feature_ids <- function(bundle, matrix_id, feature_type = NULL) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"),
             "bundle must be a scworkbench_bundle handle")

  .wb_assert(is.character(matrix_id) && length(matrix_id) == 1 && nzchar(matrix_id),
             "matrix_id must be a non-empty string")

  con <- bundle$con
  .wb_assert(!is.null(con), "bundle$con is NULL (no DB connection).")
  .wb_assert(.wb_table_exists(con, "features"), "features table not found in SQLite")

  q <- "SELECT feature_id FROM features WHERE matrix_id = ?"
  params <- list(matrix_id)

  if (!is.null(feature_type)) {
    .wb_assert(is.character(feature_type) && length(feature_type) == 1 && nzchar(feature_type),
               "feature_type must be a non-empty string when provided")
    q <- paste0(q, " AND feature_type = ?")
    params <- c(params, list(feature_type))
  }

  # `rowid` preserves insertion order from publish (canonical order).
  q <- paste0(q, " ORDER BY rowid;")

  res <- DBI::dbGetQuery(con, q, params = params)$feature_id
  .wb_assert(length(res) > 0, paste0("No features found for matrix_id: ", matrix_id))
  as.character(res)
}


#' Get space registry info
#'
#' @param bundle Bundle handle from `wb_open_bundle()`
#' @param space_id Optional space_id to filter (exact match)
#' @return A data.frame of spaces
#' @export
wb_space_info <- function(bundle, space_id = NULL) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be a scworkbench_bundle handle")
  con <- bundle$con
  .wb_assert(.wb_table_exists(con, "spaces"), "spaces table not found in SQLite")

  if (is.null(space_id)) {
    return(DBI::dbReadTable(con, "spaces"))
  }
  DBI::dbGetQuery(con, "SELECT * FROM spaces WHERE space_id = ?;", params = list(space_id))
}

#' Get space coordinates
#'
#' Unified getter that automatically reads either:
#' - `space_2d` if the space is stored as 2D wide coords
#' - `space_coords` if stored as long coords
#'
#' Always aligns rows to the requested `cells` order if provided.
#'
#' @param bundle Bundle handle from `wb_open_bundle()`
#' @param space_id Space identifier
#' @param cells Optional cell_ids to subset/align (order preserved)
#' @param dims Optional integer vector of dims (only for long storage)
#' @return If 2D: data.frame with columns cell_id,x,y. If >2D: numeric matrix (cells x dims).
#' @export
wb_space <- function(bundle, space_id, cells = NULL, dims = NULL) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be a scworkbench_bundle handle")
  con <- bundle$con

  info <- .wb_get_spaces_row(con, space_id)
  storage <- .wb_nonempty_or(info$storage, "")
  dims_total <- as.integer(.wb_nonempty_or(info$dims, NA_integer_))

  if (grepl("^wide:space_2d", storage) || (!is.na(dims_total) && dims_total == 2 && .wb_table_exists(con, "space_2d"))) {
    df <- DBI::dbGetQuery(con,
                          "SELECT cell_id, x, y FROM space_2d WHERE space_id = ?;",
                          params = list(space_id)
    )

    if (!is.null(cells)) {
      ii <- match(cells, df$cell_id)
      .wb_assert(!anyNA(ii), "Some requested cells not found in space_2d for this space_id.")
      df <- df[ii, , drop = FALSE]
    }

    return(df)
  }

  # Long storage: space_coords
  .wb_assert(.wb_table_exists(con, "space_coords"), "space_coords table not found in SQLite")

  if (is.null(dims)) {
    # determine max dim from table
    dmax <- DBI::dbGetQuery(con,
                            "SELECT MAX(dim) AS dmax FROM space_coords WHERE space_id = ?;",
                            params = list(space_id)
    )$dmax
    .wb_assert(!is.na(dmax), paste0("No coords found for space_id: ", space_id))
    dims <- seq_len(as.integer(dmax))
  } else {
    dims <- as.integer(dims)
    .wb_assert(length(dims) > 0, "dims must be a non-empty integer vector")
  }

  # Fetch only required rows. dims IN (...) built for modest dims vectors.
  cl <- .wb_sql_in_clause(as.integer(dims))
  q <- paste0(
    "SELECT cell_id, dim, value FROM space_coords WHERE space_id = ? AND dim ",
    cl$sql
  )

  df <- DBI::dbGetQuery(con, q, params = c(list(space_id), cl$params))

  .wb_assert(nrow(df) > 0, paste0("No coords found for space_id: ", space_id))

  if (is.null(cells)) {
    # Use canonical cell order if available: bundle cells order
    cells <- wb_cells(bundle)
    df <- df[df$cell_id %in% cells, , drop = FALSE]
  } else {
    df <- df[df$cell_id %in% cells, , drop = FALSE]
  }

  # Build dense matrix (cells x dims)
  ci <- match(df$cell_id, cells)
  di <- match(df$dim, dims)

  mat <- matrix(NA_real_, nrow = length(cells), ncol = length(dims))
  mat[cbind(ci, di)] <- df$value

  rownames(mat) <- cells
  colnames(mat) <- paste0("dim", dims)
  mat
}

#' List spaces in the bundle
#' @export
wb_spaces <- function(bundle) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  con <- bundle$con

  df <- DBI::dbGetQuery(con, "
    SELECT space_id, source, dims, storage, description
    FROM spaces
    ORDER BY space_id;
  ")

  # hard guard: never allow phantom rows
  df <- df[!is.na(df$space_id) & nzchar(df$space_id), , drop = FALSE]

  df
}

#' Get matrix registry info
#'
#' @param bundle Bundle handle from `wb_open_bundle()`
#' @param matrix_id Optional matrix_id to filter (exact match)
#' @return A data.frame of matrices
#' @export
wb_matrix_info <- function(bundle, matrix_id = NULL) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be a scworkbench_bundle handle")
  con <- bundle$con
  .wb_assert(.wb_table_exists(con, "matrices"), "matrices table not found in SQLite")

  if (is.null(matrix_id)) return(DBI::dbReadTable(con, "matrices"))
  DBI::dbGetQuery(con, "SELECT * FROM matrices WHERE matrix_id = ?;", params = list(matrix_id))
}

#' Get a matrix handle (BPCells)
#'
#' Returns a BPCells matrix object; does not materialize into memory.
#'
#' @param bundle Bundle handle from `wb_open_bundle()`
#' @param matrix_id Matrix identifier
#' @return BPCells matrix handle
#' @export
wb_matrix <- function(bundle, matrix_id) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be a scworkbench_bundle handle")
  con <- bundle$con

  row <- .wb_get_matrices_row(con, matrix_id)

  abs_path <- file.path(bundle$dir, row$path)
  .wb_assert(dir.exists(abs_path), paste0("Missing BPCells matrix directory: ", abs_path))

  .wb_bp_open_matrix_dir(abs_path)
}


#' Search features by matrix_id
#'
#' Returns feature IDs registered for a specific matrix, filtered by a text query.
#'
#' @param bundle Bundle handle from `wb_bundle_open()`.
#' @param matrix_id Matrix ID (exact match), e.g. "RNA_counts".
#' @param query Search string. If empty, returns the first `limit` features (sorted).
#' @param limit Max number of results to return.
#' @param mode Match mode: "prefix" (fast, uses `query%`) or "substring" (`%query%`).
#'
#' @return Character vector of feature IDs.
#' @export
wb_search_features <- function(bundle,
                               matrix_id,
                               query = "",
                               limit = 50,
                               mode = c("prefix", "substring")) {
  mode <- match.arg(mode)

  .wb_assert(inherits(bundle, "scworkbench_bundle"),
             "bundle must be a scworkbench_bundle handle")
  .wb_assert(is.character(matrix_id) && length(matrix_id) == 1 && nzchar(matrix_id),
             "matrix_id must be a non-empty string")
  .wb_assert(is.character(query) && length(query) == 1,
             "query must be a length-1 string")
  .wb_assert(is.numeric(limit) && length(limit) == 1 && is.finite(limit) && limit > 0,
             "limit must be a positive number")

  con <- bundle$con
  .wb_assert(!is.null(con), "bundle$con is NULL (no DB connection).")
  .wb_assert(.wb_table_exists(con, "matrices"), "matrices table not found in SQLite")
  .wb_assert(.wb_table_exists(con, "features"), "features table not found in SQLite")

  # Validate matrix exists (nice error message)
  ok <- DBI::dbGetQuery(
    con,
    "SELECT matrix_id FROM matrices WHERE matrix_id = ?;",
    params = list(matrix_id)
  )
  .wb_assert(nrow(ok) == 1, paste0("Unknown matrix_id: ", matrix_id))

  like <- if (mode == "prefix") paste0(query, "%") else paste0("%", query, "%")

  res <- DBI::dbGetQuery(
    con,
    "SELECT feature_id
     FROM features
     WHERE matrix_id = ?
       AND feature_id LIKE ?
     ORDER BY feature_id
     LIMIT ?;",
    params = list(matrix_id, like, as.integer(limit))
  )

  as.character(res$feature_id)
}

#' Slice a matrix into memory (sparse)
#'
#' Returns a sparse `Matrix` subset for downstream wranglers.
#' Subsetting preserves the order of `features` and `cells` if provided.
#'
#' Canonical ordering:
#' - Cells: `wb_cells(bundle, cell_set="all")`
#' - Features: registry order for this matrix (if available), otherwise `rownames(wb_matrix())`
#'
#' @param bundle Bundle handle from `wb_bundle_open()`.
#' @param matrix_id Matrix identifier (exact match).
#' @param features Optional character vector of feature_ids to subset rows (order preserved).
#' @param cells Optional character vector of cell_ids to subset columns (order preserved).
#'
#' @return A sparse Matrix (dgCMatrix).
#' @export
wb_slice <- function(bundle, matrix_id, features = NULL, cells = NULL) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"),
             "bundle must be a scworkbench_bundle handle")
  .wb_assert(is.character(matrix_id) && length(matrix_id) == 1 && nzchar(matrix_id),
             "matrix_id must be a non-empty string")

  con <- bundle$con
  .wb_assert(!is.null(con), "bundle$con is NULL (no DB connection).")
  .wb_assert(.wb_table_exists(con, "matrices"), "matrices table not found in SQLite")

  # Ensure matrix exists (nice error early)
  .wb_get_matrices_row(con, matrix_id)

  # Load matrix (can be sparse/delayed/whatever your wb_matrix returns)
  m <- wb_matrix(bundle, matrix_id)
  .wb_assert(!is.null(m), paste0("wb_matrix() returned NULL for matrix_id: ", matrix_id))

  # Canonical cells: bundle order
  all_cells <- wb_cells(bundle, cell_set = "all")

  # Canonical features: prefer registry-by-matrix if present, else matrix rownames
  all_features <- NULL
  if (.wb_table_exists(con, "features")) {
    # New world: features table keyed by matrix_id
    if ("matrix_id" %in% DBI::dbListFields(con, "features")) {
      all_features <- DBI::dbGetQuery(
        con,
        "SELECT feature_id FROM features WHERE matrix_id = ? ORDER BY rowid;",
        params = list(matrix_id)
      )$feature_id
      all_features <- as.character(all_features)
    }
  }

  if (is.null(all_features) || length(all_features) == 0) {
    rn <- rownames(m)
    .wb_assert(!is.null(rn) && length(rn) > 0,
               paste0("No feature registry for matrix_id='", matrix_id,
                      "' and matrix has no rownames."))
    all_features <- as.character(rn)
  }

  # Resolve indices preserving requested order
  if (!is.null(features)) {
    .wb_assert(is.character(features), "features must be a character vector")
    fi <- match(features, all_features)
    .wb_assert(!anyNA(fi), "Some requested features not found for this matrix_id.")
    feat_out <- as.character(features)
  } else {
    fi <- seq_along(all_features)
    feat_out <- all_features
  }

  if (!is.null(cells)) {
    .wb_assert(is.character(cells), "cells must be a character vector")
    ci <- match(cells, all_cells)
    .wb_assert(!anyNA(ci), "Some requested cells not found in bundle.")
    cell_out <- as.character(cells)
  } else {
    ci <- seq_along(all_cells)
    cell_out <- all_cells
  }

  out <- m[fi, ci, drop = FALSE]
  out <- .wb_as_sparse(out)

  rownames(out) <- feat_out
  colnames(out) <- cell_out
  out
}


#' Get a single feature vector across cells
#'
#' Convenience getter for fast "one gene/peak" access from a matrix.
#' Returns a named numeric vector aligned to `cells` (or bundle cell order).
#'
#' Canonical ordering:
#' - Cells: `wb_cells(bundle, cell_set="all")`
#' - Features: registry order for this matrix (if available), otherwise `rownames(wb_matrix())`
#'
#' @param bundle Bundle handle from `wb_bundle_open()`.
#' @param matrix_id Matrix identifier (exact match).
#' @param feature_id Single feature id (character length-1).
#' @param cells Optional cell_ids to subset/align (order preserved).
#'
#' @return Named numeric vector (names are cell_ids).
#' @export
wb_vector <- function(bundle, matrix_id, feature_id, cells = NULL) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"),
             "bundle must be a scworkbench_bundle handle")
  .wb_assert(is.character(matrix_id) && length(matrix_id) == 1 && nzchar(matrix_id),
             "matrix_id must be a non-empty string")
  .wb_assert(is.character(feature_id) && length(feature_id) == 1 && nzchar(feature_id),
             "feature_id must be a non-empty string")

  con <- bundle$con
  .wb_assert(!is.null(con), "bundle$con is NULL (no DB connection).")
  .wb_assert(.wb_table_exists(con, "matrices"), "matrices table not found in SQLite")

  # Ensure matrix exists
  .wb_get_matrices_row(con, matrix_id)

  # Canonical cells
  all_cells <- wb_cells(bundle, cell_set = "all")

  # Load matrix
  m <- wb_matrix(bundle, matrix_id)
  .wb_assert(!is.null(m), paste0("wb_matrix() returned NULL for matrix_id: ", matrix_id))

  # Canonical features: prefer features registry keyed by matrix_id; else matrix rownames
  all_features <- NULL
  if (.wb_table_exists(con, "features") && ("matrix_id" %in% DBI::dbListFields(con, "features"))) {
    all_features <- DBI::dbGetQuery(
      con,
      "SELECT feature_id FROM features WHERE matrix_id = ? ORDER BY rowid;",
      params = list(matrix_id)
    )$feature_id
    all_features <- as.character(all_features)
  }
  if (is.null(all_features) || length(all_features) == 0) {
    rn <- rownames(m)
    .wb_assert(!is.null(rn) && length(rn) > 0,
               paste0("No feature registry for matrix_id='", matrix_id,
                      "' and matrix has no rownames."))
    all_features <- as.character(rn)
  }

  fi <- match(feature_id, all_features)
  .wb_assert(!is.na(fi),
             paste0("Feature not found in matrix_id='", matrix_id, "': ", feature_id))

  # Resolve column indices preserving requested order
  if (is.null(cells)) {
    ci <- seq_along(all_cells)
    cell_out <- all_cells
  } else {
    .wb_assert(is.character(cells), "cells must be a character vector")
    ci <- match(cells, all_cells)
    .wb_assert(!anyNA(ci), "Some requested cells not found in bundle.")
    cell_out <- as.character(cells)
  }

  v <- m[fi, ci, drop = TRUE]
  v <- .wb_as_numeric(v)
  names(v) <- cell_out
  v
}


#' Resolve matrix fragments to absolute paths
#' @export
wb_matrix_resolve <- function(bundle, matrix_id) {
  fr <- wb_matrix_fragments(bundle, matrix_id)

  # Back-compat: bundles without matrix_fragments
  if (nrow(fr) == 0) {
    # fall back to old 'matrices' table path
    m <- wb_matrix(bundle, matrix_id) # <- if you already have a base getter; otherwise read matrices row
    # If you don't have wb_matrix() yet, implement a wb_matrix_row(bundle, matrix_id)
    stop("No matrix_fragments found for matrix_id=", matrix_id, " and no legacy fallback implemented.")
  }

  # Return absolute paths + metadata
  fr$abs_path <- file.path(bundle$dir, fr$path)
  fr
}
