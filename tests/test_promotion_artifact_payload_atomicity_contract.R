test_promotion_artifact_payload_atomicity_contract <- function() {
  root <- tempfile("scwb_promotion_artifact_payload_")
  b <- wb_init_bundle(root, overwrite = TRUE)
  on.exit({
    options(scworkbench.promotion_workspace_publish_hook = NULL)
    try(wb_close_bundle(b), silent = TRUE)
    unlink(root, recursive = TRUE, force = TRUE)
  }, add = TRUE)
  cells <- paste0("c", seq_len(3L))
  wb_define_cells(b, cells)

  make_model_run <- function(tag) {
    model <- wb_prim_model_ref(model_space_id = "synthetic", in_space_id = "synthetic", engine = "monocle3")
    model$model_obj <- list(tag = tag, payload = seq_len(3L))
    wb_new_run(
      op_name = "monocle3_fit",
      inputs = list(cell_set = "all", parents = character(0), user_inputs = list()),
      params = list(fit_space_id = "synthetic"), outputs = list(model = model)
    )
  }
  model_a <- make_model_run("a")
  model_b <- make_model_run("b")
  vector_run <- wb_new_run(
    op_name = "leiden",
    inputs = list(cell_set = "all", parents = character(0), user_inputs = list()),
    params = list(),
    outputs = list(clusters = wb_prim_cell_vector(stats::setNames(c("A", "B", "A"), cells)))
  )
  runs <- setNames(list(model_a, model_b, vector_run), c(model_a$run_id, model_b$run_id, vector_run$run_id))

  calls <- 0L
  options(scworkbench.promotion_workspace_publish_hook = function(workspace, final_rel) {
    calls <<- calls + 1L
    if (calls == 5L) stop("forced artifact payload publication failure", call. = FALSE)
  })
  failed <- try(wb_promote_analysis(
    b, runs, head_run_id = c(model_a$run_id, model_b$run_id, vector_run$run_id),
    outputs = c("model", "clusters")
  ), silent = TRUE)
  stopifnot(inherits(failed, "try-error"), calls >= 5L)
  stopifnot(DBI::dbGetQuery(b$con, "SELECT COUNT(*) AS n FROM artifacts;")$n[1] == 0L)
  stopifnot(DBI::dbGetQuery(b$con, "SELECT COUNT(*) AS n FROM artifact_model_ref;")$n[1] == 0L)
  stopifnot(DBI::dbGetQuery(b$con, "SELECT COUNT(*) AS n FROM prov_heads;")$n[1] == 0L)
  stopifnot(DBI::dbGetQuery(b$con, "SELECT COUNT(*) AS n FROM prov_commits;")$n[1] == 0L)
  artifact_dir <- file.path(root, "artifact_models")
  stopifnot(!dir.exists(artifact_dir) || !length(list.files(artifact_dir, all.files = FALSE, no.. = TRUE)))
  pending_root <- file.path(root, "provenance", ".pending")
  stopifnot(!dir.exists(pending_root) || !length(list.files(pending_root, all.files = FALSE, no.. = TRUE)))

  options(scworkbench.promotion_workspace_publish_hook = NULL)
  success <- wb_promote_analysis(
    b, setNames(list(model_a, vector_run), c(model_a$run_id, vector_run$run_id)),
    head_run_id = c(model_a$run_id, vector_run$run_id), outputs = c("model", "clusters")
  )
  model_artifact <- success$promoted[
    as.character(success$promoted$output) == "model" & as.character(success$promoted$status) == "ok",
    "artifact_id"
  ][1]
  row <- DBI::dbGetQuery(b$con, "SELECT model_path FROM artifact_model_ref WHERE artifact_id = ?;", params = list(model_artifact))
  stopifnot(nrow(row) == 1L, startsWith(as.character(row$model_path[1]), "artifact_models/"))
  stopifnot(file.exists(file.path(root, as.character(row$model_path[1]))))
  wb_close_bundle(b)
  b <- wb_open_bundle(root)
  loaded <- wb_art_load(b, as.character(model_artifact), expected_kind = "model_ref")
  stopifnot(identical(as.character(loaded$model_obj$tag), "a"))
  TRUE
}

test_promotion_staged_model_payload_contract <- function() {
  root <- tempfile("scwb_promotion_staged_model_")
  b <- wb_init_bundle(root, overwrite = TRUE)
  stage_session <- NULL
  on.exit({
    options(scworkbench.promotion_workspace_publish_hook = NULL)
    if (!is.null(stage_session)) try(wb_session_discard(stage_session), silent = TRUE)
    try(wb_close_bundle(b), silent = TRUE)
    unlink(root, recursive = TRUE, force = TRUE)
  }, add = TRUE)
  cells <- paste0("c", seq_len(3L))
  wb_define_cells(b, cells)

  make_staged_model <- function(tag) {
    staged <- .wb_session_stage_bundle(b, wb_session_new())
    stage_session <<- staged$session
    model_rel <- file.path("artifact_models", paste0("synthetic_", tag, "_scvi"))
    model_dir <- file.path(staged$bundle$dir, model_rel)
    dir.create(model_dir, recursive = TRUE, showWarnings = FALSE)
    writeLines(paste0("model=", tag), file.path(model_dir, "model.txt"), useBytes = TRUE)
    model <- wb_prim_model_ref(
      model_space_id = paste0("synthetic_", tag),
      in_space_id = paste0("synthetic_", tag),
      engine = "scvi"
    )
    model$model_type <- "scvi_train"
    model$model_path <- normalizePath(model_dir, winslash = "/", mustWork = TRUE)
    run <- wb_new_run(
      op_name = "scvi_train",
      inputs = list(cell_set = "all", parents = character(0), user_inputs = list()),
      params = list(output_space_id = paste0("synthetic_", tag)),
      outputs = list(model = model)
    )
    list(session = staged$session, bundle = staged$bundle, run = run, model_rel = model_rel)
  }

  success_case <- make_staged_model("success")
  promoted <- wb_promote_analysis(
    b,
    setNames(list(success_case$run), success_case$run$run_id),
    head_run_id = success_case$run$run_id,
    outputs = "model",
    staging_bundle = success_case$bundle
  )
  model_artifact <- as.character(promoted$promoted$artifact_id[
    as.character(promoted$promoted$output) == "model" &
      as.character(promoted$promoted$status) == "ok"
  ][1])
  stopifnot(nzchar(model_artifact))
  model_row <- DBI::dbGetQuery(
    b$con,
    "SELECT model_path FROM artifact_model_ref WHERE artifact_id = ?;",
    params = list(model_artifact)
  )
  stopifnot(nrow(model_row) == 1L)
  stopifnot(identical(as.character(model_row$model_path[1]), success_case$model_rel))
  stopifnot(file.exists(file.path(root, success_case$model_rel, "model.txt")))
  commit_id <- DBI::dbGetQuery(
    b$con,
    "SELECT commit_id FROM prov_heads WHERE snapshot_id = ?;",
    params = list(promoted$provenance_snapshot_id)
  )$commit_id[1]
  mat_row <- DBI::dbGetQuery(
    b$con,
    "SELECT path FROM prov_materializations WHERE commit_id = ? AND run_id = ? AND output_name = 'model';",
    params = list(commit_id, success_case$run$run_id)
  )
  stopifnot(nrow(mat_row) == 1L)
  materialized_model <- readRDS(file.path(root, as.character(mat_row$path[1])))
  stopifnot(identical(as.character(materialized_model$model_path), success_case$model_rel))

  # Continuing the same session after promoting the model must use the prior
  # durable materialization, not the primitive's now-stale staging path.
  continuation <- wb_new_run(
    op_name = "scvi_train",
    inputs = list(
      cell_set = "all",
      parents = success_case$run$run_id,
      user_inputs = list(model = wb_ref_run(success_case$run$run_id, "model"))
    ),
    params = list(output_space_id = "synthetic_success"),
    outputs = list(fit_summary = wb_prim_obs_table(
      data.frame(status = "continued", stringsAsFactors = FALSE),
      table_type = "scvi_fit_summary"
    ))
  )
  continued <- wb_promote_analysis(
    b,
    setNames(
      list(success_case$run, continuation),
      c(success_case$run$run_id, continuation$run_id)
    ),
    head_run_id = continuation$run_id,
    outputs = "fit_summary",
    staging_bundle = success_case$bundle
  )
  continued_commit <- DBI::dbGetQuery(
    b$con,
    "SELECT commit_id FROM prov_heads WHERE snapshot_id = ?;",
    params = list(continued$provenance_snapshot_id)
  )$commit_id[1]
  continued_model_mat <- DBI::dbGetQuery(
    b$con,
    "SELECT path, output_hash FROM prov_materializations WHERE commit_id = ? AND run_id = ? AND output_name = 'model';",
    params = list(continued_commit, success_case$run$run_id)
  )
  stopifnot(nrow(continued_model_mat) == 1L)
  continued_model <- readRDS(file.path(root, as.character(continued_model_mat$path[1])))
  stopifnot(identical(as.character(continued_model$model_path), success_case$model_rel))
  stopifnot(identical(as.character(continued_model_mat$output_hash[1]), as.character(
    DBI::dbGetQuery(
      b$con,
      "SELECT output_hash FROM prov_materializations WHERE commit_id = ? AND run_id = ? AND output_name = 'model';",
      params = list(commit_id, success_case$run$run_id)
    )$output_hash[1]
  )))
  stage_session <- wb_session_discard(stage_session)

  wb_close_bundle(b)
  b <- wb_open_bundle(root)
  loaded <- wb_art_load(b, model_artifact, expected_kind = "model_ref")
  stopifnot(dir.exists(loaded$model_path))

  failure_case <- make_staged_model("rollback")
  artifact_n_before <- nrow(wb_art_list(b))
  commit_n_before <- DBI::dbGetQuery(b$con, "SELECT COUNT(*) AS n FROM prov_commits;")$n[1]
  options(scworkbench.promotion_workspace_publish_hook = function(workspace, final_rel) {
    stop("forced staged-model publication failure", call. = FALSE)
  })
  failed <- try(wb_promote_analysis(
    b,
    setNames(list(failure_case$run), failure_case$run$run_id),
    head_run_id = failure_case$run$run_id,
    outputs = "model",
    staging_bundle = failure_case$bundle
  ), silent = TRUE)
  options(scworkbench.promotion_workspace_publish_hook = NULL)
  stopifnot(inherits(failed, "try-error"))
  stopifnot(nrow(wb_art_list(b)) == artifact_n_before)
  stopifnot(DBI::dbGetQuery(b$con, "SELECT COUNT(*) AS n FROM prov_commits;")$n[1] == commit_n_before)
  stopifnot(!file.exists(file.path(root, failure_case$model_rel)))

  TRUE
}
