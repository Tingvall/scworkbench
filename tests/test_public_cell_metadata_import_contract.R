.metadata_import_source <- function(path, source_id, format) {
  wb_source_input(
    path = path, source_id = source_id, accession = paste0("fixture-", source_id),
    role = "cell_metadata", format = format, scope = "external_file"
  )
}

test_public_cell_metadata_import_contract <- function() {
  root <- tempfile("scwb_metadata_import_")
  work <- tempfile("scwb_metadata_source_"); dir.create(work)
  b <- wb_init_bundle(root, overwrite = TRUE)
  on.exit({ try(wb_close_bundle(b), silent=TRUE); unlink(c(root,work),recursive=TRUE,force=TRUE) }, add=TRUE)
  cells <- paste0("cell_", seq_len(8L)); wb_define_cells(b, cells)

  csv <- file.path(work, "metadata.csv")
  writeLines(c(
    "score,label,cell_key,count,pass",
    "0.8,B,cell_5,5,TRUE", "0.1,A,cell_1,1,FALSE",
    "0.3,B,cell_3,3,TRUE", "0.9,A,cell_7,7,TRUE",
    "0.2,A,cell_2,2,FALSE", "0.4,B,cell_4,4,TRUE",
    "0.5,A,cell_6,6,FALSE", "0.6,,cell_8,8,TRUE"
  ), csv)
  csv_source <- .metadata_import_source(csv, "csv_metadata", "csv")
  plan <- wb_metadata_import(
    b, csv, cell_id_col="cell_key", source_identity=csv_source,
    fields=c("label","score","count","pass"), validate_only=TRUE
  )
  stopifnot(
    inherits(plan,"wb_metadata_import_plan"), identical(plan$input,"metadata.csv"),
    identical(plan$selected_fields,c("label","score","count","pass")),
    identical(plan$counts,list(supplied=8L,matched=8L,unknown=0L,rejected=0L,unsupplied_known=0L)),
    identical(plan$fields$storage_type,c("TEXT","REAL","INTEGER","INTEGER")),
    identical(plan$fields$source_type,c("character","double","integer","logical"))
  )
  result <- wb_metadata_import(
    b, csv, cell_id_col="cell_key", source_identity=csv_source,
    fields=c("label","score","count","pass"), created_by="contract"
  )
  stopifnot(
    inherits(result,"wb_metadata_import_result"), result$source_sha256==wb_source_sha256(csv),
    identical(result$fields$source_name,c("label","score","count","pass")),
    all(result$fields$action=="create"), nzchar(result$report_artifact_id)
  )
  stable_ids <- result$fields$field_id
  values <- wb_meta(b,cells=c("cell_1","cell_3","cell_5","cell_7","cell_8"),
                    cols=c(list(wb_ref_metadata_field("core:cell_id")),lapply(stable_ids,wb_ref_metadata_field)))
  stopifnot(
    identical(as.character(values[[1L]]),c("cell_1","cell_3","cell_5","cell_7","cell_8")),
    identical(as.character(values[[2L]]),c("A","B","B","A",NA_character_)),
    isTRUE(all.equal(as.numeric(values[[3L]]),c(0.1,0.3,0.8,0.9,0.6))), is.na(values[[2L]][5L]),
    identical(as.integer(values[[4L]][1:4]),c(1L,3L,5L,7L)),
    identical(as.integer(values[[5L]][1:4]),c(0L,1L,1L,1L))
  )
  evidence <- wb_art_load(b,result$report_artifact_id,expected_kind="obs_table")
  stopifnot(
    evidence$table_type=="cell_metadata_import_evidence",
    evidence$meta$checksum_status=="verified_sha256",
    evidence$meta$assurance$values=="externally_supplied",
    evidence$meta$assurance$upstream_derivation=="not_engine_observed",
    identical(evidence$meta$counts$unsupplied_known,0L), nrow(evidence$table)==4L
  )

  tsv <- file.path(work,"metadata.tsv")
  writeLines(c("status\tcell_key", "kept\tcell_8", "kept\tcell_2"),tsv)
  tsv_result <- wb_metadata_import(
    b,tsv,"cell_key",.metadata_import_source(tsv,"tsv_metadata","tsv")
  )
  stopifnot(tsv_result$fields$source_name=="status",tsv_result$fields$storage_type=="TEXT")

  update <- file.path(work,"update.csv")
  writeLines(c("cell_key,relabel","cell_1,Z","cell_7,Y"),update)
  updated <- wb_metadata_import(
    b,update,"cell_key",.metadata_import_source(update,"update_metadata","csv"),
    fields="relabel",field_refs=list(wb_ref_metadata_field(stable_ids[[1L]]))
  )
  stopifnot(updated$fields$field_id==stable_ids[[1L]],updated$fields$action=="compatible_update")
  stopifnot(identical(
    as.character(wb_meta(b,cells=c("cell_1","cell_7"),cols=list(wb_ref_metadata_field("core:cell_id"),wb_ref_metadata_field(stable_ids[[1L]])))[[2L]]),
    c("Z","Y")
  ))

  stopifnot(identical(wb_metadata_fields(b,FALSE)$field_id,c(stable_ids,tsv_result$fields$field_id)))
  source_cert <- wb_entity_certificate(b,"external_source",result$source_id)
  field_cert <- wb_entity_certificate(b,"metadata_field",stable_ids[[2L]])
  updated_field_cert <- wb_entity_certificate(b,"metadata_field",stable_ids[[1L]])
  stopifnot(
    source_cert$details$checksum$value==result$source_sha256,
    field_cert$producer$status=="available",
    updated_field_cert$producer$status=="available",length(updated_field_cert$producer$history)==2L,
    field_cert$details$assurance$upstream_derivation=="not_engine_observed"
  )
  graph <- wb_prov_bundle_dag(b)
  stopifnot(
    any(graph$edges$from==paste0("external_source:",result$source_id) & graph$edges$to==paste0("run:",result$run_id) & graph$edges$edge_type=="CONSUMES"),
    any(graph$edges$from==paste0("run:",result$run_id) & graph$edges$to==paste0("metadata_field:",stable_ids[[2L]]) & graph$edges$edge_type=="PRODUCES")
  )

  vector_run <- wb_session_run_op(
    wb_session_new(),b,"metadata_cell_vector",
    inputs=list(source_column=wb_ref_metadata_field(stable_ids[[2L]]),vector_name="imported_score",
                value_type="continuous",missing_policy="drop",cell_set="all",min_cells=1L)
  )
  promoted <- wb_session_promote_current(b,vector_run$session,outputs="vector",created_by="contract")
  vector_artifact <- as.character(promoted$promoted$artifact_id[[1L]])
  selected <- wb_sel_vector(b,vector_id=paste0("artifact:",vector_artifact),min=0.5)
  derived <- wb_cell_set_derive(
    b,"set:imported_high",selected,role="analysis_universe",status="accepted",
    created_by="contract",promote_manifest=TRUE
  )
  downstream <- wb_session_run_op(
    wb_session_new(),b,"metadata_cell_vector",
    inputs=list(source_column=wb_ref_metadata_field(stable_ids[[1L]]),
                vector_name="imported_label",value_type="categorical",
                missing_policy="drop",cell_set="set:imported_high",min_cells=1L)
  )
  stopifnot(length(wb_cells(b,"set:imported_high"))>=1L,
            length(downstream$run$outputs$vector$cell_id)>=1L)
  graph2 <- wb_prov_bundle_dag(b)
  stopifnot(
    any(graph2$edges$from==paste0("metadata_field:",stable_ids[[2L]]) & graph2$edges$to==paste0("run:",vector_run$run$run_id)),
    any(graph2$edges$from==paste0("artifact:",vector_artifact) & graph2$edges$edge_type=="SELECTS_FOR" & graph2$edges$to=="cell_set:set:imported_high")
  )
  wb_close_bundle(b); b<-wb_open_bundle(root)
  stopifnot(identical(wb_metadata_fields(b,FALSE)$field_id,c(stable_ids,tsv_result$fields$field_id)),
            identical(sort(wb_cells(b,"set:imported_high")),sort(as.character(selected))))
  TRUE
}
