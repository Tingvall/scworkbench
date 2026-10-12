args <- commandArgs(TRUE)
stopifnot(length(args) == 1L)
.libPaths(c(file.path(args[[1L]], "library"), .libPaths()))
library(scworkbench)
prototype <- new.env(parent = asNamespace("scworkbench"))
sys.source("notes/generic_graph_implementation/prototype_object_closure_batch.R", prototype)
path <- tempfile("object_closure_batch_", fileext = ".sqlite")
con <- DBI::dbConnect(RSQLite::SQLite(), path)
DBI::dbExecute(con, "CREATE TABLE artifact_object_payload_meta(artifact_id TEXT,kind TEXT,value_type TEXT,meta_present INTEGER,content_identity_json TEXT,closure_identity_json TEXT);")
DBI::dbExecute(con, "CREATE TABLE artifact_object_metadata_chunks(artifact_id TEXT,chunk_ordinal INTEGER,chunk BLOB);")
DBI::dbExecute(con, "CREATE TABLE artifact_labels(artifact_id TEXT,payload_ordinal INTEGER,cell_id TEXT,label TEXT,value_type TEXT,value_num REAL);")
DBI::dbExecute(con, "CREATE TABLE artifact_pseudotime(artifact_id TEXT,payload_ordinal INTEGER,cell_id TEXT,lineage_id TEXT,pseudotime REAL);")
identity <- jsonlite::toJSON(list(scheme = "scworkbench.content.object.canonical-json.v1", sha256 = strrep("a",64)), auto_unbox = TRUE)
for (kind in c("cell_vector", "cell_vector_family")) DBI::dbExecute(con,
  "INSERT INTO artifact_object_payload_meta VALUES(?,?,?,0,?,NULL);", params = list(kind,kind,"number",identity))
policy <- scworkbench:::.wb_graph_budgets(list(memory_bytes = "8388608", sqlite_cache_kib = 2048L,
  partition_bytes = 262144L, partition_rows = 256L, collect_bytes = 4194304L))
default_policy <- policy
original <- scworkbench:::.wb_graph_object_closure
observed <- prototype$.wb_graph_object_closure_batched
run <- function(fun, kind, policy = default_policy) {
  restore <- scworkbench:::.wb_graph_aggregate_connection_budget(list(con), policy)
  on.exit(restore(), add = TRUE)
  fun(con, kind, policy)
}
caption <- c("null_word", "", "/é😀\u2028", "quotes\"and\\slashes\n",
  intToUtf8(seq_len(31L)), strrep("long_ascii_", 40L))
values <- c(NA_real_, -0, 1.5, 5e300, -5e-300, 0)
for (count in c(0L,1L,63L,64L,65L,5001L)) {
  DBI::dbExecute(con, "DELETE FROM artifact_labels;")
  DBI::dbExecute(con, "DELETE FROM artifact_pseudotime;")
  if (count) {
    cells <- paste0("cell_",seq_len(count),strrep("a",192L))
    labels <- rep(caption,length.out=count)
    numeric <- rep(values,length.out=count)
    DBI::dbAppendTable(con,"artifact_labels",data.frame(artifact_id="cell_vector",
      payload_ordinal=seq_len(count)-1L,cell_id=cells,label=labels,value_type="number",value_num=numeric))
    DBI::dbAppendTable(con,"artifact_pseudotime",data.frame(artifact_id="cell_vector_family",
      payload_ordinal=seq_len(count)-1L,cell_id=cells,lineage_id=labels,pseudotime=numeric))
  }
  for (kind in c("cell_vector","cell_vector_family")) {
    expected <- run(original,kind)
    actual <- run(observed,kind)
    stopifnot(identical(expected,actual))
    if (count == 5001L) {
      elapsed <- system.time(actual <- run(observed,kind))[["elapsed"]]
      cat("OBJECT_CLOSURE_BATCH_PROTOTYPE kind=",kind," rows=",count," exact_identity=PASS elapsed=",elapsed,"\n",sep="")
    }
  }
}
# Preserve the original missing-string rejection while numeric SQL NULL remains valid.
DBI::dbExecute(con,"UPDATE artifact_labels SET label=NULL WHERE payload_ordinal=0;")
errors <- lapply(list(original,observed),function(fun) tryCatch({run(fun,"cell_vector");NULL},error=base::identity))
stopifnot(all(vapply(errors,inherits,logical(1),"error")), identical(conditionMessage(errors[[1L]]),conditionMessage(errors[[2L]])))
DBI::dbExecute(con,"UPDATE artifact_labels SET label='null_word' WHERE payload_ordinal=0;")
DBI::dbExecute(con,"UPDATE artifact_labels SET label=CAST(X'c3' AS TEXT) WHERE payload_ordinal=0;")
errors <- lapply(list(original,observed),function(fun) tryCatch({run(fun,"cell_vector");NULL},error=base::identity))
stopifnot(all(vapply(errors,inherits,logical(1),"error")), identical(conditionMessage(errors[[1L]]),conditionMessage(errors[[2L]])))
DBI::dbExecute(con,"UPDATE artifact_labels SET label='null_word' WHERE payload_ordinal=0;")
# Tiny reservation preserves the scalar route rather than allocating candidate carriers.
tiny <- policy; tiny$partition_bytes <- 2048L
stopifnot(identical(run(original,"cell_vector",tiny),run(observed,"cell_vector",tiny)))
tiny_reject <- policy; tiny_reject$partition_bytes <- 128L
errors <- lapply(list(original,observed),function(fun) tryCatch({run(fun,"cell_vector",tiny_reject);NULL},error=base::identity))
stopifnot(all(vapply(errors,inherits,logical(1),"error")), identical(conditionMessage(errors[[1L]]),conditionMessage(errors[[2L]])))
before <- list(cache = DBI::dbGetQuery(con,"PRAGMA cache_size;")[[1L]][[1L]],
  temp = DBI::dbGetQuery(con,"PRAGMA temp_store;")[[1L]][[1L]],policy = con@ref$wb_graph_policy,cap = con@ref$wb_graph_cache_kib)
private_before <- sort(list.files(tempdir(),pattern="^scwb_(graph_identity_|object_meta_)",full.names=TRUE))
batches <- 0L
hook <- options(scworkbench.graph_storage_test_hook = function(event,state) {
  if (event == "source_object_batch_fetch" && state$enabled) {
    batches <<- batches + 1L
    stopifnot(state$reservation_bytes <= state$decoded_reservation_bytes,
      state$decoded_reservation_bytes + policy$sqlite_cache_kib*1024 +65536 < as.numeric(policy$memory_bytes),
      state$con@ref$wb_graph_cache_kib +128L <= 2048L,
      identical(state$con@ref$wb_graph_policy$memory_bytes,"8388608"))
  }
})
stopifnot(identical(run(original,"cell_vector"),run(observed,"cell_vector")),batches>0L)
options(hook)
hook <- options(scworkbench.graph_storage_test_hook = function(event,state) {
  if (event == "source_object_batch_fetch") stop("OBJECT_BATCH_INJECTED")
})
error <- tryCatch({run(observed,"cell_vector");NULL},error=base::identity)
stopifnot(inherits(error,"error"),grepl("OBJECT_BATCH_INJECTED",conditionMessage(error),fixed=TRUE))
options(hook)
stopifnot(identical(before,list(cache=DBI::dbGetQuery(con,"PRAGMA cache_size;")[[1L]][[1L]],
  temp=DBI::dbGetQuery(con,"PRAGMA temp_store;")[[1L]][[1L]],policy=con@ref$wb_graph_policy,cap=con@ref$wb_graph_cache_kib)),
  identical(private_before,sort(list.files(tempdir(),pattern="^scwb_(graph_identity_|object_meta_)",full.names=TRUE))))
# Bound remains enforced if a source grows between admission and opening its cursor.
hook <- options(scworkbench.graph_storage_test_hook = function(event,state) {
  if (event == "source_object_batch_admission") {
    writer <- DBI::dbConnect(RSQLite::SQLite(),path)
    on.exit(DBI::dbDisconnect(writer),add=TRUE)
    DBI::dbExecute(writer,"PRAGMA cache_size=-64;")
    DBI::dbExecute(writer,"PRAGMA temp_store=FILE;")
    DBI::dbExecute(writer,"UPDATE artifact_labels SET label=? WHERE payload_ordinal=5000;",params=list(strrep("late_growth",100L)))
  }
})
error <- tryCatch({run(observed,"cell_vector");NULL},error=base::identity)
stopifnot(inherits(error,"error"),grepl("Source changed across admitted",conditionMessage(error),fixed=TRUE))
options(hook)
DBI::dbDisconnect(con);unlink(path)
cat("OBJECT_CLOSURE_BATCH_PROTOTYPE empty/boundaries/long_ids/UTF8/control/null/finite_f64/tiny/late_growth=PASS qualification=FALSE installed=UNCHANGED\n")
