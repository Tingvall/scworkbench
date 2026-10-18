# Positive modern sources must receive original independent authority at
# publication, never a rewritten closure/certificate after physical tampering.
.graph_compact_issue_admissible <- function(bundle,text) {
  metadata <- jsonlite::unserializeJSON(text)
  prim <- wb_prim_cell_vector(c(c1='a'),meta=metadata)
  run <- wb_new_run('metadata_cell_vector',list(),list(),list(vector=prim),
    notes='Synthetic admitted metadata fixture; no method execution.')
  promoted <- wb_promote_analysis(bundle,setNames(list(run),run$run_id),
    head_run_id=run$run_id,outputs='vector',fail_fast=TRUE)
  stopifnot(nrow(promoted$promoted)==1L,promoted$promoted$status[[1L]]=='ok')
  id <- promoted$promoted$artifact_id[[1L]]
  stopifnot(DBI::dbGetQuery(bundle$con,
    'SELECT COUNT(*) AS n FROM prov_run_outputs WHERE artifact_id=?;',
    params=list(id))$n[[1L]]==1L)
  id
}

.graph_compact_policy <- function()scworkbench:::.wb_graph_budgets(list(memory_bytes="8388608",sqlite_cache_kib=2048L,partition_bytes=262144L,partition_rows=256L,collect_bytes=4194304L))

.graph_compact_row_text <- function(n,type='integer',first='null',key='row.names')
  paste0('{"type":"list","attributes":{"',key,'":{"type":"',type,'","attributes":{},"value":[',first,',',n,']}},"value":[]}')
.graph_compact_row_wrap <- function(text,key='value') {
  if(key=='value')paste0('{"type":"list","attributes":{},"value":[',text,']}') else
    paste0('{"type":"integer","attributes":{"',key,'":',text,'},"value":[1]}')
}
.graph_compact_replace_physical_metadata <- function(bundle,id,text) {
  prov <- jsonlite::fromJSON(DBI::dbGetQuery(bundle$con,
    'SELECT provenance_json FROM artifacts WHERE artifact_id=?',params=list(id))$provenance_json[[1L]],simplifyVector=FALSE)
  prov$primitive_payload$meta_r_json <- text
  DBI::dbExecute(bundle$con,'UPDATE artifacts SET provenance_json=? WHERE artifact_id=?',
    params=list(as.character(jsonlite::toJSON(prov,auto_unbox=TRUE,null='null',digits=NA)),id))
  DBI::dbExecute(bundle$con,'DELETE FROM artifact_object_metadata_chunks WHERE artifact_id=?',params=list(id))
  DBI::dbExecute(bundle$con,'INSERT INTO artifact_object_metadata_chunks VALUES(?,0,?)',params=list(id,list(charToRaw(text))))
  invisible(NULL)
}

.graph_duplicate_rows_metadata <- function(first,last,key='row.names',last_key='row.names') {
  row <- function(n)paste0('{"type":"integer","attributes":{},"value":[null,',n,']}')
  paste0('{"type":"list","attributes":{"',key,'":',row(first),',"',last_key,'":',row(last),'},"value":[]}')
}

test_graph_bounded_legacy_duplicate_attribute_predecode_contract <- function() {
  policy <- .graph_compact_policy()
  codec <- scworkbench:::.wb_getter_metadata_admitted_codec
  root <- function(attributes)paste0('{"type":"list","attributes":{',attributes,'},"value":[]}')
  typed_class <- function(value)paste0('{"type":"character","attributes":{},"value":["',value,'"]}')
  wrap <- function(text)paste0('{"type":"list","attributes":{},"value":[',text,']}')
  cases <- list(duplicate_last_large=.graph_duplicate_rows_metadata(0,-2000000),
    duplicate_first_large=.graph_duplicate_rows_metadata(-2000000,-5),
    escaped_dot=.graph_duplicate_rows_metadata(0,-2000000,last_key='row\\u002enames'),
    nested_duplicate=wrap(.graph_duplicate_rows_metadata(0,-2000000)),
    duplicate_native_class=root(paste0('"class":',typed_class('plain'),',"class":',typed_class('NativeSymbolInfo'))),
    mixed_class_alias=root(paste0('".Class":',typed_class('plain'),',"class":',typed_class('NativeSymbolInfo'))),
    later_class_alias=root(paste0('"class":',typed_class('plain'),',".Class":',typed_class('NativeSymbolInfo'))),
    escaped_class=root(paste0('"class":',typed_class('plain'),',"cl\\u0061ss":',typed_class('NativeSymbolInfo'))))
  traced <- FALSE
  on.exit({Rprofmem(NULL);if(traced)untrace('unserializeJSON',where=asNamespace('jsonlite'))},add=TRUE)
  for(name in names(cases)) {
    calls <- 0L
    trace('unserializeJSON',where=asNamespace('jsonlite'),tracer=function()calls <<- calls+1L,print=FALSE)
    traced <- TRUE
    warm <- tryCatch(codec(cases[[name]],policy),error=identity)
    stopifnot(inherits(warm,'wb_graph_error'),identical(warm$code,'GRAPH_RESOURCE_EXCEEDED'),calls==0L)
    path <- tempfile('duplicate_attribute_alloc_');on.exit(unlink(path),add=TRUE)
    Rprofmem(path)
    result <- tryCatch(codec(cases[[name]],policy),error=identity)
    Rprofmem(NULL)
    untrace('unserializeJSON',where=asNamespace('jsonlite'));traced <- FALSE
    sizes <- suppressWarnings(as.numeric(sub(' .*','',readLines(path))))
    maximum <- max(c(0,sizes),na.rm=TRUE)
    stopifnot(inherits(result,'wb_graph_error'),identical(result$code,'GRAPH_RESOURCE_EXCEEDED'),calls==0L,
      maximum<=8*policy$partition_bytes)
    cat('DUPLICATE_ATTRIBUTE_REJECT',name,'decoder_calls=0 max_allocation=',maximum,'PASS\n');flush.console()
  }
  valid <- list(duplicate_small=.graph_duplicate_rows_metadata(-3,-5),
    escaped_small=.graph_duplicate_rows_metadata(-3,-5,last_key='row\\u002enames'),
    inert_alias_large=.graph_duplicate_rows_metadata(-2000000,-5,key='.row_names'),
    ordinary_duplicate_class=root(paste0('"class":',typed_class('plain'),',"class":',typed_class('other'))),
    marker_in_names=paste0('{"type":"integer","attributes":{"names":',typed_class('NativeSymbolInfo'),'},"value":[1]}'))
  for(name in names(valid)) {
    expected <- as.character(jsonlite::serializeJSON(jsonlite::unserializeJSON(valid[[name]]),digits=NA))
    stopifnot(identical(codec(valid[[name]],policy)$text,expected))
    cat('DUPLICATE_ATTRIBUTE_VALID',name,'exact_oldcodec=PASS\n')
  }
  # Both escaped keys must decode to the same actual attribute name.
  stopifnot(identical(names(jsonlite::fromJSON(valid$escaped_small,simplifyVector=FALSE)$attributes),
    c('row.names','row.names')))
  TRUE
}

test_graph_bounded_legacy_duplicate_rows_public_predecode_contract <- function() {
  root <- tempfile('duplicate_rows_public_');bundle <- wb_init_bundle(root)
  traced <- FALSE;restore <- NULL
  on.exit({Rprofmem(NULL);if(traced)untrace('unserializeJSON',where=asNamespace('jsonlite'));
    if(!is.null(restore))restore();wb_close_bundle(bundle);unlink(root,recursive=TRUE)},add=TRUE)
  wb_define_cells(bundle,'c1')
  prim <- wb_prim_cell_vector(c(c1='a'),meta=list(x=1L))
  run <- wb_new_run('metadata_cell_vector',list(),list(),list(vector=prim))
  promoted <- wb_promote_analysis(bundle,setNames(list(run),run$run_id),head_run_id=run$run_id,outputs='vector')
  id <- promoted$promoted$artifact_id[promoted$promoted$output=='vector'][[1L]]
  cases <- list(direct=.graph_duplicate_rows_metadata(0,-2000000),
    escaped=.graph_duplicate_rows_metadata(0,-2000000,last_key='row\\u002enames'),
    nested=.graph_compact_row_wrap(.graph_duplicate_rows_metadata(0,-2000000)),
    native_class='{"type":"list","attributes":{"class":{"type":"character","attributes":{},"value":["plain"]},".Class":{"type":"character","attributes":{},"value":["NativeSymbolInfo"]}},"value":[]}')
  cache <- DBI::dbGetQuery(bundle$con,'PRAGMA cache_size;')[[1L]][[1L]]
  paths <- function()sort(list.files(tempdir(),pattern='^scwb_(graph_identity_|object_meta_|graph_identity_metadata_keys_)',full.names=TRUE))
  for(name in names(cases)) {
    .graph_compact_replace_physical_metadata(bundle,id,cases[[name]])
    before <- paths();policy <- .graph_compact_policy()
    restore <- scworkbench:::.wb_graph_aggregate_connection_budget(list(bundle$con),policy)
    calls <- 0L
    trace('unserializeJSON',where=asNamespace('jsonlite'),tracer=function()calls <<- calls+1L,print=FALSE)
    traced <- TRUE
    warm <- tryCatch(wb_entity_certificate(bundle,'artifact',id),error=identity)
    stopifnot(inherits(warm,'wb_graph_error'),identical(warm$code,'GRAPH_RESOURCE_EXCEEDED'),calls==0L)
    path <- tempfile('duplicate_public_alloc_');on.exit(unlink(path),add=TRUE)
    Rprofmem(path)
    result <- tryCatch(wb_entity_certificate(bundle,'artifact',id),error=identity)
    Rprofmem(NULL)
    untrace('unserializeJSON',where=asNamespace('jsonlite'));traced <- FALSE
    sizes <- suppressWarnings(as.numeric(sub(' .*','',readLines(path))))
    maximum <- max(c(0,sizes),na.rm=TRUE)
    stopifnot(inherits(result,'wb_graph_error'),identical(result$code,'GRAPH_RESOURCE_EXCEEDED'),calls==0L,
      maximum<=8*policy$partition_bytes,identical(paths(),before))
    restore();restore <- NULL
    stopifnot(identical(cache,DBI::dbGetQuery(bundle$con,'PRAGMA cache_size;')[[1L]][[1L]]))
    cat('DUPLICATE_PUBLIC_REJECT',name,'bytes=',nchar(cases[[name]],type='bytes'),
      'decoder_calls=0 max_allocation=',maximum,'cleanup=PASS cache_restore=PASS\n');flush.console()
  }
  admissible <- .graph_duplicate_rows_metadata(-3,-5)
  .graph_compact_replace_physical_metadata(bundle,id,admissible)
  stale_certificate <- wb_entity_certificate(bundle,'artifact',id)
  stale <- tryCatch(wb_art_load(bundle,id),error=function(error)error)
  stopifnot(identical(stale_certificate$identity$verification_status,'failed'),
    identical(stale_certificate$identity$observed$status,'corrupt'),
    inherits(stale,'wb_graph_error'),identical(stale$code,'GRAPH_SOURCE_PAYLOAD_INVALID'))
  id <- .graph_compact_issue_admissible(bundle,admissible)
  baseline <- wb_entity_certificate(bundle,'artifact',id)
  expected <- scworkbench:::.wb_prov_payload_identity(bundle,wb_art_load(bundle,id))$content_sha256
  restore <- scworkbench:::.wb_graph_aggregate_connection_budget(list(bundle$con),.graph_compact_policy())
  actual <- wb_entity_certificate(bundle,'artifact',id)
  identity <- scworkbench:::.wb_getter_legacy_object_identity(bundle,id)
  stopifnot(identical(actual,baseline),identical(identity$content_sha256,expected))
  restore();restore <- NULL
  cat('DUPLICATE_PUBLIC_VALID complete_certificate_and_oldgetter_identity=PASS\n')
  TRUE
}

test_graph_bounded_legacy_compact_rows_direct_admission_contract <- function() {
  policy <- .graph_compact_policy()
  codec <- scworkbench:::.wb_getter_metadata_admitted_codec
  traced <- FALSE
  on.exit({Rprofmem(NULL);if(traced)untrace('unserializeJSON',where=asNamespace('jsonlite'))},add=TRUE)
  reject <- function(text,name,budget=policy) {
    decoder_calls <- 0L
    trace('unserializeJSON',where=asNamespace('jsonlite'),tracer=function()decoder_calls <<- decoder_calls+1L,print=FALSE)
    traced <<- TRUE
    warm <- tryCatch(codec(text,budget),error=identity)
    stopifnot(inherits(warm,'wb_graph_error'),identical(warm$code,'GRAPH_RESOURCE_EXCEEDED'),decoder_calls==0L)
    log <- tempfile('compact_direct_alloc_');on.exit(unlink(log),add=TRUE)
    Rprofmem(log)
    result <- tryCatch(codec(text,budget),error=identity)
    Rprofmem(NULL)
    untrace('unserializeJSON',where=asNamespace('jsonlite'));traced <<- FALSE
    sizes <- suppressWarnings(as.numeric(sub(' .*','',readLines(log))))
    maximum <- max(c(0,sizes),na.rm=TRUE)
    stopifnot(inherits(result,'wb_graph_error'),identical(result$code,'GRAPH_RESOURCE_EXCEEDED'),
      decoder_calls==0L,maximum<=8*budget$partition_bytes)
    cat('COMPACT_DIRECT_REJECTION',name,'decoder_calls=0 max_allocation=',maximum,'carrier_budget=',8*budget$partition_bytes,'PASS\n');flush.console()
  }
  cases <- list(direct2m=.graph_compact_row_text(-2000000),positive2m=.graph_compact_row_text(2000000),
    double2m=.graph_compact_row_text(-2000000,'double'),
    integer_inf_first=.graph_compact_row_text(-2000000,'integer','"Inf"'),
    integer_missing_first=.graph_compact_row_text(-2000000,'integer','"missing"'),
    nested_value=.graph_compact_row_wrap(.graph_compact_row_text(-2000000)),
    nested_attribute=.graph_compact_row_wrap(.graph_compact_row_text(-2000000),'custom'),
    nested_alias=.graph_compact_row_wrap(.graph_compact_row_text(-2000000),'.row_names'))
  for(name in names(cases))reject(cases[[name]],name)
  for(n in c(0,-5,-1000,5,1000)) {
    text <- .graph_compact_row_text(n)
    expected <- as.character(jsonlite::serializeJSON(jsonlite::unserializeJSON(text),digits=NA))
    stopifnot(identical(codec(text,policy)$text,expected))
    cat('COMPACT_DIRECT_ADMITTED',n,'exact_oldcodec=PASS\n')
  }
  text <- .graph_compact_row_text(-2000000,key='.row_names')
  stopifnot(identical(codec(text,policy)$text,
    as.character(jsonlite::serializeJSON(jsonlite::unserializeJSON(text),digits=NA))))
  cat('COMPACT_DIRECT_INERT_ALIAS exact_oldcodec=PASS\n')
  small <- policy;small$partition_bytes <- 4096L
  reject(.graph_compact_row_text(-50000),'small_partition',small)
  sibling <- .graph_compact_row_text(-5000)
  stopifnot(is.list(codec(sibling,policy)))
  reject(paste0('{"type":"list","attributes":{},"value":[',sibling,',',sibling,']}'),'aggregate_siblings')
  # Derive the exact boundary from independent native token enumeration.
  text <- .graph_compact_row_text(-1000)
  path <- tempfile('compact_boundary_');writeBin(charToRaw(text),path)
  on.exit(unlink(path),add=TRUE)
  pointer <- .Call(scworkbench:::C_scwb_graph_json_file_open,path,as.numeric(policy$token_bytes))
  on.exit(.Call(scworkbench:::C_scwb_graph_json_close,pointer),add=TRUE)
  count <- 0
  repeat {token <- .Call(scworkbench:::C_scwb_graph_json_next,pointer);count <- count+1;if(token$type=='end')break}
  .Call(scworkbench:::C_scwb_graph_json_close,pointer);unlink(path)
  exact <- ceiling((4*nchar(text,type='bytes')+256*count+256*1000)/8)
  bound <- policy;bound$partition_bytes <- exact
  expected <- as.character(jsonlite::serializeJSON(jsonlite::unserializeJSON(text),digits=NA))
  stopifnot(identical(codec(text,bound)$text,expected))
  bound$partition_bytes <- exact-1
  reject(text,'one_below_carrier_boundary',bound)
  cat('COMPACT_DIRECT_BOUNDARY exact_partition=',exact,'accepted_one_below_rejected=PASS\n')
  for(value in c('-1e308','1e308','2147483648'))
    reject(.graph_compact_row_text(value,'double'),paste0('overflow_',value))
  TRUE
}

test_graph_bounded_legacy_compact_rows_public_predecode_admission_contract <- function() {
  root <- tempfile('compact_rows_public_');bundle <- wb_init_bundle(root)
  on.exit({Rprofmem(NULL);wb_close_bundle(bundle);unlink(root,recursive=TRUE)},add=TRUE)
  wb_define_cells(bundle,'c1')
  primitive <- wb_prim_cell_vector(c(c1='a'),meta=list(x=1L))
  run <- wb_new_run('metadata_cell_vector',list(),list(),list(vector=primitive))
  out <- wb_promote_analysis(bundle,setNames(list(run),run$run_id),head_run_id=run$run_id,outputs='vector')
  id <- out$promoted$artifact_id[out$promoted$output=='vector'][[1L]]
  classed <- sub('"attributes":{','"attributes":{"class":{"type":"character","attributes":{},"value":["data.frame"]},',.graph_compact_row_text(-2000000),fixed=TRUE)
  cases <- list(direct=.graph_compact_row_text(-2000000),data_frame=classed,positive=.graph_compact_row_text(2000000),
    nested_value=.graph_compact_row_wrap(.graph_compact_row_text(-2000000)),
    nested_attribute=.graph_compact_row_wrap(.graph_compact_row_text(-2000000),'custom'),
    nested_alias=.graph_compact_row_wrap(.graph_compact_row_text(-2000000),'.row_names'),
    coercion=.graph_compact_row_text(-2000000,'integer','"Inf"'))
  traced <- FALSE;restore <- NULL
  on.exit({if(traced)untrace('unserializeJSON',where=asNamespace('jsonlite'));if(!is.null(restore))restore()},add=TRUE)
  cache <- DBI::dbGetQuery(bundle$con,'PRAGMA cache_size;')[[1L]][[1L]]
  paths <- function()sort(list.files(tempdir(),pattern='^scwb_(graph_identity_|object_meta_|graph_identity_metadata_keys_)',full.names=TRUE))
  for(name in names(cases)) {
    .graph_compact_replace_physical_metadata(bundle,id,cases[[name]])
    before <- paths()
    policy <- .graph_compact_policy()
    restore <- scworkbench:::.wb_graph_aggregate_connection_budget(list(bundle$con),policy)
    decoder_calls <- 0L
    trace('unserializeJSON',where=asNamespace('jsonlite'),tracer=function()decoder_calls <<- decoder_calls+1L,print=FALSE)
    traced <- TRUE
    warm <- tryCatch(wb_entity_certificate(bundle,'artifact',id),error=identity)
    stopifnot(inherits(warm,'wb_graph_error'),identical(warm$code,'GRAPH_RESOURCE_EXCEEDED'),decoder_calls==0L)
    log <- tempfile('compact_rows_alloc_');on.exit(unlink(log),add=TRUE)
    Rprofmem(log)
    result <- tryCatch(wb_entity_certificate(bundle,'artifact',id),error=identity)
    Rprofmem(NULL)
    untrace('unserializeJSON',where=asNamespace('jsonlite'));traced <- FALSE
    lines <- readLines(log)
    sizes <- suppressWarnings(as.numeric(sub(' .*','',lines)))
    maximum <- max(c(0,sizes),na.rm=TRUE)
    stopifnot(inherits(result,'wb_graph_error'),identical(result$code,'GRAPH_RESOURCE_EXCEEDED'),decoder_calls==0L,
      maximum<=8*policy$partition_bytes,identical(paths(),before))
    restore();restore <- NULL
    stopifnot(identical(cache,DBI::dbGetQuery(bundle$con,'PRAGMA cache_size;')[[1L]][[1L]]))
    cat('COMPACT_PUBLIC_REJECTION',name,'decoder_calls=0 max_allocation=',maximum,'cache_restore=PASS cleanup=PASS\n');flush.console()
  }
  admitted <- list(small=.graph_compact_row_text(-5),nested=.graph_compact_row_wrap(.graph_compact_row_text(-1000)),inert_alias=.graph_compact_row_text(-2000000,key='.row_names'))
  for(name in names(admitted)) {
    # Preserve raw compact-codec admission at the original tight policy.
    codec <- scworkbench:::.wb_getter_metadata_admitted_codec
    stopifnot(identical(codec(admitted[[name]],.graph_compact_policy())$text,
      as.character(jsonlite::serializeJSON(jsonlite::unserializeJSON(admitted[[name]]),digits=NA))))
    .graph_compact_replace_physical_metadata(bundle,id,admitted[[name]])
    stale_certificate <- wb_entity_certificate(bundle,'artifact',id)
    stale <- tryCatch(wb_art_load(bundle,id),error=function(error)error)
    stopifnot(identical(stale_certificate$identity$verification_status,'failed'),
      identical(stale_certificate$identity$observed$status,'corrupt'),
      inherits(stale,'wb_graph_error'),identical(stale$code,'GRAPH_SOURCE_PAYLOAD_INVALID'))
    id <- .graph_compact_issue_admissible(bundle,admitted[[name]])
    stored_bytes <- DBI::dbGetQuery(bundle$con,
      'SELECT SUM(length(chunk)) AS n FROM artifact_object_metadata_chunks WHERE artifact_id=?;',
      params=list(id))$n[[1L]]
    cat('COMPACT_PUBLIC_ENCODING',name,'raw_bytes=',nchar(admitted[[name]],type='bytes'),
      'published_bytes=',stored_bytes,'original_partition_bytes=',.graph_compact_policy()$partition_bytes,
      'positive_partition_bytes=',if(name=='nested')524288L else .graph_compact_policy()$partition_bytes,'\n')
    baseline <- wb_entity_certificate(bundle,'artifact',id)
    expected <- scworkbench:::.wb_prov_payload_identity(bundle,wb_art_load(bundle,id))$content_sha256
    restore <- scworkbench:::.wb_graph_aggregate_connection_budget(list(bundle$con),.graph_compact_policy())
    actual <- tryCatch(wb_entity_certificate(bundle,'artifact',id),error=function(error)error)
    if(name=='nested') {
      # Public publication normalizes compact row names into a larger lexical
      # carrier. The original small bound MUST still reject that carrier.
      stopifnot(inherits(actual,'wb_graph_error'),identical(actual$code,'GRAPH_RESOURCE_EXCEEDED'))
      restore();restore <- NULL
      expanded_policy <- .graph_compact_policy();expanded_policy$partition_bytes <- 524288L
      restore <- scworkbench:::.wb_graph_aggregate_connection_budget(list(bundle$con),expanded_policy)
      actual <- wb_entity_certificate(bundle,'artifact',id)
    }
    identity <- scworkbench:::.wb_getter_legacy_object_identity(bundle,id)
    stopifnot(identical(actual,baseline),identical(identity$content_sha256,expected))
    restore();restore <- NULL
    cat('COMPACT_PUBLIC_ADMITTED',name,'certificate_and_oldgetter_identity=PASS\n');flush.console()
  }
  TRUE
}
