.typed_cell_set_copy_bundle <- function(from, to) {
  fs::dir_copy(from, to)
  to
}

.typed_cell_set_report_codes <- function(path) {
  report <- wb_bundle_validation_report(path, level = "content")
  as.character(report$diagnostics$code)
}

test_typed_cell_set_consumption_provenance_contract <- function() {
  contract_test_activate_core_conformance_pack()
  if (!requireNamespace("BPCells", quietly=TRUE)) {
    return(contract_test_skip("BPCells is not installed."))
  }
  root <- tempfile("typed_cell_set_source_")
  replay_root <- tempfile("typed_cell_set_replay_")
  target_root <- tempfile("typed_cell_set_target_")
  drift_root <- tempfile("typed_cell_set_drift_")
  mutants_root <- tempfile("typed_cell_set_mutants_")
  dir.create(mutants_root,recursive=TRUE)
  on.exit(unlink(c(root,replay_root,target_root,drift_root,mutants_root),recursive=TRUE,force=TRUE),add=TRUE)

  b <- wb_init_bundle(root,overwrite=TRUE)
  cells <- paste0("c",seq_len(12L))
  wb_define_cells(b,cells,metadata=data.frame(cell_id=cells,dataset_id="fixture",stringsAsFactors=FALSE),dataset_id="fixture")
  counts <- Matrix::Matrix(matrix(seq_len(48L),nrow=4L,dimnames=list(paste0("g",1:4),cells)),sparse=TRUE)
  wb_attach_matrix(b,"RNA",counts,feature_type="gene")
  wb_attach_space(b,"latent",data.frame(cell_id=cells,d1=seq_along(cells),d2=rev(seq_along(cells)),d3=seq_along(cells)/2))
  .wb_with_mutation_context(bundle=b,route="ingestion",code={
    wb_cell_set_replace(b,"set:universe",cells[1:10],source="test")
    wb_cell_set_replace(b,"set:group_a",cells[1:5],source="test")
    wb_cell_set_replace(b,"set:group_b",cells[6:10],source="test")
    wb_cell_set_replace(b,"set:query",cells[1:2],source="test")
    wb_cell_set_replace(b,"set:candidates",cells[3:10],source="test")
  })
  wb_close_bundle(b)
  .typed_cell_set_copy_bundle(root,replay_root)
  .typed_cell_set_copy_bundle(root,target_root)
  .typed_cell_set_copy_bundle(root,drift_root)
  b <- wb_open_bundle(root)
  on.exit(try(wb_close_bundle(b),silent=TRUE),add=TRUE)

  de <- wb_session_run_op(wb_session_new(),b,"scwbv2reference::grouped_feature_table",inputs=list(
    matrix="RNA",cell_set="set:universe",left_cells="set:group_a",
    right_cells="set:group_b",min_cells=2L
  ))
  resolutions <- de$run$inputs$cell_set_resolutions
  by_role <- stats::setNames(resolutions,vapply(resolutions,`[[`,character(1),"binding_name"))
  stopifnot(setequal(names(by_role),c("cell_set","left_cells","right_cells")),
            identical(by_role$cell_set$effective_member_count,10L),
            identical(by_role$left_cells$effective_member_count,5L),
            identical(by_role$right_cells$effective_member_count,5L))
  de_promoted <- wb_session_promote_current(b,de$session,outputs="result",created_by="test")
  de_sid <- as.character(de_promoted$provenance_snapshot_id)
  de_artifact <- as.character(de_promoted$promoted$artifact_id[de_promoted$promoted$output=="result"])[1]

  persisted <- DBI::dbGetQuery(b$con,"SELECT * FROM prov_run_entity_bindings WHERE snapshot_id=? AND run_id=? AND entity_kind='cell_set' ORDER BY binding_name;",params=list(de_sid,de$run$run_id))
  stopifnot(identical(as.character(persisted$binding_name),c("cell_set","left_cells","right_cells")),
            identical(as.character(persisted$entity_id),c("set:universe","set:group_a","set:group_b")),
            all(persisted$relationship_type=="CONSUMES"),
            identical(as.integer(persisted$effective_member_count),c(10L,5L,5L)),
            all(grepl("^[0-9a-f]{64}$",persisted$source_membership_sha256)),
            all(grepl("^[0-9a-f]{64}$",persisted$effective_membership_sha256)))

  details <- wb_prov_run_details(b,de$run$run_id,de_sid)
  stopifnot(all(c("cell_set","left_cells","right_cells") %in% details$entity_bindings$binding_name))
  graph <- wb_prov_bundle_dag(b,snapshot_id=de_sid)
  wanted <- data.frame(from=c("cell_set:set:universe","cell_set:set:group_a","cell_set:set:group_b"),label=c("cell_set","left_cells","right_cells"),stringsAsFactors=FALSE)
  for (i in seq_len(nrow(wanted))) stopifnot(any(graph$edges$from==wanted$from[i] & graph$edges$to==paste0("run:",de$run$run_id) & graph$edges$edge_type=="CONSUMES" & graph$edges$label==wanted$label[i]))
  artifact_lineage <- wb_prov_artifact_lineage(b,de_artifact,direction="upstream")
  stopifnot(all(wanted$from %in% artifact_lineage$nodes$id))
  run_cert <- wb_entity_certificate(b,"run",de$run$run_id)
  set_cert <- wb_entity_certificate(b,"cell_set","set:group_a")
  stopifnot(all(c("cell_set","left_cells","right_cells") %in% vapply(run_cert$details$entity_bindings$items,function(x) as.character(x$binding_name %||% ""),character(1))),
            identical(set_cert$identity$verification_status,"content_verified"),
            any(vapply(set_cert$relationships$immediate_outputs$items,function(x) identical(x$binding,"left_cells"),logical(1))))

  wb_close_bundle(b); b <- wb_open_bundle(root,read_only=TRUE)
  stopifnot(nrow(wb_prov_run_details(b,de$run$run_id,de_sid)$entity_bindings)>=4L)
  wb_close_bundle(b); b <- wb_open_bundle(root)

  replay_bundle <- wb_open_bundle(replay_root)
  replay <- wb_prov_validate_replay(b,snapshot_id=de_sid,profile="strict",strict=TRUE,destination_bundle=replay_bundle)
  stopifnot(all(replay$per_run$status=="ok"))
  wb_close_bundle(replay_bundle)
  plan <- wb_target_reproduction_plan(b,paste0("artifact:",de_artifact))
  stopifnot(identical(plan$status,"ok"),all(c("set:universe","set:group_a","set:group_b") %in% plan$boundary_prerequisites$entity_id))
  target <- wb_target_execute_plan(plan,target_root)
  stopifnot(identical(target$status,"promoted_and_verified"))

  drift <- wb_open_bundle(drift_root)
  DBI::dbExecute(drift$con,"DELETE FROM cell_set_membership WHERE cell_set='set:group_a' AND cell_id='c1';")
  non_strict_replay <- wb_prov_validate_replay(
    b,snapshot_id=de_sid,profile="strict",strict=FALSE,destination_bundle=drift
  )
  stopifnot(any(non_strict_replay$per_run$status=="error"),
            any(grepl("CELL_SET_RESOLUTION_MISMATCH",non_strict_replay$per_run$error,fixed=TRUE)))
  replay_error <- tryCatch({
    wb_prov_validate_replay(b,snapshot_id=de_sid,profile="strict",strict=TRUE,destination_bundle=drift)
    NULL
  },error=identity)
  stopifnot(inherits(replay_error,"wb_cell_set_resolution_error"),
            identical(as.character(replay_error$code),"CELL_SET_RESOLUTION_MISMATCH"))
  wb_close_bundle(drift)
  before <- .wb_prov_sha256_object(as.list(file.info(list.files(drift_root,recursive=TRUE,full.names=TRUE))[,c("size","mtime")]))
  drift_error <- try(wb_target_execute_plan(plan,drift_root),silent=TRUE)
  after <- .wb_prov_sha256_object(as.list(file.info(list.files(drift_root,recursive=TRUE,full.names=TRUE))[,c("size","mtime")]))
  stopifnot(inherits(drift_error,"try-error"),grepl("CELL_SET_RESOLUTION_MISMATCH|membership|identity mismatch",as.character(drift_error),ignore.case=TRUE),identical(before,after))

  # The merged catalog, including loaded pack definitions, is the sole source
  # of named-set-capable parameter discovery.
  catalog <- .wb_operation_catalog()
  audited <- list()
  for (op_name in names(catalog)) {
    params <- catalog[[op_name]]$params %||% list()
    capable <- params[vapply(params,function(x) as.character(x$type %||% "") %in% c("cell_set","cell_ids_or_set","list_or_cell_set"),logical(1))]
    if (!length(capable)) next
    expected <- character(0)
    for (param in capable) {
      nm <- as.character(param$name); tp <- as.character(param$type)
      sample_inputs <- list(cell_set="all")
      if (identical(nm,"cell_set")) sample_inputs$cell_set <- "set:universe"
      else if (identical(tp,"list_or_cell_set")) sample_inputs[[nm]] <- list(cell_set="set:group_a")
      else sample_inputs[[nm]] <- "set:group_a"
      observed <- vapply(.wb_named_cell_set_selectors(b,op_name,sample_inputs),`[[`,character(1),"binding_name")
      stopifnot(nm %in% observed)
      expected <- c(expected,nm)
    }
    audited[[op_name]] <- unique(expected)
  }
  stopifnot(all(c("scwbv2reference::grouped_feature_table",
    "trajectory_space_path_segment") %in% names(audited)))
  explicit_endpoint <- .wb_named_cell_set_selectors(b,"trajectory_space_path_segment",list(
    cell_set="all",start_endpoint=list(x=0,y=0,cell_set="set:group_a"),
    start_cell_set="set:group_b"
  ))
  stopifnot(!any(vapply(explicit_endpoint,function(x) x$binding_name %in% c("start_endpoint","start_cell_set"),logical(1))))
  overridden_endpoint <- .wb_named_cell_set_selectors(b,"trajectory_space_path_segment",list(
    cell_set="all",start_endpoint="set:group_a",start_cell_set="set:group_b"
  ))
  stopifnot(identical(vapply(overridden_endpoint,`[[`,character(1),"binding_name"),"start_cell_set"))

  wb_close_bundle(b); b <- NULL
  make_mutant <- function(name,sql,params=list()) {
    path <- file.path(mutants_root,name); .typed_cell_set_copy_bundle(root,path)
    x <- wb_open_bundle(path); if(length(params)) DBI::dbExecute(x$con,sql,params=params) else DBI::dbExecute(x$con,sql); wb_close_bundle(x); path
  }
  q <- list(de_sid,de$run$run_id)
  missing <- make_mutant("missing","DELETE FROM prov_run_entity_bindings WHERE snapshot_id=? AND run_id=? AND binding_name='left_cells' AND entity_kind='cell_set';",q)
  wrong_role <- make_mutant("wrong_role","UPDATE prov_run_entity_bindings SET binding_name='wrong_role' WHERE snapshot_id=? AND run_id=? AND binding_name='left_cells' AND entity_kind='cell_set';",q)
  wrong_set <- make_mutant("wrong_set","UPDATE prov_run_entity_bindings SET entity_id='set:group_b' WHERE snapshot_id=? AND run_id=? AND binding_name='left_cells' AND entity_kind='cell_set';",q)
  identity <- make_mutant("identity","UPDATE prov_run_entity_bindings SET source_membership_sha256=? WHERE snapshot_id=? AND run_id=? AND binding_name='left_cells' AND entity_kind='cell_set';",c(list(paste(rep("0",64),collapse="")),q))
  dangling <- make_mutant("dangling","DELETE FROM cell_set_membership WHERE cell_set='set:group_a';")
  fabricated <- make_mutant("fabricated","INSERT INTO prov_run_entity_bindings(snapshot_id,commit_id,run_id,direction,binding_name,entity_kind,entity_id,relationship_type,path,content_hash,source,content_identity_scheme) SELECT snapshot_id,commit_id,run_id,direction,'fabricated_role',entity_kind,entity_id,relationship_type,path,content_hash,source,content_identity_scheme FROM prov_run_entity_bindings WHERE snapshot_id=? AND run_id=? AND binding_name='left_cells' AND entity_kind='cell_set';",q)
  stale <- make_mutant("stale","UPDATE prov_run_entity_bindings SET content_hash=? WHERE snapshot_id=? AND run_id=? AND binding_name='left_cells' AND entity_kind='cell_set';",c(list(paste(rep("f",64),collapse="")),q))
  stopifnot("RUN_NAMED_CELL_SET_BINDING_MISSING" %in% .typed_cell_set_report_codes(missing),
            "RUN_NAMED_CELL_SET_BINDING_ROLE_MISMATCH" %in% .typed_cell_set_report_codes(wrong_role),
            "RUN_NAMED_CELL_SET_BINDING_SET_MISMATCH" %in% .typed_cell_set_report_codes(wrong_set),
            "RUN_NAMED_CELL_SET_MEMBERSHIP_IDENTITY_MISMATCH" %in% .typed_cell_set_report_codes(identity),
            "RUN_NAMED_CELL_SET_BINDING_DANGLING" %in% .typed_cell_set_report_codes(dangling),
            "RUN_NAMED_CELL_SET_BINDING_FABRICATED" %in% .typed_cell_set_report_codes(fabricated),
            "RUN_NAMED_CELL_SET_STALE_RESOLUTION" %in% .typed_cell_set_report_codes(stale))
  TRUE
}
