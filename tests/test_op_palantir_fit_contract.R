test_op_palantir_fit_contract <- function(bundle_dir,
                                          pybench_python = .wb_pybench_default_python()) {
  if (!file.exists(pybench_python)) {
    return(contract_test_skip(paste("Pybench interpreter not found at", pybench_python)))
  }

  b <- wb_open_bundle(bundle_dir)
  on.exit(wb_close_bundle(b), add = TRUE)

  cells <- tryCatch(wb_cells(b, cell_set = "core"), error = function(e) character(0))
  stopifnot(length(cells) >= 300L)
  cells <- as.character(head(cells, 800))
  root_cell <- as.character(cells[1])
  terminal_cells <- as.character(cells[c(2, 3)])

  iface <- wb_op_interface("palantir_fit", bundle = b)
  stopifnot(is.list(iface))
  stopifnot(identical(as.character(iface$produces$pseudotime$kind), "cell_vector"))
  stopifnot(identical(as.character(iface$produces$branch_membership$kind), "relation_family"))
  stopifnot(identical(as.character(iface$produces$branch_summary$kind), "obs_table"))
  stopifnot(identical(as.character(iface$produces$entropy$kind), "cell_vector"))
  stopifnot(identical(as.character(iface$produces$model$kind), "model_ref"))

  s <- wb_session_new()
  rr <- wb_session_run_op(
    session = s,
    bundle = b,
    op_name = "palantir_fit",
    inputs = list(
      cell_set = "all",
      cell_ids = cells,
      fit_space = wb_prim_space("peakvi_space"),
      root_cell = root_cell,
      terminal_cells = terminal_cells,
      dims = as.character(1:20),
      knn = 30L,
      n_diffusion_components = 10L,
      n_waypoints = 100L,
      seed = 20L
    ),
    notes = "contract test palantir_fit"
  )

  run <- rr$run
  stopifnot(wb_is_run(run))
  stopifnot(identical(as.character(run$op_name), "palantir_fit"))

  pt <- run$outputs$pseudotime
  bm <- run$outputs$branch_membership
  bs <- run$outputs$branch_summary
  en <- run$outputs$entropy
  mr <- run$outputs$model

  stopifnot(inherits(pt, "wb_primitive"), identical(as.character(pt$kind), "cell_vector"))
  stopifnot(inherits(bm, "wb_primitive"), identical(as.character(bm$kind), "relation_family"))
  stopifnot(inherits(bs, "wb_primitive"), identical(as.character(bs$kind), "obs_table"))
  stopifnot(inherits(en, "wb_primitive"), identical(as.character(en$kind), "cell_vector"))
  stopifnot(inherits(mr, "wb_primitive"), identical(as.character(mr$kind), "model_ref"))
  stopifnot(identical(as.character(mr$engine), "palantir"))

  stopifnot(length(pt$cell_id) == length(cells))
  stopifnot(setequal(as.character(pt$cell_id), cells))
  stopifnot(identical(as.character(pt$value_type), "continuous"))

  stopifnot(length(en$cell_id) == length(cells))
  stopifnot(setequal(as.character(en$cell_id), cells))
  stopifnot(identical(as.character(en$value_type), "continuous"))

  bm_tbl <- wb_primitive_to_table(bm, include_context = FALSE)
  stopifnot(is.data.frame(bm_tbl), nrow(bm_tbl) > 0L)
  stopifnot(all(c("key", "cell_id", "weight") %in% names(bm_tbl)))
  stopifnot(all(grepl("^branch:", as.character(bm_tbl$key))))
  stopifnot(all(is.finite(as.numeric(bm_tbl$weight))))
  stopifnot(all(as.numeric(bm_tbl$weight) >= 0))
  stopifnot(all(as.numeric(bm_tbl$weight) <= 1 + 1e-8))

  stopifnot(is.data.frame(bs$table), nrow(bs$table) >= 1L)
  stopifnot(all(c("relation_key", "branch", "n_cells_prob_gt_0", "mean_prob", "max_prob") %in% names(bs$table)))
  stopifnot(all(grepl("^branch:", as.character(bs$table$relation_key))))

  stopifnot(identical(as.character(run$params$space_id), "peakvi_space"))
  stopifnot(identical(as.character(run$params$root_cell), root_cell))
  stopifnot(setequal(as.character(run$params$terminal_cells %||% character(0)), terminal_cells))
  stopifnot(identical(as.character(run$params$branch_membership_key_prefix), "branch:"))
  stopifnot(is.list(run$params$pybench_runtime))

  prom <- wb_session_promote_current(
    bundle = b,
    session = rr$session,
    name_prefix = "palantir_fit_contract",
    created_by = "test",
    outputs = c("pseudotime", "branch_membership", "branch_summary", "entropy", "model"),
    fail_fast = TRUE
  )
  promoted_ok <- prom$promoted[as.character(prom$promoted$status %||% "") == "ok", , drop = FALSE]
  stopifnot(nrow(promoted_ok) >= 5L)

  get_art <- function(output_name) {
    x <- promoted_ok[as.character(promoted_ok$output %||% "") == output_name, , drop = FALSE]
    stopifnot(nrow(x) == 1L)
    as.character(x$artifact_id[1])
  }

  bm2 <- wb_art_load(b, get_art("branch_membership"), expected_kind = "relation_family")
  bs2 <- wb_art_load(b, get_art("branch_summary"), expected_kind = "obs_table")
  mr2 <- wb_art_load(b, get_art("model"), expected_kind = "model_ref")

  stopifnot(inherits(bm2, "wb_primitive"), identical(as.character(bm2$kind), "relation_family"))
  stopifnot(inherits(bs2, "wb_primitive"), identical(as.character(bs2$kind), "obs_table"))
  stopifnot(inherits(mr2, "wb_primitive"), identical(as.character(mr2$kind), "model_ref"))
  stopifnot(identical(as.character(mr2$engine), "palantir"))
  stopifnot(file.exists(as.character(mr2$model_path)))

  TRUE
}
