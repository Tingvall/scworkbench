.engine_partition_old <- function() {
  env <- new.env(parent=asNamespace("scworkbench"))
  sys.source("tests/fixtures/engine_canonical_repaired_oracle.R",env)
  env$.engine_canonical_repaired_oracle
}
.engine_partition_admit <- function(value)
  .Call(get("C_scwb_canonical_numeric_partitionable",asNamespace("scworkbench")),value)
.engine_partition_outcome <- function(fun,value) tryCatch(fun(value),error=function(e)
  list(class=class(e),message=conditionMessage(e)))

test_engine_numeric_partition_exact_flat_bytes_contract <- function() {
  encode <- scworkbench:::.wb_operation_pack_canonical_json
  old <- .engine_partition_old()
  pattern <- c(0,-0,1/3,pi,NA_real_,NaN,-1e-307,1e308,1.234567890123455)
  tokens <- vapply(seq_along(pattern),function(i) old(pattern[[i]]),character(1))
  for(n in c(65535L,65536L,65537L,131071L,131072L,131073L,200003L)) {
    value <- rep(pattern,length.out=n)
    expected <- paste0("[",paste(rep(tokens,length.out=n),collapse=","),"]")
    variants <- list(value,structure(value,names=rep("duplicate",n)),
      matrix(value,nrow=1L,dimnames=list("nonlex_row",rev(paste0("d",seq_len(n))))))
    for(item in variants) stopifnot(.engine_partition_admit(item),
      identical(charToRaw(encode(item)),charToRaw(expected)),
      identical(digest::digest(encode(item),algo="sha256",serialize=FALSE),
        digest::digest(expected,algo="sha256",serialize=FALSE)))
  }
  matrix <- matrix(rep(pattern,length.out=200006L),2L,100003L,
    dimnames=list(c("cell_2","cell_1"),NULL))
  expected <- paste0("[",paste(rep(tokens,length.out=length(matrix)),collapse=","),"]")
  stopifnot(identical(encode(matrix),expected))
  for(value in list(numeric(),integer(),1,NA_real_,matrix(1,1,1),matrix(numeric(),0,2)))
    stopifnot(identical(encode(value),old(value)))
  TRUE
}

test_engine_numeric_partition_strict_admission_contract <- function() {
  encode <- scworkbench:::.wb_operation_pack_canonical_json
  old <- .engine_partition_old()
  # These compact INT/REAL sequences have no object bit or attributes. Their
  # native rejection therefore exercises the actual ALTREP gate, not a class
  # or attribute surrogate. Ordinary equal twins must be admitted.
  for(value in list(seq_len(200003L),as.double(seq_len(200003L)))) {
    stopifnot(typeof(value)%in%c("integer","double"),!is.object(value),
      is.null(attributes(value)),!.engine_partition_admit(value))
    twin <- rep(value,length.out=length(value))
    stopifnot(identical(value,twin),.engine_partition_admit(twin),
      identical(encode(value),encode(twin)))
  }
  for(value in list(structure(c(1,2),label="old fallback"),
      structure(c(1,2),operation_pack_json_number="not scalar"),
      structure(c(1,2),class="unknown_numeric"),c(TRUE,FALSE),
      c(1+1i,2+0i),as.raw(1:2),list(1,2))) {
    stopifnot(!.engine_partition_admit(value),
      identical(.engine_partition_outcome(encode,value),
        .engine_partition_outcome(old,value)))
  }
  TRUE
}

test_engine_numeric_partition_late_error_and_source_purity_contract <- function() {
  encode <- scworkbench:::.wb_operation_pack_canonical_json
  old <- .engine_partition_old()
  for(last in c(Inf,-Inf,1e-310,-1e-310)) {
    value <- rep(1/3,140003L);value[[140000L]] <- last
    before <- serialize(value,NULL,version=3)
    stopifnot(identical(.engine_partition_outcome(encode,value),
      .engine_partition_outcome(old,value)),identical(before,serialize(value,NULL,version=3)))
  }
  value <- matrix(rep(c(-0,1/3,NA_real_),length.out=200004L),3L)
  before <- serialize(value,NULL,version=3)
  env <- new.env(parent=asNamespace("scworkbench"))
  calls <- list()
  symbol <- get("C_scwb_canonical_numeric_array",asNamespace("scworkbench"))
  env$.Call <- function(.NAME,...) {
    args <- list(...)
    result <- base::.Call(.NAME,...)
    if(identical(.NAME,symbol)) calls[[length(calls)+1L]] <<-
      list(length=length(args[[1L]]),admitted=!is.null(result))
    result
  }
  scoped <- encode;environment(scoped) <- env
  stopifnot(identical(scoped(value),encode(value)),
    identical(before,serialize(value,NULL,version=3)))
  admitted <- Filter(function(x)x$admitted,calls)
  stopifnot(length(admitted)==4L,
    identical(vapply(admitted,`[[`,integer(1),"length"),c(65536L,65536L,65536L,3396L)))
  TRUE
}

test_engine_numeric_partition_locale_and_missing_symbol_contract <- function() {
  encode <- scworkbench:::.wb_operation_pack_canonical_json
  value <- matrix(rep(c(1/3,NA_real_,0),length.out=65538L),3L)
  env <- new.env(parent=asNamespace("scworkbench"))
  env$exists <- function(x,...) if(identical(x,"C_scwb_canonical_numeric_partitionable"))
    FALSE else base::exists(x,...)
  fallback <- encode;environment(fallback) <- env
  stopifnot(identical(encode(value),fallback(value)))
  old_options <- options(OutDec=",");on.exit(options(old_options),add=TRUE)
  old <- .engine_partition_old()
  stopifnot(identical(.engine_partition_outcome(encode,value),
    .engine_partition_outcome(old,value)))
  TRUE
}
