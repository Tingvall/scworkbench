test_pybench_palantir_bridge_contract <- function(bundle_dir,
                                                  pybench_python = .wb_pybench_default_python()) {
  if (!file.exists(pybench_python)) {
    message("Skipping pybench palantir bridge test: pybench interpreter not found at ", pybench_python)
    return(TRUE)
  }

  b <- wb_open_bundle(bundle_dir)
  on.exit(wb_close_bundle(b), add = TRUE)
  con <- b$con

  core <- wb_cells(b, "core")
  stopifnot(length(core) >= 300L)
  cell_ids <- as.character(core[1:800])
  root_cell <- as.character(cell_ids[1])
  terminal_cells <- as.character(cell_ids[c(2, 3)])

  run <- wb_new_run(
    op_name = "palantir_fit",
    inputs = list(cell_set = "all", cell_ids = cell_ids, fit_space = "peakvi_space", root_cell = root_cell,
                  terminal_cells = terminal_cells),
    params = list(dims = as.character(1:20), knn = 30, n_diffusion_components = 10, n_waypoints = 100, seed = 20),
    outputs = list(),
    notes = "pybench palantir bridge contract test"
  )

  outs_spec <- list(
    pseudotime = list(type = "cell_vector", name = "palantir pseudotime"),
    branch_membership = list(type = "relation_family", name = "palantir branch membership"),
    branch_summary = list(type = "obs_table", name = "palantir branch summary"),
    entropy = list(type = "cell_vector", name = "palantir entropy"),
    model = list(type = "model_ref", name = "palantir model")
  )

  prereg <- .wb_pybench_preregister_outputs(
    bundle = b,
    run = run,
    outputs_spec = outs_spec,
    created_by = "test-pybench-palantir"
  )
  created_art_ids <- vapply(prereg, function(x) as.character(x$artifact_id), character(1))

  cleanup <- function() {
    ids <- as.list(unname(created_art_ids))
    if (!length(ids)) return(invisible(TRUE))
    for (tbl in c("artifact_labels", "artifact_relation_rows", "artifact_table_rows", "artifact_tables", "artifact_model_ref")) {
      try(DBI::dbExecute(con, paste0(
        "DELETE FROM ", tbl, " WHERE artifact_id IN (", paste(rep("?", length(ids)), collapse = ","), ");"
      ), params = ids), silent = TRUE)
    }
    try(DBI::dbExecute(con, paste0(
      "DELETE FROM artifacts WHERE artifact_id IN (", paste(rep("?", length(ids)), collapse = ","), ");"
    ), params = ids), silent = TRUE)
    # Remove generated Python model files if present.
    model_dir <- file.path(bundle_dir, "artifact_models")
    for (aid in unname(created_art_ids)) {
      fp <- file.path(model_dir, paste0(aid, ".pkl"))
      if (file.exists(fp)) try(unlink(fp, force = TRUE), silent = TRUE)
    }
    invisible(TRUE)
  }
  on.exit(cleanup(), add = TRUE)

  req <- .wb_pybench_build_request(
    bundle = b,
    op_name = "palantir_fit",
    run_id = as.character(run$run_id),
    inputs = list(
      cell_set = "all",
      cell_ids = cell_ids,
      fit_space = "peakvi_space",
      root_cell = root_cell,
      terminal_cells = terminal_cells
    ),
    params = list(
      dims = as.character(1:20),
      knn = 30,
      n_diffusion_components = 10,
      n_waypoints = 100,
      seed = 20
    ),
    outputs = prereg
  )

  bridge <- .wb_pybench_run_module(
    module = "pybench.ops.palantir_fit",
    request = req,
    python_bin = pybench_python
  )

  rec <- bridge$receipt
  stopifnot(identical(as.character(rec$status), "ok"))
  stopifnot(identical(as.character(rec$op_name), "palantir_fit"))
  stopifnot(identical(as.character(rec$run_id), as.character(run$run_id)))
  stopifnot(is.list(rec$outputs))
  stopifnot(all(names(prereg) %in% names(rec$outputs)))

  pt <- wb_art_load(b, prereg$pseudotime$artifact_id, expected_kind = "cell_vector")
  bm <- wb_art_load(b, prereg$branch_membership$artifact_id, expected_kind = "relation_family")
  bs <- wb_art_load(b, prereg$branch_summary$artifact_id, expected_kind = "obs_table")
  en <- wb_art_load(b, prereg$entropy$artifact_id, expected_kind = "cell_vector")
  mr <- wb_art_load(b, prereg$model$artifact_id, expected_kind = "model_ref")

  stopifnot(identical(as.character(pt$kind), "cell_vector"))
  stopifnot(identical(as.character(pt$value_type), "continuous"))
  stopifnot(length(pt$cell_id) == length(cell_ids))
  stopifnot(setequal(as.character(pt$cell_id), cell_ids))

  stopifnot(identical(as.character(en$kind), "cell_vector"))
  stopifnot(identical(as.character(en$value_type), "continuous"))
  stopifnot(length(en$cell_id) == length(cell_ids))

  stopifnot(identical(as.character(bm$kind), "relation_family"))
  bm_tbl <- wb_primitive_to_table(bm, include_context = FALSE)
  stopifnot(is.data.frame(bm_tbl), nrow(bm_tbl) > 0L)
  stopifnot(all(grepl("^branch:", as.character(bm_tbl$key))))
  stopifnot(all(is.finite(as.numeric(bm_tbl$weight))))
  stopifnot(all(as.numeric(bm_tbl$weight) >= 0))
  stopifnot(all(as.numeric(bm_tbl$weight) <= 1 + 1e-8))
  stopifnot(length(unique(as.character(bm_tbl$key))) >= 1L)

  stopifnot(identical(as.character(bs$kind), "obs_table"))
  stopifnot(is.data.frame(bs$table))
  stopifnot(all(c("relation_key", "branch", "n_cells_prob_gt_0", "mean_prob", "max_prob") %in% names(bs$table)))
  stopifnot(all(grepl("^branch:", as.character(bs$table$relation_key))))

  stopifnot(identical(as.character(mr$kind), "model_ref"))
  stopifnot(identical(as.character(mr$engine), "palantir"))
  stopifnot(identical(as.character(mr$model_space_id), "peakvi_space"))
  stopifnot(file.exists(as.character(mr$model_path)))

  TRUE
}
