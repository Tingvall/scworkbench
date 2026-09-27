test_reporting_contracts <- function() {
  tmp <- tempfile("scwb_reporting_contracts_")
  b <- wb_init_bundle(tmp, overwrite = TRUE)
  on.exit({
    try(wb_close_bundle(b), silent = TRUE)
    unlink(tmp, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  cells <- c("c1", "c2", "c3", "c4")
  meta <- data.frame(
    cell_id = cells,
    dataset_id = c("d1", "d1", "d2", "d2"),
    cell_type = c("A", "A", "B", "B"),
    score = c(0.1, 0.2, 0.9, NA),
    stringsAsFactors = FALSE
  )
  wb_define_cells(b, cell_ids = cells, metadata = meta, dataset_id = meta$dataset_id)

  mat <- Matrix::Matrix(
    matrix(c(1, 0, 0, 2, 0, 3, 1, 0), nrow = 2, byrow = TRUE, dimnames = list(c("g1", "g2"), cells)),
    sparse = TRUE
  )
  wb_attach_matrix(b, matrix_id = "RNA_counts", mat = mat, feature_type = "gene")
  wb_attach_space(
    b,
    space_id = "umap_test",
    coords = data.frame(cell_id = cells, UMAP_1 = c(0, 1, 2, 3), UMAP_2 = c(0, 1, 0, 1), stringsAsFactors = FALSE)
  )

  model <- wb_prim_model_ref(model_space_id = "umap_test", in_space_id = "umap_test", engine = "monocle3")
  model$model_type <- "monocle3"
  model$model_obj <- list(contract = "reporting_contracts")
  run <- wb_new_run(
    op_name = "slingshot_adopt",
    inputs = list(
      cell_set = "core",
      user_inputs = list(fit_space = wb_prim_space("umap_test")),
      execution_inputs = list(effective_n = length(cells), resolved = list(fit_space = wb_prim_space("umap_test")))
    ),
    params = list(fit_space_id = "umap_test", cells_fit = length(cells), n_lineages = 1L),
    outputs = list(
      model = model,
      summary = wb_prim_obs_table(
        data.frame(metric = "n_cells", value = length(cells), stringsAsFactors = FALSE),
        table_type = "reporting_contract_summary",
        entity_kind = "metric"
      )
    ),
    notes = "reporting contract synthetic run"
  )
  prom <- wb_promote_analysis(
    bundle = b,
    runs = setNames(list(run), run$run_id),
    head_run_id = run$run_id,
    name_prefix = "Reporting Contract",
    fail_fast = TRUE
  )
  stopifnot(is.data.frame(prom$promoted), nrow(prom$promoted) >= 1L)

  cols <- wb_cell_metadata_columns(b)
  stopifnot(is.data.frame(cols), all(c("column_name", "r_class", "n_missing", "n_distinct", "useful_for_coloring") %in% names(cols)))
  stopifnot(all(c("cell_id", "cell_type", "score") %in% as.character(cols$column_name)))
  stopifnot(!isTRUE(cols$useful_for_coloring[match("cell_id", cols$column_name)]))
  stopifnot(isTRUE(cols$useful_for_grouping[match("cell_type", cols$column_name)]))

  overview <- wb_bundle_overview(b, validate = FALSE)
  stopifnot(is.list(overview), identical(as.character(overview$schema), "bundle_overview_v1"))
  stopifnot(identical(as.integer(overview$counts$n_cells), length(cells)))
  stopifnot(overview$counts$n_matrices >= 1L)
  stopifnot(overview$counts$n_artifacts >= 1L)
  stopifnot(is.data.frame(overview$artifact_counts_by_type))
  stopifnot(any(as.character(overview$artifact_counts_by_type$type) == "model_ref"))

  traj <- wb_list_trajectory_models(b, inspect_payload = FALSE)
  stopifnot(is.data.frame(traj), nrow(traj) >= 1L)
  stopifnot(all(c("artifact_id", "engine", "model_space_id", "fitted_cell_count", "n_lineages", "warnings") %in% names(traj)))
  stopifnot(any(as.character(traj$engine) == "monocle3"))
  hit <- traj[as.character(traj$engine) == "monocle3", , drop = FALSE][1, , drop = FALSE]
  stopifnot(identical(as.integer(hit$fitted_cell_count), length(cells)))
  stopifnot(identical(as.integer(hit$n_lineages), 1L))

  # Core reporting still inspects an authenticated model payload independently
  # of the retired trajectory method implementations.
  report_model <- wb_prim_model_ref("umap_test", "umap_test", engine = "synthetic")
  report_model$pseudotime_table <- data.frame(
    lineage_id = "L1", cell_id = cells,
    pseudotime = seq(0, 1, length.out = length(cells)),
    stringsAsFactors = FALSE
  )
  inspected <- scworkbench:::.wb_reporting_trajectory_lineages(report_model)
  stopifnot(identical(names(inspected), "L1"),
            identical(as.character(inspected$L1$cell_id), cells),
            identical(as.numeric(inspected$L1$pseudotime),
                      seq(0, 1, length.out = length(cells))))

  hist <- wb_run_history(b)
  stopifnot(is.data.frame(hist), nrow(hist) >= 1L)
  stopifnot(all(c("snapshot_id", "run_id", "op_name", "promoted_artifact_ids", "parent_count", "child_count") %in% names(hist)))
  stopifnot(any(as.character(hist$run_id) == run$run_id))
  stopifnot(any(grepl("model_ref_", as.character(hist$promoted_artifact_ids), fixed = TRUE)))

  hist_one <- wb_run_history(b, snapshot_id = as.character(hist$snapshot_id[1]))
  stopifnot(is.data.frame(hist_one), nrow(hist_one) >= 1L)
  stopifnot(all(as.character(hist_one$snapshot_id) == as.character(hist$snapshot_id[1])))

  TRUE
}
