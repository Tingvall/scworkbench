args <- commandArgs(TRUE)
.libPaths(c(file.path(args[[1L]],"library"),.libPaths()))
library(scworkbench)
dyn.load("/tmp/scwb-json-file-lexer-350.so")
source("notes/generic_graph_implementation/prototype_bounded_metadata_canonical.R")
policy <- scworkbench:::.wb_graph_budgets(list(memory_bytes="8388608",
  sqlite_cache_kib=2048L,partition_bytes=262144L,partition_rows=256L,collect_bytes=4194304L))
cases <- list(NULL,list(),c(TRUE,FALSE,NA),c(1L,NA_integer_),
  c(1/3,-0,1e-20,1e20,NA_real_,NaN,Inf,-Inf),c('é🙂','quote"','backslash\\','line\n',NA_character_),
  list(factor=factor(c('b','a')),date=as.Date('2026-10-11'),nested=list(a=1,b=list())),
  matrix(1:4,2L,dimnames=list(c('a','b'),c('x','y'))),
  ts(1:5,start=c(2001,2),frequency=4),data.frame(x=1:3,y=c('a','b','c')),
  structure(1:3,custom=list(a='é🙂')),as.raw(0:255),as.pairlist(list(a=1,b='x')),
  quote(foo(a=1,b='é🙂')),expression(a+b),
  list(huge=strrep('é🙂',400000L)),
  setNames(rep(c('é🙂','a','quote"'),20000L),rep('long_name',60000L)),
  list(many=as.list(seq_len(10000L))),
  rep(as.raw(0:255),5000L))
for(i in seq_along(cases)) {
  input <- as.character(jsonlite::serializeJSON(cases[[i]],digits=NA))
  expected <- as.character(jsonlite::serializeJSON(jsonlite::unserializeJSON(input),digits=NA))
  path <- tempfile('scwb_object_meta_canonical_');writeBin(charToRaw(enc2utf8(input)),path)
  time <- system.time(actual <- prototype_metadata_canonical_hash(path,policy))
  stopifnot(identical(actual$sha256,digest::digest(expected,algo='sha256',serialize=FALSE)))
  unlink(path)
  cat('BOUNDED_METADATA case=',i,' bytes=',nchar(input,type='bytes'),
    ' exact_old_roundtrip_hash=TRUE elapsed=',time[['elapsed']],' PASS\n',sep='');flush.console()
}
cat('BOUNDED_METADATA_FOCUSED executed=',length(cases),' passed=',length(cases),
  ' skipped=0 prototype_only=TRUE qualification=FALSE\n',sep='')
