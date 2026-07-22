test_recipient_audit_external_source_contract <- function() {
  if (!requireNamespace("BPCells", quietly = TRUE)) return(TRUE)
  root <- tempfile("scwb_recipient_audit_"); b <- wb_init_bundle(root, overwrite=TRUE)
  on.exit({ try(wb_close_bundle(b), silent=TRUE); unlink(root, recursive=TRUE, force=TRUE) }, add=TRUE)
  ids <- paste0("c", 1:4); feats <- paste0("g", 1:3); counts <- matrix(seq_len(12), 3, dimnames=list(feats, ids))
  wb_define_cells(b, ids)
  identity <- list(dataset_name="generic recipient fixture", inputs=list(
    list(uri="https://example.org/library-1", checksum_algorithm="sha256", checksum="aaa", format="10x_mtx", role="counts"),
    list(accession="GSE99999", format="metadata_tsv", role="metadata")
  ))
  wb_attach_matrix(b, "RNA_counts", counts, feature_type="gene")
  .wb_ingest_report_artifact(b, "core", "atomic", list(n_cells=length(ids)), list(), list(),
    matrix_ids="RNA_counts", source_identity=identity)
  inputs <- wb_prov_source_inputs(b)
  stopifnot(nrow(inputs)==2L, setequal(as.character(inputs$checksum_status), c("checksummed", "declared_no_checksum")))
  dag <- wb_prov_bundle_dag(b); run <- as.character(inputs$run_id[1]); art <- wb_ingest_reports(b)$artifact_id[1]
  key <- paste(dag$edges$from, dag$edges$to, sep="|")
  stopifnot(all(paste0("external_source:", inputs$source_id, "|run:", run) %in% key), any(paste0("run:", run, "|artifact:", art) == key))
  stopifnot(any(grepl("^external_source:", wb_kg_provenance_graph(b)$nodes$id)))
  wb_close_bundle(b); before <- file.info(file.path(root, "db", "app.sqlite"))$mtime
  ro <- wb_open_bundle(root, read_only=TRUE, validate=TRUE)
  on.exit(try(wb_close_bundle(ro), silent=TRUE), add=TRUE)
  stopifnot(isTRUE(ro$read_only), nrow(wb_matrices(ro))==1L, nrow(wb_art_list(ro))>=1L, nrow(wb_prov_source_inputs(ro))==2L,
            nrow(wb_prov_bundle_dag(ro)$nodes)>0L, !inherits(try(wb_art_load(ro, art), silent=TRUE), "try-error"),
            inherits(try(wb_session_run_op(wb_session_new(), ro, "hvg_select", inputs=list(matrix="RNA_counts", n_features=2L)), silent=TRUE), "try-error"))
  wb_close_bundle(ro); stopifnot(identical(before, file.info(file.path(root, "db", "app.sqlite"))$mtime))
  TRUE
}
