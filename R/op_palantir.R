#' @keywords internal
.wb_palantir_as_int_vec <- function(x, allow_null = TRUE, name = "dims") {
  if (is.null(x)) {
    if (allow_null) return(NULL)
    stop(name, " is required.", call. = FALSE)
  }
  if (!length(x)) return(integer(0))
  xi <- suppressWarnings(as.integer(x))
  .wb_assert(!anyNA(xi), paste0(name, " must be coercible to integer(s)."))
  xi
}

#' @keywords internal
.wb_palantir_cleanup_staging_artifacts <- function(bundle, artifact_ids, keep_model_files = TRUE) {
  artifact_ids <- unique(as.character(artifact_ids %||% character(0)))
  artifact_ids <- artifact_ids[nzchar(artifact_ids)]
  if (!length(artifact_ids)) return(invisible(TRUE))

  con <- bundle$con
  params <- as.list(artifact_ids)
  qmarks <- paste(rep("?", length(artifact_ids)), collapse = ",")

  for (tbl in c(
    "artifact_labels",
    "artifact_pseudotime",
    "artifact_relation_rows",
    "artifact_curves_2d",
    "artifact_table_rows",
    "artifact_tables",
    "artifact_model_ref"
  )) {
    try(DBI::dbExecute(con, paste0("DELETE FROM ", tbl, " WHERE artifact_id IN (", qmarks, ");"),
                       params = params), silent = TRUE)
  }

  if (!isTRUE(keep_model_files)) {
    model_dir <- file.path(bundle$dir, "artifact_models")
    for (aid in artifact_ids) {
      fp_pkl <- file.path(model_dir, paste0(aid, ".pkl"))
      fp_rds <- file.path(model_dir, paste0(aid, ".rds"))
      if (file.exists(fp_pkl)) try(unlink(fp_pkl, force = TRUE), silent = TRUE)
      if (file.exists(fp_rds)) try(unlink(fp_rds, force = TRUE), silent = TRUE)
    }
  }

  try(DBI::dbExecute(con, paste0("DELETE FROM artifacts WHERE artifact_id IN (", qmarks, ");"),
                     params = params), silent = TRUE)
  invisible(TRUE)
}

#' @keywords internal
.wb_palantir_bridge_run_or_stop <- function(bundle = NULL, ...) {
  bridge <- .wb_pybench_run_module(..., bundle=bundle)
  rec <- bridge$receipt %||% list()
  if (!identical(as.character(rec$status %||% "error"), "ok")) {
    msg <- paste0(
      "pybench op failed: ",
      as.character(rec$error_class %||% "PybenchOpError"), ": ",
      as.character(rec$message %||% "unknown error")
    )
    stop(msg, call. = FALSE)
  }
  bridge
}

#' Project Palantir branch trajectories into a 2D display space
#'
#' Derived display projection mirroring Palantir's trajectory plotting idea:
#' interpolate branch-specific embedding coordinates across pseudotime to obtain
#' branch paths suitable for Scene overlays.
#'
#' @export
wb_op_palantir_project <- function(bundle,
                                   model,
                                   plot_space_id,
                                   prob_min = 0.05,
                                   smoothness = 1.0,
                                   min_cells_per_branch = 50L,
                                   approx_points = 200L,
                                   python_bin = .wb_pybench_default_python(),
                                   ...) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert_operation_execution(bundle, "palantir_project")
  .wb_assert_kind(model, "model_ref")
  .wb_assert(identical(as.character(model$engine %||% "")[1], "palantir"),
             "palantir_project requires model_ref(engine='palantir').")
  .wb_assert(is.character(plot_space_id) && length(plot_space_id) == 1L && nzchar(plot_space_id),
             "palantir_project requires plot_space_id.")
  model_path <- .wb_pybench_model_request_path(
    bundle, model, purpose = "Palantir project model"
  )

  # Validate target plot space exists and is 2D before handing off to Python.
  sp <- wb_space(bundle, space_id = plot_space_id)
  X_plot <- .wb_as_coord_matrix(sp)
  .wb_assert(ncol(X_plot) == 2L, "palantir_project requires a 2D plot space.")

  run_tmp <- wb_new_run(
    op_name = "palantir_project",
    inputs = list(
      cell_set = "all",
      user_inputs = list(model_path = model_path, plot_space = plot_space_id)
    ),
    params = list(plot_space_id = plot_space_id),
    outputs = list(),
    notes = "pybench staging preregistration"
  )
  outs_spec <- list(curves = list(type = "path_2d_family", name = "Palantir projected trajectories"))
  prereg <- .wb_pybench_preregister_outputs(bundle = bundle, run = run_tmp, outputs_spec = outs_spec)
  staging_ids <- vapply(prereg, function(x) as.character(x$artifact_id), character(1))
  pybench_success <- FALSE
  on.exit(if (!isTRUE(pybench_success)) .wb_palantir_cleanup_staging_artifacts(bundle, staging_ids, keep_model_files = FALSE), add = TRUE)

  req <- .wb_pybench_build_request(
    bundle = bundle,
    op_name = "palantir_project",
    run_id = .wb_pybench_current_run_id(bundle),
    inputs = list(
      model_path = model_path,
      plot_space = plot_space_id
    ),
    params = list(
      prob_min = as.numeric(prob_min)[1],
      smoothness = as.numeric(smoothness %||% 1.0)[1],
      min_cells_per_branch = as.integer(min_cells_per_branch %||% 50L)[1],
      sample_points = as.integer(approx_points %||% 200L)[1]
    ),
    outputs = prereg
  )
  bridge <- .wb_palantir_bridge_run_or_stop(
    bundle = bundle,
    module = "pybench.ops.palantir_project",
    request = req,
    python_bin = python_bin
  )
  rec <- bridge$receipt

  cv_prim <- wb_art_load(bundle, prereg$curves$artifact_id, expected_kind = "path_2d_family")
  cv_prim$plot_space_id <- as.character(plot_space_id)
  pybench_success <- TRUE

  list(
    outputs = list(curves = cv_prim),
    params = list(
      plot_space_id = as.character(plot_space_id),
      prob_min = as.numeric(prob_min)[1],
      smoothness = as.numeric(smoothness %||% 1.0)[1],
      min_cells_per_branch = as.integer(min_cells_per_branch)[1],
      approx_points = as.integer(approx_points)[1],
      n_lineages = length(unique(as.character(cv_prim$key))),
      curve_method = "palantir_mellon_interpolation",
      pybench_runtime = list(
        protocol_version = as.character(rec$protocol_version %||% .wb_pyproto_version())[1],
        pybench_version = as.character(rec$pybench$version %||% NA_character_)[1],
        timings = rec$timings %||% list()
      )
    )
  )
}

#' Run Palantir trajectory inference via pybench (Python runtime)
#'
#' Bench remains provenance/registry authority; Python writes payload tables/files
#' for pre-registered artifacts and returns a protocol receipt.
#'
#' @export
wb_op_palantir_fit <- function(bundle,
                               fit_space_id,
                               cells,
                               root_cell,
                               terminal_cells = NULL,
                               dims = NULL,
                               knn = 30L,
                               n_diffusion_components = 10L,
                               n_waypoints = 300L,
                               use_early_cell_as_start = TRUE,
                               seed = 20L,
                               cell_set = "all",
                               python_bin = .wb_pybench_default_python()) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert_operation_execution(bundle, "palantir_fit")
  .wb_assert(is.character(fit_space_id) && length(fit_space_id) == 1L && nzchar(fit_space_id),
             "palantir_fit requires fit_space_id.")

  cells <- unique(as.character(cells %||% character(0)))
  .wb_assert(length(cells) >= 10L, "palantir_fit requires at least 10 cells.")

  .wb_assert(is.character(root_cell) && length(root_cell) == 1L && nzchar(root_cell),
             "palantir_fit requires root_cell (length-1 cell id).")
  root_cell <- as.character(root_cell)[1]
  .wb_assert(root_cell %in% cells, "palantir_fit root_cell must be present in effective cells.")
  terminal_cells <- unique(as.character(terminal_cells %||% character(0)))
  terminal_cells <- terminal_cells[nzchar(terminal_cells)]
  if (length(terminal_cells)) {
    .wb_assert(all(terminal_cells %in% cells),
               "palantir_fit terminal_cells must all be present in effective cells.")
  } else {
    terminal_cells <- NULL
  }

  dims_i <- .wb_palantir_as_int_vec(dims, allow_null = TRUE, name = "dims")
  knn <- as.integer(knn %||% 30L)
  n_diffusion_components <- as.integer(n_diffusion_components %||% 10L)
  n_waypoints <- as.integer(n_waypoints %||% 300L)
  use_early_cell_as_start <- isTRUE(use_early_cell_as_start)
  seed_i <- if (is.null(seed)) NULL else as.integer(seed)
  .wb_assert(!is.na(knn) && knn >= 2L, "palantir_fit knn must be >= 2.")
  .wb_assert(!is.na(n_diffusion_components) && n_diffusion_components >= 2L,
             "palantir_fit n_diffusion_components must be >= 2.")
  .wb_assert(!is.na(n_waypoints) && n_waypoints >= 1L, "palantir_fit n_waypoints must be >= 1.")
  if (!is.null(seed_i)) .wb_assert(!is.na(seed_i), "palantir_fit seed must be integer-like or NULL.")

  # Temporary run object only to pre-register payload artifacts. The real run is
  # created by wb_session_run_op() after this op returns primitives.
  run_tmp <- wb_new_run(
    op_name = "palantir_fit",
    inputs = list(
      cell_set = as.character(cell_set %||% "all")[1],
      user_inputs = list(
        fit_space = fit_space_id,
        root_cell = root_cell,
        terminal_cells = terminal_cells,
        cell_ids = cells
      )
    ),
    params = list(space_id = fit_space_id),
    outputs = list(),
    notes = "pybench staging preregistration"
  )

  outs_spec <- list(
    pseudotime = list(type = "cell_vector", name = "Palantir pseudotime"),
    branch_membership = list(type = "relation_family", name = "Palantir branch membership"),
    branch_summary = list(type = "obs_table", name = "Palantir branch summary"),
    entropy = list(type = "cell_vector", name = "Palantir entropy"),
    model = list(type = "model_ref", name = "Palantir model")
  )
  prereg <- .wb_pybench_preregister_outputs(bundle = bundle, run = run_tmp, outputs_spec = outs_spec)
  staging_ids <- vapply(prereg, function(x) as.character(x$artifact_id), character(1))
  pybench_success <- FALSE
  on.exit(if (!isTRUE(pybench_success)) .wb_palantir_cleanup_staging_artifacts(bundle, staging_ids, keep_model_files = FALSE), add = TRUE)

  req <- .wb_pybench_build_request(
    bundle = bundle,
    op_name = "palantir_fit",
    run_id = .wb_pybench_current_run_id(bundle),
    inputs = list(
      cell_set = as.character(cell_set %||% "all")[1],
      cell_ids = cells,
      fit_space = fit_space_id,
      root_cell = root_cell
      ,
      terminal_cells = if (is.null(terminal_cells)) NULL else as.list(as.character(terminal_cells))
    ),
    params = list(
      dims = if (is.null(dims_i)) NULL else as.character(dims_i),
      knn = knn,
      n_diffusion_components = n_diffusion_components,
      n_waypoints = n_waypoints,
      use_early_cell_as_start = use_early_cell_as_start,
      seed = seed_i
    ),
    outputs = prereg
  )

  bridge <- .wb_palantir_bridge_run_or_stop(
    bundle = bundle,
    module = "pybench.ops.palantir_fit",
    request = req,
    python_bin = python_bin
  )

  rec <- bridge$receipt

  outputs <- list(
    pseudotime = wb_art_load(bundle, prereg$pseudotime$artifact_id, expected_kind = "cell_vector"),
    branch_membership = wb_art_load(bundle, prereg$branch_membership$artifact_id, expected_kind = "relation_family"),
    branch_summary = wb_art_load(bundle, prereg$branch_summary$artifact_id, expected_kind = "obs_table"),
    entropy = wb_art_load(bundle, prereg$entropy$artifact_id, expected_kind = "cell_vector"),
    model = wb_art_load(bundle, prereg$model$artifact_id, expected_kind = "model_ref")
  )
  # Palantir fits and projects in the same analytical space.  Preserve that
  # association and the exact fitted-cell universe on the session primitive so
  # a process-replaced dependent project can derive typed coverage without
  # inspecting Python model internals.
  outputs$model$in_space_id <- as.character(fit_space_id)
  outputs$model$model_space_id <- as.character(fit_space_id)
  outputs$model$cells <- as.character(cells)
  pybench_success <- TRUE

  params_out <- list(
    space_id = fit_space_id,
    root_cell = root_cell,
    terminal_cells = terminal_cells,
    dims = if (is.null(dims_i)) NULL else as.integer(dims_i),
    knn = knn,
    n_diffusion_components = n_diffusion_components,
    n_waypoints = n_waypoints,
    use_early_cell_as_start = use_early_cell_as_start,
    seed = seed_i,
    pybench_runtime = list(
      protocol_version = as.character(rec$protocol_version %||% .wb_pyproto_version())[1],
      pybench_version = as.character(rec$pybench$version %||% NA_character_)[1],
      timings = rec$timings %||% list()
    ),
    weight_semantics = "palantir_branch_probability",
    branch_membership_key_prefix = "branch:",
    branch_membership_requires_terminal_states = TRUE
  )

  list(outputs = outputs, params = params_out)
}
