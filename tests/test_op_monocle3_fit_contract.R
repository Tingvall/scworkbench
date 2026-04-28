test_op_monocle3_fit_contract <- function(bundle_dir) {
  if (!requireNamespace("monocle3", quietly = TRUE)) {
    message("Skipping monocle3 contract test: monocle3 not installed.")
    return(TRUE)
  }

  b <- wb_open_bundle(bundle_dir)
  on.exit(wb_close_bundle(b), add = TRUE)

  cells <- tryCatch(wb_cells(b, cell_set = "core"), error = function(e) character(0))
  stopifnot(length(cells) >= 300)
  cells <- as.character(head(cells, 600))
  root_cells <- as.character(head(cells, 20))

  iface <- wb_op_interface("monocle3_fit", bundle = b)
  stopifnot(is.list(iface))
  stopifnot(identical(as.character(iface$produces$pseudotime$kind), "cell_vector"))
  stopifnot(identical(as.character(iface$produces$branch_membership$kind), "relation_family"))
  stopifnot(identical(as.character(iface$produces$model$kind), "model_ref"))

  s <- wb_session_new()
  rr <- wb_session_run_op(
    session = s,
    bundle = b,
    op_name = "monocle3_fit",
    inputs = list(
      cell_set = "all",
      cell_ids = cells,
      fit_space = wb_prim_space("peakvi_space"),
      dims = as.character(1:20),
      root_cells = root_cells,
      k = 20,
      cluster_method = "leiden",
      num_iter = 2,
      partition_qval = 0.05,
      use_partition = FALSE,
      close_loop = FALSE
    ),
    notes = "contract test monocle3_fit"
  )

  run <- rr$run
  stopifnot(wb_is_run(run))
  stopifnot(identical(as.character(run$op_name), "monocle3_fit"))

  pt <- run$outputs$pseudotime
  bm <- run$outputs$branch_membership
  mr <- run$outputs$model

  stopifnot(inherits(pt, "wb_primitive"), identical(as.character(pt$kind), "cell_vector"))
  stopifnot(inherits(bm, "wb_primitive"), identical(as.character(bm$kind), "relation_family"))
  stopifnot(inherits(mr, "wb_primitive"), identical(as.character(mr$kind), "model_ref"))
  stopifnot(identical(as.character(mr$engine), "monocle3"))

  stopifnot(length(pt$cell_id) == length(cells))
  stopifnot(setequal(as.character(pt$cell_id), cells))

  bm_tbl <- wb_primitive_to_table(bm, include_context = TRUE)
  stopifnot(is.data.frame(bm_tbl), nrow(bm_tbl) > 0)
  stopifnot(all(c("key", "cell_id", "weight", "kind") %in% names(bm_tbl)))
  stopifnot(all(as.character(bm_tbl$kind) == "relation_family"))
  stopifnot(all(grepl("^root:[^:]+::lineage:[^:]+$", as.character(bm_tbl$key))))
  stopifnot(all(as.numeric(bm_tbl$weight) %in% c(1)))

  # Root cells should participate in at least one lineage relation and have pseudotime values.
  stopifnot(any(as.character(bm_tbl$cell_id) %in% root_cells))
  ptv <- setNames(as.numeric(pt$value), as.character(pt$cell_id))
  stopifnot(all(!is.na(ptv[root_cells])))

  # Family helper interoperability for relation_family keys.
  rf_keys <- wb_family_keys(b, bm)
  stopifnot(is.data.frame(rf_keys), nrow(rf_keys) >= 1L)
  stopifnot(all(as.character(rf_keys$kind) == "relation_family"))
  parsed_keys <- wb_relation_key_parse_lineage(as.character(rf_keys$key))
  stopifnot(is.data.frame(parsed_keys), nrow(parsed_keys) == nrow(rf_keys))
  stopifnot(all(parsed_keys$ok))
  stopifnot(length(unique(stats::na.omit(parsed_keys$root_id))) >= 1L)
  stopifnot(all(nzchar(as.character(parsed_keys$lineage_leaf_id))))
  stopifnot(length(as.character(run$params$root_pr_nodes %||% character(0))) >= 1L)

  # Promotion/load roundtrip for relation_family (new primitive artifact path).
  prom <- wb_promote_analysis(
    bundle = b,
    runs = rr$session$runs,
    head_run_id = rr$session$head_run_id,
    name_prefix = "monocle3_fit_contract",
    created_by = "test",
    fail_fast = TRUE
  )
  ok_bm <- prom$promoted[
    as.character(prom$promoted$status %||% "") == "ok" &
      as.character(prom$promoted$output %||% "") == "branch_membership",
    ,
    drop = FALSE
  ]
  stopifnot(nrow(ok_bm) == 1L)
  bm_art_id <- as.character(ok_bm$artifact_id[1])
  bm2 <- wb_art_load(b, bm_art_id, expected_kind = "relation_family")
  stopifnot(inherits(bm2, "wb_primitive"), identical(as.character(bm2$kind), "relation_family"))
  bm2_tbl <- wb_primitive_to_table(bm2, include_context = FALSE)
  stopifnot(is.data.frame(bm2_tbl), nrow(bm2_tbl) == nrow(bm_tbl))
  stopifnot(setequal(
    paste(as.character(bm_tbl$key), as.character(bm_tbl$cell_id), as.numeric(bm_tbl$weight)),
    paste(as.character(bm2_tbl$key), as.character(bm2_tbl$cell_id), as.numeric(bm2_tbl$weight))
  ))

  TRUE
}
