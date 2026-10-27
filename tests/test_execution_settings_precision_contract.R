.settings_precision_values <- function() c(0.123456789, 0.049999999999999996,
  0.05000000000000001, pi, 1e-300, .Machine$double.xmax,
  .Machine$double.xmin, 5e-324, -0.0, 1.0)

.settings_precision_bundle <- function(root) {
  b <- wb_init_bundle(root)
  cells <- paste0("c", 1:4); wb_define_cells(b, cells)
  mat <- Matrix::Matrix(matrix(1:8, nrow = 2,
    dimnames = list(c("g1", "g2"), cells)), sparse = TRUE)
  wb_attach_matrix(b, "source", mat, feature_type = "gene")
  wb_attach_matrix(b, "target", mat[1, , drop = FALSE], feature_type = "gene")
  wb_feature_set_replace(b, "SET_A", "source", c("g1", "g2"),
    namespace = "precision", strict = TRUE)
  b
}

.settings_precision_inputs <- function(value) list(source_matrix = "source",
  target_matrix = "target", namespace = "precision", target_namespace = "copy",
  mode = "intersect", min_retained_features = 1L, min_retained_fraction = value,
  strict = FALSE, overwrite = TRUE, cell_set = "all", min_cells = 1L)

test_execution_settings_numeric_and_legacy_bytes_contract <- function() {
  values <- .settings_precision_values()
  value <- list(values = values, integer = 1L, double = 1.0,
    logical = TRUE, text = "NA", absent = NULL)
  text <- scworkbench:::.wb_execution_settings_json(value)
  observed <- jsonlite::fromJSON(text, simplifyVector = TRUE)
  stopifnot(identical(writeBin(values, raw(), size = 8),
    writeBin(observed$values, raw(), size = 8)), is.integer(observed$integer),
    is.double(observed$double), identical(observed$logical, TRUE),
    identical(observed$text, "NA"), is.null(observed$absent))
  run <- wb_new_run("metadata_cell_vector", params = list(values = values))
  provenance <- jsonlite::fromJSON(scworkbench:::.wb_prov_json(run, list(),
    primitive_payload = list(meta = list(values = values))))
  stopifnot(identical(writeBin(provenance$params$values, raw(), size = 8),
    writeBin(values, raw(), size = 8)),
    identical(writeBin(provenance$primitive_payload$meta$values, raw(), size = 8),
      writeBin(values, raw(), size = 8)))
  pretty <- scworkbench:::.wb_emit_r_object_assign("value", value)
  env <- new.env(parent = baseenv()); eval(parse(text = pretty), env)
  stopifnot(identical(writeBin(values, raw(), size = 8),
    writeBin(env$value$values, raw(), size = 8)))
  legacy <- jsonlite::read_json("tests/fixtures/execution_settings_legacy_1_10.json")$row
  stopifnot(identical(scworkbench:::.wb_prov_run_hash(legacy$op_name,
    legacy$params_json, legacy$inputs_json, legacy$symbolic_inputs_json,
    legacy$execution_inputs_json, scheme = legacy$run_hash_scheme), legacy$run_hash),
    identical(scworkbench:::.wb_prov_contract_hash(legacy$contract_json,
      scheme = legacy$contract_hash_scheme), legacy$contract_hash),
    identical(jsonlite::fromJSON(legacy$params_json)$min_retained_fraction, 0.5))
  TRUE
}

test_execution_settings_public_persist_reopen_replay_script_contract <- function() {
  root <- tempfile("settings_precision_"); b <- .settings_precision_bundle(root)
  parent <- tempfile("settings_precision_copy_"); dir.create(parent)
  on.exit({try(wb_close_bundle(b), silent = TRUE);unlink(c(root,parent),recursive=TRUE)}, add=TRUE)
  wb_close_bundle(b);stopifnot(file.copy(root,parent,recursive=TRUE));b<-wb_open_bundle(root)
  value <- 0.5000000000000001
  inputs <- .settings_precision_inputs(value)
  run <- wb_session_run_op(wb_session_new(), b, "feature_set_namespace_transfer", inputs=inputs)
  stopifnot(nrow(run$run$outputs$transfer_rejected$table)==1L)
  promoted <- wb_session_promote_current(b,run$session,
    outputs=c("transfer_summary","transfer_manifest","transfer_rejected"))
  sid<-promoted$provenance_snapshot_id;rid<-run$run$run_id
  wb_close_bundle(b);b<-wb_open_bundle(root)
  details<-wb_prov_run_details(b,rid,sid);spec<-wb_prov_run_replay_inputs(b,rid,sid)
  stopifnot(identical(details$run$params$min_retained_fraction,value),
    identical(details$run$inputs$user_inputs$min_retained_fraction,value),
    identical(details$run$symbolic_inputs$min_retained_fraction,value),
    identical(details$run$contract$parameters$min_retained_fraction,value),
    identical(spec$inputs$min_retained_fraction,value))
  artifacts<-wb_art_list(b,include_provenance=TRUE)
  for(text in artifacts$provenance_json){
    prov<-jsonlite::fromJSON(text,simplifyVector=FALSE)
    stopifnot(identical(prov$params$min_retained_fraction,value),
      identical(prov$execution_settings_encoding,scworkbench:::.wb_execution_settings_encoding()))
  }
  child<-file.path(parent,"fresh.R");observed<-file.path(parent,"fresh.rds")
  library<-dirname(find.package("scworkbench"))
  writeLines(c("args<-commandArgs(TRUE);.libPaths(c(args[1],.libPaths()));library(scworkbench)",
    "b<-wb_open_bundle(args[2],read_only=TRUE)",
    "spec<-wb_prov_run_replay_inputs(b,args[3],args[4])",
    "saveRDS(spec$inputs$min_retained_fraction,args[5]);wb_close_bundle(b)"),child)
  stopifnot(wb_finalize_recipient_bundle(b)$ready)
  wb_close_bundle(b)
  status<-system2(file.path(R.home("bin"),"Rscript"),vapply(c(child,library,root,rid,sid,observed),shQuote,""))
  stopifnot(status==0L,identical(readRDS(observed),value))
  b<-wb_open_bundle(root)
  replay<-wb_prov_validate_replay(b,sid,profile="strict",strict=TRUE)
  stopifnot(isTRUE(replay$summary$valid),all(replay$per_output$output_match))
  for(mode in c("symbolic","literal")) for(style in c("bench_pretty","raw_json")){
    sidecar<-file.path(parent,paste0(mode,style,".rds"))
    script<-wb_prov_emit_r_script(b,sid,bundle_dir_literal=file.path(parent,basename(root)),
      mode=mode,style=style,sidecar_rds_path=sidecar)
    env<-new.env(parent=globalenv());eval(parse(text=script),env)
    stopifnot(identical(env$res$run$inputs$user_inputs$min_retained_fraction,value),
      nrow(env$res$run$outputs$transfer_rejected$table)==1L)
    wb_session_discard(env$sess);wb_close_bundle(env$bundle)
  }
  # A threshold-neighbour contradiction must be visible in new records even
  # though the historical portable-object preimage rounds both values alike.
  row<-DBI::dbGetQuery(b$con,"SELECT * FROM prov_runs WHERE snapshot_id=? AND run_id=?",params=list(sid,rid))
  changed<-jsonlite::fromJSON(row$params_json);changed$min_retained_fraction<-0.5
  text<-as.character(scworkbench:::.wb_execution_settings_json(changed))
  hash<-scworkbench:::.wb_prov_run_hash(row$op_name,text,row$inputs_json,row$symbolic_inputs_json,row$execution_inputs_json)
  DBI::dbExecute(b$con,"UPDATE prov_runs SET params_json=?,run_hash=? WHERE snapshot_id=? AND run_id=?",params=list(text,hash,sid,rid))
  wb_close_bundle(b)
  report<-wb_bundle_validation_report(root,"content")
  stopifnot(!report$ok,"RUN_CONTRACT_PARAMETERS_MISMATCH" %in% report$diagnostics$code)
  b<-wb_open_bundle(root,validate=FALSE)
  DBI::dbExecute(b$con,"UPDATE prov_runs SET params_json=?,run_hash=? WHERE snapshot_id=? AND run_id=?",params=list(row$params_json,row$run_hash,sid,rid))
  for(bad in list(NA_real_,NaN,Inf,-Inf)){
    failure<-try(wb_session_run_op(wb_session_new(),b,"feature_set_namespace_transfer",inputs=.settings_precision_inputs(bad)),silent=TRUE)
    stopifnot(inherits(failure,"try-error"))
  }
  TRUE
}

test_execution_settings_actual_python_boundary_contract <- function() {
  python<-Sys.getenv("PYBENCH_PARITY_PYTHON","")
  manifest<-Sys.getenv("SCWORKBENCH_PYTHON_PACK_MANIFEST","")
  stopifnot(file.exists(python),file.exists(manifest))
  wb_operation_pack_activate(manifest,python=python,timeout_seconds=60)
  root<-tempfile("settings_python_");b<-wb_init_bundle(root)
  on.exit({try(wb_close_bundle(b),silent=TRUE);unlink(root,recursive=TRUE)},add=TRUE)
  cells<-paste0("c",1:4);wb_define_cells(b,cells,metadata=data.frame(cell_id=cells,signal=as.numeric(1:4)))
  first<-wb_session_run_op(wb_session_new(),b,"metadata_cell_vector",inputs=list(source_column="signal",vector_name="signal",value_type="continuous",cell_set="all",min_cells=1L))
  scale<-0.049999999999999996
  run<-wb_session_run_op(first$session,b,"scwbpython::affine_cell_vector",inputs=list(signal=wb_ref_run(first$run$run_id,"vector"),scale=scale,cell_set="all",min_cells=1L))
  # The actual Python runner emits its executed numeric parameter in summary.
  stopifnot(identical(writeBin(run$run$outputs$summary$table$scale,raw(),size=8),
    writeBin(scale,raw(),size=8)))
  promoted<-wb_session_promote_current(b,run$session,outputs=c("vector","summary"))
  details<-wb_prov_run_details(b,run$run$run_id,promoted$provenance_snapshot_id)
  stopifnot(identical(details$run$params$scale,scale),identical(details$run$inputs$user_inputs$scale,scale))
  # Exercise the actual Python artifact-provenance consumer, not JSON alone.
  id<-promoted$promoted$artifact_id[promoted$promoted$output=="summary"]
  code<-paste("import sys,json,struct;from pybench.bundle import open_bundle,close_bundle;from pybench.getters import art_get_row,artifact_table;",
    "b=open_bundle(sys.argv[1]);p=json.loads(art_get_row(b,sys.argv[2])['provenance_json']);artifact_table(b,sys.argv[2]);",
    "assert struct.pack('d',p['params']['scale'])==struct.pack('d',0.049999999999999996);close_bundle(b)")
  stopifnot(wb_finalize_recipient_bundle(b)$ready)
  wb_close_bundle(b)
  status<-system2(python,c("-c",shQuote(code),shQuote(root),shQuote(id)))
  stopifnot(status==0L)
  TRUE
}

test_execution_settings_atomic_transport_python_readback_contract <- function() {
  python <- Sys.getenv("PYBENCH_PARITY_PYTHON", "");stopifnot(file.exists(python))
  root <- tempfile("settings_transport_");b <- wb_init_bundle(root)
  path <- tempfile(fileext=".json")
  on.exit({try(wb_close_bundle(b),silent=TRUE);unlink(c(root,path),recursive=TRUE)},add=TRUE)
  wb_define_cells(b,c("c1","c2"))
  request <- scworkbench:::.wb_pybench_build_request(b,"py_protocol_hello","settings_probe",
    inputs=list(cell_set="all"),params=list(values=.settings_precision_values(),integer=1L,double=1.0),
    outputs=list(summary=list(type="obs_table",artifact_id="settings_summary")),mode="read_only")
  scworkbench:::.wb_operation_pack_v2_atomic_json(request,path)
  code <- paste("import sys,math;from pybench.protocol import load_request;",
    "r=load_request(sys.argv[1]);p=r['params'];v=p['values'];",
    "assert v[1].hex()==(0.049999999999999996).hex();assert v[2].hex()==(0.05000000000000001).hex();",
    "assert v[5]==sys.float_info.max and v[6]==sys.float_info.min;assert v[7]==float.fromhex('0x0.0000000000001p-1022');",
    "assert math.copysign(1,v[8])==-1;assert type(p['integer']) is int and type(p['double']) is float")
  status <- system2(python,c("-c",shQuote(code),shQuote(path)))
  stopifnot(status==0L)
  TRUE
}
