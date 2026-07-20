# R/op_umap_transform.R

#' Project cells into an existing fitted UMAP space
#'
#' @param bundle scworkbench bundle
#' @param model_space_id 2D UMAP space_id that has a stored model in space_models
#' @param in_space_id high-D space_id used as input for transform (e.g. lsi, peakvi)
#' @param cells optional explicit cell IDs to project
#' @param cell_set if cells is NULL, resolve cells via wb_cells(bundle, cell_set=cell_set)
#' @param dims optional dims for in_space_id (e.g. 2:30); defaults to model dims_json
#' @param overwrite whether to overwrite existing rows for these cells in model_space_id
#' @param ... passed to uwot::umap_transform
#' @return list(n_projected=int, params=list(...))
#' @export
wb_op_umap_transform <- function(bundle,
                                 model_space_id,
                                 in_space_id,
                                 cells = NULL,
                                 cell_set = "all",
                                 dims = NULL,
                                 overwrite = TRUE,
                                 ...) {

  .wb_require_pkg("uwot", "UMAP transform")

  .wb_assert(is.character(model_space_id) && nzchar(model_space_id),
             "model_space_id must be a non-empty string.")
  .wb_assert(is.character(in_space_id) && nzchar(in_space_id),
             "in_space_id must be a non-empty string.")

  # Resolve cells (bench owns this logic)
  if (is.null(cells)) {
    cells <- wb_cells(bundle, cell_set = cell_set)
  }
  cells <- as.character(cells)
  .wb_assert(length(cells) > 0, "umap_transform: resolved 0 cells.")

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

  DBI::dbWithTransaction(con, {
    if (isTRUE(overwrite)) {
      DBI::dbExecute(
        con,
        "DELETE FROM space_2d WHERE space_id = ? AND cell_id IN (SELECT value FROM json_each(?));",
        params = list(model_space_id, jsonlite::toJSON(as.list(cells), auto_unbox = TRUE))
      )
    }

    stmt <- DBI::dbSendStatement(
      con,
      "INSERT INTO space_2d(space_id, cell_id, x, y) VALUES(?, ?, ?, ?);"
    )
    tryCatch(
      {
        chunk_size <- 5000L
        for (i in seq(1, nrow(df2), by = chunk_size)) {
          j <- min(i + chunk_size - 1L, nrow(df2))
          sub <- df2[i:j, , drop = FALSE]

          for (k in seq_len(nrow(sub))) {
            DBI::dbBind(stmt, list(
              model_space_id,
              sub$cell_id[k],
              sub$x[k],
              sub$y[k]
            ))
          }
        }
      },
      finally = DBI::dbClearResult(stmt)
    )
  })

  out_space_2d <- list(
    space_id = model_space_id,
    cell_ids = cells,
    n = nrow(df2)
  )
  out_params <- list(
    model_space_id = model_space_id,
    in_space_id = in_space_id,
    dims = dims_use,
    cell_set = cell_set,
    overwrite = overwrite
  )

  space_prim <- wb_prim_space_2d(model_space_id)
  space_prim$promotion_mode <- "merge_space_2d"
  space_prim$cell_ids <- cells
  space_prim$overwrite <- isTRUE(overwrite)

  list(
    outputs = list(
      space_2d = space_prim
    ),
    space_2d = out_space_2d,
    n_projected = nrow(df2),
    params = out_params
  )

}
