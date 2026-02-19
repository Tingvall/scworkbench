test_op_knn_neighbors_contract <- function(bundle_dir) {
  b <- wb_open_bundle(bundle_dir)
  on.exit(wb_close_bundle(b), add = TRUE)

  ops <- wb_list_ops()
  stopifnot("knn_neighbors" %in% ops)

  spec <- wb_op_interface("knn_neighbors", bundle = b)
  stopifnot(is.list(spec))
  stopifnot(identical(as.character(spec$op_name), "knn_neighbors"))
  prods <- spec$produces
  if (is.null(prods)) prods <- list()
  stopifnot("neighbors" %in% names(prods))
  stopifnot("neighbor_distance" %in% names(prods))

  sp <- wb_spaces(b)
  if (!is.data.frame(sp) || nrow(sp) < 1) return(TRUE)

  sid <- as.character(sp$space_id[1])
  cells <- wb_cells(b, cell_set = "all")
  if (length(cells) < 3) return(TRUE)

  q <- cells[1]
  candidates <- cells[2:min(40, length(cells))]

  raw <- wb_op_knn_neighbors(
    bundle = b,
    space_id = sid,
    query_cells = q,
    candidate_cells = candidates,
    k = min(10L, length(candidates)),
    include_query = FALSE
  )
  stopifnot(is.list(raw), is.list(raw$outputs), is.list(raw$params))
  stopifnot("neighbors" %in% names(raw$outputs))
  stopifnot("neighbor_distance" %in% names(raw$outputs))
  stopifnot(identical(as.character(raw$outputs$neighbors$kind), "obs_table"))
  stopifnot(identical(as.character(raw$outputs$neighbor_distance$kind), "cell_vector_family"))

  sess <- wb_session_new()
  run <- wb_session_run_op(
    session = sess,
    bundle = b,
    op_name = "knn_neighbors",
    inputs = list(
      space_id = sid,
      query_cells = q,
      candidate_cells = candidates,
      k = min(10L, length(candidates)),
      include_query = FALSE,
      cell_set = "all"
    )
  )
  stopifnot(is.list(run), wb_is_session(run$session), wb_is_run(run$run))
  stopifnot("neighbors" %in% names(run$run$outputs))
  stopifnot("neighbor_distance" %in% names(run$run$outputs))

  # Regression: canonical set token ("core") must resolve as set, not literal cell_id.
  run2 <- wb_session_run_op(
    session = run$session,
    bundle = b,
    op_name = "knn_neighbors",
    inputs = list(
      space_id = sid,
      query_cells = q,
      candidate_cells = "core",
      k = 5L,
      include_query = TRUE,
      cell_set = "all"
    )
  )
  stopifnot(is.list(run2), wb_is_session(run2$session), wb_is_run(run2$run))
  stopifnot("neighbors" %in% names(run2$run$outputs))
  stopifnot(nrow(run2$run$outputs$neighbors$table) >= 1)

  TRUE
}
