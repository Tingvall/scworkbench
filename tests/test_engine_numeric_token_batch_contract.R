.engine_numeric_batch_oracle <- function() {
  env <- new.env(parent=asNamespace("scworkbench"))
  sys.source("tests/fixtures/engine_canonical_repaired_oracle.R",env)
  # Force the frozen R formatC/number-token path, independently of both native
  # scalar and batch formatters. Keep all old byte/error/shape rules untouched.
  env$exists <- function(x,...) if (identical(x,"C_scwb_canonical_numeric"))
    FALSE else base::exists(x,...)
  env$.engine_canonical_repaired_oracle
}

.engine_numeric_batch_compare <- function(value) {
  old <- tryCatch(.engine_numeric_batch_oracle()(value),error=identity)
  new <- tryCatch(scworkbench:::.wb_operation_pack_canonical_json(value),error=identity)
  if (inherits(old,"error")) stopifnot(inherits(new,"error"),
    identical(class(old),class(new)),identical(conditionMessage(old),conditionMessage(new)))
  else stopifnot(!inherits(new,"error"),identical(charToRaw(new),charToRaw(old)),
    identical(digest::digest(new,algo="sha256",serialize=FALSE),
      digest::digest(old,algo="sha256",serialize=FALSE)))
  invisible(TRUE)
}

.engine_numeric_batch_native <- function(value)
  .Call(get("C_scwb_canonical_numeric_tokens",asNamespace("scworkbench")),value)

test_engine_numeric_batch_frozen_preimage_contract <- function() {
  numbers <- c(0,-0,1,-1,1/3,pi,NA_real_,NaN,1e-307,-1e-307,
    1e308,-1e308,.Machine$double.xmax,-.Machine$double.xmax,
    .Machine$double.eps,1.234567890123445,1.234567890123455,
    -1.234567890123445,9.999999999999995e-100,9.999999999999995e100,
    1.000000000000005,1.000000000000015)
  cases <- list(numbers,as.list(numbers),c(NA_integer_,-2147483647L,0L,2147483647L),
    list(1L,2.5,NA_integer_,NaN),numeric(),integer(),list(),1,1L,
    list(1),list(numeric()),matrix(numbers,2L),matrix(7,1L,1L),
    array(numbers,c(1L,2L,length(numbers)/2L)),
    structure(numbers,label="ordinary attribute fallback"),
    stats::setNames(numbers,paste0("not_canonical_",rev(seq_along(numbers)))),
    list(list(1,2),list(3,4)),structure(list(),names=character()))
  for (value in cases) .engine_numeric_batch_compare(value)
  encode <- scworkbench:::.wb_operation_pack_canonical_json
  stopifnot(encode(1)=="1e0",encode(list(1))=="[1e0]",
    encode(numeric())=="[]",encode(list())=="[]",
    encode(structure(list(),names=character()))=="{}")
  TRUE
}

test_engine_numeric_batch_complete_validation_fallback_contract <- function() {
  parsed <- structure(1,operation_pack_json_number="1.000000000000001")
  invalid <- list(Inf,-Inf,1e-308,-1e-308,.Machine$double.xmin,
    TRUE,NA,1+2i,raw(1),factor("x"),as.Date("2020-01-01"),
    structure(7,label="attribute"),parsed,as.name("x"),new.env(parent=emptyenv()))
  for (item in invalid) {
    value <- list(1L,2.5,item)
    stopifnot(is.null(.engine_numeric_batch_native(value)))
    .engine_numeric_batch_compare(value)
  }
  # Entire block validation must defer to the old first error, not emit valid
  # prefixes or choose an unrelated later unsupported/range diagnostic.
  for (value in list(list(1,Inf,new.env(parent=emptyenv())),
      list(1,new.env(parent=emptyenv()),Inf),list(1,1e-310,Inf),
      list(1,parsed,Inf),list(1,structure(list(7),names="duplicate"),Inf),
      c(rep(1,32L),Inf),c(rep(1,32L),1e-310)))
    .engine_numeric_batch_compare(value)
  for (value in list(structure(c(1,2),label="attributed"),
      c(a=1,b=2),structure(list(1,2),label="attributed"),
      list(structure(1,names="named")),matrix(1:4,2L)))
    stopifnot(is.null(.engine_numeric_batch_native(value)))
  TRUE
}

test_engine_numeric_batch_dataframe_precedence_contract <- function() {
  base <- data.frame(z=c(NA_real_,NaN,-0,pi,1e-307),
    a=c(-2147483647L,NA_integer_,1L,2L,2147483647L),
    label=c("雪",NA,"quote\"\\\n","","x"),flag=c(TRUE,FALSE,NA,TRUE,FALSE),
    stringsAsFactors=FALSE)
  for (n in c(0L,1L,999L,1000L,1001L))
    .engine_numeric_batch_compare(base[rep(seq_len(nrow(base)),length.out=n),,drop=FALSE])
  special <- base;special$factor<-factor(c("a","b",NA,"a","b"))
  special$date<-as.Date("2020-01-01")+seq_len(nrow(base))
  attributed <- base;attr(attributed$z,"label")<-"conservative fallback"
  stopifnot(.engine_numeric_batch_compare(special),
    .engine_numeric_batch_compare(attributed))
  for (value in list(data.frame(a=c(0,Inf),b=c(Inf,0)),
      data.frame(a=c(0,1e-310),b=c(1e-309,0)),
      data.frame(a=structure(c(0,1),operation_pack_json_number="2"),b=c(Inf,0))))
    .engine_numeric_batch_compare(value)
  TRUE
}

test_engine_numeric_batch_ceiling_and_carriers_contract <- function() {
  n <- 131072L
  # Compact integer ALTREP input is read with ELT; no full-source DATAPTR is
  # requested by the native helper. The result is an explicitly bounded batch.
  values <- seq_len(n)
  tokens <- .engine_numeric_batch_native(values)
  stopifnot(length(tokens)==n,
    identical(tokens[c(1L,n)],vapply(c(1L,n),.engine_numeric_batch_oracle(),character(1))),
    is.null(.engine_numeric_batch_native(seq_len(n+1L))))
  scalars <- as.list(values)
  list_tokens <- .engine_numeric_batch_native(scalars)
  json <- paste0("[",paste(list_tokens,collapse=","),"]")
  stopifnot(identical(tokens,list_tokens),
    as.double(object.size(list(input=scalars,tokens=list_tokens,json=json)))<=256*as.double(n))
  scalars[[n]] <- Inf
  stopifnot(is.null(.engine_numeric_batch_native(scalars)),
    identical(.engine_numeric_batch_native(numeric()),character()),
    identical(.engine_numeric_batch_native(list()),character()),
    identical(.engine_numeric_batch_native(c(NA_real_,NaN,-0)),c("null","null","0")))
  TRUE
}

test_engine_numeric_batch_locale_symbol_and_rng_contract <- function() {
  encode <- scworkbench:::.wb_operation_pack_canonical_json
  old_options <- options(OutDec=",")
  on.exit(options(old_options),add=TRUE)
  for (value in list(c(1.25,NA,2),list(1.25,2L),data.frame(x=c(1.25,2))))
    .engine_numeric_batch_compare(value)
  options(OutDec=".")
  fallback <- new.env(parent=baseenv())
  ns <- asNamespace("scworkbench")
  for (name in ls(ns,all.names=TRUE)) if (startsWith(name,".wb_"))
    assign(name,get(name,ns),fallback)
  # Model the standalone generator: existing helpers and scalar symbol may be
  # present, while the new optional native batch binding is absent.
  assign("C_scwb_canonical_numeric",get("C_scwb_canonical_numeric",ns),fallback)
  standalone <- encode;environment(standalone)<-fallback
  stopifnot(!exists("C_scwb_canonical_numeric_tokens",fallback,inherits=TRUE))
  for (value in list(c(1.25,NA,2),list(1.25,2L),data.frame(x=c(1.25,2))))
    stopifnot(identical(standalone(value),encode(value)))
  had_seed <- exists(".Random.seed",globalenv(),inherits=FALSE)
  seed <- if (had_seed) get(".Random.seed",globalenv()) else NULL
  on.exit(if (had_seed) assign(".Random.seed",seed,globalenv()) else
    if (exists(".Random.seed",globalenv(),inherits=FALSE)) rm(".Random.seed",envir=globalenv()),add=TRUE)
  set.seed(1847);before<-get(".Random.seed",globalenv())
  encode(as.list(seq_len(100L)))
  stopifnot(identical(before,get(".Random.seed",globalenv())))
  rm(".Random.seed",envir=globalenv());encode(c(1,2,3))
  stopifnot(!exists(".Random.seed",globalenv(),inherits=FALSE))
  TRUE
}
