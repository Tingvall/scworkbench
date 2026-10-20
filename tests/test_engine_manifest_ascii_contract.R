.engine_manifest_ascii_native <- function(rows) {
  keys <- vapply(names(rows),function(x)as.character(jsonlite::toJSON(x,auto_unbox=TRUE)),character(1))
  .Call(get('C_scwb_manifest_scalar_json',asNamespace('scworkbench')),rows,keys,as.double(1e7))
}
.engine_manifest_ascii_oracle <- function(rows)as.character(jsonlite::toJSON(rows,
  dataframe='rows',auto_unbox=TRUE,null='null',na='null'))

test_engine_manifest_ascii_complete_admitted_alphabet_contract <- function() {
  codes <- setdiff(32:126,c(34L,60L,92L))
  for(code in codes) {
    text <- intToUtf8(code)
    rows <- data.frame(value=c(text,NA_character_))
    names(rows) <- paste0('key',text)
    expected <- .engine_manifest_ascii_oracle(rows)
    actual <- .engine_manifest_ascii_native(rows)
    stopifnot(!is.null(actual),identical(charToRaw(actual),charToRaw(expected)),
      identical(digest::digest(actual,algo='sha256',serialize=FALSE),
        digest::digest(expected,algo='sha256',serialize=FALSE)))
  }
  for(text in c(intToUtf8(codes),"sample=SIGAA10","x+y@example.org","apostrophe'")) {
    rows <- data.frame(value=c(text,NA_character_,'NA',''))
    stopifnot(identical(charToRaw(.engine_manifest_ascii_native(rows)),
      charToRaw(.engine_manifest_ascii_oracle(rows))))
  }
  TRUE
}

test_engine_manifest_ascii_escape_and_rownames_fallback_contract <- function() {
  for(text in c(vapply(1:31,intToUtf8,character(1)),intToUtf8(127L),
      'quote"','backslash\\','<','</','snow雪',strrep('=',257L))) {
    rows <- data.frame(value=c('ordinary',text))
    stopifnot(is.null(.engine_manifest_ascii_native(rows)))
  }
  for(text in c('=','+','apostrophe\'','[',']')) {
    rows <- data.frame(value=c('ordinary','ordinary'))
    rownames(rows) <- c(paste0('1',text),'2')
    stopifnot(is.null(.engine_manifest_ascii_native(rows)))
  }
  # The conservative '<' exclusion protects the actual context-sensitive old
  # jsonlite format, not merely JSON grammar or operation-pack canonical JSON.
  stopifnot(identical(as.character(jsonlite::toJSON('</',auto_unbox=TRUE)),'"<\\/"'))
  TRUE
}

test_engine_manifest_ascii_actual_fold_mutation_and_purity_contract <- function() {
  path <- tempfile('manifest_ascii_',fileext='.sqlite')
  con <- DBI::dbConnect(RSQLite::SQLite(),path)
  on.exit({DBI::dbDisconnect(con);unlink(path)},add=TRUE)
  DBI::dbExecute(con,'CREATE TABLE membership(cell_id TEXT,description TEXT);')
  rows <- data.frame(cell_id=paste0('cell_',seq_len(10020L)),
    description=rep(c('Imported categorical label sample=SIGAA10',"x+y@example.org's [label]"),5010L))
  DBI::dbAppendTable(con,'membership',rows)
  before <- digest::digest(file=path,algo='sha256')
  hits <- 0L
  old <- options(scworkbench.graph_storage_test_hook=function(event,state) {
    if(event=='manifest_native_json'&&state$mode=='native')hits <<- hits+1L
  });on.exit(options(old),add=TRUE)
  expected <- scworkbench:::.wb_manifest_table_identity_materialized(con,'membership')
  actual <- scworkbench:::.wb_manifest_table_identity(con,'membership')
  known <- identical(as.character(getRversion()),'4.4.1')&&
    identical(as.character(getNamespaceVersion('jsonlite')),'1.8.8')
  stopifnot(identical(actual,expected),if(known)hits>0L else hits==0L,
    identical(before,digest::digest(file=path,algo='sha256')))
  DBI::dbExecute(con,'UPDATE membership SET description=? WHERE rowid=5001;',params=list('changed=label'))
  changed <- scworkbench:::.wb_manifest_table_identity(con,'membership')
  stopifnot(!identical(changed,actual),identical(changed,
    scworkbench:::.wb_manifest_table_identity_materialized(con,'membership')))
  TRUE
}
