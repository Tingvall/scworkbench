test_space_path_promotion_contract <- function() {
  tmp <- file.path(tempdir(), paste0("scwb_space_path_", as.integer(Sys.time())))
  b <- wb_init_bundle(tmp, overwrite = TRUE)
  on.exit(try(wb_close_bundle(b), silent = TRUE), add = TRUE)
  cells <- c("cell_1", "cell_2", "cell_3")
  wb_define_cells(b, cells)
  wb_attach_space(
    b, "peakvi_space",
    data.frame(cell_id = cells, x = c(0, 1, 2), y = c(0, 1, 1.5), stringsAsFactors = FALSE)
  )

  prim <- wb_prim_space_path_family(
    space_id = rep("peakvi_space", 6),
    path_id = rep("P1", 6),
    point = c(1L, 1L, 2L, 2L, 3L, 3L),
    dim = c(1L, 2L, 1L, 2L, 1L, 2L),
    value = c(0, 0, 1, 1, 2, 1.5),
    meta = list(
      fit_mode = "linear",
      anchor_label = c("A", "B", "C"),
      anchor_order = c(1L, 2L, 3L),
      anchor_cell_set = c("set:A", "set:B", "set:C"),
      anchor_n_cells = c(10L, 12L, 8L),
      anchor_summary = "centroid"
    )
  )

  run <- wb_new_run(
    op_name = "space_path_define",
    inputs = list(
      cell_set = "all",
      parents = character(0),
      provenance_refs = list(),
      user_inputs = list(space_id = "peakvi_space")
    ),
    params = list(space_id = "peakvi_space"),
    outputs = list(path = prim),
    notes = "space_path promotion/load test"
  )

  s <- wb_session_new()
  s <- wb_session_add_run(s, run)
  s$head_run_id <- run$run_id

  prom <- wb_promote_analysis(
    bundle = b,
    runs = s$runs,
    head_run_id = run$run_id,
    name_prefix = "space_path_contract",
    created_by = "test",
    fail_fast = TRUE
  )
  ok <- prom$promoted[
    as.character(prom$promoted$status %||% "") == "ok" &
      as.character(prom$promoted$output %||% "") == "path",
    ,
    drop = FALSE
  ]
  stopifnot(nrow(ok) == 1L)

  aid <- as.character(ok$artifact_id[1])
  p2 <- wb_art_load(b, aid, expected_kind = "space_path_family")
  stopifnot(inherits(p2, "wb_primitive"), identical(as.character(p2$kind), "space_path_family"))
  stopifnot(identical(as.character(unique(p2$space_id)), "peakvi_space"))
  stopifnot(identical(as.character(unique(p2$path_id)), "P1"))
  stopifnot(length(p2$point) == 6L, length(p2$dim) == 6L, length(p2$value) == 6L)
  stopifnot(identical(as.character(p2$meta$fit_mode), "linear"))
  stopifnot(identical(as.character(p2$meta$anchor_summary), "centroid"))
  stopifnot(identical(as.character(p2$meta$anchor_cell_set), c("set:A", "set:B", "set:C")))

  tbl <- wb_client_load_table(
    bundle = b,
    ref = wb_ref_artifact(aid, "path"),
    include_context = TRUE
  )
  stopifnot(is.data.frame(tbl), nrow(tbl) == 6L)
  stopifnot(all(c("space_id", "path_id", "point", "dim", "value", "kind") %in% names(tbl)))

  TRUE
}
