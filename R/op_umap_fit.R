#' Fit UMAP from a high-D space and persist model for later transform
#' @export
wb_op_umap_fit <- function(bundle,
                           source_space_id,
                           cells = NULL,
                           cell_set = "all",
                           dims = NULL,
                           space_id_out = NULL,
                           n_neighbors = 30,
                           min_dist = 0.3,
                           metric = "euclidean",
                           nn_method = "nndescent",
                           spread = 1.0,
                           seed = 1,
                           verbose = FALSE) {
  .wb_require_pkg("uwot", "UMAP fitting")

  .wb_assert(is.character(source_space_id) && nzchar(source_space_id),
             "source_space_id must be a non-empty string.")

  if (is.null(cells)) cells <- wb_cells(bundle, cell_set = "core")
  cells <- as.character(cells)

  # Pull high-D coords (matrix)
  S <- wb_space(bundle, space_id = source_space_id, cells = cells)
  X <- .wb_as_coord_matrix(S)
  .wb_assert(nrow(X) == length(cells), "Internal: wb_space returned unexpected rows.")

  X <- .wb_select_dims(X, dims)  # will validate bounds

  if (!exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) set.seed(1)
  set.seed(as.integer(seed))

  if (is.null(space_id_out) || !nzchar(space_id_out)) {
    # Stable default: derived from source + cell role
    space_id_out <- paste0("umap.", source_space_id)
  }

  # Fit UMAP
  fit <- uwot::umap(
    X,
    n_neighbors = as.integer(n_neighbors),
    min_dist = min_dist,
    metric = metric,
    nn_method = nn_method,
    spread = spread,
    ret_model = TRUE,
    verbose = isTRUE(verbose)
  )

  emb <- fit$embedding
  .wb_assert(is.matrix(emb) && ncol(emb) == 2, "uwot returned invalid embedding.")

  uwot_args <- list(
    n_neighbors = n_neighbors,
    min_dist = min_dist,
    nn_method = nn_method,
    n_components = 2
  )
  uwot_args_json <- jsonlite::toJSON(uwot_args, auto_unbox = TRUE)


  df2 <- data.frame(
    cell_id = cells,
    x = as.numeric(emb[, 1]),
    y = as.numeric(emb[, 2]),
    stringsAsFactors = FALSE
  )

  # ---- Persist embedding to bundle ----
  con <- bundle$con

  # register 2D space in `spaces`
  .wb_upsert_space_row(con,
                       space_id = space_id_out,
                       source = paste0("uwot_fit:", source_space_id),
                       dims = 2L,
                       storage = "wide:space_2d",
                       description = paste0("UMAP fit from ", source_space_id, " (uwot)")
  )

  # write coords
  # (delete existing if re-fit same space_id_out)
  DBI::dbExecute(con, "DELETE FROM space_2d WHERE space_id = ?;", params = list(space_id_out))
  # df2 must contain: cell_id, x, y (n rows)
  df2 <- df2[, c("cell_id","x","y")]
  df2$cell_id <- as.character(df2$cell_id)

  DBI::dbWithTransaction(con, {

    # overwrite semantics for this space_id if you want deterministic reruns
    DBI::dbExecute(con, "DELETE FROM space_2d WHERE space_id = ?;", params = list(space_id_out))

    stmt <- DBI::dbSendStatement(con,
                                 "INSERT INTO space_2d(space_id, cell_id, x, y) VALUES(?, ?, ?, ?);"
    )
    on.exit(DBI::dbClearResult(stmt), add = TRUE)

    # Bind per-row (correct shape: list(space_id, cell_id, x, y))
    for (i in seq_len(nrow(df2))) {
      DBI::dbBind(stmt, params = list(
        space_id_out,
        df2$cell_id[i],
        as.numeric(df2$x[i]),
        as.numeric(df2$y[i])
      ))
    }
  })

  # NOTE: above insert is illustrative; you probably already have a bulk insert helper.
  # Use your existing ingestion helper for space_2d if you have one.

  # ---- Persist model to disk + register in space_models ----
  .wb_ensure_space_models_table(con)
  model_dir <- file.path(bundle$dir, "models", "umap")
  dir.create(model_dir, recursive = TRUE, showWarnings = FALSE)

  .wb_assert(dir.exists(model_dir),
             paste0("Failed to create model directory: ", model_dir))


  model_id <- paste0("umap_", space_id_out, "_", format(Sys.time(), "%Y%m%d%H%M%S"))
  model_id <- paste0(
    "umap_",
    space_id_out,
    "_",
    format(Sys.time(), "%Y%m%d%H%M%S")
  )
  model_file <- paste0(space_id_out, ".uwot")
  model_path_abs <- file.path(model_dir, model_file)
  model_path_rel <- file.path("models", "umap", model_file)
  uwot::save_uwot(model = fit, file = model_path_abs, verbose = T)
  #uwot::save_uwot(fit, file = model_path_abs)

  # register model (1 per space_id)
  # register model (1 per space_id)
  con <- bundle$con
  has_prov <- .wb_db_has_column(con, "space_models", "provenance_json")

  provenance <- list(
    space_id = space_id_out,
    model_kind = "uwot_umap",
    source_space_id = source_space_id,
    dims = dims,
    cell_set = cell_set,
    uwot_args = uwot_args,
    seed = seed,
    created_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  )

  if (has_prov) {
    sql <- paste0(
      "INSERT INTO space_models(",
      " space_id, model_type, source_space_id, dims_json, cell_set, uwot_args_json, seed, model_path, created_at, provenance_json",
      ") VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
      " ON CONFLICT(space_id) DO UPDATE SET ",
      " model_type=excluded.model_type,",
      " source_space_id=excluded.source_space_id,",
      " dims_json=excluded.dims_json,",
      " cell_set=excluded.cell_set,",
      " uwot_args_json=excluded.uwot_args_json,",
      " seed=excluded.seed,",
      " model_path=excluded.model_path,",
      " created_at=excluded.created_at,",
      " provenance_json=excluded.provenance_json"
    )

    params <- list(
      space_id_out,
      "uwot_umap",
      source_space_id,
      jsonlite::toJSON(as.list(dims), auto_unbox = TRUE),
      cell_set,
      jsonlite::toJSON(uwot_args, auto_unbox = TRUE),
      if (is.null(seed)) NA_integer_ else as.integer(seed),
      model_path_rel,
      provenance$created_at,
      jsonlite::toJSON(provenance, auto_unbox = TRUE)
    )

  } else {
    # older bundles: no provenance_json column
    sql <- paste0(
      "INSERT INTO space_models(",
      " space_id, model_type, source_space_id, dims_json, cell_set, uwot_args_json, seed, model_path, created_at",
      ") VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)",
      " ON CONFLICT(space_id) DO UPDATE SET ",
      " model_type=excluded.model_type,",
      " source_space_id=excluded.source_space_id,",
      " dims_json=excluded.dims_json,",
      " cell_set=excluded.cell_set,",
      " uwot_args_json=excluded.uwot_args_json,",
      " seed=excluded.seed,",
      " model_path=excluded.model_path,",
      " created_at=excluded.created_at"
    )

    params <- list(
      space_id_out,
      "uwot_umap",
      source_space_id,
      jsonlite::toJSON(as.list(dims), auto_unbox = TRUE),
      cell_set,
      jsonlite::toJSON(uwot_args, auto_unbox = TRUE),
      if (is.null(seed)) NA_integer_ else as.integer(seed),
      model_path_rel,
      provenance$created_at
    )
  }

  DBI::dbExecute(con, sql, params = params)

  list(
    space_id = space_id_out,
    coords = df2,
    model_path = model_path_rel,
    params = list(
      source_space_id = source_space_id,
      space_id_out = space_id_out,
      dims = dims,
      cell_set = "core",
      seed = seed,
      uwot = uwot_args
    )
  )
}
