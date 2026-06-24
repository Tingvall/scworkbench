test_op_slingshot_fit_project_contract <- function(bundle_dir) {
  b <- wb_open_bundle(bundle_dir)
  tmp_synthetic <- NULL
  on.exit({
    try(wb_close_bundle(b), silent = TRUE)
    if (!is.null(tmp_synthetic)) unlink(tmp_synthetic, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  if (length(wb_cells(b, cell_set = "all")) < 100L) {
    try(wb_close_bundle(b), silent = TRUE)
    tmp_synthetic <- tempfile("scwb_slingshot_fixture_")
    b <- wb_init_bundle(tmp_synthetic, overwrite = TRUE)

    n <- 120L
    cells_syn <- paste0("s", seq_len(n))
    t <- seq(0, 1, length.out = n)
    cl <- rep(c("root", "mid", "end"), each = n / 3L)
    set.seed(20260624)
    meta <- data.frame(
      cell_id = cells_syn,
      dataset_id = "synthetic",
      synthetic_cluster = cl,
      stringsAsFactors = FALSE
    )
    wb_define_cells(b, cells_syn, metadata = meta, dataset_id = meta$dataset_id)
    fit_mat <- cbind(
      dim1 = t * 10,
      dim2 = sin(t * pi) + stats::rnorm(n, sd = 0.02),
      dim3 = cos(t * pi) * 0.2
    )
    rownames(fit_mat) <- cells_syn
    fit_coords <- data.frame(
      cell_id = rep(cells_syn, times = ncol(fit_mat)),
      dim = rep(seq_len(ncol(fit_mat)), each = length(cells_syn)),
      value = as.numeric(fit_mat),
      stringsAsFactors = FALSE
    )
    plot_coords <- data.frame(
      cell_id = cells_syn,
      x = fit_mat[, "dim1"],
      y = fit_mat[, "dim2"],
      stringsAsFactors = FALSE
    )
    wb_attach_space(b, "peakvi_space", fit_coords, source = "test", created_by = "test")
    wb_attach_space(b, "umap.peakvi_space", plot_coords, source = "test", created_by = "test")
  }

  # Prefer the known B-lineage/trajectory subset in cooltest; fall back to core.
  candidate_sets <- c("set:usecase1_btraj_early", "core", "all")
  cell_set <- candidate_sets[which(vapply(candidate_sets, function(cs) {
    length(tryCatch(wb_cells(b, cell_set = cs), error = function(e) character(0))) >= 100
  }, logical(1)))[1]]
  stopifnot(length(cell_set) == 1, nzchar(cell_set))

  cells <- wb_cells(b, cell_set = cell_set)
  stopifnot(length(cells) >= 100)
  cell_ids <- as.character(head(cells, 600))

  s <- wb_session_new()

  x1 <- wb_session_run_op(
    session = s,
    bundle = b,
    op_name = "leiden",
    inputs = list(
      cell_set = cell_set,
      cell_ids = cell_ids,
      space = wb_prim_space("peakvi_space"),
      k = 20,
      resolution = 0.3
    ),
    notes = "test slingshot fit/project: leiden seed clusters"
  )
  s <- x1$session

  x2 <- wb_session_run_op(
    session = s,
    bundle = b,
    op_name = "slingshot_fit",
    inputs = list(
      cell_set = cell_set,
      cell_ids = cell_ids,
      fit_space = wb_prim_space("peakvi_space"),
      clusters = wb_ref_run(x1$run$run_id, "clusters")
    ),
    notes = "test slingshot fit/project: fit"
  )
  s <- x2$session

  stopifnot("pseudotime" %in% names(x2$run$outputs))
  stopifnot("lineage_weights" %in% names(x2$run$outputs))
  stopifnot("model" %in% names(x2$run$outputs))
  stopifnot(identical(as.character(x2$run$outputs$lineage_weights$kind), "cell_vector_family"))
  stopifnot(identical(as.character(x2$run$outputs$lineage_weights$value_type), "continuous"))
  stopifnot(identical(as.character(x2$run$outputs$lineage_weights$meta$family_kind), "trajectory_membership_weight"))
  stopifnot(identical(as.character(x2$run$outputs$lineage_weights$meta$engine), "slingshot"))
  stopifnot(identical(as.character(x2$run$outputs$model$engine), "slingshot"))
  stopifnot(!is.null(x2$run$outputs$model$model_obj))
  model_cells <- x2$run$outputs$model$cells
  if (is.null(model_cells)) model_cells <- character(0)
  stopifnot(length(as.character(model_cells)) >= 10)

  pt_keys <- sort(unique(as.character(x2$run$outputs$pseudotime$key)))
  wt_keys <- sort(unique(as.character(x2$run$outputs$lineage_weights$key)))
  stopifnot(identical(wt_keys, pt_keys))
  wt_vals <- suppressWarnings(as.numeric(x2$run$outputs$lineage_weights$value))
  stopifnot(length(wt_vals) > 0L)
  stopifnot(all(is.na(wt_vals) | (wt_vals >= -1e-8 & wt_vals <= 1 + 1e-8)))

  prom_fit <- wb_session_promote_current(
    bundle = b,
    session = s,
    name_prefix = "test_slingshot_fit_weights",
    created_by = "test",
    fail_fast = TRUE
  )
  promoted <- prom_fit$promoted
  pseudotime_artifact_id <- as.character(promoted$artifact_id[as.character(promoted$output) == "pseudotime"][1])
  lineage_weights_artifact_id <- as.character(promoted$artifact_id[as.character(promoted$output) == "lineage_weights"][1])
  model_artifact_id <- as.character(promoted$artifact_id[as.character(promoted$output) == "model"][1])
  stopifnot(nzchar(pseudotime_artifact_id), nzchar(lineage_weights_artifact_id), nzchar(model_artifact_id))

  loaded_weights <- wb_art_load(b, lineage_weights_artifact_id, expected_kind = "cell_vector_family")
  stopifnot(identical(as.character(loaded_weights$kind), "cell_vector_family"))
  stopifnot(identical(sort(unique(as.character(loaded_weights$key))), pt_keys))
  lw_explicit <- wb_trajectory_lineage_weights(b, lineage_weights_artifact = lineage_weights_artifact_id)
  stopifnot(identical(as.character(lw_explicit$meta$artifact_id), lineage_weights_artifact_id))
  lw_from_pt <- wb_trajectory_lineage_weights(b, pseudotime_artifact = pseudotime_artifact_id)
  stopifnot(identical(as.character(lw_from_pt$meta$artifact_id), lineage_weights_artifact_id))
  lw_from_model <- wb_trajectory_lineage_weights(b, model_ref = model_artifact_id)
  stopifnot(identical(as.character(lw_from_model$meta$artifact_id), lineage_weights_artifact_id))

  l1 <- wb_read_cell_vector_family(
    b,
    vector_id = paste0("artifact:", lineage_weights_artifact_id),
    key = "L1",
    cell_ids = wb_cells(b, cell_set = "all")
  )
  l1_num <- suppressWarnings(as.numeric(l1))
  finite_l1 <- l1_num[is.finite(l1_num)]
  stopifnot(length(finite_l1) > 0L)
  l1_min <- as.numeric(stats::quantile(finite_l1, probs = 0.5, names = FALSE, na.rm = TRUE))
  l1_cells <- wb_sel_all(b, "all") |>
    wb_sel_vector_family(
      vector_id = paste0("artifact:", lineage_weights_artifact_id),
      key = "L1",
      min = l1_min
    )
  stopifnot(length(l1_cells) > 0L)
  derived <- wb_cell_set_derive(
    bundle = b,
    cell_set = "set:test_slingshot_l1_weight_universe",
    cells = l1_cells,
    role = "analysis_universe",
    status = "candidate",
    created_by = "test",
    description = "Derived from promoted Slingshot L1 lineage weights"
  )
  manifest <- derived$outputs$manifest$table
  stopifnot(nrow(manifest) == 1L)
  stopifnot(isTRUE(manifest$recipe_available[1]))
  stopifnot(identical(as.character(manifest$derivation_type[1]), "selector_recipe"))

  x3 <- wb_session_run_op(
    session = s,
    bundle = b,
    op_name = "slingshot_project",
    inputs = list(
      cell_set = cell_set,
      cell_ids = cell_ids,
      model = wb_ref_run(x2$run$run_id, "model"),
      plot_space = wb_prim_space_2d("umap.peakvi_space")
    ),
    notes = "test slingshot fit/project: project to umap"
  )

  stopifnot("curves" %in% names(x3$run$outputs))
  cv <- x3$run$outputs$curves
  stopifnot(identical(cv$kind, "path_2d_family"))
  stopifnot(length(cv$point) > 0)
  stopifnot(length(unique(as.character(cv$key))) >= 1)
  tab_cv <- table(as.character(cv$key))
  stopifnot(all(as.integer(tab_cv) <= 200L))

  # Provenance params should make fit/display distinction explicit in the new ops.
  stopifnot(identical(as.character(x2$run$params$fit_space_id), "peakvi_space"))
  stopifnot(identical(as.character(x3$run$params$plot_space_id), "umap.peakvi_space"))
  stopifnot(identical(as.integer(x3$run$params$approx_points), 200L))

  TRUE
}
