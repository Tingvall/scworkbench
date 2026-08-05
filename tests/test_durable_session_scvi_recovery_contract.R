test_durable_session_scvi_recovery_contract <- function() {
  required <- c("BPCells", "Matrix")
  missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing)) return(contract_test_skip(paste("Missing runtime dependencies:", paste(missing, collapse = ", "))))

  bundle_dir <- tempfile("scwb_durable_scvi_bundle_")
  workspace_root <- tempfile("scwb_durable_scvi_sessions_")
  b <- wb_init_bundle(bundle_dir, overwrite = TRUE)
  op_env <- environment(wb_op_scvi_train)
  old_bridge <- get(".wb_palantir_bridge_run_or_stop", envir = op_env)
  bridge_unlocked <- FALSE
  on.exit({
    if (bridge_unlocked) {
      assign(".wb_palantir_bridge_run_or_stop", old_bridge, envir = op_env)
      lockBinding(".wb_palantir_bridge_run_or_stop", op_env)
    }
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

  # The sole mock is the expensive PyBench call. It writes the same registered
  # outputs the real bridge owns; R session, staging, checkpoint and promotion
  # paths remain untouched.
  unlockBinding(".wb_palantir_bridge_run_or_stop", op_env)
  bridge_unlocked <- TRUE
  assign(".wb_palantir_bridge_run_or_stop", function(bundle = NULL, module, request, ...) {
    stopifnot(identical(module, "pybench.ops.scvi_train"))
    sb <- wb_open_bundle(request$bundle_dir, validate = FALSE)
    on.exit(wb_close_bundle(sb), add = TRUE)
    ids <- as.character(request$inputs$cell_ids)
    n_latent <- as.integer(request$params$n_latent)
    sid <- as.character(request$params$output_space_id)
    latent <- matrix(seq_len(length(ids) * n_latent) / 100, nrow = length(ids),
                     dimnames = list(ids, paste0("latent_", seq_len(n_latent))))
    wb_add_space(sb, sid, latent, source = "durable-scvi-mocked-pybench")

    model_id <- as.character(request$outputs$model$artifact_id)
    model_rel <- file.path("artifact_models", paste0(model_id, "_tree"))
    model_dir <- file.path(sb$dir, model_rel)
    dir.create(file.path(model_dir, "weights"), recursive = TRUE, showWarnings = FALSE)
    writeLines("mock-scvi-config-v1", file.path(model_dir, "model.json"), useBytes = TRUE)
    writeBin(as.raw(seq_len(32L)), file.path(model_dir, "weights", "weights.bin"))
    DBI::dbExecute(sb$con, paste(
      "INSERT INTO artifact_model_ref(artifact_id,engine,model_space_id,in_space_id,model_type,model_path)",
      "VALUES(?,?,?,?,?,?);"),
      params = list(model_id, "scvi", sid, sid, "scvi_train", model_rel))

    summary_id <- as.character(request$outputs$fit_summary$artifact_id)
    DBI::dbExecute(sb$con,
      "INSERT INTO artifact_tables(artifact_id,table_type,entity_kind,meta_json) VALUES(?,?,?,?);",
      params = list(summary_id, "scvi_fit_summary", "training", "{}"))
    row <- jsonlite::toJSON(list(status = "ok", epochs = 3L, final_loss = 0.125), auto_unbox = TRUE)
    DBI::dbExecute(sb$con,
      "INSERT INTO artifact_table_rows(artifact_id,row_idx,row_json) VALUES(?,?,?);",
      params = list(summary_id, 1L, as.character(row)))
    list(receipt = list(status = "ok", protocol_version = "pybench-op-v1",
                        pybench = list(version = "durable-scvi-mock"), timings = list(total_sec = 0)))
  }, envir = op_env)

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

  assign(".wb_palantir_bridge_run_or_stop", old_bridge, envir = op_env)
  lockBinding(".wb_palantir_bridge_run_or_stop", op_env)
  bridge_unlocked <- FALSE
  wb_close_bundle(b)
  rm(s)
  gc()
  result_path <- tempfile("scwb_durable_scvi_result_", fileext = ".rds")
  child_log <- tempfile("scwb_durable_scvi_child_", fileext = ".log")
  esc <- function(x) gsub("'", "\\\\'", x)
  code <- paste0(
    "devtools::load_all('", esc(normalizePath(".", winslash = "/", mustWork = TRUE)), "',quiet=TRUE);",
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
  cert <- wb_art_birth_certificate(b, model_art)
  stopifnot(identical(as.character(cert$artifact$source_op), "scvi_train"),
            identical(as.character(cert$inline_provenance$parsed$run_id), run_id),
            nrow(DBI::dbGetQuery(b$con, "SELECT run_id FROM prov_runs WHERE run_id = ?;", params = list(run_id))) == 1L)
  wb_session_discard(wb_session_open(workspace))
  TRUE
}
