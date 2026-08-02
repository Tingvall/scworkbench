test_chunked_provenance_replay_contract <- function() {
  if (!requireNamespace("UCell", quietly = TRUE)) {
    return(contract_test_skip("UCell is not installed."))
  }

  tmp <- tempfile("scwb_chunked_prov_")
  b <- wb_init_bundle(tmp, overwrite = TRUE)
  on.exit(wb_close_bundle(b), add = TRUE)

  cells <- paste0("c", seq_len(6))
  wb_define_cells(b, cells)

  mat <- Matrix::Matrix(
    matrix(
      c(
        8, 7, 0, 0, 1, 0,
        7, 6, 0, 0, 1, 0,
        0, 1, 8, 7, 0, 0,
        0, 1, 7, 6, 0, 0,
        0, 0, 0, 0, 8, 7,
        0, 0, 0, 0, 7, 6
      ),
      nrow = 6,
      byrow = TRUE,
      dimnames = list(c("g1", "g2", "g3", "g4", "g5", "g6"), cells)
    ),
    sparse = TRUE
  )
  wb_attach_matrix(b, matrix_id = "RNA_counts", mat = mat, feature_type = "gene")

  sigs <- list(
    sig_a = c("g1", "g2"),
    sig_b = c("g3", "g4"),
    sig_c = c("g5", "g6")
  )

  s <- wb_session_new()
  rr <- wb_session_run_op(
    session = s,
    bundle = b,
    op_name = "ucell",
    inputs = list(
      matrix = "RNA_counts",
      cell_set = "all",
      min_cells = 1L,
      features = sigs,
      chunk_size = 2L,
      ncores = 1L,
      parallel_backend = "serial",
      max_rank = 100L,
      missing_features_policy = "drop"
    ),
    notes = "test chunked provenance ucell"
  )
  s <- rr$session

  stopifnot(is.list(rr$run$params$chunking))
  stopifnot(isTRUE(rr$run$params$chunking$enabled))

  prom <- wb_promote_analysis(
    bundle = b,
    runs = s$runs,
    head_run_id = s$head_run_id,
    name_prefix = "chunked_prov_ucell",
    created_by = "test",
    fail_fast = TRUE
  )

  sid <- as.character(prom$provenance_snapshot_id %||% "")[1]
  stopifnot(nzchar(sid))

  det <- wb_prov_run_details(b, run_id = rr$run$run_id, snapshot_id = sid)
  stopifnot(is.list(det), is.list(det$run))
  stopifnot(is.list(det$run$params$chunking))
  stopifnot(isTRUE(det$run$params$chunking$enabled))
  stopifnot(identical(as.character(det$run$params$chunking$axis), "cells"))
  stopifnot(identical(as.integer(det$run$params$chunking$chunk_size), 2L))
  stopifnot(identical(as.character(det$run$params$parallel_backend), "serial"))

  replay <- wb_prov_emit_r_script(
    b,
    snapshot_id = sid,
    bundle_dir_literal = "/tmp/replay_bundle",
    mode = "symbolic",
    style = "bench_pretty"
  )
  stopifnot(is.character(replay), length(replay) == 1L)
  stopifnot(grepl("chunk_size", replay, fixed = TRUE))
  stopifnot(grepl("parallel_backend", replay, fixed = TRUE))
  stopifnot(grepl("serial", replay, fixed = TRUE))

  val <- wb_prov_validate_replay(
    b,
    snapshot_id = sid,
    mode = "symbolic",
    strict = FALSE
  )
  stopifnot(is.list(val), is.list(val$summary))
  stopifnot(is.numeric(val$summary$n_runs), val$summary$n_runs >= 1)
  stopifnot(is.data.frame(val$per_run), nrow(val$per_run) >= 1)
  stopifnot(any(as.character(val$per_run$op_name) == "ucell"))

  TRUE
}
