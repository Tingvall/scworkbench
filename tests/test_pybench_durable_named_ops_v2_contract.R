.pybench_v2_test_env <- function() {
  python <- .wb_pybench_default_python()
  if (!file.exists(python)) return(NULL)
  old <- Sys.getenv("PYBENCH_TEST_MOCK_TRAINING", unset = NA_character_)
  Sys.setenv(PYBENCH_TEST_MOCK_TRAINING = "1")
  list(old = old)
}

.pybench_v2_restore_env <- function(x) {
  if (is.na(x$old)) Sys.unsetenv("PYBENCH_TEST_MOCK_TRAINING") else Sys.setenv(PYBENCH_TEST_MOCK_TRAINING = x$old)
}

.pybench_v2_atac_fixture <- function() {
  if (!requireNamespace("BPCells", quietly = TRUE) || !requireNamespace("Matrix", quietly = TRUE)) return(NULL)
  bundle_dir <- tempfile("scwb_named_v2_bundle_"); workspace <- tempfile("scwb_named_v2_sessions_")
  b <- wb_init_bundle(bundle_dir, overwrite = TRUE)
  cells <- paste0("cell_", seq_len(12L)); peaks <- paste0("peak_", seq_len(5L))
  wb_define_cells(b, cells, metadata = data.frame(cell_id = cells, batch = rep(c("a", "b"), each = 6L)))
  counts <- Matrix::Matrix(matrix(seq_len(60L) %% 4L, nrow = 5L, dimnames = list(peaks, cells)), sparse = TRUE)
  wb_attach_matrix(b, "ATAC_counts", counts, layer = "counts", feature_type = "peak")
  list(b = b, bundle_dir = bundle_dir, workspace = workspace, cells = cells)
}

test_pybench_durable_peakvi_fit_v2_contract <- function() {
  env <- .pybench_v2_test_env(); if (is.null(env)) return(contract_test_skip("PyBench interpreter unavailable"))
  x <- .pybench_v2_atac_fixture(); if (is.null(x)) return(contract_test_skip("BPCells/Matrix unavailable"))
  b <- x$b; on.exit({ .pybench_v2_restore_env(env); try(wb_close_bundle(b), silent=TRUE); unlink(x$bundle_dir,recursive=TRUE); unlink(x$workspace,recursive=TRUE) }, add=TRUE)
  fit <- wb_session_run_op(wb_session_create(b, x$workspace, "peakvi_fit_v2"), b, "peakvi_fit", inputs = list(
    matrix="ATAC_counts", n_latent=3L, max_epochs=1L, space_id_out="peakvi.mock", cell_set="all", min_cells=2L))
  expected <- fit$session$durable$payload_identities[[fit$run$run_id]]
  ws <- fit$session$durable$workspace; wb_close_bundle(b); b <- wb_open_bundle(x$bundle_dir)
  p <- wb_session_promote_current(b, wb_session_resume(b, ws), outputs="model", created_by="named-v2")
  id <- as.character(p$promoted$artifact_id[p$promoted$output=="model"])[1]
  model <- wb_art_load(b,id,"model_ref")
  downstream <- wb_space(b,"peakvi.mock",cells=x$cells)
  stopifnot(p$session$durable$state=="promoted", "peakvi.mock" %in% wb_spaces(b)$space_id,
            identical(model$engine,"peakvi"), nrow(downstream)==length(x$cells),
            identical(expected$space$content_sha256,.wb_prov_payload_identity(b,wb_prim_space("peakvi.mock"))$content_sha256),
            identical(expected$model$content_sha256,.wb_prov_payload_identity(b,model)$content_sha256))
  TRUE
}

test_pybench_durable_peakvi_project_v2_contract <- function() {
  env <- .pybench_v2_test_env(); if (is.null(env)) return(contract_test_skip("PyBench interpreter unavailable"))
  x <- .pybench_v2_atac_fixture(); if (is.null(x)) return(contract_test_skip("BPCells/Matrix unavailable"))
  b <- x$b; on.exit({ .pybench_v2_restore_env(env); try(wb_close_bundle(b), silent=TRUE); unlink(x$bundle_dir,recursive=TRUE); unlink(x$workspace,recursive=TRUE) }, add=TRUE)
  wb_attach_space(
    b, "peakvi.fixture",
    data.frame(
      cell_id = x$cells,
      z1 = seq_along(x$cells),
      z2 = rev(seq_along(x$cells)),
      z3 = seq_along(x$cells) / 10,
      stringsAsFactors = FALSE
    ),
    source = "retained PeakVI model-space fixture"
  )
  rel <- "artifact_models/peakvi_fixture"; dir.create(file.path(x$bundle_dir,rel),recursive=TRUE); writeLines("fixture",file.path(x$bundle_dir,rel,"model.txt"))
  prim <- wb_prim_model_ref("peakvi.fixture","peakvi.fixture","peakvi"); prim$model_type <- "peakvi"; prim$model_path <- file.path(x$bundle_dir,rel)
  run <- wb_new_run("peakvi_fit",inputs=list(cell_set="all",user_inputs=list()),outputs=list(model=prim))
  made <- wb_promote_analysis(b,setNames(list(run),run$run_id),run$run_id,outputs="model",name_prefix="fixture")
  model_id <- as.character(made$promoted$artifact_id[made$promoted$output=="model"])[1]
  model <- wb_art_load(b,model_id,"model_ref")
  projected <- wb_session_run_op(wb_session_create(b,x$workspace,"peakvi_project_v2"),b,"peakvi_project",inputs=list(
    matrix="ATAC_counts",model=model,space_id_out="peakvi.projected.mock",cell_set="all",min_cells=1L))
  expected <- projected$session$durable$payload_identities[[projected$run$run_id]]
  ws <- projected$session$durable$workspace; wb_close_bundle(b); b <- wb_open_bundle(x$bundle_dir)
  p <- wb_session_promote_current(b,wb_session_resume(b,ws),outputs="fit_summary",created_by="named-v2")
  summary_id <- as.character(p$promoted$artifact_id[p$promoted$output=="fit_summary"])[1]
  summary <- wb_art_load(b,summary_id,"obs_table")
  downstream <- wb_space(b,"peakvi.projected.mock",cells=x$cells)
  stopifnot(all(p$promoted$status[p$promoted$output=="fit_summary"]=="ok"),
            "peakvi.projected.mock" %in% wb_spaces(b)$space_id,
            nrow(downstream)==length(x$cells),
            identical(expected$space$content_sha256,.wb_prov_payload_identity(b,wb_prim_space("peakvi.projected.mock"))$content_sha256),
            identical(expected$fit_summary$content_sha256,.wb_prov_payload_identity(b,summary)$content_sha256))
  TRUE
}
