# Only core uses these SQL selectors. Packs receive identities and scoped
# readers, never a connection, path, query or state-authority handle.
.wb_graph_source_snapshot <- function(bundle, identity, budgets) {
  con <- bundle$con
  .wb_graph_identity_assert(identity, "scworkbench.provenance.snapshot_head.v1")
  after <- ""; matched <- NULL
  # Finish each tiny selector query before reading the complete admitted head.
  repeat {
    row <- DBI::dbGetQuery(con, paste0("SELECT snapshot_id FROM prov_heads ",
      "WHERE snapshot_id>? AND octet_length(snapshot_id)<=256 ",
      "ORDER BY snapshot_id LIMIT 1;"), params = list(after))
    if (!nrow(row)) break
    # Head count is typically tiny; keep only the selector while the cursor is
    # open, not a whole graph/source axis. Each query is closed before the next.
    after <- row$snapshot_id[[1]]
    header <- DBI::dbGetQuery(con, paste0("SELECT snapshot_id,schema_version,",
      "head_run_ids_json,n_runs,n_artifacts,commit_id,replay_status FROM prov_heads ",
      "WHERE snapshot_id=? AND COALESCE(octet_length(head_run_ids_json),0)+",
      "COALESCE(octet_length(commit_id),0)+COALESCE(octet_length(replay_status),0)+",
      "COALESCE(octet_length(schema_version),0)+COALESCE(octet_length(snapshot_id),0)<=? ",
      "AND typeof(n_runs)='integer' AND n_runs>=0 AND typeof(n_artifacts)='integer' AND n_artifacts>=0;"), params = list(
        row$snapshot_id[[1]], budgets$partition_bytes))
    .wb_graph_require(nrow(header) == 1L, "GRAPH_RESOURCE_EXCEEDED",
      "Source snapshot header exceeds decoded partition admission.")
    actual <- .wb_operation_pack_v3_head_snapshot(header)$source_snapshot_identity
    actual$scope <- NULL
    if (identical(actual, identity)) {
      .wb_graph_require(is.null(matched), "GRAPH_SOURCE_AUTHORITY_INVALID",
        "Source snapshot identity is ambiguous.")
      malformed <- DBI::dbGetQuery(con, paste0("SELECT 1 FROM prov_heads h WHERE h.snapshot_id=? AND (",
        "NOT json_valid(h.head_run_ids_json) OR json_type(h.head_run_ids_json)!='array' OR ",
        "EXISTS(SELECT 1 FROM json_each(h.head_run_ids_json) j WHERE j.type!='text' OR ",
        "octet_length(j.value)>256 OR j.value='' OR NOT EXISTS(SELECT 1 FROM prov_runs r ",
        "WHERE r.snapshot_id=h.snapshot_id AND r.run_id=j.value)) OR ",
        "EXISTS(SELECT 1 FROM json_each(h.head_run_ids_json) GROUP BY value HAVING COUNT(*)>1));"),
        params = list(row$snapshot_id[[1]]))
      .wb_graph_require(!nrow(malformed), "GRAPH_SOURCE_AUTHORITY_INVALID",
        "Retained snapshot declares foreign, duplicate or malformed head runs.")
      counts <- DBI::dbGetQuery(con, paste0("SELECT ",
        "(SELECT COUNT(*) FROM prov_runs WHERE snapshot_id=?) n_runs,",
        "(SELECT COUNT(*) FROM prov_run_outputs WHERE snapshot_id=? ",
        "AND artifact_id IS NOT NULL AND artifact_id!='') n_artifacts;"),
        params = list(row$snapshot_id[[1]], row$snapshot_id[[1]]))
      .wb_graph_require(identical(as.character(counts$n_runs[[1]]),
        as.character(header$n_runs[[1]])) && identical(as.character(counts$n_artifacts[[1]]),
          as.character(header$n_artifacts[[1]])), "GRAPH_SOURCE_AUTHORITY_INVALID",
        "Retained snapshot counts disagree with actual provenance records.")
      matched <- row$snapshot_id[[1]]
    }
  }
  .wb_graph_require(!is.null(matched), "GRAPH_SOURCE_UNAVAILABLE",
    "Exact retained source snapshot is unavailable or changed.")
  matched
}

.wb_graph_source_axis_query <- function(bundle, source_ref, axis_kind) {
  con <- bundle$con
  if (source_ref$kind == "retained_cell_axis") {
    row <- DBI::dbGetQuery(con, "SELECT type FROM artifacts WHERE artifact_id=?;",
      params = list(source_ref$source_id))
    .wb_graph_require(nrow(row) == 1L && row$type[[1]] %in%
      c("cell_vector", "cell_vector_family") && axis_kind == "cell",
      "GRAPH_SOURCE_UNAVAILABLE", "Unsupported or absent retained cell-axis source.")
    table <- if (row$type[[1]] == "cell_vector") "artifact_labels" else "artifact_pseudotime"
    return(list(sql = paste0("SELECT cell_id axis_id,MIN(payload_ordinal) axis_ordinal FROM ",
      table, " WHERE artifact_id=? GROUP BY cell_id"), params = list(source_ref$source_id)))
  }
  row <- DBI::dbGetQuery(con, "SELECT matrix_id FROM matrices WHERE matrix_id=?;",
    params = list(source_ref$source_id))
  .wb_graph_require(nrow(row) == 1L, "GRAPH_SOURCE_UNAVAILABLE", "Matrix source is absent.")
  if (axis_kind == "feature") return(list(sql = paste0(
    "SELECT feature_id axis_id,rowid axis_ordinal FROM features WHERE matrix_id=?"),
    params = list(source_ref$source_id)))
  list(sql = paste0("SELECT c.cell_id axis_id,c.rowid axis_ordinal FROM cells c ",
    "JOIN matrix_cells m ON m.cell_id=c.cell_id WHERE m.matrix_id=?"),
    params = list(source_ref$source_id))
}

.wb_graph_source_axis_hash <- function(bundle, source_ref, axis_kind, budgets) {
  query <- .wb_graph_source_axis_query(bundle, source_ref, axis_kind)
  con <- bundle$con
  oversized <- DBI::dbGetQuery(con, paste0("SELECT 1 FROM (", query$sql,
    ") WHERE octet_length(axis_id)>? LIMIT 1;"), params = c(query$params,
      list(min(256, budgets$partition_bytes))))
  .wb_graph_require(!nrow(oversized), "GRAPH_SOURCE_AUTHORITY_INVALID", "Invalid/oversized source axis ID.")
  emit_axis <- function(emit, membership = FALSE) {
    cursor <- DBI::dbSendQuery(con, paste0("SELECT axis_id FROM (", query$sql,
      ") ORDER BY ", if (membership) "CAST(axis_id AS BLOB)" else "axis_ordinal", ";"),
      params = query$params)
    first <- TRUE; previous <- NULL; count <- "0"
    tryCatch(repeat {
      rows <- DBI::dbFetch(cursor, n = 1L)
      if (!nrow(rows)) break
      id <- rows$axis_id[[1]]
      .wb_graph_require(.wb_graph_string(id) && (!membership || !identical(id, previous)),
        "GRAPH_SOURCE_AUTHORITY_INVALID", "Invalid/duplicate source axis ID.")
      if (!first) emit(",")
      emit(.wb_operation_pack_canonical_json(id))
      first <- FALSE; previous <- id; count <- .wb_graph_add_count(count, 1L)
    }, finally = DBI::dbClearResult(cursor))
    count
  }
  count <- "0"
  ordered <- .wb_graph_token_hash(function(emit) {
    emit("["); count <<- emit_axis(emit); emit("]")
  }, budgets)
  membership <- .wb_graph_token_hash(function(emit) {
    emit(paste0('{"axis_ids":[')); emit_axis(emit, TRUE)
    emit(paste0('],"axis_kind":', .wb_operation_pack_canonical_json(axis_kind),
      ',"schema":"scworkbench.graph.source-axis-content.v1","source_ref":',
      .wb_operation_pack_canonical_json(source_ref), "}"))
  }, budgets)
  list(axis_content_identity = list(
    scheme = "scworkbench.graph.source-axis-content.canonical-json.v1", sha256 = membership),
    axis_order_identity = list(scheme = paste0("scworkbench.", axis_kind, "_order.v1"),
      sha256 = ordered), axis_count = count)
}

.wb_graph_source_authorize <- function(bundle, binding, budgets) {
  .wb_graph_binding_header_validate(binding)
  snapshot <- .wb_graph_source_snapshot(bundle, binding$source_snapshot_identity, budgets)
  source <- binding$source_ref
  if (source$kind == "retained_cell_axis") {
    matches <- DBI::dbGetQuery(bundle$con, paste0("SELECT COUNT(*) n,",
      "COALESCE(MAX(octet_length(primitive_kind)),0) bytes FROM prov_run_outputs ",
      "WHERE snapshot_id=? AND artifact_id=?;"), params = list(snapshot, source$source_id))
    .wb_graph_require(matches$n[[1L]] == 1L && matches$bytes[[1L]] <= 32,
      "GRAPH_SOURCE_AUTHORITY_INVALID", "Retained source output is duplicate, missing or oversized.")
    output <- DBI::dbGetQuery(bundle$con, paste0("SELECT primitive_kind FROM prov_run_outputs ",
      "WHERE snapshot_id=? AND artifact_id=? AND octet_length(primitive_kind)<=32 LIMIT 2;"),
      params = list(snapshot, source$source_id))
    .wb_graph_require(nrow(output) == 1L && output$primitive_kind[[1]] %in%
      c("cell_vector", "cell_vector_family"), "GRAPH_SOURCE_AUTHORITY_INVALID",
      "Retained axis is not authenticated in the exact declared snapshot.")
    kinds <- DBI::dbGetQuery(bundle$con, paste0("SELECT a.type artifact_kind,m.kind closure_kind ",
      "FROM artifacts a JOIN artifact_object_payload_meta m ON m.artifact_id=a.artifact_id ",
      "WHERE a.artifact_id=? AND octet_length(a.type)<=32 AND octet_length(m.kind)<=32;"),
      params = list(source$source_id))
    .wb_graph_require(nrow(kinds) == 1L &&
      identical(kinds$artifact_kind[[1]], output$primitive_kind[[1]]) &&
      identical(kinds$closure_kind[[1]], output$primitive_kind[[1]]),
      "GRAPH_SOURCE_AUTHORITY_INVALID", "Source artifact, payload and snapshot primitive kinds disagree.")
    payload <- .wb_graph_object_verify(bundle$con, source$source_id, budgets)
  } else {
    .wb_graph_error("GRAPH_SOURCE_AUTHORITY_REQUIRED",
      "Bounded matrix payload authority requires the pending generic source-closure amendment.")
  }
  axes <- .wb_graph_source_axis_hash(bundle, source, binding$axis_kind, budgets)
  for (field in c("axis_content_identity", "axis_order_identity"))
    .wb_graph_require(identical(axes[[field]], binding[[field]]),
      "GRAPH_SOURCE_AUTHORITY_INVALID", paste0("Actual source disagrees at ", field))
  c(axes, list(source_payload_closure_identity = payload, source_snapshot_id = snapshot))
}
