.engine_object_rows_oracle <- function() {
  env<-new.env(parent=asNamespace("scworkbench"))
  sys.source("tests/fixtures/engine_canonical_repaired_oracle.R",env)
  env$exists<-function(x,...)if(identical(x,"C_scwb_canonical_numeric"))FALSE else base::exists(x,...)
  env$.engine_canonical_repaired_oracle
}
.engine_object_rows_compare <- function(value,encoder=scworkbench:::.wb_operation_pack_canonical_json) {
  old<-tryCatch(.engine_object_rows_oracle()(value),error=identity)
  new<-tryCatch(encoder(value),error=identity)
  if(inherits(old,"error"))stopifnot(inherits(new,"error"),identical(class(old),class(new)),
    identical(conditionMessage(old),conditionMessage(new)),identical(old$code,new$code)) else
    stopifnot(!inherits(new,"error"),identical(charToRaw(new),charToRaw(old)),
      identical(digest::digest(new,algo="sha256",serialize=FALSE),digest::digest(old,algo="sha256",serialize=FALSE)))
  TRUE
}
.engine_object_rows_fixture <- function(n)lapply(seq_len(n),function(i)
  list(values=list(feature_type=if(i%%3L==0L)NA_character_ else "Gene Expression",empty=NULL),
    feature_id=paste0("feature_雪_",i),score=as.double(i)/7L,ordinal=as.integer(i),
    selected=if(i%%5L==0L)NA else i%%2L==0L))

test_engine_canonical_object_rows_frozen_preimage_contract <- function() {
  fast<-scworkbench:::.wb_operation_pack_canonical_object_rows
  for(n in c(1L,2L,999L,1000L,1001L,2001L)) {
    rows<-.engine_object_rows_fixture(n)
    stopifnot(!is.null(fast(rows,TRUE)),.engine_object_rows_compare(rows))
  }
  special<-list(list(z=list(b="\"\\\b\t\n\f\r\u0001雪",a=NULL),a=-0),
    list(z=list(b=NA_character_,a=NULL),a=NaN))
  stopifnot(!is.null(fast(special,TRUE)),.engine_object_rows_compare(special))
  numbers<-c(1/3,1e-307,-1e-307,.Machine$double.xmax,-.Machine$double.xmax,
    1.234567890123445,1.234567890123455,9.999999999999995e-100,NA_real_,NaN)
  rows<-lapply(numbers,function(number)list(values=list(number=number),null=NULL))
  stopifnot(!is.null(fast(rows,TRUE)),.engine_object_rows_compare(rows))
  TRUE
}

test_engine_canonical_object_rows_complete_fallback_contract <- function() {
  fast<-scworkbench:::.wb_operation_pack_canonical_object_rows
  invalid<-list(Inf,-Inf,1e-308,.Machine$double.xmin,1+2i,raw(1),new.env(parent=emptyenv()),
    factor("gene"),as.Date("2020-01-01"),structure(1,operation_pack_json_number="1.000000000000001"),
    structure("label",note="attribute"),c("long","vector"),list(array="nested array"))
  for(item in invalid) {
    rows<-.engine_object_rows_fixture(3L)
    rows[[3L]]$values["feature_type"]<-list(item)
    stopifnot(is.null(fast(rows,TRUE)),.engine_object_rows_compare(rows))
  }
  rows<-.engine_object_rows_fixture(3L);names(rows[[3L]])[2L]<-names(rows[[3L]])[1L]
  stopifnot(is.null(fast(rows,TRUE)),.engine_object_rows_compare(rows))
  rows<-.engine_object_rows_fixture(3L);rows[[1L]]$score<-Inf
  names(rows[[3L]])[2L]<-names(rows[[3L]])[1L]
  stopifnot(is.null(fast(rows,TRUE)),.engine_object_rows_compare(rows))
  # Integer versus double cannot be coerced by a column gather: 1 != 1e0.
  rows<-list(list(value=1L),list(value=1))
  stopifnot(is.null(fast(rows,TRUE)),.engine_object_rows_compare(rows))
  invalid_utf8<-rawToChar(as.raw(c(0xc3,0x28)));Encoding(invalid_utf8)<-"UTF-8"
  for(key in c(FALSE,TRUE)) {
    rows<-.engine_object_rows_fixture(3L)
    if(key)names(rows[[3L]])[[1L]]<-invalid_utf8 else rows[[3L]]$feature_id<-invalid_utf8
    stopifnot(is.null(fast(rows,TRUE)),.engine_object_rows_compare(rows))
  }
  TRUE
}

test_engine_canonical_object_rows_temporary_budget_contract <- function() {
  fast<-scworkbench:::.wb_operation_pack_canonical_object_rows
  deep<-"leaf";for(i in 1:9)deep<-list(value=deep)
  stopifnot(is.null(fast(list(deep),TRUE)),.engine_object_rows_compare(list(deep)))
  wide<-as.list(seq_len(129L));names(wide)<-paste0("key",seq_along(wide))
  stopifnot(is.null(fast(list(wide),TRUE)),.engine_object_rows_compare(list(wide)))
  saved<-options(scworkbench.max_dense_materialize_mb=.1);on.exit(options(saved),add=TRUE)
  giant<-list(list(id="one",value=strrep("x",10000L)))
  stopifnot(is.null(fast(giant,TRUE)),.engine_object_rows_compare(giant))
  # No optimized string/prefix emission may occur before a late invalid row.
  env<-new.env(parent=asNamespace("scworkbench"));counter<-new.env(parent=emptyenv());counter$n<-0L
  env$.wb_operation_pack_canonical_string<-function(...) {
    counter$n<-counter$n+1L;scworkbench:::.wb_operation_pack_canonical_string(...)
  }
  env$.wb_operation_pack_canonical_string_tokens<-function(...) {
    counter$n<-counter$n+1L;scworkbench:::.wb_operation_pack_canonical_string_tokens(...)
  }
  local_fast<-fast;environment(local_fast)<-env
  options(scworkbench.max_dense_materialize_mb=256)
  rows<-.engine_object_rows_fixture(2001L);rows[[2001L]]$score<-Inf
  stopifnot(is.null(local_fast(rows,TRUE)),counter$n==0L,.engine_object_rows_compare(rows))
  TRUE
}

test_engine_canonical_object_rows_locale_symbol_and_rng_contract <- function() {
  value<-.engine_object_rows_fixture(3L)
  set.seed(923L);before<-.Random.seed
  stopifnot(.engine_object_rows_compare(value),identical(before,.Random.seed))
  env<-new.env(parent=asNamespace("scworkbench"))
  env$exists<-function(x,...)if(startsWith(x,"C_scwb_canonical_numeric"))FALSE else base::exists(x,...)
  standalone<-scworkbench:::.wb_operation_pack_canonical_json;environment(standalone)<-env
  stopifnot(.engine_object_rows_compare(value,standalone))
  saved<-options(OutDec=",");on.exit(options(saved),add=TRUE)
  stopifnot(.engine_object_rows_compare(value),identical(before,.Random.seed))
  TRUE
}

test_engine_canonical_object_rows_shape_and_null_contract <- function() {
  fast<-scworkbench:::.wb_operation_pack_canonical_object_rows
  nulls<-list(list(z=NULL,a=list(value=NULL)),list(z=NULL,a=list(value=NULL)))
  stopifnot(!is.null(fast(nulls,TRUE)),.engine_object_rows_compare(nulls))
  reordered<-.engine_object_rows_fixture(2L);reordered[[2L]]<-rev(reordered[[2L]])
  stopifnot(is.null(fast(reordered,TRUE)),.engine_object_rows_compare(reordered))
  absent<-nulls;absent[[2L]]$z<-NULL
  stopifnot(is.null(fast(absent,TRUE)),.engine_object_rows_compare(absent))
  attributed<-.engine_object_rows_fixture(2L);attr(attributed,"label")<-"ordinary fallback"
  stopifnot(is.null(fast(attributed,TRUE)),.engine_object_rows_compare(attributed))
  flat<-lapply(seq_len(7L),function(i)stats::setNames(as.list(rep(as.integer(i),11L)),paste0("field",11:1)))
  stopifnot(!is.null(fast(flat,TRUE)),.engine_object_rows_compare(flat))
  TRUE
}
