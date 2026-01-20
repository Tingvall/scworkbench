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

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && nzchar(as.character(a[1]))) a else b


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

  # 4) Last resort: materialize small dense matrix then sparsify.
  # This is acceptable for slices (like 10x50) but not huge pulls.
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

#' Open an scworkbench bundle
#'
#' Opens a bundle directory and returns a handle containing:
#' - `manifest`: parsed manifest.json
#' - `con`: SQLite connection
#' - `dir`: bundle directory path
#'
#' @param bundle_dir Path to bundle directory
#' @param validate If TRUE, runs `wb_validate_bundle(bundle_dir)` if available
#' @return An object of class `scworkbench_bundle`
#' @export
wb_open_bundle <- function(bundle_dir, validate = FALSE) {
  .wb_assert(dir.exists(bundle_dir), paste0("Bundle directory does not exist: ", bundle_dir))

  man_path <- file.path(bundle_dir, "manifest.json")
  .wb_assert(file.exists(man_path), paste0("Missing manifest.json in bundle: ", bundle_dir))

  manifest <- jsonlite::read_json(man_path, simplifyVector = TRUE)

  db_rel <- manifest$storage$sqlite$path
  .wb_assert(!is.null(db_rel) && nzchar(db_rel), "manifest.json missing storage$sqlite$path")

  db_path <- file.path(bundle_dir, db_rel)
  .wb_assert(file.exists(db_path), paste0("SQLite DB not found: ", db_path))

  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)

  bundle <- list(dir = bundle_dir, manifest = manifest, con = con)
  class(bundle) <- "scworkbench_bundle"

  if (isTRUE(validate) && exists("wb_validate_bundle", mode = "function")) {
    wb_validate_bundle(bundle_dir)
  }

  bundle
}

#' Close an scworkbench bundle
#'
#' @param bundle Bundle handle from `wb_open_bundle()`
#' @return TRUE (invisibly)
#' @export
wb_close_bundle <- function(bundle) {
  if (inherits(bundle, "scworkbench_bundle") && !is.null(bundle$con)) {
    DBI::dbDisconnect(bundle$con)
  }
  invisible(TRUE)
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
wb_cells <- function(bundle, dataset_id = NULL, cell_set = "core") {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be a scworkbench_bundle handle")
  con <- bundle$con

  cell_set <- as.character(cell_set %||% "core")

  # Validate cell_set selector
  if (!identical(cell_set, "all")) {
    avail <- wb_cell_sets(bundle)
    .wb_assert(cell_set %in% avail,
               paste0(
                 "Unknown cell_set: ", cell_set, "\n",
                 "Available: ", paste(avail, collapse = ", "), "\n",
                 "Use 'all' for all cells."
               )
    )
  }

  # Build query with filters, preserving canonical rowid order
  where <- character(0)
  params <- list()

  if (!is.null(dataset_id)) {
    where <- c(where, "dataset_id = ?")
    params <- c(params, list(dataset_id))
  }

  if (!identical(cell_set, "all")) {
    where <- c(where, "cell_set = ?")
    params <- c(params, list(cell_set))
  }

  q <- "SELECT cell_id FROM cells"
  if (length(where)) {
    q <- paste0(q, " WHERE ", paste(where, collapse = " AND "))
  }
  q <- paste0(q, " ORDER BY rowid;")

  if (length(params)) {
    res <- DBI::dbGetQuery(con, q, params = params)
  } else {
    res <- DBI::dbGetQuery(con, q)
  }

  res$cell_id
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
#' @param bundle Bundle handle from `wb_open_bundle()`
#' @param assay Optional assay filter (exact match)
#' @param feature_type Optional feature_type filter (e.g. "gene", "peak")
#' @return A data.frame of features
#' @export
wb_features <- function(bundle, assay = NULL, feature_type = NULL) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be a scworkbench_bundle handle")
  con <- bundle$con
  .wb_assert(.wb_table_exists(con, "features"), "features table not found in SQLite")

  q <- "SELECT assay, feature_id, feature_type, chr, start, end FROM features"
  params <- list()
  where <- character(0)

  if (!is.null(assay)) {
    where <- c(where, "assay = ?")
    params <- c(params, list(assay))
  }
  if (!is.null(feature_type)) {
    where <- c(where, "feature_type = ?")
    params <- c(params, list(feature_type))
  }
  if (length(where) > 0) q <- paste0(q, " WHERE ", paste(where, collapse = " AND "))

  if (length(params) == 0) DBI::dbGetQuery(con, q) else DBI::dbGetQuery(con, q, params = params)
}

#' Get feature IDs in canonical order for an assay
#'
#' Important: this defines the row order for matrices for that assay.
#'
#' @param bundle Bundle handle from `wb_open_bundle()`
#' @param assay Assay name (exact match)
#' @param feature_type Optional filter (e.g. "gene", "peak")
#' @return Character vector of feature_ids
#' @export
wb_feature_ids <- function(bundle, assay, feature_type = NULL) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be a scworkbench_bundle handle")
  con <- bundle$con

  q <- "SELECT feature_id FROM features WHERE assay = ?"
  params <- list(assay)

  if (!is.null(feature_type)) {
    q <- paste0(q, " AND feature_type = ?")
    params <- c(params, list(feature_type))
  }

  # rowid order = insertion order during publish (canonical)
  q <- paste0(q, " ORDER BY rowid;")

  res <- DBI::dbGetQuery(con, q, params = params)$feature_id
  .wb_assert(length(res) > 0, paste0("No features found for assay: ", assay))
  res
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
  storage <- info$storage %||% ""
  dims_total <- as.integer(info$dims %||% NA_integer_)

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
  DBI::dbReadTable(bundle$con, "spaces")
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

#' Matrix metadata
#' @export
wb_matrix_info <- function(bundle, matrix_id) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be a scworkbench_bundle handle")
  con <- bundle$con
  row <- .wb_get_matrices_row(con, matrix_id)
  row
}




#' Search features by matrix (assay + feature_type)
#' @export
wb_search_features <- function(bundle, matrix_id, query = "", limit = 50,
                               mode = c("prefix", "substring")) {
  mode <- match.arg(mode)
  con <- bundle$con

  # Resolve matrix -> assay + feature_type
  m <- DBI::dbGetQuery(
    con,
    "SELECT assay, feature_type FROM matrices WHERE matrix_id = ?;",
    params = list(matrix_id)
  )
  .wb_assert(nrow(m) == 1, paste0("Unknown matrix_id: ", matrix_id))
  assay <- as.character(m$assay[[1]])
  ftype <- as.character(m$feature_type[[1]])

  like <- if (mode == "prefix") paste0(query, "%") else paste0("%", query, "%")

  res <- DBI::dbGetQuery(
    con,
    "SELECT feature_id
     FROM features
     WHERE assay = ? AND feature_type = ? AND feature_id LIKE ?
     ORDER BY feature_id
     LIMIT ?;",
    params = list(assay, ftype, like, as.integer(limit))
  )

  res$feature_id
}




#' Slice a matrix into memory (sparse)
#'
#' Returns a sparse `Matrix` subset for downstream wranglers.
#' Subsetting preserves the order of `features` and `cells` if provided.
#'
#' @param bundle Bundle handle from `wb_open_bundle()`
#' @param matrix_id Matrix identifier
#' @param features Optional feature_ids (character) to subset rows
#' @param cells Optional cell_ids (character) to subset columns
#' @return A sparse Matrix (dgCMatrix)
#' @export
wb_slice <- function(bundle, matrix_id, features = NULL, cells = NULL) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be a scworkbench_bundle handle")
  con <- bundle$con

  row <- .wb_get_matrices_row(con, matrix_id)
  assay <- row$assay

  # Canonical IDs
  all_cells <- wb_cells(bundle)
  all_features <- wb_feature_ids(bundle, assay = assay)  # canonical feature order for that assay

  all_features <- wb_feature_ids(bundle, assay = assay)

  if (length(all_features) == 0) {
    m0 <- wb_matrix(bundle, matrix_id)
    .wb_assert(!is.null(rownames(m0)) && length(rownames(m0)) > 0,
               paste0("No features registered for assay: ", assay,
                      " and matrix has no rownames."))
    all_features <- rownames(m0)
  }


  # Resolve indices preserving requested order
  if (!is.null(features)) {
    fi <- match(features, all_features)
    .wb_assert(!anyNA(fi), "Some requested features not found for this assay/matrix.")
    feat_out <- features
  } else {
    fi <- seq_along(all_features)
    feat_out <- all_features
  }

  if (!is.null(cells)) {
    ci <- match(cells, all_cells)
    .wb_assert(!anyNA(ci), "Some requested cells not found in bundle.")
    cell_out <- cells
  } else {
    ci <- seq_along(all_cells)
    cell_out <- all_cells
  }

  m <- wb_matrix(bundle, matrix_id)
  out <- m[fi, ci, drop = FALSE]
  out <- .wb_as_sparse(out)

  rownames(out) <- feat_out
  colnames(out) <- cell_out
  out

}

#' Get a single feature vector across cells
#'
#' Convenience getter for fast "one gene/peak" access.
#'
#' @param bundle Bundle handle from `wb_open_bundle()`
#' @param matrix_id Matrix identifier
#' @param feature_id Single feature id (character)
#' @param cells Optional cell_ids to subset/align
#' @return Named numeric vector (names are cell_ids)
#' @export
wb_vector <- function(bundle, matrix_id, feature_id, cells = NULL) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be a scworkbench_bundle handle")
  con <- bundle$con

  row <- .wb_get_matrices_row(con, matrix_id)
  assay <- row$assay

  all_cells <- wb_cells(bundle)
  all_features <- wb_feature_ids(bundle, assay = assay)

  fi <- match(feature_id, all_features)
  .wb_assert(!is.na(fi), paste0("Feature not found in assay '", assay, "': ", feature_id))

  if (is.null(cells)) {
    ci <- seq_along(all_cells)
    cell_out <- all_cells
  } else {
    ci <- match(cells, all_cells)
    .wb_assert(!anyNA(ci), "Some requested cells not found in bundle.")
    cell_out <- cells
  }

  m <- wb_matrix(bundle, matrix_id)
  v <- m[fi, ci, drop = TRUE]
  v <- .wb_as_numeric(v)
  names(v) <- cell_out
  v

}

#' Cells with coordinates available for a given space
#' @export
wb_cells_with_space <- function(bundle, space_id) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be a scworkbench_bundle handle")
  con <- bundle$con
  space_id <- as.character(space_id)

  info <- .wb_get_spaces_row(con, space_id)
  storage <- info$storage %||% ""
  dims_total <- as.integer(info$dims %||% NA_integer_)

  if (grepl("^wide:space_2d", storage) ||
      (!is.na(dims_total) && dims_total == 2 && .wb_table_exists(con, "space_2d"))) {
    df <- DBI::dbGetQuery(con,
                          "SELECT cell_id FROM space_2d WHERE space_id = ?;",
                          params = list(space_id)
    )
    return(as.character(df$cell_id))
  }

  .wb_assert(.wb_table_exists(con, "space_coords"), "space_coords table not found in SQLite")

  df <- DBI::dbGetQuery(con,
                        "SELECT DISTINCT cell_id FROM space_coords WHERE space_id = ?;",
                        params = list(space_id)
  )
  as.character(df$cell_id)
}

#' Cells with data available for a given matrix
#' @export
wb_cells_with_matrix <- function(bundle, matrix_id) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be a scworkbench_bundle")
  con <- bundle$con

  .wb_assert(.wb_table_exists(con, "matrices"), "No matrices table in bundle.")
  row <- .wb_get_matrices_row(con, matrix_id)
  .wb_assert(nrow(row) == 1, paste0("Unknown matrix_id: ", matrix_id))

  all_cells <- wb_cells(bundle)
  n_all <- length(all_cells)

  n_cells <- as.integer(row$n_cells %||% NA_integer_)
  .wb_assert(!is.na(n_cells) && n_cells >= 0, "matrices$n_cells missing or invalid.")

  if (n_cells == 0) return(character(0))

  if (n_cells != n_all) {
    stop(
      paste0(
        "Matrix coverage unknown for matrix_id='", matrix_id, "':\n",
        "  matrices$n_cells=", n_cells, " but bundle has ", n_all, " cells.\n",
        "Add a matrix_cells mapping table or store per-matrix cell_id list to support partial matrices."
      ),
      call. = FALSE
    )
  }

  all_cells
}

#' Coverage of required inputs within a cell_set
#'
#' @param inputs list(space_id=..., matrix_id=...) (either/both)
#' @export
wb_cell_coverage <- function(bundle, cell_set = "all", inputs = list()) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be a scworkbench_bundle handle")
  req_cells <- wb_cells(bundle, cell_set = cell_set)
  req_cells <- as.character(req_cells)

  res <- list(
    cell_set = cell_set,
    n_requested = length(req_cells),
    inputs = list(),
    n_effective = NA_integer_,
    pct_effective = NA_real_
  )

  eff <- req_cells

  if (!is.null(inputs$space_id)) {
    sid <- as.character(inputs$space_id)
    has <- wb_cells_with_space(bundle, sid)
    has <- as.character(has)

    res$inputs$space_id <- list(
      space_id = sid,
      n_available = length(has),
      n_in_set = sum(req_cells %in% has)
    )

    eff <- intersect(eff, has)
  }

  if (!is.null(inputs$matrix_id)) {
    mid <- as.character(inputs$matrix_id)
    has <- wb_cells_with_matrix(bundle, mid)
    has <- as.character(has)

    res$inputs$matrix_id <- list(
      matrix_id = mid,
      n_available = length(has),
      n_in_set = sum(req_cells %in% has)
    )

    eff <- intersect(eff, has)
  }

  res$n_effective <- length(eff)
  res$pct_effective <- if (length(req_cells) == 0) 0 else (100 * length(eff) / length(req_cells))
  res$cells_effective <- eff

  class(res) <- "wb_cell_coverage"
  res
}


