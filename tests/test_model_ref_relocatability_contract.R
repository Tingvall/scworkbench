test_model_ref_relocatability_contract <- function() {
  tmp <- tempfile("scwb_model_ref_reloc_")
  b <- wb_init_bundle(tmp, overwrite = TRUE)

  cells <- c("c1", "c2", "c3")
  wb_define_cells(b, cells)
  coords <- data.frame(cell_id = cells, x = c(0, 1, 2), y = c(0, 1, 0), stringsAsFactors = FALSE)
  wb_attach_space(b, space_id = "umap_test", coords = coords)

  model <- wb_prim_model_ref(
    model_space_id = "umap_test",
    in_space_id = "umap_test",
    engine = "monocle3"
  )
  model$model_type <- "monocle3"
  model$model_obj <- list(
    contract = "model_ref_relocatability",
    pseudotime_table = data.frame(
      lineage_id = "L1",
      cell_id = cells,
      pseudotime = c(0, 1, 2),
      stringsAsFactors = FALSE
    )
  )

  run <- wb_new_run(
    op_name = "monocle3_fit",
    inputs = list(
      cell_set = "core",
      user_inputs = list(fit_space = wb_prim_space("umap_test")),
      execution_inputs = list(resolved = list(fit_space = wb_prim_space("umap_test")))
    ),
    params = list(fit_space_id = "umap_test", n_lineages = 1L),
    outputs = list(model = model),
    notes = "model_ref relocatability contract"
  )

  prom <- wb_promote_analysis(
    bundle = b,
    runs = setNames(list(run), run$run_id),
    head_run_id = run$run_id,
    name_prefix = "model_ref relocatability",
    fail_fast = TRUE
  )
  output_col <- if ("output_name" %in% names(prom$promoted)) "output_name" else "output"
  model_artifact_id <- as.character(prom$promoted$artifact_id[as.character(prom$promoted[[output_col]]) == "model"])[1]
  stopifnot(nzchar(model_artifact_id))

  row <- DBI::dbGetQuery(
    b$con,
    "SELECT model_path FROM artifact_model_ref WHERE artifact_id = ?;",
    params = list(model_artifact_id)
  )
  stopifnot(nrow(row) == 1L)
  stored <- as.character(row$model_path[[1]])
  stopifnot(nzchar(stored))
  stopifnot(!.wb_path_is_absolute(stored))
  stopifnot(startsWith(stored, "artifact_models/"))
  stopifnot(file.exists(file.path(tmp, stored)))

  loaded <- wb_art_load(b, model_artifact_id, expected_kind = "model_ref")
  stopifnot(identical(as.character(loaded$kind), "model_ref"))
  stopifnot(file.exists(as.character(loaded$model_path)))
  stopifnot(!is.null(loaded$model_obj))
  stopifnot(identical(loaded$model_obj$contract, "model_ref_relocatability"))

  wb_close_bundle(b)

  moved_parent <- tempfile("scwb_model_ref_moved_parent_")
  dir.create(moved_parent, recursive = TRUE, showWarnings = FALSE)
  moved <- file.path(moved_parent, "signal_copy")
  ok <- file.copy(tmp, moved_parent, recursive = TRUE)
  stopifnot(isTRUE(ok))
  moved <- file.path(moved_parent, basename(tmp))

  b2 <- wb_open_bundle(moved)
  on.exit({
    try(wb_close_bundle(b2), silent = TRUE)
    unlink(tmp, recursive = TRUE, force = TRUE)
    unlink(moved_parent, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  loaded2 <- wb_art_load(b2, model_artifact_id, expected_kind = "model_ref")
  stopifnot(identical(as.character(loaded2$kind), "model_ref"))
  stopifnot(file.exists(as.character(loaded2$model_path)))
  stopifnot(startsWith(normalizePath(loaded2$model_path, winslash = "/", mustWork = TRUE),
                       normalizePath(moved, winslash = "/", mustWork = TRUE)))
  stopifnot(identical(loaded2$model_obj$contract, "model_ref_relocatability"))

  stale_abs <- file.path("/old/location/artifact_models", basename(stored))
  DBI::dbExecute(
    b2$con,
    "UPDATE artifact_model_ref SET model_path = ? WHERE artifact_id = ?;",
    params = list(stale_abs, model_artifact_id)
  )

  loaded3 <- wb_art_load(b2, model_artifact_id, expected_kind = "model_ref")
  stopifnot(identical(as.character(loaded3$kind), "model_ref"))
  stopifnot(file.exists(as.character(loaded3$model_path)))
  stopifnot(identical(normalizePath(loaded3$model_path, winslash = "/", mustWork = TRUE),
                      normalizePath(file.path(moved, "artifact_models", basename(stored)), winslash = "/", mustWork = TRUE)))
  stopifnot(identical(loaded3$model_obj$contract, "model_ref_relocatability"))

  repair_plan <- wb_repair_model_ref_paths(b2, dry_run = TRUE)
  repair_row <- repair_plan[repair_plan$artifact_id == model_artifact_id, , drop = FALSE]
  stopifnot(nrow(repair_row) == 1L)
  stopifnot(identical(as.character(repair_row$action), "repair_stale_absolute_basename"))
  stopifnot(identical(as.character(repair_row$new_model_path), file.path("artifact_models", basename(stored))))

  invisible(wb_repair_model_ref_paths(b2, dry_run = FALSE))
  repaired <- DBI::dbGetQuery(
    b2$con,
    "SELECT model_path FROM artifact_model_ref WHERE artifact_id = ?;",
    params = list(model_artifact_id)
  )
  stopifnot(identical(as.character(repaired$model_path[[1]]), file.path("artifact_models", basename(stored))))

  DBI::dbExecute(
    b2$con,
    "UPDATE artifact_model_ref SET model_path = ? WHERE artifact_id = ?;",
    params = list("/old/location/artifact_models/does_not_exist.rds", model_artifact_id)
  )
  err <- tryCatch(
    wb_art_load(b2, model_artifact_id, expected_kind = "model_ref"),
    error = function(e) e
  )
  stopifnot(inherits(err, "error"))
  stopifnot(grepl("Attempted:", conditionMessage(err), fixed = TRUE))
  stopifnot(grepl(file.path(moved, "artifact_models", "does_not_exist.rds"), conditionMessage(err), fixed = TRUE))

  TRUE
}
