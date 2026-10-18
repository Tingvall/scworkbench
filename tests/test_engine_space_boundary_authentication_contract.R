.engine_space_auth_fixture <- function() {
  root <- tempfile("engine_space_auth_"); b <- wb_init_bundle(root)
  cells <- paste0("c",seq_len(33L));wb_define_cells(b,cells)
  values <- matrix(as.double(seq_len(99L)),33L,dimnames=list(cells,c("A","B","C")))
  wb_add_space(b,"source",values)
  list(root=root,b=b,cells=cells,values=values)
}

.engine_space_auth_request <- function(plan) {
  cells <- plan$cells[c(3L,1L)]
  record <- list(name="source",descriptor_identity=list(sha256="descriptor"),
    content_identity=list(sha256="content"))
  grant <- list(name="read_source",input_name="source",source_reference=list(
    space_id="source",selected_content_identity=list(sha256="semantic")),
    cells_axis=list(count=length(cells)))
  attr(grant,"operation_pack_v3_cells") <- cells
  request <- list(inputs=list(record),typed_space_grants=list(grant))
  attr(request,"operation_pack_v3_typed_space_values") <- list(read_source=list(
    cells=cells,input=list(space_id="source",cell_id=plan$cells,dimensions=plan$dimensions),
    issued_grant=grant,issued_input_record=list(record),plan=plan))
  request
}

test_engine_space_boundary_private_issuance_contract <- function() {
  f <- .engine_space_auth_fixture();b<-f$b
  plan <- scworkbench:::.wb_space_payload_reader(b,"source")
  on.exit({plan$close();wb_close_bundle(b);unlink(f$root,recursive=TRUE)},add=TRUE)
  authenticate <- scworkbench:::.wb_operation_pack_v3_native_space_sources_authenticate
  request <- .engine_space_auth_request(plan)
  stopifnot(identical(authenticate(b,request),"read_source"))
  for(field in c("source_reference","cells_axis","name")) {
    bad<-request;bad$typed_space_grants[[1]][[field]]<-list(rehashed="substitute")
    stopifnot(inherits(try(authenticate(b,bad),silent=TRUE),"try-error"))
  }
  bad<-request;bad$inputs[[1]]$content_identity<-list(sha256="self_rehashed")
  stopifnot(inherits(try(authenticate(b,bad),silent=TRUE),"try-error"))
  # No private native state means no exemption from the legacy semantic path.
  plain<-request;attr(plain,"operation_pack_v3_typed_space_values")<-NULL
  stopifnot(identical(authenticate(b,plain),character()),
    inherits(try(scworkbench:::.wb_operation_pack_v3_typed_slice_sources_assert_current(b,plain),
      silent=TRUE),"try-error"))
  TRUE
}

test_engine_space_boundary_actual_bytes_and_rows_contract <- function() {
  f <- .engine_space_auth_fixture();b<-f$b
  plan<-scworkbench:::.wb_space_payload_reader(b,"source")
  on.exit({plan$close();wb_close_bundle(b);unlink(f$root,recursive=TRUE)},add=TRUE)
  for(sql in c("UPDATE spaces SET source='changed'", "UPDATE spaces SET description='changed'",
      "UPDATE spaces SET storage='legacy'", "UPDATE spaces SET dims=4",
      "UPDATE space_payloads SET provenance_identity='changed'",
      "UPDATE space_payloads SET content_identity_scheme='changed'",
      "UPDATE cells SET cell_id='foreign' WHERE cell_id='c1'")) {
    DBI::dbBegin(b$con);DBI::dbExecute(b$con,sql)
    rejected<-inherits(try(plan$authenticate(b),silent=TRUE),"try-error")
    DBI::dbRollback(b$con);stopifnot(rejected)
  }
  row<-scworkbench:::.wb_space_payload_registry_row(b,"source")
  path<-scworkbench:::.wb_space_payload_path(b,row,must_exist=TRUE)
  backup<-tempfile();stopifnot(file.copy(path,backup))
  on.exit(unlink(backup),add=TRUE)
  rhdf5::h5write(999,path,"coordinates",index=list(1L,1L))
  DBI::dbExecute(b$con,"UPDATE space_payloads SET content_sha256=? WHERE space_id='source'",
    params=list(scworkbench:::.wb_prov_sha256_file(path)))
  # Even a self-rehashed current row cannot replace the original private SHA.
  stopifnot(inherits(try(plan$authenticate(b),silent=TRUE),"try-error"))
  stopifnot(file.copy(backup,path,overwrite=TRUE))
  DBI::dbExecute(b$con,"UPDATE space_payloads SET content_sha256=? WHERE space_id='source'",
    params=list(row$content_sha256[[1L]]))
  # File observational timestamps changed; the original guard also rejects.
  stopifnot(inherits(try(plan$authenticate(b),silent=TRUE),"try-error"))
  fresh<-scworkbench:::.wb_space_payload_reader(b,"source")
  tryCatch(stopifnot(isTRUE(fresh$authenticate(b))),finally=fresh$close())
  TRUE
}

test_engine_space_boundary_connection_and_storage_contract <- function() {
  f<-.engine_space_auth_fixture();b<-f$b
  plan<-scworkbench:::.wb_space_payload_reader(b,"source")
  other<-wb_open_bundle(f$root,validate=FALSE,read_only=TRUE)
  on.exit({plan$close();wb_close_bundle(other);wb_close_bundle(b);unlink(f$root,recursive=TRUE)},add=TRUE)
  stopifnot(inherits(try(plan$authenticate(other),silent=TRUE),"try-error"))
  DBI::dbBegin(b$con);DBI::dbExecute(b$con,"UPDATE spaces SET storage='table'")
  invalid<-try(scworkbench:::.wb_space_payload_reader(b,"source"),silent=TRUE)
  if(!inherits(invalid,"try-error")) invalid$close()
  DBI::dbRollback(b$con)
  stopifnot(inherits(invalid,"try-error"),isTRUE(plan$authenticate(b)))
  TRUE
}

test_engine_space_boundary_fresh_counts_and_release_contract <- function() {
  f<-.engine_space_auth_fixture();b<-f$b
  budget<-scworkbench:::.wb_operation_pack_v3_broker_projection_budget(b)
  plan<-scworkbench:::.wb_space_payload_reader(b,"source",.budget=budget)
  on.exit({plan$close();wb_close_bundle(b);unlink(f$root,recursive=TRUE)},add=TRUE)
  counter<-new.env(parent=emptyenv());counter$n<-0L
  saved<-options(scworkbench.space_auth_hash_counter=counter)
  on.exit(options(saved),add=TRUE)
  trace(".wb_prov_sha256_file",where=asNamespace("scworkbench"),print=FALSE,
    tracer=quote({.counter<-getOption("scworkbench.space_auth_hash_counter")
      .counter$n<-.counter$n+1L}))
  on.exit(untrace(".wb_prov_sha256_file",where=asNamespace("scworkbench")),add=TRUE)
  held<-budget$used
  for(partitions in c(8L,32L)) {
    for(index in split(seq_along(f$cells),ceiling(seq_along(f$cells)/ceiling(33/partitions))))
      stopifnot(identical(as.numeric(plan$read(f$cells[index])),as.numeric(f$values[index,,drop=FALSE])))
    for(boundary in seq_len(2L)) stopifnot(isTRUE(plan$authenticate(b)),budget$used==held)
  }
  stopifnot(counter$n==4L)
  plan$close();stopifnot(budget$used==0,
    inherits(try(plan$authenticate(b),silent=TRUE),"try-error"))
  TRUE
}

test_engine_space_boundary_lifecycle_rollback_retry_contract <- function() {
  root<-tempfile("engine_space_auth_lifecycle_");dir.create(root)
  lib<-file.path(root,"library");dir.create(lib);old_lib<-.libPaths()
  b<-NULL;sessions<-list();ns<-asNamespace("scworkbench")
  symbol<-".wb_operation_pack_v3_native_space_sources_authenticate"
  original<-get(symbol,ns)
  replace<-function(value) {unlockBinding(symbol,ns);assign(symbol,value,ns);lockBinding(symbol,ns)}
  on.exit({replace(original)
    for(s in sessions)try(wb_session_discard(s),silent=TRUE)
    try(wb_operation_pack_unload("enginespacefixture"),silent=TRUE)
    if("scwbEngineSpaceFixture" %in% loadedNamespaces())try(unloadNamespace("scwbEngineSpaceFixture"),silent=TRUE)
    .libPaths(old_lib);if(!is.null(b))try(wb_close_bundle(b),silent=TRUE)
    unlink(root,recursive=TRUE)},add=TRUE)
  log<-file.path(root,"install.log")
  status<-system2(file.path(R.home("bin"),"R"),c("CMD","INSTALL",
    paste0("--library=",shQuote(lib)),shQuote(normalizePath("tests/fixtures/engine-typed-space"))),
    stdout=log,stderr=log)
  if(status!=0L)stop(paste(readLines(log),collapse="\n"))
  .libPaths(c(lib,old_lib))
  wb_operation_pack_activate(system.file("scworkbench","operation-pack.json",
    package="scwbEngineSpaceFixture",lib.loc=lib),lib.loc=lib)
  b<-wb_init_bundle(file.path(root,"bundle"));cells<-paste0("c",1:33)
  wb_define_cells(b,cells)
  values<-matrix(as.double(1:99),33L,dimnames=list(cells,c("A","B","C")))
  wb_add_space(b,"source",values)
  workspace<-file.path(root,"sessions");dir.create(workspace)
  initial<-wb_session_create(b,workspace_root=workspace,session_id="auth_boundary")
  sessions[[1L]]<-initial
  run<-function()wb_session_run_op(initial,b,"enginespacefixture::row_sum",
    inputs=list(source="source",chunk_size=4L))
  before<-list.files(file.path(b$dir,"operation_pack_v2"),recursive=TRUE,all.files=TRUE)
  for(failed_boundary in c(1L,2L)) {
    calls<-0L
    replace(function(bundle,request) {
      calls<<-calls+1L
      if(calls==failed_boundary) {
        previous<-DBI::dbGetQuery(bundle$con,"SELECT description FROM spaces WHERE space_id='source'")
        on.exit(DBI::dbExecute(bundle$con,"UPDATE spaces SET description=? WHERE space_id='source'",
          params=list(previous$description[[1L]])),add=TRUE)
        DBI::dbExecute(bundle$con,"UPDATE spaces SET description='stale association' WHERE space_id='source'")
      }
      original(bundle,request)
    })
    failure<-try(run(),silent=TRUE);replace(original)
    stopifnot(inherits(failure,"try-error"),grepl("PYBENCH_INPUT_IDENTITY_MISMATCH",as.character(failure)),
      calls==failed_boundary,length(initial$runs)==0L,nrow(wb_art_list(b))==0L,
      identical(before,list.files(file.path(b$dir,"operation_pack_v2"),recursive=TRUE,all.files=TRUE)))
  }
  result<-run();sessions[[2L]]<-result$session
  stopifnot(identical(result$run$outputs$sums$cell_id,cells),
    identical(as.numeric(result$run$outputs$sums$value),as.numeric(rowSums(values))),
    is.null(result$run$inputs$space_plans))
  TRUE
}
