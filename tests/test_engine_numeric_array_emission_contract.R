.engine_array_emission_oracle <- function() {
  env <- new.env(parent=asNamespace("scworkbench"))
  sys.source("tests/fixtures/engine_canonical_repaired_oracle.R",env)
  env$exists <- function(x,...) if(identical(x,"C_scwb_canonical_numeric"))
    FALSE else base::exists(x,...)
  env$.engine_canonical_repaired_oracle
}
.engine_array_emit <- function(value,rows=FALSE)
  .Call(get("C_scwb_canonical_numeric_array",asNamespace("scworkbench")),value,rows)

test_engine_numeric_array_flat_emission_contract <- function() {
  old <- .engine_array_emission_oracle()
  values <- c(0,-0,1,-2,1/3,pi,NA_real_,NaN,1e-307,-1e-307,1e308,
    -.Machine$double.xmax,1.234567890123445,1.234567890123455)
  for(value in list(numeric(),integer(),list(),values,as.list(values),
      list(1L,2.5,NA_integer_),seq_len(131072L))) {
    actual <- .engine_array_emit(value)
    expected <- if(is.atomic(value)&&length(value)==1L) paste0("[",old(value),"]") else old(value)
    stopifnot(identical(charToRaw(actual),charToRaw(expected)),
      identical(digest::digest(actual,algo="sha256",serialize=FALSE),
        digest::digest(expected,algo="sha256",serialize=FALSE)))
  }
  stopifnot(identical(.engine_array_emit(1),"[1e0]"),
    identical(scworkbench:::.wb_operation_pack_canonical_json(1),"1e0"))
  TRUE
}

test_engine_numeric_array_rows_emission_contract <- function() {
  old <- .engine_array_emission_oracle()
  for(shape in list(c(0L,1L),c(1L,1L),c(2L,3L),c(17L,50L),c(128L,1024L))) {
    values <- matrix(rep(c(0,-0,1/3,NA_real_,NaN,1e-307,-1e308),
      length.out=prod(shape)),shape[[1L]],shape[[2L]])
    dimnames(values) <- list(if(nrow(values)) paste0("row_",rev(seq_len(nrow(values)))) else character(),
      paste0("axis_",rev(seq_len(ncol(values)))))
    attr(values,"scworkbench_payload_read") <- list(diagnostic="getter-only")
    expected <- old(lapply(seq_len(nrow(values)),function(i)
      unname(as.list(as.numeric(values[i,])))))
    actual <- .engine_array_emit(values,TRUE)
    stopifnot(identical(charToRaw(actual),charToRaw(expected)),
      nchar(actual,type="bytes")<=max(2,32*length(values)+3*nrow(values)))
  }
  TRUE
}

test_engine_numeric_array_rejection_and_ceiling_contract <- function() {
  for(value in list(c(1,Inf),c(1,1e-310),list(1,TRUE),list(1,new.env()),
      c(a=1,b=2),structure(c(1,2),label="fallback"),
      list(structure(1,operation_pack_json_number="1.000000000000001")),
      seq_len(131073L),factor(c("a","b")),as.Date("2020-01-01")))
    stopifnot(is.null(.engine_array_emit(value)))
  for(value in list(matrix(c(1,Inf),1L),matrix(c(1,1e-310),1L),
      matrix(TRUE,1L),matrix(numeric(),3L,0L),matrix(1,1L,131073L)))
    stopifnot(is.null(.engine_array_emit(value,TRUE)))
  stopifnot(is.null(.engine_array_emit(1,NA)),is.null(.engine_array_emit(1,1L)))
  TRUE
}
