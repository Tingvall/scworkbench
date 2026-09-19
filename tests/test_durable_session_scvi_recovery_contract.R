test_durable_session_scvi_recovery_contract <- function() {
  contract_test_activate_representation_pack()
  on.exit(try(wb_operation_pack_unload("scwbrepresentation"), silent = TRUE),
    add = TRUE)
  required <- c("BPCells", "Matrix")
  missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing)) return(contract_test_skip(paste("Missing runtime dependencies:", paste(missing, collapse = ", "))))

  bundle_dir <- tempfile("scwb_durable_scvi_bundle_")
  workspace_root <- tempfile("scwb_durable_scvi_sessions_")
  b <- wb_init_bundle(bundle_dir, overwrite = TRUE)
  old_mock <- Sys.getenv("PYBENCH_TEST_MOCK_TRAINING", unset = NA_character_)
  Sys.setenv(PYBENCH_TEST_MOCK_TRAINING = "1")
  on.exit({
    if (is.na(old_mock)) Sys.unsetenv("PYBENCH_TEST_MOCK_TRAINING") else Sys.setenv(PYBENCH_TEST_MOCK_TRAINING = old_mock)
    try(wb_close_bundle(b), silent = TRUE)
    unlink(bundle_dir, recursive = TRUE, force = TRUE)
    unlink(workspace_root, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  cells <- paste0("cell_", seq_len(6L))
  genes <- paste0("gene_", seq_len(4L))
  wb_define_cells(b, cells, metadata = data.frame(
    cell_id = cells, batch = rep(c("b1", "b2"), each = 3L), stringsAsFactors = FALSE
  ))
  counts <- Matrix::Matrix(
    matrix(c(1,0,3,0, 0,2,0,4, 5,0,1,0, 0,1,0,1, 2,0,2,0, 1,1,0,2), nrow = 4L,
           dimnames = list(genes, cells)), sparse = TRUE
  )
  wb_attach_matrix(b, "RNA_counts", counts, layer = "counts", feature_type = "gene")

  s <- wb_session_create(b, workspace_root, "scvi_recovery")
  trained <- wb_session_run_op(s, b, "scvi_train", inputs = list(
    matrix = "RNA_counts", batch_key = "batch", n_latent = 3L,
    output_space_id = "rna.scvi.durable", cell_set = "all", min_cells = 2L
  ))
  workspace <- trained$session$durable$workspace
  run_id <- trained$run$run_id
  expected <- trained$session$durable$payload_identities[[run_id]]
  stopifnot(all(c("space", "model", "fit_summary") %in% names(expected)),
            dir.exists(trained$run$outputs$model$model_path))

  Sys.unsetenv("PYBENCH_TEST_MOCK_TRAINING")
  wb_close_bundle(b)
  rm(s)
  gc()
  result_path <- tempfile("scwb_durable_scvi_result_", fileext = ".rds")
  child_log <- tempfile("scwb_durable_scvi_child_", fileext = ".log")
  esc <- function(x) gsub("'", "\\\\'", x)
  code <- paste0(
    "devtools::load_all('", esc(normalizePath(".", winslash = "/", mustWork = TRUE)), "',quiet=TRUE);",
    "wb_operation_pack_load('scwbRepresentation',lib.loc=.libPaths());",
    "b<-wb_open_bundle('", esc(bundle_dir), "');s<-wb_session_resume(b,'", esc(workspace), "');",
    "stopifnot(identical(names(s$runs),'", run_id, "'),",
    "all(c('space','model','fit_summary')%in%names(s$runs[['", run_id, "']]$outputs)));",
    "p<-wb_session_promote_current(b,s,created_by='durable-scvi-contract',",
    "outputs=list(wb_ref_run('", run_id, "','model'),wb_ref_run('", run_id, "','fit_summary')));",
    "saveRDS(list(promoted=p$promoted,state=p$session$durable$state),'", esc(result_path), "')"
  )
  status <- system2(file.path(R.home("bin"), "Rscript"), c("-e", shQuote(code)), stdout = child_log, stderr = child_log)
  if (!identical(as.integer(status), 0L) || !file.exists(result_path)) {
    stop("scVI recovery child failed:\n", paste(readLines(child_log, warn = FALSE), collapse = "\n"), call. = FALSE)
  }
  child <- readRDS(result_path)
  stopifnot(identical(child$state, "promoted"))
  b <- wb_open_bundle(bundle_dir)
  latent <- wb_space(b, "rna.scvi.durable", cells = cells)
  model_art <- as.character(child$promoted$artifact_id[child$promoted$output == "model"])[1]
  summary_art <- as.character(child$promoted$artifact_id[child$promoted$output == "fit_summary"])[1]
  model <- wb_art_load(b, model_art, expected_kind = "model_ref")
  summary <- wb_art_load(b, summary_art, expected_kind = "obs_table")
  stopifnot(nrow(latent) == length(cells), ncol(latent) == 3L,
            file.exists(file.path(model$model_path, "model.json")),
            file.exists(file.path(model$model_path, "weights", "weights.bin")),
            identical(as.character(summary$table$status), "ok"),
            identical(expected$space$content_sha256,
                      .wb_prov_payload_identity(b, wb_prim_space("rna.scvi.durable"))$content_sha256),
            identical(expected$model$content_sha256, .wb_prov_payload_identity(b, model)$content_sha256),
            identical(expected$fit_summary$content_sha256, .wb_prov_payload_identity(b, summary)$content_sha256))
  downstream <- wb_space(b, space_id = "rna.scvi.durable", cells = cells)
  stopifnot(nrow(downstream) == length(cells))
  cert <- wb_entity_certificate(b, "artifact", model_art)
  stopifnot(identical(as.character(cert$producer$operation$name), "scvi_train"),
            identical(as.character(cert$producer$run_id), run_id),
            nrow(DBI::dbGetQuery(b$con, "SELECT run_id FROM prov_runs WHERE run_id = ?;", params = list(run_id))) == 1L)
  wb_session_discard(wb_session_open(workspace))
  TRUE
}

test_durable_typed_scvi_umap_sibling_recovery_contract <- function() {
  contract_test_activate_representation_pack()
  on.exit(try(wb_operation_pack_unload("scwbrepresentation"), silent = TRUE),
    add = TRUE)
  required <- c("BPCells", "Matrix", "uwot")
  missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing)) return(contract_test_skip(paste("Missing runtime dependencies:", paste(missing, collapse = ", "))))
  sibling_python <- file.path(normalizePath(file.path(getwd(), "..", "..", "pybench"),
                                            winslash = "/", mustWork = FALSE),
                              ".venv", "bin", "python")
  real_python <- if (file.exists(sibling_python)) sibling_python else scworkbench:::.wb_pybench_default_python()
  if (!nzchar(real_python) || !file.exists(real_python)) {
    return(contract_test_skip("PyBench Python interpreter is unavailable."))
  }

  bundle_dir <- tempfile("scwb_typed_scvi_sibling_bundle_")
  workspace_root <- tempfile("scwb_typed_scvi_sibling_sessions_")
  wrapper_dir <- tempfile("scwb_typed_scvi_counter_")
  dir.create(wrapper_dir, recursive = TRUE)
  counter <- file.path(wrapper_dir, "training_invocations")
  wrapper <- file.path(wrapper_dir, "python")
  writeLines(c(
    "#!/usr/bin/env bash", "set -euo pipefail",
    paste0("printf 'training\\n' >> ", shQuote(counter)),
    paste0("exec ", shQuote(real_python), " \"$@\"")
  ), wrapper)
  Sys.chmod(wrapper, "0755")
  old_mock <- Sys.getenv("PYBENCH_TEST_MOCK_TRAINING", unset = NA_character_)
  old_python <- Sys.getenv("SCWORKBENCH_PYBENCH_PYTHON", unset = NA_character_)
  old_pythonpath <- Sys.getenv("PYTHONPATH", unset = NA_character_)
  pybench_source <- normalizePath(file.path(getwd(), "..", "..", "pybench", "src"),
                                  winslash = "/", mustWork = FALSE)
  pythonpath <- paste(c(pybench_source, if (!is.na(old_pythonpath) && nzchar(old_pythonpath)) old_pythonpath),
                      collapse = .Platform$path.sep)
  Sys.setenv(PYBENCH_TEST_MOCK_TRAINING = "1", SCWORKBENCH_PYBENCH_PYTHON = wrapper,
             PYTHONPATH = pythonpath)
  b <- wb_init_bundle(bundle_dir, overwrite = TRUE)
  on.exit({
    if (is.na(old_mock)) Sys.unsetenv("PYBENCH_TEST_MOCK_TRAINING") else Sys.setenv(PYBENCH_TEST_MOCK_TRAINING = old_mock)
    if (is.na(old_python)) Sys.unsetenv("SCWORKBENCH_PYBENCH_PYTHON") else Sys.setenv(SCWORKBENCH_PYBENCH_PYTHON = old_python)
    if (is.na(old_pythonpath)) Sys.unsetenv("PYTHONPATH") else Sys.setenv(PYTHONPATH = old_pythonpath)
    try(wb_close_bundle(b), silent = TRUE)
    unlink(bundle_dir, recursive = TRUE, force = TRUE)
    unlink(workspace_root, recursive = TRUE, force = TRUE)
    unlink(wrapper_dir, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  cells <- paste0("cell_", seq_len(18L))
  genes <- paste0("gene_", seq_len(8L))
  wb_define_cells(b, cells, metadata = data.frame(
    cell_id = cells, sample_id = rep(c("s1", "s2", "s3"), each = 6L),
    donor_id = rep(c("d1", "d2"), 9L), stringsAsFactors = FALSE
  ))
  counts <- outer(seq_along(genes), seq_along(cells), function(i, j) as.integer((i * 7L + j * 3L) %% 13L))
  counts <- Matrix::Matrix(counts, sparse = TRUE, dimnames = list(genes, cells))
  wb_attach_matrix(b, "RNA_counts", counts, layer = "counts", feature_type = "gene")

  parent_scvi <- wb_session_run_op(wb_session_new(), b, "scvi_train", inputs = list(
    matrix = "RNA_counts", batch_key = NULL, categorical_covariates = "donor_id",
    n_latent = 4L, n_hidden = 16L, n_layers = 1L, dropout = 0.05,
    max_epochs = 50L, early_stopping = TRUE, seed = 31L, use_gpu = FALSE,
    output_space_id = "rna.scvi.unbatched", cell_set = "all", min_cells = 2L
  ))
  parent_umap <- wb_session_run_op(parent_scvi$session, b, "umap_fit", inputs = list(
    space = wb_ref_run(parent_scvi$run$run_id, "space"), dims = 1:4,
    space_id_out = "rna.umap.unbatched", n_neighbors = 5L, min_dist = 0.2,
    metric = "euclidean", nn_method = "annoy", spread = 1, seed = 31L,
    cell_set = "all", min_cells = 2L
  ))
  parent_promotion <- wb_session_promote_current(b, parent_umap$session, outputs = list(
    wb_ref_run(parent_scvi$run$run_id, "model"),
    wb_ref_run(parent_scvi$run$run_id, "fit_summary"),
    wb_ref_run(parent_umap$run$run_id, "model")
  ), created_by = "typed-sibling-parent")
  stopifnot(all(parent_promotion$promoted$status == "ok"))
  sid <- parent_promotion$provenance_snapshot_id
  parent_scvi_spec <- wb_prov_run_replay_inputs(b, parent_scvi$run$run_id, sid)
  parent_umap_spec <- wb_prov_run_replay_inputs(b, parent_umap$run$run_id, sid)
  stopifnot(identical(parent_scvi_spec$diagnostics$status, "compatible"),
            identical(parent_umap_spec$inputs$dims, 1:4))

  # Count only the sample-aware sibling training. The source fixture above is
  # setup, not part of the recovery invocation count.
  writeLines(character(0), counter)
  durable <- wb_session_create(b, workspace_root, "typed_scvi_sibling")
  scvi_inputs <- parent_scvi_spec$inputs
  scvi_inputs$batch_key <- "sample_id"
  scvi_inputs$output_space_id <- "rna.scvi.sample_aware"
  sibling_scvi <- wb_session_run_op(durable, b, "scvi_train", inputs = scvi_inputs)
  workspace <- sibling_scvi$session$durable$workspace
  sibling_scvi_id <- sibling_scvi$run$run_id
  stopifnot(length(readLines(counter, warn = FALSE)) == 1L)

  exact_details <- wb_prov_run_details(b, parent_umap$run$run_id, sid)
  invalid_inputs <- parent_umap_spec$inputs
  invalid_inputs$dims <- exact_details$run$inputs$user_inputs$dims
  invalid_inputs$space <- wb_ref_run(sibling_scvi_id, "space")
  invalid_inputs$space_id_out <- "rna.umap.sample_aware"
  invalid <- tryCatch(wb_session_run_op(sibling_scvi$session, b, "umap_fit", inputs = invalid_inputs), error = identity)
  stopifnot(inherits(invalid, "error"),
            grepl("inputs\\$dims must be numeric and mathematically integral", conditionMessage(invalid)),
            length(readLines(counter, warn = FALSE)) == 1L)

  # Drop every in-memory handle. A new R process resumes the durable checkpoint,
  # obtains typed UMAP inputs publicly, runs, promotes, closes, and reopens.
  wb_close_bundle(b)
  b <- NULL
  rm(durable, sibling_scvi)
  gc()
  result_path <- tempfile("scwb_typed_sibling_result_", fileext = ".rds")
  child_log <- tempfile("scwb_typed_sibling_child_", fileext = ".log")
  esc <- function(x) gsub("'", "\\\\'", x)
  code <- paste0(
    "devtools::load_all('", esc(normalizePath(".", winslash = "/", mustWork = TRUE)), "',quiet=TRUE);",
    "wb_operation_pack_load('scwbRepresentation',lib.loc=.libPaths());",
    "b<-wb_open_bundle('", esc(bundle_dir), "');s<-wb_session_resume(b,'", esc(workspace), "');",
    "u<-wb_prov_run_replay_inputs(b,'", parent_umap$run$run_id, "','", sid, "')$inputs;",
    "u$space<-wb_ref_run('", sibling_scvi_id, "','space');u$space_id_out<-'rna.umap.sample_aware';",
    "fit<-wb_session_run_op(s,b,'umap_fit',inputs=u);",
    "p<-wb_session_promote_current(b,fit$session,outputs=list(",
    "wb_ref_run('", sibling_scvi_id, "','model'),wb_ref_run('", sibling_scvi_id, "','fit_summary'),",
    "wb_ref_run(fit$run$run_id,'model')),created_by='typed-sibling-recovery');",
    "wb_close_bundle(b);v<-wb_validate_bundle('", esc(bundle_dir), "',read_only=TRUE);",
    "b<-wb_open_bundle('", esc(bundle_dir), "',read_only=TRUE);saveRDS(list(run=fit$run,promotion=p,validation=v),'", esc(result_path), "');wb_close_bundle(b)"
  )
  status <- system2(file.path(R.home("bin"), "Rscript"), c("-e", shQuote(code)),
                    stdout = child_log, stderr = child_log)
  if (!identical(as.integer(status), 0L) || !file.exists(result_path)) {
    stop("typed durable sibling child failed:\n", paste(readLines(child_log, warn = FALSE), collapse = "\n"), call. = FALSE)
  }
  child <- readRDS(result_path)
  stopifnot(length(readLines(counter, warn = FALSE)) == 1L,
            identical(child$promotion$session$durable$state, "promoted"),
            all(child$promotion$promoted$status == "ok"), isTRUE(child$validation),
            identical(child$run$inputs$user_inputs$dims, 1:4))

  # Apart from the requested branch axes, every public effective input stays
  # byte-identical to the persisted parents.
  actual_scvi <- child$promotion$session$runs[[sibling_scvi_id]]$inputs$user_inputs
  stopifnot(identical(actual_scvi[names(parent_scvi_spec$inputs)[
    !names(parent_scvi_spec$inputs) %in% c("batch_key", "output_space_id")]],
    parent_scvi_spec$inputs[!names(parent_scvi_spec$inputs) %in% c("batch_key", "output_space_id")]))
  actual_umap <- child$run$inputs$user_inputs
  inherited <- setdiff(names(parent_umap_spec$inputs), c("space", "space_id_out"))
  stopifnot(identical(actual_umap[inherited], parent_umap_spec$inputs[inherited]))
  b <- wb_open_bundle(bundle_dir)
  TRUE
}
