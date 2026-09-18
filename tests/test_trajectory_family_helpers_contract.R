test_trajectory_family_helpers_contract <- function(bundle_dir) {
  b <- wb_open_bundle(bundle_dir)
  on.exit(wb_close_bundle(b), add = TRUE)

  cells <- tryCatch(wb_cells(b, cell_set = "set:usecase1_btraj_early"), error = function(e) character(0))
  if (length(cells) < 200) cells <- wb_cells(b, cell_set = "core")
  stopifnot(length(cells) >= 100)
  cell_ids <- as.character(head(cells, 500))

  s <- wb_session_new()

  r1 <- contract_test_add_core_metadata_labels(
    session = s, bundle = b, cells = cell_ids,
    notes = "trajectory family helper test: synthetic seed clusters"
  )
  s <- r1$session

  r2 <- wb_session_run_op(
    session = s,
    bundle = b,
    op_name = "slingshot_fit",
    inputs = list(
      cell_set = "all",
      cell_ids = cell_ids,
      fit_space = wb_prim_space("peakvi_space"),
      clusters = wb_ref_run(r1$run$run_id, "vector")
    ),
    notes = "trajectory family helper test: slingshot_fit"
  )
  s <- r2$session

  r3 <- wb_session_run_op(
    session = s,
    bundle = b,
    op_name = "slingshot_project",
    inputs = list(
      cell_set = "all",
      cell_ids = cell_ids,
      model = wb_ref_run(r2$run$run_id, "model"),
      plot_space = wb_prim_space_2d("umap.peakvi_space")
    ),
    notes = "trajectory family helper test: slingshot_project"
  )
  s <- r3$session

  pt_ref <- wb_ref_run(r2$run$run_id, "pseudotime")
  cv_ref <- wb_ref_run(r3$run$run_id, "curves")

  pt_keys <- wb_family_keys(b, pt_ref, runs = s$runs)
  cv_keys <- wb_family_keys(b, cv_ref, runs = s$runs)
  tk <- wb_trajectory_keys(b, pt_ref, cv_ref, runs = s$runs)

  stopifnot(is.data.frame(pt_keys), is.data.frame(cv_keys))
  stopifnot(all(c("key", "n", "kind") %in% names(pt_keys)))
  stopifnot(all(c("key", "n", "kind") %in% names(cv_keys)))
  stopifnot(nrow(pt_keys) >= 1, nrow(cv_keys) >= 1)
  stopifnot(all(pt_keys$kind == "cell_vector_family"))
  stopifnot(all(cv_keys$kind == "path_2d_family"))
  stopifnot(is.data.frame(tk))
  stopifnot(all(c("lineage_id", "shared", "n_pseudotime_cells", "n_curve_points") %in% names(tk)))
  stopifnot(any(tk$shared))
  stopifnot(setequal(tk$lineage_id[tk$shared], intersect(pt_keys$key, cv_keys$key)))

  # Primitive pass-through should also work (same summaries).
  tk2 <- wb_trajectory_keys(b, r2$run$outputs$pseudotime, r3$run$outputs$curves)
  stopifnot(setequal(tk2$lineage_id[tk2$shared], tk$lineage_id[tk$shared]))

  # Generic family helper should support weighted cell-family primitives too.
  rf <- wb_prim_relation_family(
    key = c("L1", "L2", "L2"),
    cell_id = c(cell_ids[1], cell_ids[1], cell_ids[2]),
    weight = c(0.7, 0.3, 1.0)
  )
  rf_keys <- wb_family_keys(b, rf)
  stopifnot(is.data.frame(rf_keys), nrow(rf_keys) == 2L)
  stopifnot(all(rf_keys$kind == "relation_family"))
  stopifnot(setequal(as.character(rf_keys$key), c("L1", "L2")))

  spf <- wb_prim_space_path_family(
    space_id = c("peakvi_space", "peakvi_space", "peakvi_space", "peakvi_space"),
    path_id = c("P1", "P1", "P2", "P2"),
    point = c(1L, 2L, 1L, 2L),
    dim = c(1L, 1L, 1L, 1L),
    value = c(0, 1, 0, 1)
  )
  spf_keys <- wb_family_keys(b, spf)
  stopifnot(is.data.frame(spf_keys), nrow(spf_keys) == 2L)
  stopifnot(all(spf_keys$kind == "space_path_family"))
  stopifnot(setequal(as.character(spf_keys$key), c("P1", "P2")))

  parsed_demo <- wb_relation_key_parse_lineage(c("root:Y_1::lineage:Y_10", "bad_key"))
  stopifnot(is.data.frame(parsed_demo), nrow(parsed_demo) == 2L)
  stopifnot(isTRUE(parsed_demo$ok[1]), !isTRUE(parsed_demo$ok[2]))
  stopifnot(identical(as.character(parsed_demo$root_id[1]), "Y_1"))
  stopifnot(identical(as.character(parsed_demo$lineage_leaf_id[1]), "Y_10"))

  # Canonical artifact/run-binding plot-space lookup for trajectory curves.
  cv_space_session <- wb_path_2d_family_space_id(b, cv_ref, runs = s$runs)
  stopifnot(identical(as.character(cv_space_session), "umap.peakvi_space"))

  prom <- wb_promote_analysis(
    bundle = b,
    runs = s$runs,
    head_run_id = s$head_run_id,
    name_prefix = "traj_space_lookup",
    created_by = "test",
    fail_fast = TRUE
  )
  ok <- prom$promoted[
    as.character(prom$promoted$status %||% "") == "ok" &
      as.character(prom$promoted$output %||% "") == "curves",
    ,
    drop = FALSE
  ]
  stopifnot(nrow(ok) == 1L)
  cv_art <- wb_ref_artifact(as.character(ok$artifact_id[1]), "curves")
  cv_space_art <- wb_path_2d_family_space_id(b, cv_art, runs = s$runs)
  stopifnot(identical(as.character(cv_space_art), "umap.peakvi_space"))

  TRUE
}
