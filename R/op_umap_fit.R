# R/op_umap_fit.R

.wb_umap_supported_nn_methods <- function() c("nndescent", "annoy", "fnn")

.wb_umap_preflight <- function(nn_method,
                               pkg_available = function(pkg) requireNamespace(pkg, quietly = TRUE)) {
  .wb_assert(is.character(nn_method) && length(nn_method) == 1L && nzchar(nn_method),
             "umap_fit: nn_method must be a non-empty string.")
  nn_method <- as.character(nn_method)[1]
  supported <- .wb_umap_supported_nn_methods()
  .wb_assert(
    nn_method %in% supported,
    paste0(
      "umap_fit: unsupported nn_method='", nn_method, "'. Supported values: ",
      paste(supported, collapse = ", "), "."
    )
  )

  if (identical(nn_method, "nndescent") && !isTRUE(pkg_available("rnndescent"))) {
    stop(
      "umap_fit: nn_method='nndescent' requires the R package 'rnndescent', ",
      "but it is not installed in this runtime. Install rnndescent or rerun ",
      "with nn_method='annoy' or nn_method='fnn'.",
      call. = FALSE
    )
  }

  if (identical(nn_method, "fnn") && !isTRUE(pkg_available("FNN"))) {
    stop(
      "umap_fit: nn_method='fnn' requires the R package 'FNN', ",
      "but it is not installed in this runtime. Install FNN or rerun ",
      "with nn_method='annoy' or nn_method='nndescent' when rnndescent is available.",
      call. = FALSE
    )
  }

  invisible(nn_method)
}

#' Fit UMAP from a high-D space and persist model for later transform
#'
#' Fits a 2D UMAP embedding from a high-dimensional space (e.g. LSI/PeakVI latent),
#' writes the 2D coordinates through the file-backed space payload contract,
#' and saves a uwot model to disk,
#' registered in `space_models` for later `wb_op_umap_transform()`.
#'
#' Session contract:
#' - produces: space_2d, model
#'
#' @param bundle scworkbench bundle
#' @param source_space_id High-D space id used for fitting (e.g. "lsi", "peakvi_latent")
#' @param cells Optional explicit cell IDs to fit on. If NULL, uses cell_set.
#' @param cell_set If cells is NULL, resolved via wb_cells(bundle, cell_set=cell_set)
#' @param dims Optional dims to use (e.g. 2:30). If NULL uses all dims returned by wb_space().
#' @param space_id_out 2D space id to write. Default: paste0("umap.", source_space_id)
#' @details `n_neighbors`, `min_dist`, `metric`, `nn_method`, and `spread`
#'   control the UMAP neighborhood graph and layout. Their current validated
#'   defaults are exposed by [wb_op_interface()].
#' @param seed Random seed for reproducibility
#' @param verbose Passed to uwot
#' @return list(
#'   space_2d = list(space_id, n, cell_set),
#'   model    = list(space_id, model_path),
#'   params   = list(...)
#' )
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

  .wb_assert_operation_execution(bundle, "umap_fit")
  .wb_require_pkg("uwot", "UMAP fitting")
  nn_method <- .wb_umap_preflight(nn_method)

  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert(is.character(source_space_id) && length(source_space_id) == 1 && nzchar(source_space_id),
             "source_space_id must be a non-empty string.")

  # ---- Resolve cells ----
  if (is.null(cells)) {
    cells <- wb_cells(bundle, cell_set = cell_set)
  }
  cells <- as.character(cells)
  .wb_assert(length(cells) > 0, "umap_fit: resolved 0 cells.")

  # ---- Pull high-D coords -> X matrix ----
  S <- wb_space(bundle, space_id = source_space_id, cells = cells)

  X <- S
  # The wide 2D getter deliberately returns a plotting-friendly table. Convert
  # it at the getter boundary so every operation receives canonical cell IDs.
  if (is.data.frame(S)) X <- .wb_as_coord_matrix(S)

  .wb_assert(is.matrix(X), "High-D space must yield a matrix after wb_space/.wb_as_coord_matrix().")
  .wb_assert(!is.null(rownames(X)), "High-D coords must have rownames = cell_id.")

  # reorder rows to match requested 'cells'
  ii <- match(cells, rownames(X))
  .wb_assert(!anyNA(ii), "Some requested cells are missing from source_space_id coords.")
  X <- X[ii, , drop = FALSE]

  # dims selection
  dims_use <- dims
  if (!is.null(dims_use)) {
    X <- .wb_select_dims(X, dims_use)   # validates bounds & returns subset
  } else {
    # default = all columns in the returned matrix
    dims_use <- seq_len(ncol(X))
  }

  .wb_assert(nrow(X) == length(cells), "Internal: X rows != length(cells) after reordering.")
  .wb_assert(ncol(X) == length(dims_use), "Internal: X cols != length(dims_use) after dim selection.")

  # ---- Decide output space id ----
  if (is.null(space_id_out) || !nzchar(space_id_out)) {
    space_id_out <- paste0("umap.", source_space_id)
  }

  # Preflight all public names before creating either staged registry rows or
  # a model payload.  A session overlay may contain linked durable payloads,
  # so writing through an existing target is never safe.
  con <- bundle$con
  existing_space <- DBI::dbGetQuery(
    con, "SELECT space_id FROM spaces WHERE space_id = ?;", params = list(space_id_out)
  )
  .wb_assert(!nrow(existing_space), paste0(
    "umap_fit: output space already exists: ", space_id_out,
    ". Use a new output space ID."
  ))
  model_file <- paste0(space_id_out, ".uwot")
  model_path_rel <- file.path("models", "umap", model_file)
  model_path_abs <- .wb_bundle_path_require(bundle,model_path_rel,expected_type="file",must_exist=FALSE,
                                             purpose="UMAP model output")
  .wb_assert(!file.exists(model_path_abs) && !dir.exists(model_path_abs), paste0(
    "umap_fit: output model path already exists: ", model_path_rel,
    ". Use a new output space ID."
  ))

  # ---- RNG ----
  if (!exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) set.seed(1)
  set.seed(as.integer(seed))

  # ---- Fit UMAP ----
  fit <- uwot::umap(
    X,
    n_neighbors = as.integer(n_neighbors),
    min_dist = min_dist,
    metric = metric,
    nn_method = nn_method,
    spread = spread,
    # Keep fixed-seed coordinate replay stable across fresh R processes.
    # Serialized uwot model bytes are still compared through
    # loadable_reference, never promised byte-equal.
    n_threads = 1L,
    n_sgd_threads = 1L,
    seed = as.integer(seed),
    ret_model = TRUE,
    verbose = isTRUE(verbose)
  )

  emb <- fit$embedding
  .wb_assert(is.matrix(emb) && ncol(emb) == 2, "uwot returned invalid embedding.")

  df2 <- data.frame(
    cell_id = cells,
    x = as.numeric(emb[, 1]),
    y = as.numeric(emb[, 2]),
    stringsAsFactors = FALSE
  )

  # ---- Persist embedding through the one canonical dense-space writer ----
  wb_add_space(
    bundle, space_id_out, df2,
    source = paste0("uwot_fit:", source_space_id),
    description = paste0("UMAP fit from ", source_space_id, " (uwot)"),
    overwrite = FALSE
  )

  # ---- Persist model to disk + register in space_models ----
  .wb_ensure_space_models_table(con)

  model_dir <- file.path(bundle$dir, "models", "umap")
  dir.create(model_dir, recursive = TRUE, showWarnings = FALSE)
  .wb_assert(dir.exists(model_dir), paste0("Failed to create model directory: ", model_dir))

  uwot::save_uwot(model = fit, file = model_path_abs, verbose = isTRUE(verbose))

  uwot_args <- list(
    n_neighbors = n_neighbors,
    min_dist = min_dist,
    metric = metric,
    nn_method = nn_method,
    spread = spread,
    n_components = 2
  )

  created_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

  provenance <- list(
    space_id = space_id_out,
    model_kind = "uwot_umap",
    source_space_id = source_space_id,
    dims = dims_use,
    cell_set = cell_set,
    uwot_args = uwot_args,
    seed = seed,
    created_at = created_at
  )

  has_prov <- .wb_db_has_column(con, "space_models", "provenance_json")

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
      jsonlite::toJSON(as.list(dims_use), auto_unbox = TRUE),
      cell_set,
      jsonlite::toJSON(uwot_args, auto_unbox = TRUE),
      if (is.null(seed)) NA_integer_ else as.integer(seed),
      model_path_rel,
      created_at,
      jsonlite::toJSON(provenance, auto_unbox = TRUE)
    )

  } else {
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
      jsonlite::toJSON(as.list(dims_use), auto_unbox = TRUE),
      cell_set,
      jsonlite::toJSON(uwot_args, auto_unbox = TRUE),
      if (is.null(seed)) NA_integer_ else as.integer(seed),
      model_path_rel,
      created_at
    )
  }

  DBI::dbExecute(con, sql, params = params)

  # ---- Session-facing return contract ----
  # Keep top-level metadata fields for direct callers, but always expose
  # canonical primitive outputs for session dispatch.
  out_space_2d <- list(
    space_id = space_id_out,
    n = nrow(df2),
    cell_set = cell_set
  )
  out_model <- list(
    space_id = space_id_out,
    model_path = model_path_rel
  )
  out_params <- list(
    source_space_id = source_space_id,
    space_id_out = space_id_out,
    dims = dims_use,
    cell_set = cell_set,
    seed = seed,
    uwot = uwot_args
  )

  list(
    outputs = list(
      model = wb_prim_model_ref(
        model_space_id = space_id_out,
        in_space_id = source_space_id,
        engine = "uwot",
        artifact_id = NULL
      ),
      space_2d = wb_prim_space_2d(space_id_out)
    ),
    space_2d = out_space_2d,
    model = out_model,
    params = out_params
  )
}
