test_op_cell_vector_winners_contract <- function() {
  iface <- wb_op_interface("cell_vector_winners")
  stopifnot(is.list(iface))
  stopifnot(identical(as.character(iface$op_name), "cell_vector_winners"))
  stopifnot(identical(as.character(iface$produces$winners$kind), "obs_table"))
  stopifnot("cell_vector_winners" %in% wb_list_ops())
  stopifnot("winner_cell_sets" %in% wb_list_ops())

  tmp <- tempfile("scwb_cell_vector_winners_")
  b <- wb_init_bundle(tmp, overwrite = TRUE)
  on.exit({
    try(wb_close_bundle(b), silent = TRUE)
    unlink(tmp, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  cells <- paste0("c", 1:5)
  wb_define_cells(b, cells)

  sig <- wb_prim_cell_vector_family(
    key = rep(c("A", "B", "C"), each = length(cells)),
    cell_id = rep(cells, times = 3L),
    value = c(
      0.9, 0.8, 0.1, 0.6, 0.4,
      0.2, 0.7, 0.9, 0.6, 0.5,
      0.1, 0.1, 0.3, 0.2, 0.5
    ),
    value_type = "continuous"
  )

  raw <- wb_op_cell_vector_winners(
    signal = sig,
    min_winners = 2L,
    tie_method = "first",
    source_score_artifact_id = "cell_vector_family_source"
  )
  stopifnot(is.list(raw), is.list(raw$outputs))
  win <- raw$outputs$winners
  stopifnot(inherits(win, "wb_primitive"), identical(as.character(win$kind), "obs_table"))
  stopifnot(identical(as.character(win$table_type), "cell_vector_winners"))
  stopifnot(identical(as.character(win$entity_kind), "cell"))
  expect_cols <- c(
    "cell_id", "winner", "winner_score", "runner_up", "runner_up_score",
    "margin", "winner_percentile", "confidence_score",
    "confidence_rank_low", "confidence_rank_high", "passes_pruning",
    "pruning_status", "pruned_winner", "pruned_cell_set"
  )
  stopifnot(all(expect_cols %in% colnames(win$table)))

  wt <- win$table
  rownames(wt) <- wt$cell_id
  stopifnot(identical(as.character(wt["c1", "winner"]), "A"))
  stopifnot(identical(as.character(wt["c3", "winner"]), "B"))
  stopifnot(identical(as.character(wt["c4", "winner"]), "A"))
  stopifnot(identical(as.character(wt["c5", "winner"]), "B"))
  stopifnot(isTRUE(wt["c4", "passes_pruning"]))
  stopifnot(isTRUE(wt["c5", "passes_pruning"]))
  stopifnot(identical(as.character(win$meta$source_score_artifact_id), "cell_vector_family_source"))

  raw_pruned <- wb_op_cell_vector_winners(
    signal = sig,
    min_winners = 3L,
    tie_method = "first"
  )
  pruned_tbl <- raw_pruned$outputs$winners$table
  stopifnot(any(!pruned_tbl$passes_pruning))
  stopifnot(!any(is.na(pruned_tbl$pruned_winner)))
  stopifnot(!any(is.na(pruned_tbl$pruned_cell_set)))

  s <- wb_session_new()
  r1 <- wb_session_run_op(
    session = s,
    bundle = b,
    op_name = "cell_vector_winners",
    inputs = list(
      signal = sig,
      cell_set = "all",
      min_cells = 1L,
      min_winners = 2L,
      source_score_artifact_id = "cell_vector_family_source"
    )
  )
  s <- r1$session
  prom1 <- wb_session_promote_current(
    bundle = b,
    session = s,
    name_prefix = "Winner Productization",
    fail_fast = TRUE
  )
  winner_artifact_id <- as.character(prom1$promoted$artifact_id[
    as.character(prom1$promoted$output) == "winners"
  ][1])
  stopifnot(nzchar(winner_artifact_id))
  loaded_win <- wb_art_load(b, winner_artifact_id, expected_kind = "obs_table")
  stopifnot(identical(as.character(loaded_win$table_type), "cell_vector_winners"))

  r2 <- wb_session_run_op(
    session = s,
    bundle = b,
    op_name = "winner_cell_sets",
    inputs = list(
      winners = wb_ref_artifact(winner_artifact_id, "winners"),
      cell_set = "all",
      min_cells = 1L,
      source_winner_artifact_id = winner_artifact_id,
      created_by = "test"
    )
  )
  s <- r2$session
  manifest <- r2$run$outputs$manifest
  stopifnot(inherits(manifest, "wb_primitive"), identical(as.character(manifest$table_type), "winner_cell_set_manifest"))
  stopifnot(all(c("cell_set", "winner", "n_cells", "selection_rule", "source_winner_artifact_id", "source_score_artifact_id") %in% colnames(manifest$table)))
  stopifnot(all(as.character(manifest$table$cell_set) %in% wb_cell_sets(b)))
  stopifnot(length(wb_cells(b, cell_set = "set:winner_A")) == 3L)
  stopifnot(length(wb_cells(b, cell_set = "set:winner_B")) == 2L)

  prom2 <- wb_session_promote_current(
    bundle = b,
    session = s,
    name_prefix = "Winner Cell Sets",
    fail_fast = TRUE
  )
  manifest_artifact_id <- as.character(prom2$promoted$artifact_id[
    as.character(prom2$promoted$output) == "manifest"
  ][1])
  stopifnot(nzchar(manifest_artifact_id))
  loaded_manifest <- wb_art_load(b, manifest_artifact_id, expected_kind = "obs_table")
  stopifnot(identical(as.character(loaded_manifest$table_type), "winner_cell_set_manifest"))

  TRUE
}
