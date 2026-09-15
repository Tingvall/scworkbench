test_durable_session_dependent_branch_contract <- function() {
  contract_test_activate_statistics_pack()
  bundle_dir <- tempfile("scwb_durable_dependent_bundle_")
  workspace_root <- tempfile("scwb_durable_dependent_sessions_")
  b <- wb_init_bundle(bundle_dir, overwrite = TRUE)
  on.exit({
    try(wb_close_bundle(b), silent = TRUE)
    unlink(bundle_dir, recursive = TRUE, force = TRUE)
    unlink(workspace_root, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  cells <- paste0("cell_", seq_len(8L))
  wb_define_cells(b, cells, metadata = data.frame(
    cell_id = cells,
    treatment = rep(c("control", "treated"), each = 4L),
    lane = rep(c("L1", "L2"), times = 4L),
    stringsAsFactors = FALSE
  ))
  s <- wb_session_create(b, workspace_root, "dependent_branch")
  treatment <- wb_session_run_op(s, b, "metadata_cell_vector", inputs = list(
    source_column = "treatment", vector_name = "durable_treatment",
    value_type = "categorical", missing_policy = "error", cell_set = "all", min_cells = 1L
  ))
  lane <- wb_session_run_op(treatment$session, b, "metadata_cell_vector", inputs = list(
    source_column = "lane", vector_name = "durable_lane",
    value_type = "categorical", missing_policy = "error", cell_set = "all", min_cells = 1L
  ))
  workspace <- lane$session$durable$workspace

  # A fresh R process reopens the bundle, resumes the checkpoint, continues
  # through explicit run refs, proves graph-binding rejection, and performs the
  # sole terminal promotion.
  wb_close_bundle(b)
  rm(s)
  gc()
  result_path <- tempfile("scwb_durable_dependent_result_", fileext = ".rds")
  child_log <- tempfile("scwb_durable_dependent_child_", fileext = ".log")
  esc <- function(x) gsub("'", "\\\\'", x)
  code <- paste0(
    "devtools::load_all('", esc(normalizePath(".", winslash = "/", mustWork = TRUE)), "',quiet=TRUE);wb_operation_pack_load('scwbStatistics');",
    "b<-wb_open_bundle('", esc(bundle_dir), "');s<-wb_session_resume(b,'", esc(workspace), "');",
    "a<-wb_session_run_op(s,b,'cell_vector_association',inputs=list(a=wb_ref_run('", treatment$run$run_id,
    "','vector'),b=wb_ref_run('", lane$run$run_id, "','vector'),cell_set='all',min_cells=1L,min_n_per_group=1L));",
    "terminal<-wb_session_resume(b,'", esc(workspace), "');",
    "da<-try(wb_session_set_active(terminal,'forged',wb_ref_run(a$run$run_id,'summary')),silent=TRUE);",
    "dr<-try(wb_session_add_run(terminal,terminal$runs[[1]]),silent=TRUE);",
    "forged<-terminal;forged$active$forged<-wb_ref_run(a$run$run_id,'summary');",
    "fp<-try(wb_session_promote_current(b,forged,outputs=list(wb_ref_run(a$run$run_id,'summary'))),silent=TRUE);",
    "stopifnot(inherits(da,'try-error'),inherits(dr,'try-error'),inherits(fp,'try-error'),",
    "grepl('DURABLE_SESSION_DIRECT_MUTATION',as.character(da),fixed=TRUE),",
    "grepl('DURABLE_SESSION_DIRECT_MUTATION',as.character(dr),fixed=TRUE),",
    "grepl('DURABLE_SESSION_UNCHECKPOINTED_STATE',as.character(fp),fixed=TRUE));",
    "p<-wb_session_promote_current(b,terminal,created_by='durable-dependent-contract',",
    "outputs=list(wb_ref_run(a$run$run_id,'summary'),wb_ref_run(a$run$run_id,'detail')));",
    "saveRDS(list(run_id=a$run$run_id,parents=a$run$inputs$parents,promoted=p$promoted,state=p$session$durable$state),'",
    esc(result_path), "')"
  )
  status <- system2(file.path(R.home("bin"), "Rscript"), c("-e", shQuote(code)), stdout = child_log, stderr = child_log)
  if (!identical(as.integer(status), 0L) || !file.exists(result_path)) {
    stop("dependent child failed:\n", paste(readLines(child_log, warn = FALSE), collapse = "\n"), call. = FALSE)
  }
  child <- readRDS(result_path)
  stopifnot(setequal(as.character(child$parents), c(treatment$run$run_id, lane$run$run_id)),
            identical(child$state, "promoted"))
  b <- wb_open_bundle(bundle_dir)
  edges <- DBI::dbGetQuery(
    b$con,
    "SELECT parent_run_id, child_run_id FROM prov_run_edges WHERE child_run_id = ? ORDER BY parent_run_id;",
    params = list(child$run_id)
  )
  stopifnot(nrow(unique(edges)) == 2L,
            setequal(as.character(edges$parent_run_id), c(treatment$run$run_id, lane$run$run_id)),
            all(as.character(child$promoted$lineage_status[child$promoted$status == "ok"]) == "complete"))
  arts <- as.character(child$promoted$artifact_id[child$promoted$status == "ok"])
  stopifnot(length(arts) == 2L,
            all(vapply(arts, function(id) inherits(wb_art_load(b, id), "wb_primitive"), logical(1))))
  terminal_resume <- try(wb_session_resume(b, workspace), silent = TRUE)
  stopifnot(inherits(terminal_resume, "try-error"),
            grepl("DURABLE_SESSION_PROMOTED", as.character(terminal_resume), fixed = TRUE))
  inspected <- wb_session_open(workspace)
  terminal_run <- try(wb_session_run_op(inspected, b, "metadata_cell_vector", inputs = list(
    source_column = "treatment", vector_name = "must_not_run", value_type = "categorical",
    missing_policy = "error", cell_set = "all", min_cells = 1L
  )), silent = TRUE)
  wb_session_cleanup(inspected)
  stopifnot(inherits(terminal_run, "try-error"),
            grepl("DURABLE_SESSION_PROMOTED", as.character(terminal_run), fixed = TRUE),
            identical(wb_session_finalize(inspected)$durable$state, "promoted"),
            length(inspected$durable$promotion_receipt$artifact_ids) >= 2L)
  wb_session_discard(inspected)
  TRUE
}
