test_strict_replay_inputs_contract <- function() {
  contract_test_activate_statistics_pack()
  same <- scworkbench:::.wb_prov_replay_execution_inputs(
    list(alpha = 1L, nested = list(ref = wb_ref_run("old_run", "vector"))),
    list(alpha = 1L, beta = c("x", "y"), nil = NULL),
    run_id = "same"
  )
  stopifnot(identical(same$alpha, 1L), identical(same$beta, c("x", "y")),
            is.null(same$nil), identical(same$nested$ref$ref_type, "run"))
  conflict <- try(
    scworkbench:::.wb_prov_replay_execution_inputs(list(alpha = 1L), list(alpha = 2L), run_id = "conflict"),
    silent = TRUE
  )
  stopifnot(inherits(conflict, "try-error"), grepl("collision", as.character(conflict), ignore.case = TRUE))
  legacy_method <- scworkbench:::.wb_prov_replay_execution_inputs(
    list(method = "auto"), list(method = "fisher_exact"),
    run_id = "legacy-association", op_name = "cell_vector_association"
  )
  stopifnot(identical(legacy_method$method, "auto"))
  raw_inputs <- list(flag = TRUE, count = 2L, ratio = 0.5, values = c("x", "y"), nil = NULL,
                     nested = list(ref = wb_ref_run("old_run", "vector")))
  raw_roundtrip <- jsonlite::fromJSON(
    jsonlite::toJSON(raw_inputs, auto_unbox = TRUE, null = "null"),
    simplifyVector = TRUE, simplifyDataFrame = FALSE
  )
  stopifnot(identical(raw_roundtrip$flag, TRUE), identical(raw_roundtrip$count, 2L),
            identical(raw_roundtrip$ratio, 0.5), identical(raw_roundtrip$values, c("x", "y")),
            is.null(raw_roundtrip$nil), identical(raw_roundtrip$nested$ref$ref_type, "run"))

  root <- tempfile("scwb_strict_replay_source_")
  clone_parent <- tempfile("scwb_strict_replay_clone_")
  clone <- file.path(clone_parent, basename(root))
  b <- wb_init_bundle(root, overwrite = TRUE)
  on.exit({
    try(wb_close_bundle(b), silent = TRUE)
    unlink(root, recursive = TRUE, force = TRUE)
    unlink(clone_parent, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  ids <- paste0("c", seq_len(8L))
  metadata <- data.frame(
    cell_id = ids,
    perturbation = rep(c("ctrl", "drug"), each = 4L),
    lane = rep(c("L1", "L2"), times = 4L),
    stringsAsFactors = FALSE
  )
  wb_define_cells(b, ids, metadata = metadata, set_name = "core")
  sess <- wb_session_new()
  perturbation <- wb_session_run_op(
    sess, b, "metadata_cell_vector",
    inputs = list(source_column = "perturbation", vector_name = "perturbation",
                  value_type = "categorical", missing_policy = "error",
                  cell_set = "all", min_cells = 1L, overwrite = TRUE)
  )
  sess <- perturbation$session
  lane <- wb_session_run_op(
    sess, b, "metadata_cell_vector",
    inputs = list(source_column = "lane", vector_name = "lane",
                  value_type = "categorical", missing_policy = "error",
                  cell_set = "all", min_cells = 1L, overwrite = TRUE)
  )
  sess <- lane$session
  association <- wb_session_run_op(
    sess, b, "cell_vector_association",
    inputs = list(
      a = wb_ref_run(perturbation$run$run_id, "vector"),
      b = wb_ref_run(lane$run$run_id, "vector"),
      cell_set = "all", min_cells = 1L, min_n_per_group = 1L, method = "auto"
    )
  )
  sess <- association$session

  promoted <- wb_session_promote_current(
    b, sess, created_by = "strict-replay-contract",
    outputs = list(
      wb_ref_run(perturbation$run$run_id, "vector"),
      wb_ref_run(lane$run$run_id, "vector"),
      wb_ref_run(association$run$run_id, "summary"),
      wb_ref_run(association$run$run_id, "detail")
    )
  )
  stopifnot(all(promoted$promoted$status == "ok"))
  sid <- as.character(promoted$provenance_snapshot_id)[1]
  stopifnot(nzchar(sid))

  wb_close_bundle(b)
  b <- NULL
  dir.create(clone_parent)
  stopifnot(file.copy(root, clone_parent, recursive = TRUE))
  b <- wb_open_bundle(clone)
  expected <- list(perturbation$run$params, lane$run$params, association$run$params)
  names(expected) <- c(perturbation$run$run_id, lane$run$run_id, association$run$run_id)

  for (mode in c("symbolic", "literal")) {
    for (style in c("bench_pretty", "raw_json")) {
      sidecar <- tempfile(paste0("scwb_replay_", mode, "_"), fileext = ".rds")
      replay <- wb_prov_emit_r_script(
        b, snapshot_id = sid, bundle_dir_literal = clone, mode = mode,
        sidecar_rds_path = sidecar, style = style
      )
      stopifnot(!grepl("wb_session_run_op[^\\n]*params\\s*=", replay, perl = TRUE))
      stopifnot(grepl("inputs = execution_inputs", replay, fixed = TRUE))
      stopifnot(grepl("rewrite_run_refs\\(execution_inputs", replay))
      if (identical(mode, "literal")) stopifnot(file.exists(sidecar))

      wrapper <- tempfile("scwb_replay_wrapper_", fileext = ".R")
      writeLines(c(
        paste0("devtools::load_all(", shQuote(normalizePath(getwd())), ", quiet = TRUE)"),
        "wb_operation_pack_load('scwbStatistics')",
        replay
      ), wrapper)
      status <- system2(file.path(R.home("bin"), "Rscript"), wrapper)
      stopifnot(identical(status, 0L))
    }
  }

  for (mode in c("symbolic", "literal")) {
    validated <- wb_prov_validate_replay(b, snapshot_id = sid, mode = mode, profile = "strict", strict = TRUE)
    stopifnot(isTRUE(validated$summary$valid), all(validated$per_run$status == "ok"))
    replay_runs <- validated$replay_session$runs
    stopifnot(length(replay_runs) == 3L)
    for (old_id in names(expected)) {
      replay_id <- validated$per_run$replay_run_id[match(old_id, validated$per_run$run_id)]
      stopifnot(identical(replay_runs[[replay_id]]$params, expected[[old_id]]))
    }
    association_replay_id <- validated$per_run$replay_run_id[
      match(association$run$run_id, validated$per_run$run_id)
    ]
    association_inputs <- replay_runs[[association_replay_id]]$inputs$user_inputs
    stopifnot(identical(association_inputs$min_n_per_group, 1L),
              identical(association_inputs$method, "auto"),
              identical(association_inputs$a$ref_type, "run"),
              association_inputs$a$run_id != perturbation$run$run_id)
  }
  TRUE
}
