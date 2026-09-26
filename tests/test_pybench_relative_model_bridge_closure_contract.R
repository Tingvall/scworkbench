test_pybench_relative_model_bridge_closure_contract <- function() {
  if (!requireNamespace("BPCells", quietly = TRUE)) {
    return(contract_test_skip("BPCells is not installed."))
  }
  pybench_python <- .wb_pybench_default_python()
  if (!file.exists(pybench_python)) {
    return(contract_test_skip(paste("PyBench interpreter not found at", pybench_python)))
  }

  source_root <- tempfile("scwb_relative_model_source_")
  b <- wb_init_bundle(source_root, overwrite = TRUE)
  moved_parent <- tempfile("scwb_relative_model_moved_")
  dir.create(moved_parent, recursive = TRUE, showWarnings = FALSE)
  moved_root <- file.path(moved_parent, "portable.bundle")
  on.exit({
    try(wb_close_bundle(b), silent = TRUE)
    unlink(source_root, recursive = TRUE, force = TRUE)
    unlink(moved_parent, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  cells <- paste0("cell_", seq_len(4L))
  wb_define_cells(b, cells)
  wb_attach_matrix(
    b, "ATAC_counts",
    matrix(seq_len(12L), nrow = 3L,
           dimnames = list(paste0("peak_", seq_len(3L)), cells)),
    feature_type = "peak"
  )
  wb_attach_space(
    b, "plot2d",
    data.frame(cell_id = cells, x = seq_along(cells),
               y = rev(seq_along(cells)), stringsAsFactors = FALSE)
  )
  wb_attach_space(
    b, "peakvi_model_space",
    data.frame(cell_id = cells, x = seq_along(cells),
               y = rev(seq_along(cells)), stringsAsFactors = FALSE)
  )

  peak_relative <- "artifact_models/promoted_peakvi"
  dir.create(file.path(source_root, peak_relative), recursive = TRUE, showWarnings = FALSE)
  writeLines("contained PeakVI model", file.path(source_root, peak_relative, "model.txt"))

  promote_model <- function(engine, model_space_id, relative) {
    model <- wb_prim_model_ref(model_space_id, model_space_id, engine = engine)
    model$model_type <- engine
    model$model_path <- file.path(source_root, relative)
    run <- wb_new_run(
      op_name = paste0(engine, "_fit"),
      inputs = list(cell_set = "all", user_inputs = list()),
      params = list(), outputs = list(model = model),
      notes = "relative PyBench bridge promoted model fixture"
    )
    promoted <- wb_promote_analysis(
      bundle = b, runs = setNames(list(run), run$run_id),
      head_run_id = run$run_id, name_prefix = paste(engine, "bridge"),
      outputs = "model", fail_fast = TRUE
    )
    as.character(promoted$promoted$artifact_id[1])
  }
  peak_artifact <- promote_model("peakvi", "peakvi_model_space", peak_relative)
  stopifnot(nzchar(peak_artifact))
  stored <- DBI::dbGetQuery(
    b$con,
    "SELECT artifact_id, model_path FROM artifact_model_ref WHERE artifact_id = ?;",
    params = list(peak_artifact)
  )
  stopifnot(nrow(stored) == 1L, all(!vapply(stored$model_path, .wb_path_is_absolute, logical(1))))

  wb_close_bundle(b)
  stopifnot(isTRUE(file.rename(source_root, moved_root)))
  b <- wb_open_bundle(moved_root)

  peak_model <- wb_art_load(b, peak_artifact, expected_kind = "model_ref")
  stopifnot(.wb_path_is_absolute(peak_model$model_path),
            identical(.wb_pybench_model_request_path(b, peak_model), peak_relative))

  captured <- new.env(parent = emptyenv())
  captured$requests <- list()
  captured$calls <- 0L
  op_env <- environment(wb_op_peakvi_project)
  old_bridge <- get(".wb_pybench_bridge_run_or_stop", envir = op_env)
  unlockBinding(".wb_pybench_bridge_run_or_stop", op_env)
  assign(".wb_pybench_bridge_run_or_stop", function(bundle = NULL, module, request, ...) {
    captured$calls <- captured$calls + 1L
    captured$requests[[length(captured$requests) + 1L]] <- request
    bridge_bundle <- wb_open_bundle(request$bundle_dir)
    on.exit(wb_close_bundle(bridge_bundle), add = TRUE)
    if (identical(module, "pybench.ops.peakvi_project")) {
      output_cells <- as.character(request$inputs$cell_ids)
      wb_add_space(
        bridge_bundle, as.character(request$params$space_id_out),
        matrix(seq_len(length(output_cells) * 2L), nrow = length(output_cells),
               dimnames = list(output_cells, c("z1", "z2"))),
        source = "relative-model-bridge-mock"
      )
    } else {
      stop("Unexpected mocked PyBench module: ", module, call. = FALSE)
    }
    list(receipt = list(
      status = "ok", protocol_version = "pybench-op-v2",
      pybench = list(version = "containment-contract"), timings = list(total_sec = 0)
    ))
  }, envir = op_env)
  on.exit({
    assign(".wb_pybench_bridge_run_or_stop", old_bridge, envir = op_env)
    lockBinding(".wb_pybench_bridge_run_or_stop", op_env)
  }, add = TRUE)

  peak_run <- wb_session_run_op(
    wb_session_new(), b, "peakvi_project",
    inputs = list(
      matrix = "ATAC_counts", model = wb_ref_artifact(peak_artifact, "model"),
      cell_set = "all", min_cells = 1L, space_id_out = "peakvi_projected"
    )
  )
  stopifnot(length(captured$requests) == 1L)
  request_paths <- vapply(
    captured$requests, function(request) as.character(request$inputs$model_path),
    character(1)
  )
  stopifnot(identical(request_paths, peak_relative),
            all(!vapply(request_paths, .wb_path_is_absolute, logical(1))),
            all(!startsWith(request_paths, normalizePath(moved_root, winslash = "/", mustWork = TRUE))))
  stopifnot(
    identical(peak_run$run$inputs$provenance_refs$model$artifact_id, peak_artifact),
    identical(peak_run$run$outputs$space$kind, "space")
  )

  relative_primitive <- wb_prim_model_ref("peakvi_model_space", "peakvi_model_space", "peakvi")
  relative_primitive$model_path <- peak_relative
  stopifnot(identical(.wb_pybench_model_request_path(b, relative_primitive), peak_relative))

  outside <- tempfile("external_model_")
  dir.create(outside)
  on.exit(unlink(outside, recursive = TRUE, force = TRUE), add = TRUE)
  escaping <- file.path(moved_root, "escaping_model")
  stopifnot(isTRUE(file.symlink(outside, escaping)))
  adversarial <- list(
    traversal = "../external-model",
    external_absolute = normalizePath(outside, winslash = "/", mustWork = TRUE),
    missing = "artifact_models/missing-model",
    symlink_escape = "escaping_model"
  )
  expected_codes <- c("PATH_ESCAPE", "PATH_ABSOLUTE", "PAYLOAD_MISSING", "PATH_SYMLINK_ESCAPE")
  observed <- vapply(seq_along(adversarial), function(i) {
    candidate <- wb_prim_model_ref("peakvi_model_space", "peakvi_model_space", "peakvi")
    candidate$model_path <- adversarial[[i]]
    error <- tryCatch(.wb_pybench_model_request_path(b, candidate), error = identity)
    stopifnot(inherits(error, "error"))
    conditionMessage(error)
  }, character(1))
  stopifnot(all(mapply(grepl, expected_codes, observed, MoreArgs = list(fixed = TRUE))))
  unlink(escaping, force = TRUE)

  calls_before_rejection <- captured$calls
  unsafe_model <- relative_primitive
  unsafe_model$artifact_id <- NULL
  unsafe_model$model_path <- normalizePath(outside, winslash = "/", mustWork = TRUE)
  unsafe_run <- tryCatch(
    wb_session_run_op(
      wb_session_new(), b, "peakvi_project",
      inputs = list(
        matrix = "ATAC_counts", model = unsafe_model,
        cell_set = "all", min_cells = 1L, space_id_out = "must_not_exist"
      )
    ),
    error = identity
  )
  stopifnot(inherits(unsafe_run, "error"),
            grepl("PATH_ABSOLUTE", conditionMessage(unsafe_run), fixed = TRUE),
            identical(captured$calls, calls_before_rejection))

  strict_model <- file.path(moved_root, "artifact_models", "strict_peakvi")
  dir.create(strict_model, recursive = TRUE, showWarnings = FALSE)
  strict_request <- try(.wb_pybench_build_request(
    b, "peakvi_project", "strict-python-absolute-rejection",
    inputs = list(matrix = "ATAC_counts", model_path = normalizePath(strict_model, winslash = "/", mustWork = TRUE)),
    params = list(matrix_id = "ATAC_counts", space_id_out = "never_written"),
    outputs = list()
  ), silent = TRUE)
  stopifnot(inherits(strict_request, "try-error"),
            grepl("PYBENCH_SOURCE_WRITE_ATTEMPT", as.character(strict_request), fixed = TRUE),
            !"never_written" %in% wb_spaces(b)$space_id)

  TRUE
}
