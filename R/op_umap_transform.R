# R/op_umap_transform.R

#' Project cells into an existing fitted UMAP space
#'
#' @param bundle scworkbench bundle
#' @param model_space_id 2D UMAP space_id that has a stored model in space_models
#' @param in_space_id high-D space_id used as input for transform (e.g. lsi, peakvi)
#' @param cells cell IDs to project (already resolved effective cells recommended)
#' @param dims optional dims for in_space_id (e.g. 2:30)
#' @param overwrite whether to overwrite existing rows for these cells in model_space_id
#' @param ... passed to uwot::umap_transform
#' @return list(coords=data.frame(cell_id,x,y), params=list(...))
#' @export
wb_op_umap_transform <- function(bundle,
                                 model_space_id,
                                 in_space_id,
                                 cells = NULL,
                                 dims = NULL,
                                 overwrite = TRUE,
                                 ...) {

  .wb_require_pkg("uwot", "UMAP transform")

  if (is.null(cells)) {
    stop("umap_transform: cells must be provided (usually effective_cells).", call. = FALSE)
  }
  cells <- as.character(cells)

  # 1) Load model row + model object
  mrow <- wb_space_model(bundle, model_space_id)
  .wb_assert(nrow(mrow) == 1, paste0("No model registered for space_id: ", model_space_id))

  model <- wb_load_space_model(bundle, model_space_id)

  # 2) Decide dims to use (stored dims are the default)
  dims_model <- NULL
  if (!is.null(mrow$dims_json) && nzchar(mrow$dims_json)) {
    dims_model <- jsonlite::fromJSON(mrow$dims_json)
  }

  dims_use <- dims %||% dims_model
  .wb_assert(!is.null(dims_use) && length(dims_use) > 0,
             paste0("Model has no dims_json stored and no dims were provided for transform (space_id=", model_space_id, ")."))

  # 3) Pull high-D coords and build X with correct shape
  S <- wb_space(bundle, space_id = in_space_id, cells = cells, dims = dims_use)

  # wb_space might return matrix for ND spaces; enforce matrix + rownames
  X <- S
  if (is.data.frame(S) && all(c("cell_id","dim","value") %in% colnames(S))) {
    X <- .wb_as_coord_matrix(S)
  }

  .wb_assert(is.matrix(X), "High-D space must yield a matrix after wb_space/.wb_as_coord_matrix().")
  .wb_assert(!is.null(rownames(X)), "High-D space coords must have rownames = cell_id.")

  # Ensure row order matches 'cells'
  ii <- match(cells, rownames(X))
  .wb_assert(!anyNA(ii), "Some requested cells are missing from in_space_id coords.")
  X <- X[ii, , drop = FALSE]

  # 4) Hard check: must match model expected columns
  .wb_assert(ncol(X) == length(dims_use),
             paste0("Incorrect dimensions: X must have ", length(dims_use),
                    " columns (dims=", paste(dims_use, collapse=","), "). Got ", ncol(X), "."))

  # 5) Transform
  emb <- uwot::umap_transform(X, model, ...)

  df2 <- data.frame(
    cell_id = cells,
    x = emb[, 1],
    y = emb[, 2],
    stringsAsFactors = FALSE
  )

  # 6) Write to space_2d for model_space_id (ONLY these cells)
  con <- bundle$con

  # optionally: delete existing rows for those cells if overwrite
  if (isTRUE(overwrite)) {
    DBI::dbExecute(
      con,
      "DELETE FROM space_2d WHERE space_id = ? AND cell_id IN (SELECT value FROM json_each(?));",
      params = list(model_space_id, jsonlite::toJSON(as.list(cells), auto_unbox = TRUE))
    )
  }

  # insert in a transaction
  # insert in a transaction
  DBI::dbExecute(con, "BEGIN;")
  on.exit(try(DBI::dbExecute(con, "ROLLBACK;"), silent = TRUE), add = TRUE)

  stmt <- DBI::dbSendStatement(
    con,
    "INSERT INTO space_2d(space_id, cell_id, x, y) VALUES(?, ?, ?, ?);"
  )
  on.exit(try(DBI::dbClearResult(stmt), silent = TRUE), add = TRUE)

  chunk_size <- 5000L
  for (i in seq(1, nrow(df2), by = chunk_size)) {
    j <- min(i + chunk_size - 1L, nrow(df2))
    sub <- df2[i:j, , drop = FALSE]

    # bind 4 params per row (SQLite-safe)
    for (k in seq_len(nrow(sub))) {
      DBI::dbBind(stmt, list(
        model_space_id,
        sub$cell_id[k],
        sub$x[k],
        sub$y[k]
      ))
    }
  }

  DBI::dbClearResult(stmt)
  DBI::dbExecute(con, "COMMIT;")
  on.exit(NULL, add = FALSE)


  list(
    n_projected = nrow(df2),
    params = list(
      model_space_id = model_space_id,
      in_space_id = in_space_id,
      dims = dims_use,
      cell_set = NA_character_
    )
  )
}
