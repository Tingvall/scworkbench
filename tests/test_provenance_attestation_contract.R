test_provenance_attestation_contract <- function() {
  required <- c("BPCells", "Matrix")
  missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing)) {
    return(contract_test_skip(paste("Missing runtime dependencies:", paste(missing, collapse = ", "))))
  }
  old_sha <- Sys.getenv("SCWORKBENCH_RUNTIME_IMAGE_SHA256", unset = NA_character_)
  on.exit(if (is.na(old_sha)) Sys.unsetenv("SCWORKBENCH_RUNTIME_IMAGE_SHA256") else Sys.setenv(SCWORKBENCH_RUNTIME_IMAGE_SHA256 = old_sha), add = TRUE)
  Sys.setenv(SCWORKBENCH_RUNTIME_IMAGE_SHA256 = "abc123recipientdigest")
  root <- tempfile("scwb_attestation_")
  b <- wb_init_bundle(root, overwrite = TRUE)
  on.exit({ try(wb_close_bundle(b), silent = TRUE); unlink(root, recursive = TRUE, force = TRUE) }, add = TRUE)
  ids <- paste0("c", 1:4); feats <- paste0("g", 1:3)
  counts <- matrix(c(1,2,0,3, 2,0,1,1, 0,1,3,2), nrow=3, dimnames=list(feats,ids))
  wb_ingest_apply(b, "core", matrices=list(RNA_counts=counts), emit_report_artifact=TRUE,
    source_identity=list(uri="doi:10.1234/example", dataset_name="recipient fixture", checksum_algorithm="sha256", checksum="deadbeef", source_object="filtered_feature_bc_matrix", organism="Homo sapiens", genome="hg38", assay="RNA", metadata=list(release="v1")))
  src <- wb_prov_source_identity(b, "RNA_counts")
  stopifnot(nrow(src) == 1L, identical(as.character(src$status), "available"), grepl("10.1234/example", src$source_identity_json, fixed=TRUE))
  source_record <- list(uri="doi:10.1234/example", dataset_name="recipient fixture", checksum_algorithm="sha256", checksum="deadbeef", source_object="filtered_feature_bc_matrix", organism="Homo sapiens", genome="hg38", assay="RNA", metadata=list(release="v1"))
  .wb_prov_record_source_identity(b, src$snapshot_id[1], src$run_id[1], "RNA_counts", source_record)
  conflicting <- try(.wb_prov_record_source_identity(b, src$snapshot_id[1], src$run_id[1], "RNA_counts", utils::modifyList(source_record, list(checksum="different"))), silent=TRUE)
  stopifnot(inherits(conflicting, "try-error"), identical(wb_prov_source_identity(b, "RNA_counts")$source_identity_json, src$source_identity_json))
  rr <- wb_session_run_op(wb_session_new(), b, "matrix_log_normalize", inputs=list(matrix="RNA_counts", output_matrix_id="RNA_log", scale_factor=5000, min_cells=1L))
  before_bad <- nrow(wb_art_list(b))
  bad_materialization <- try(wb_session_promote_current(b, rr$session, outputs="matrix"), silent=TRUE)
  stopifnot(inherits(bad_materialization, "try-error"), grepl("durability_role=materialization", as.character(bad_materialization)), grepl("summary", as.character(bad_materialization)), nrow(wb_art_list(b)) == before_bad)
  promoted <- wb_session_promote_current(b, rr$session, outputs="summary")
  sid <- as.character(promoted$provenance_snapshot_id)
  detail <- wb_prov_run_details(b, rr$run$run_id, sid)
  stopifnot(identical(as.character(detail$run$runtime_fingerprint$image$status), "bound"),
            identical(as.character(detail$run$runtime_fingerprint$image$sha256), "abc123recipientdigest"),
            identical(as.character(detail$run$contract$interface$semantics$transform), "log1p(count / cell_library_size * scale_factor)"),
            identical(as.numeric(detail$run$contract$parameters$scale_factor), 5000),
            identical(as.character(detail$run$operation_version), "1"), nzchar(as.character(detail$run$contract_hash)),
            identical(as.character(detail$run$contract$interface$produces$matrix$durability_role), "materialization"),
            identical(as.character(detail$run$contract$interface$promotion_terminals), "summary"))
  Sys.unsetenv("SCWORKBENCH_RUNTIME_IMAGE_SHA256")
  rr2 <- wb_session_run_op(wb_session_new(), b, "hvg_select", inputs=list(matrix="RNA_counts", n_features=2L, min_cells=1L))
  p2 <- wb_session_promote_current(b, rr2$session, outputs="selected_features")
  d2 <- wb_prov_run_details(b, rr2$run$run_id, p2$provenance_snapshot_id)
  stopifnot(identical(as.character(d2$run$runtime_fingerprint$image$status), "unavailable"))
  legacy <- wb_init_bundle(tempfile("scwb_legacy_"), overwrite=TRUE)
  on.exit(try(wb_close_bundle(legacy), silent=TRUE), add=TRUE)
  stopifnot(nrow(wb_prov_source_identity(legacy)) == 0L)
  TRUE
}
