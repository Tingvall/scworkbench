test_registry_replay_closure_contract <- function() {
  if (!requireNamespace("BPCells", quietly = TRUE)) return(contract_test_skip("BPCells is not installed."))
  root <- tempfile("scwb_registry_replay_closure_")
  b <- wb_init_bundle(root, overwrite = TRUE)
  on.exit({ options(scworkbench.registry_replay_hook = NULL); try(wb_close_bundle(b), silent = TRUE); unlink(root, recursive = TRUE, force = TRUE) }, add = TRUE)
  cells <- paste0("c", seq_len(12L)); feats <- paste0("g", seq_len(4L))
  wb_define_cells(b, cells); wb_attach_matrix(b, "RNA", matrix(1L, 4L, 12L, dimnames = list(feats, cells)), feature_type = "gene")
  make_import <- function(session, namespace, set_name) {
    src <- tempfile(fileext = ".rds"); saveRDS(data.frame(feature_set = set_name, feature_id = feats[1:2], namespace = namespace), src)
    wb_session_run_op(session, b, "feature_set_import", inputs = list(matrix = "RNA", source_path = src, source_format = "rds", namespace = namespace, strict = TRUE, overwrite = TRUE, min_cells = 1L))
  }
  a <- make_import(wb_session_new(), "selected_ns", "SEL"); s <- a$session
  sibling <- make_import(s, "sibling_ns", "SIB"); s <- sibling$session
  prom <- wb_promote_analysis(b, s$runs, head_run_id = a$run$run_id, outputs = "import_summary", staging_bundle = wb_session_view(s))
  wb_close_bundle(b); b <- wb_open_bundle(root)
  stopifnot(identical(wb_feature_set_get(b, "SEL", "RNA"), feats[1:2]))
  stopifnot(!nrow(wb_feature_set_info(b, "SIB", "RNA")))
  ev <- DBI::dbGetQuery(b$con, "SELECT run_id FROM prov_registry_mutations;")
  stopifnot(identical(unique(as.character(ev$run_id)), a$run$run_id))
  dag <- wb_prov_bundle_dag(b)
  stopifnot(any(as.character(dag$edges$from) == paste0("run:", a$run$run_id) & as.character(dag$edges$edge_type) == "MUTATES_REGISTRY"))
  stopifnot(!any(grepl("sibling_ns", as.character(dag$nodes$id), fixed = TRUE)))

  # A replay fault occurs after the coordinator transaction begins and rolls all state back.
  b2root <- tempfile("scwb_registry_replay_failure_"); b2 <- wb_init_bundle(b2root, overwrite = TRUE)
  on.exit({ try(wb_close_bundle(b2), silent = TRUE); unlink(b2root, recursive = TRUE, force = TRUE) }, add = TRUE)
  wb_define_cells(b2, cells); wb_attach_matrix(b2, "RNA", matrix(1L, 4L, 12L, dimnames = list(feats, cells)), feature_type = "gene")
  src <- tempfile(fileext = ".rds"); saveRDS(data.frame(feature_set = "FAIL", feature_id = feats[1:2], namespace = "fail_ns"), src)
  rr <- wb_session_run_op(wb_session_new(), b2, "feature_set_import", inputs = list(matrix = "RNA", source_path = src, source_format = "rds", namespace = "fail_ns", strict = TRUE, overwrite = TRUE, min_cells = 1L))
  options(scworkbench.registry_replay_hook = function(event) stop("forced registry replay failure", call. = FALSE))
  bad <- try(wb_promote_analysis(b2, rr$session$runs, rr$run$run_id, outputs = "import_summary", staging_bundle = wb_session_view(rr$session)), silent = TRUE)
  stopifnot(inherits(bad, "try-error"), !nrow(wb_feature_set_info(b2, "FAIL", "RNA")))
  stopifnot(DBI::dbGetQuery(b2$con, "SELECT COUNT(*) AS n FROM prov_commits;")$n[1] == 0L)
  stopifnot(!.wb_table_exists(b2$con, "prov_registry_mutations") || DBI::dbGetQuery(b2$con, "SELECT COUNT(*) AS n FROM prov_registry_mutations;")$n[1] == 0L)
  TRUE
}
