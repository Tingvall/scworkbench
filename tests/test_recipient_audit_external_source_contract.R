test_recipient_audit_external_source_contract <- function() {
  if (!requireNamespace("BPCells", quietly = TRUE)) return(contract_test_skip("BPCells is not installed."))
  root <- tempfile("scwb_recipient_audit_"); b <- wb_init_bundle(root, overwrite=TRUE)
  on.exit({ try(wb_close_bundle(b), silent=TRUE); unlink(root, recursive=TRUE, force=TRUE) }, add=TRUE)
  ids <- paste0("c", 1:4); feats <- paste0("g", 1:3); counts <- matrix(seq_len(12), 3, dimnames=list(feats, ids))
  wb_define_cells(b, ids)
  identity <- list(dataset_name="generic recipient fixture", inputs=lapply(seq_len(27L), function(i) list(
    path=paste0("library_", i, ".tsv.gz"), file_name=paste0("library_", i, ".tsv.gz"),
    sha256=paste(rep(sprintf("%x", i %% 16L), 64L), collapse=""), format="10x_mtx", role="counts", sample_id=paste0("sample", i)
  )))
  wb_attach_matrix(b, "RNA_counts", counts, feature_type="gene")
  .wb_ingest_report_artifact(b, "core", "atomic", list(n_cells=length(ids)), list(), list(),
    matrix_ids="RNA_counts", source_identity=identity)
  inputs_all <- wb_prov_source_inputs(b)
  inputs <- inputs_all[as.character(inputs_all$checksum_status) == "checksummed", , drop = FALSE]
  stopifnot(nrow(inputs)==54L, length(unique(inputs$source_id))==27L, all(as.character(inputs$checksum_status) == "checksummed"), all(as.character(inputs$checksum_algorithm) == "sha256"))
  dag <- wb_prov_bundle_dag(b); art <- wb_ingest_reports(b)$artifact_id[1]
  run <- DBI::dbGetQuery(b$con,"SELECT run_id FROM prov_run_outputs WHERE artifact_id=?;",params=list(art))$run_id[[1L]]
  key <- paste(dag$edges$from, dag$edges$to, sep="|")
  stopifnot(all(paste0("external_source:", inputs$source_id, "|run:", run) %in% key), any(paste0("run:", run, "|artifact:", art) == key))
  stopifnot(any(grepl("^external_source:", wb_kg_provenance_graph(b)$nodes$id)))
  finalized <- wb_finalize_recipient_bundle(b)
  stopifnot(isTRUE(finalized$ready), identical(as.character(finalized$journal_mode), "delete"))
  wb_close_bundle(b); before <- file.info(file.path(root, "db", "app.sqlite"))$mtime
  ro <- wb_open_bundle(root, read_only=TRUE, validate=TRUE)
  on.exit(try(wb_close_bundle(ro), silent=TRUE), add=TRUE)
  ro_inputs <- wb_prov_source_inputs(ro)
  stopifnot(isTRUE(ro$read_only), nrow(wb_matrices(ro))==1L, nrow(wb_art_list(ro))>=1L,
            sum(as.character(ro_inputs$checksum_status) == "checksummed") == 54L,
            nrow(wb_prov_bundle_dag(ro)$nodes)>0L, !inherits(try(wb_art_load(ro, art), silent=TRUE), "try-error"),
            inherits(try(wb_session_run_op(wb_session_new(), ro, "matrix_log_normalize",
              inputs=list(matrix="RNA_counts", output_matrix_id="readonly_forbidden")), silent=TRUE), "try-error"))
  wb_close_bundle(ro); stopifnot(identical(before, file.info(file.path(root, "db", "app.sqlite"))$mtime))
  TRUE
}
