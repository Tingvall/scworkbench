.table_query_publish <- function(b, table, legacy = FALSE) {
  prim <- wb_prim_obs_table(table)
  if (legacy) prim$table_storage <- NULL
  run <- wb_new_run("metadata_cell_vector", outputs = list(vector = prim))
  wb_promote_analysis(b, setNames(list(run), run$run_id),
    head_run_id = run$run_id, outputs = "vector")$promoted$artifact_id[[1L]]
}

test_table_query_filter_selection_contract <- function() {
  root <- tempfile("query_filters_"); b <- wb_init_bundle(root)
  on.exit({try(wb_close_bundle(b), silent=TRUE); unlink(root, recursive=TRUE)}, add=TRUE)
  table <- data.frame(id=c("a","b","c"), group=c("x","y","x"))
  for (legacy in c(FALSE, TRUE)) {
    id <- .table_query_publish(b, table, legacy)
    slice <- function(f) wb_art_table_slice(b,id,filters=f)
    distinct <- function(f) wb_art_table_distinct(b,id,"id",filters=f)
    for (f in list(NULL,list())) stopifnot(nrow(slice(f)) == 3L,
      identical(distinct(f),c("a","b","c")))
    for (f in list(list(id=character()),list(id=NULL),list(id=c(NA,NA)),
      list(id=character(),group="x"), list(group="x",id=NA_character_))) {
      stopifnot(nrow(slice(f)) == 0L, length(distinct(f)) == 0L)
      if (!legacy) stopifnot(identical(slice(f),table[0,]))
    }
    stopifnot(identical(slice(list(id=c(NA,"a"))),table[1,,drop=FALSE]),
      identical(distinct(list(id=c(NA,"a"))),"a"),
      identical(distinct(list(id=c("a","c"),group="x")),c("a","c")),
      nrow(slice(list(id="a' OR 1=1 --"))) == 0L)
    malformed <- list("id",list("a"),setNames(list("a","b"),c("id","")),
      setNames(list("a"),NA_character_),setNames(list("a","b"),c("id","id")),
      list(id=list("a")),list(id=matrix("a")),list(unknown="a"),
      list(id=character(),unknown="a"))
    for (f in malformed) for (query in list(slice,distinct))
      stopifnot(inherits(try(query(f),silent=TRUE),"try-error"))
  }
  TRUE
}

test_table_query_accepted_names_fresh_reopen_contract <- function() {
  root <- tempfile("query_names_"); b <- wb_init_bundle(root)
  on.exit({try(wb_close_bundle(b),silent=TRUE);unlink(root,recursive=TRUE)},add=TRUE)
  names <- c("ordinary","space name","_leading","雪","a.b",'a"b',"a\\b","a'b",'both"\\',"x') OR 1=1 --", "line\nbreak")
  table <- as.data.frame(setNames(rep(list(c("x","y","x")),length(names)),names),check.names=FALSE)
  id <- .table_query_publish(b,table)
  empty <- .table_query_publish(b,table[0,])
  bytes <- DBI::dbGetQuery(b$con,"SELECT row_json FROM artifact_table_rows WHERE artifact_id=? ORDER BY row_idx",params=list(id))
  check <- function(b) {
    stopifnot(identical(wb_art_load(b,id)$table,table))
    for (nm in names) {
      stopifnot(identical(wb_art_table_distinct(b,id,nm),c("x","y")),
        identical(wb_art_table_distinct(b,id,nm,filters=setNames(list("x"),nm)),"x"),
        identical(wb_art_table_slice(b,id,filters=setNames(list("y"),nm)),table[2,,drop=FALSE] |> `rownames<-`(NULL)),
        identical(wb_art_table_slice(b,empty,filters=setNames(list("x"),nm)),table[0,]))
    }
    for (nm in list(character(),c("ordinary","a.b"),NA_character_,1L,"", "unknown"))
      stopifnot(inherits(try(wb_art_table_distinct(b,id,nm),silent=TRUE),"try-error"))
    stopifnot(identical(bytes,DBI::dbGetQuery(b$con,"SELECT row_json FROM artifact_table_rows WHERE artifact_id=? ORDER BY row_idx",params=list(id))))
  }
  check(b); stopifnot(wb_finalize_recipient_bundle(b)$ready);wb_close_bundle(b)
  # A separate process loads the installed package and queries every accepted name.
  fixture <- tempfile(fileext=".rds");saveRDS(list(id=id,names=names,table=table),fixture)
  on.exit(unlink(fixture),add=TRUE)
  code <- paste0('a<-commandArgs(TRUE);.libPaths(c(a[1],.libPaths()));library(scworkbench);',
    'f<-readRDS(a[3]);b<-wb_open_bundle(a[2],read_only=TRUE);',
    'stopifnot(identical(names(wb_art_load(b,f$id)$table),f$names));',
    'for(nm in f$names) stopifnot(identical(wb_art_table_distinct(b,f$id,nm),c("x","y")),',
    'nrow(wb_art_table_slice(b,f$id,filters=setNames(list("y"),nm)))==1L);wb_close_bundle(b)')
  child <- processx::run(file.path(R.home("bin"),"Rscript"),c("-e",code,
    dirname(find.package("scworkbench")),root,fixture),timeout=60000,error_on_status=FALSE)
  stopifnot(child$status == 0L)
  b <- wb_open_bundle(root,read_only=TRUE);check(b)
  TRUE
}
