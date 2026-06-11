test_op_cell_vector_family_graph_smooth_contract <- function() {
  if (!requireNamespace("RANN", quietly = TRUE)) {
    message("Skipping cell_vector_family_graph_smooth contract test: RANN not installed.")
    return(TRUE)
  }

  iface <- wb_op_interface("cell_vector_family_graph_smooth")
  stopifnot(is.list(iface))
  stopifnot(identical(as.character(iface$op_name), "cell_vector_family_graph_smooth"))
  stopifnot(identical(as.character(iface$produces$smoothed_signal$kind), "cell_vector_family"))
  stopifnot(identical(as.character(iface$produces$smoothing_summary$kind), "obs_table"))
  stopifnot("cell_vector_family_graph_smooth" %in% wb_list_ops())

  tmp <- tempfile("scwb_cvf_graph_smooth_")
  b <- wb_init_bundle(tmp, overwrite = TRUE)
  on.exit({
    try(wb_close_bundle(b), silent = TRUE)
    unlink(tmp, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  cells <- paste0("c", 1:6)
  wb_define_cells(b, cells)
  coord_mat <- matrix(
    c(0, 0, 0, 1, 0, 0, 2, 0, 0, 10, 0, 0, 11, 0, 0, 12, 0, 0),
    ncol = 3L,
    byrow = TRUE,
    dimnames = list(cells, c("dim1", "dim2", "dim3"))
  )
  coords <- data.frame(
    cell_id = rep(cells, each = 3L),
    dim = rep(1:3, times = length(cells)),
    value = as.numeric(t(coord_mat)),
    stringsAsFactors = FALSE
  )
  wb_attach_space(
    b,
    space_id = "lsi",
    coords = coords,
    source = "test"
  )

  sig <- wb_prim_cell_vector_family(
    key = rep(c("A", "B"), each = length(cells)),
    cell_id = rep(cells, times = 2L),
    value = c(
      1, 1, 1, 10, 10, 10,
      10, 10, 10, 1, 1, 1
    ),
    value_type = "continuous"
  )

  raw <- wb_op_cell_vector_family_graph_smooth(
    bundle = b,
    signal = sig,
    space_id = "lsi",
    cells = cells,
    dims = 1:3,
    k = 2L,
    alpha = 0.5,
    query_chunk_size = 2L,
    include_self = FALSE,
    source_signal_artifact_id = "cell_vector_family_source"
  )
  stopifnot(is.list(raw), is.list(raw$outputs), is.list(raw$params))
  sm <- raw$outputs$smoothed_signal
  ss <- raw$outputs$smoothing_summary
  stopifnot(inherits(sm, "wb_primitive"), identical(as.character(sm$kind), "cell_vector_family"))
  stopifnot(inherits(ss, "wb_primitive"), identical(as.character(ss$kind), "obs_table"))
  stopifnot(identical(as.character(ss$table_type), "cell_vector_family_graph_smooth_summary"))
  stopifnot(identical(as.character(ss$entity_kind), "signal_key"))
  stopifnot(nrow(ss$table) == 2L)
  stopifnot(all(c("key", "n_cells", "raw_mean", "smoothed_mean", "avg_neighbor_count") %in% colnames(ss$table)))
  stopifnot(identical(as.character(ss$meta$source_signal_artifact_id), "cell_vector_family_source"))
  stopifnot(identical(as.character(ss$meta$source_space_id), "lsi"))

  smat <- .wb_cell_vector_family_score_matrix(sm)$matrix
  stopifnot(identical(rownames(smat), cells))
  stopifnot(identical(colnames(smat), c("A", "B")))
  stopifnot(all(is.finite(smat)))
  stopifnot(smat["c1", "A"] < 2)
  stopifnot(smat["c4", "A"] > 9)

  sess <- wb_session_new()
  r1 <- wb_session_run_op(
    session = sess,
    bundle = b,
    op_name = "cell_vector_family_graph_smooth",
    inputs = list(
      signal = sig,
      space_id = "lsi",
      cell_set = "all",
      min_cells = 1L,
      dims = 1:3,
      k = 2L,
      alpha = 0.5,
      query_chunk_size = 2L,
      include_self = FALSE
    )
  )
  stopifnot(is.list(r1), wb_is_session(r1$session), wb_is_run(r1$run))
  stopifnot("smoothed_signal" %in% names(r1$run$outputs))
  stopifnot("smoothing_summary" %in% names(r1$run$outputs))

  prom1 <- wb_session_promote_current(
    bundle = b,
    session = r1$session,
    name_prefix = "Graph Smooth Test",
    fail_fast = TRUE
  )
  smoothed_id <- as.character(prom1$promoted$artifact_id[
    as.character(prom1$promoted$output) == "smoothed_signal"
  ][1])
  summary_id <- as.character(prom1$promoted$artifact_id[
    as.character(prom1$promoted$output) == "smoothing_summary"
  ][1])
  stopifnot(nzchar(smoothed_id), nzchar(summary_id))
  loaded_sm <- wb_art_load(b, smoothed_id, expected_kind = "cell_vector_family")
  loaded_ss <- wb_art_load(b, summary_id, expected_kind = "obs_table")
  stopifnot(identical(as.character(loaded_sm$kind), "cell_vector_family"))
  stopifnot(identical(as.character(loaded_ss$table_type), "cell_vector_family_graph_smooth_summary"))

  r2 <- wb_session_run_op(
    session = r1$session,
    bundle = b,
    op_name = "cell_vector_winners",
    inputs = list(
      signal = wb_ref_artifact(smoothed_id, "smoothed_signal"),
      cell_set = "all",
      min_cells = 1L,
      min_winners = 1L,
      source_score_artifact_id = smoothed_id
    )
  )
  win <- r2$run$outputs$winners
  stopifnot(identical(as.character(win$table_type), "cell_vector_winners"))
  stopifnot(all(c("winner", "runner_up", "margin") %in% colnames(win$table)))

  TRUE
}
