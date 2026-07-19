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
