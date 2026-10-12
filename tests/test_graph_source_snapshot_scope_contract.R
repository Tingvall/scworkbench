test_graph_source_snapshot_unrelated_head_scope_contract <- function() {
  root <- tempfile("graph_snapshot_scope_");bundle <- wb_init_bundle(root)
  old <- options("scworkbench.graph_storage_test_hook")
  on.exit({options(old);wb_close_bundle(bundle);unlink(root,recursive=TRUE)},add=TRUE)
  wb_define_cells(bundle,c("c1","c2"))
  wb_attach_matrix(bundle,"RNA",Matrix::Matrix(matrix(1:4,2L,
    dimnames=list(c("g1","g2"),c("c1","c2"))),sparse=TRUE))
  policy <- scworkbench:::.wb_graph_budgets(list(memory_bytes="8388608",sqlite_cache_kib=2048L,
    partition_bytes=262144L,partition_rows=256L,collect_bytes=4194304L))
  selection <- scworkbench:::.wb_graph_matrix_retained_selector(bundle,"RNA",policy)
  expected <- scworkbench:::.wb_graph_matrix_retained_snapshot(bundle,selection,policy)
  unrelated <- c("unrelated_oversized_header","unrelated_malformed_header")
  for (i in seq_along(unrelated)) DBI::dbExecute(bundle$con,
    "INSERT INTO prov_heads(snapshot_id,created_at,schema_version,head_run_ids_json,n_runs,n_artifacts) VALUES(?,?,?,?,0,0);",
    params=list(unrelated[[i]],"2026-10-11","scworkbench.provenance.v1",
      if(i==1L) paste0('[',strrep(' ',262145L),']') else 'malformed'))
  visited <- character()
  options(scworkbench.graph_storage_test_hook=function(event,state) {
    if(event=="source_snapshot_candidate") visited <<- c(visited,state$snapshot_id)
  })
  stopifnot(identical(selection,scworkbench:::.wb_graph_matrix_retained_selector(bundle,"RNA",policy)),
    identical(expected,scworkbench:::.wb_graph_matrix_retained_snapshot(bundle,selection,policy)),
    identical(scworkbench:::.wb_graph_source_snapshot(bundle,expected$source_snapshot_identity,policy,
      source_ref=list(kind="matrix",source_id="RNA")),selection$snapshot_id),
    length(visited)>0L,!any(visited %in% unrelated))
  # Exact requested identity remains independently checked; no latest-head substitution.
  forged <- expected$source_snapshot_identity;forged$sha256 <- strrep("0",64L)
  error <- tryCatch(scworkbench:::.wb_graph_source_snapshot(bundle,forged,policy,
    source_ref=list(kind="matrix",source_id="RNA")),error=base::identity)
  stopifnot(inherits(error,"wb_graph_error"),error$code=="GRAPH_SOURCE_UNAVAILABLE")
  original <- DBI::dbGetQuery(bundle$con,"SELECT head_run_ids_json FROM prov_heads WHERE snapshot_id=?;",
    params=list(selection$snapshot_id))$head_run_ids_json[[1L]]
  DBI::dbExecute(bundle$con,"UPDATE prov_heads SET head_run_ids_json=? WHERE snapshot_id=?;",
    params=list(paste0('[',strrep(' ',262145L),']'),selection$snapshot_id))
  error <- tryCatch(scworkbench:::.wb_graph_matrix_retained_snapshot(bundle,selection,policy),error=base::identity)
  stopifnot(inherits(error,"wb_graph_error"),error$code=="GRAPH_SOURCE_AUTHORITY_REQUIRED")
  DBI::dbExecute(bundle$con,"UPDATE prov_heads SET head_run_ids_json=? WHERE snapshot_id=?;",
    params=list(original,selection$snapshot_id))
  stopifnot(identical(expected,scworkbench:::.wb_graph_matrix_retained_snapshot(bundle,selection,policy)))
  TRUE
}
