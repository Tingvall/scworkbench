.wb_graph_retained_plain_budgets <- function(value) {
  if (is.null(value)) return(TRUE)
  if (!is.list(value) || is.object(value)) return(FALSE)
  attrs <- attributes(value)
  if (length(setdiff(names(attrs),c("names","wb_graph_session_copy_bytes")))) return(FALSE)
  owned <- attr(value,"wb_graph_session_copy_bytes",exact=TRUE)
  if (!is.null(owned) && (!is.numeric(owned) || length(owned)!=1L ||
      !is.null(attributes(owned)) || !is.finite(owned))) return(FALSE)
  all(vapply(value,function(item) is.atomic(item) && length(item)==1L &&
    is.null(attributes(item)) && !is.object(item),logical(1)))
}

# A bounded observation of the exact main-DB dependencies, not a generic
# database cache. Unsafe states return NULL and force actual graph verification.
.wb_graph_retained_epoch <- function(con, artifact_id, budgets) {
  tryCatch({
    if (!DBI::dbIsValid(con) || isTRUE(RSQLite::sqliteIsTransacting(con)) ||
        !.wb_graph_retained_plain_budgets(budgets)) return(NULL)
    if (nrow(DBI::dbGetQuery(con,"SELECT 1 FROM sqlite_temp_schema LIMIT 1;"))) return(NULL)
    # Only main/temp may participate. Do not fetch arbitrary attachment paths.
    if (DBI::dbGetQuery(con,paste0("SELECT COUNT(*) AS n FROM pragma_database_list ",
        "WHERE name NOT IN ('main','temp');"))$n[[1L]] != 0L) return(NULL)
    databases <- DBI::dbGetQuery(con,
      "SELECT seq,name FROM pragma_database_list ORDER BY seq LIMIT 2;")
    if (any(!databases$name %in% c("main","temp"))) return(NULL)
    exact <- function(value) {
      if (length(value)!=1L || is.na(value)) return(NULL)
      text <- as.character(value)
      if (nchar(text,type="bytes")>16L || !grepl("^(0|[1-9][0-9]*)$",text)) return(NULL)
      number <- suppressWarnings(as.numeric(text))
      if (!is.finite(number) || number>2^53-1 ||
          !identical(sprintf("%.0f",number),text)) return(NULL)
      text
    }
    counters <- function() {
      values <- list(changes=exact(DBI::dbGetQuery(con,
        "SELECT CAST(total_changes() AS TEXT) AS n;")$n),
        data=exact(DBI::dbGetQuery(con,"PRAGMA main.data_version;")[[1L]]),
        schema=exact(DBI::dbGetQuery(con,"PRAGMA main.schema_version;")[[1L]]))
      if (any(vapply(values,is.null,logical(1)))) NULL else values
    }
    before <- counters();if(is.null(before))return(NULL)
    dependencies <- "name COLLATE NOCASE IN ('artifact_graph_meta','artifact_graph_rows','prov_run_outputs')"
    bytes <- paste0("COALESCE(octet_length(",c("type","name","tbl_name","sql"),"),0)",collapse="+")
    allowance <- min(32768,budgets$partition_bytes)
    size <- DBI::dbGetQuery(con,paste0("SELECT COUNT(*) n,COALESCE(SUM(",bytes,
      "),0) bytes FROM main.sqlite_schema WHERE ",dependencies,";"))
    if (size$n[[1L]]!=3L || !is.finite(size$bytes[[1L]]) ||
        size$bytes[[1L]]+3072>allowance) return(NULL)
    definitions <- DBI::dbGetQuery(con,paste0(
      "SELECT type,name,tbl_name,sql FROM main.sqlite_schema WHERE ",dependencies,
      " AND (",bytes,")<=? ORDER BY name LIMIT 4;"),params=list(allowance))
    if (nrow(definitions)!=3L || anyNA(definitions$sql) || any(definitions$type!="table") ||
        any(grepl("CREATE[[:space:]]+VIRTUAL",definitions$sql,ignore.case=TRUE)) ||
        sum(vapply(definitions,function(column)sum(nchar(column,type="bytes")),numeric(1)))+3072>allowance)
      return(NULL)
    after <- counters()
    if (is.null(after) || !identical(before,after) ||
        isTRUE(RSQLite::sqliteIsTransacting(con))) return(NULL)
    list(connection=con@ref,artifact_id=artifact_id,budgets=budgets,counters=after,
      databases=lapply(databases,identity),definitions=lapply(definitions,identity))
  },error=function(e)NULL)
}

.wb_graph_retained_identities <- function(bundle, artifact_id, budgets = list()) {
  con <- bundle$con
  complete <- FALSE
  on.exit(if(!complete)con@ref$wb_graph_retained_observation<-NULL,add=TRUE)
  eligible <- .wb_graph_retained_plain_budgets(budgets) &&
    .wb_graph_retained_plain_budgets(con@ref$wb_graph_policy)
  budgets <- .wb_graph_effective_budgets(con, budgets)
  .wb_assert_observational_schema(bundle,
    c("artifact_graph_meta", "artifact_graph_rows"), "graph inspection")
  before <- if(eligible).wb_graph_retained_epoch(con,artifact_id,budgets) else NULL
  prior <- con@ref$wb_graph_retained_observation
  reusable <- !is.null(before) && is.list(prior) && identical(prior$key,before)
  if(!reusable) {con@ref$wb_graph_retained_observation<-NULL;prior<-NULL}
  verify_claims <- function(observed) {
  row <- DBI::dbGetQuery(bundle$con,
    paste0("SELECT * FROM artifact_graph_meta WHERE artifact_id=? AND ",
      "COALESCE(octet_length(content_identity_json),0)+COALESCE(octet_length(binding_identity_json),0)+",
      "COALESCE(octet_length(descriptor_json),0)+COALESCE(octet_length(descriptor_identity_json),0)+",
      "COALESCE(octet_length(profile),0)+COALESCE(octet_length(direction_mode),0)+",
      "COALESCE(octet_length(canonical_bytes),0)+COALESCE(octet_length(artifact_id),0)<=?;"),
    params = list(artifact_id, .wb_graph_budgets(budgets)$partition_bytes))
  .wb_graph_require(nrow(row) == 1L, "GRAPH_RESOURCE_EXCEEDED",
    "Retained graph header changed during admitted fetch.")
  for (field in c("content_identity", "binding_identity", "descriptor_identity", "descriptor"))
    .wb_graph_require(identical(.wb_operation_pack_canonical_json(observed[[field]]),
      .wb_operation_pack_canonical_json(.wb_graph_parse(row[[paste0(field, "_json")]][[1]]))),
      "GRAPH_CONTENT_IDENTITY_MISMATCH", paste0("Retained graph differs at ", field))
  expected <- observed[c("content_identity", "binding_identity", "descriptor_identity")]
  .wb_graph_certificate_scan(bundle$con, artifact_id, function(certificate) .wb_graph_require(
    !is.na(certificate$retained_payload_identity_json[[1]]) &&
      identical(.wb_operation_pack_canonical_json(.wb_graph_parse(
        certificate$retained_payload_identity_json[[1]])), .wb_operation_pack_canonical_json(expected)) &&
      identical(certificate$content_identity_scheme[[1]], observed$content_identity$scheme) &&
      identical(certificate$content_sha256[[1]], observed$content_identity$sha256),
    "GRAPH_CONTENT_IDENTITY_MISMATCH",
    "Graph claims disagree with independently retained promotion evidence."),
    .wb_graph_budgets(budgets))
    invisible(TRUE)
  }
  # A hit never supplies authority for a header or retained certificate. Both
  # are freshly compared against the independently computed actual IDs.
  for (attempt in seq_len(2L)) {
    observed <- if(reusable)prior$value else
      .wb_graph_sql_identities(con,artifact_id,.wb_graph_budgets(budgets))
    checked <- tryCatch(verify_claims(observed),error=identity)
    after <- if(eligible).wb_graph_retained_epoch(con,artifact_id,budgets) else NULL
    stable <- !is.null(before) && identical(before,after)
    if(reusable && !stable) {
      con@ref$wb_graph_retained_observation<-NULL;prior<-NULL;reusable<-FALSE
      .wb_assert_observational_schema(bundle,
        c("artifact_graph_meta","artifact_graph_rows"),"graph inspection retry")
      before <- if(eligible).wb_graph_retained_epoch(con,artifact_id,budgets) else NULL
      next
    }
    if(inherits(checked,"error"))stop(checked)
    con@ref$wb_graph_retained_observation<-NULL
    candidate <- list(key=before,value=observed)
    if(stable && as.numeric(utils::object.size(candidate))<=65536)
      con@ref$wb_graph_retained_observation<-candidate
    complete<-TRUE
    return(observed)
  }
}

.wb_graph_load_reference <- function(bundle, artifact_id) {
  identities <- .wb_graph_retained_identities(bundle, artifact_id)
  structure(list(kind = "graph", artifact_id = artifact_id,
    content_identity = identities$content_identity, binding_identity = identities$binding_identity,
    descriptor_identity = identities$descriptor_identity), class = "wb_primitive")
}

#' Inspect a Retained Graph Without Materializing Its Rows
#' @param bundle Open bundle.
#' @param artifact_id Graph artifact ID.
#' @param budgets Resource overrides for bounded validation and token spill.
#' @return Logical identities and component counts. No physical path is returned.
#' @export
wb_art_graph_info <- function(bundle, artifact_id, budgets = list()) {
  identity <- .wb_graph_retained_identities(bundle, artifact_id, budgets)
  counts <- stats::setNames(lapply(.wb_graph_components(), function(component)
    .wb_graph_count(bundle$con, artifact_id, component)), .wb_graph_components())
  source <- tryCatch({.wb_graph_sources_assert(bundle, bundle$con, artifact_id,
      .wb_graph_budgets(budgets)); list(status = "verified")}, error = function(error)
        list(status = "unverified", reason = conditionMessage(error)))
  c(list(artifact_id = artifact_id, storage_profile = "graph_sqlite_v1",
    source_authority = source,
    component_counts = counts), identity)
}

#' Read an Ordered Retained Graph Partition
#' @param bundle Open bundle.
#' @param artifact_id Graph artifact ID.
#' @param component Graph component name.
#' @param offset Exact nonnegative decimal int64 starting row ordinal.
#' @param limit Maximum number of rows in this partition.
#' @param partition_bytes Maximum encoded bytes admitted before decoding rows.
#' @return Ordered component records. Full identity validation is available via
#'   wb_art_graph_info; invocation readers independently validate complete closure.
#' @export
wb_art_graph_slice <- function(bundle, artifact_id, component, offset = "0", limit = 512L,
                              partition_bytes = 1048576) {
  .wb_assert_observational_schema(bundle,
    c("artifact_graph_meta", "artifact_graph_rows"), "graph slice")
  .wb_graph_i64(offset)
  .wb_graph_require(component %in% .wb_graph_components() && length(component) == 1L &&
    is.numeric(limit) && length(limit) == 1L && limit > 0 && limit <= 512 && limit == floor(limit) &&
    is.numeric(partition_bytes) && length(partition_bytes) == 1L &&
    is.finite(partition_bytes) && partition_bytes > 0,
    "GRAPH_RESOURCE_EXCEEDED", "Invalid bounded slice request.")
  rows <- .wb_graph_page(bundle$con, artifact_id, component, offset, limit, partition_bytes)
  lapply(rows$record_json, function(json) {
    row <- .wb_graph_parse(json); .wb_graph_row_validate(component, row); row
  })
}

.wb_promote_graph <- function(bundle, run, out_name, prim, name = NULL,
  description = NULL, created_by = NULL, parent_artifacts = list(), workspace = NULL) {
  # Called only under the existing promotion writer lock/transaction.
  .wb_graph_require(isTRUE(RSQLite::sqliteIsTransacting(bundle$con)),
    "GRAPH_PUBLICATION_AUTHORITY_REQUIRED", "Graph publication requires promotion transaction.")
  stage <- attr(prim, "graph_stage", exact = TRUE)
  owned <- is.null(stage)
  restore_owned <- restore_budget <- NULL
  on.exit({
    if (owned && !is.null(stage)) .wb_graph_stage_discard(stage)
    if (!is.null(restore_budget)) restore_budget()
    if (!is.null(restore_owned)) restore_owned()
  }, add = TRUE)
  if (owned) {
    policy <- .wb_graph_effective_budgets(bundle$con)
    restore_owned <- .wb_graph_aggregate_connection_budget(.wb_graph_bundle_connections(bundle), policy, extra = 1L)
    stage <- .wb_graph_stage_small(prim, policy, bundle$con@ref$wb_graph_cache_kib)
  }
  restore_budget <- .wb_graph_aggregate_connection_budget(c(.wb_graph_bundle_connections(bundle), list(stage$con)),
    .wb_graph_effective_budgets(bundle$con, stage$budgets))
  baseline <- .wb_graph_disk_usage(bundle$con)
  identity <- .wb_graph_sql_identities(stage$con, "staged", stage$budgets)
  .wb_graph_require(.wb_graph_i64(identity$canonical_bytes) <= .wb_graph_i64(stage$budgets$published_bytes),
    "GRAPH_RESOURCE_EXCEEDED", "Graph canonical payload exceeds publication budget.")
  # Bindings require independent core source admission, not just self-hashes.
  .wb_graph_sources_assert(bundle, stage$con, "staged", stage$budgets)
  if (!is.null(stage$seal)) .wb_graph_require(identical(identity, stage$seal),
    "GRAPH_SEAL_MISMATCH", "Output changed after the independently recorded seal.")
  artifact_id <- .wb_new_artifact_id("graph", bundle)
  DBI::dbExecute(bundle$con, paste0("INSERT INTO artifacts(artifact_id,type,name,description,",
    "created_at,created_by,source_op,input_space_id,input_matrix_id,cell_set,provenance_json,",
    "scworkbench_version) VALUES(?,?,?,?,?,?,?,?,?,?,?,?);"), params = list(
      artifact_id, "graph", name %||% out_name, description %||% NA_character_,
      format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), created_by %||% NA_character_, run$op_name,
      .wb_run_input_space_id(run), .wb_run_input_matrix_id(run), NA_character_,
      .wb_prov_json(run, parent_artifacts), as.character(utils::packageVersion("scworkbench"))))
  DBI::dbExecute(bundle$con, paste0("INSERT INTO artifact_graph_meta(artifact_id,profile,",
    "direction_mode,content_identity_json,binding_identity_json,descriptor_json,",
    "descriptor_identity_json,canonical_bytes) VALUES(?,'graph_sqlite_v1',?,?,?,?,?,?);"),
    params = list(artifact_id, DBI::dbGetQuery(stage$con,
      "SELECT direction_mode FROM artifact_graph_meta;")$direction_mode[[1]],
      .wb_operation_pack_canonical_json(identity$content_identity),
      .wb_operation_pack_canonical_json(identity$binding_identity),
      .wb_operation_pack_canonical_json(identity$descriptor),
      .wb_operation_pack_canonical_json(identity$descriptor_identity), identity$canonical_bytes))
  published_records_bytes <- bit64::as.integer64(0)
  for (component in .wb_graph_components()) .wb_graph_scan(stage$con, "staged", component,
    function(rows) {
      published_records_bytes <<- published_records_bytes + bit64::as.integer64(sum(nchar(rows$record_json, type = "bytes")))
      .wb_graph_require(!is.na(published_records_bytes) && published_records_bytes <=
        .wb_graph_i64(stage$budgets$published_bytes), "GRAPH_RESOURCE_EXCEEDED",
        "Graph retained component bytes exceed publication budget.")
      rows$artifact_id <- artifact_id; rows$component <- component
      rows$row_ordinal <- bit64::as.integer64(rows$row_ordinal)
      DBI::dbAppendTable(bundle$con, "artifact_graph_rows", rows)
      .wb_graph_disk_admit(bundle$con, stage$budgets, baseline)
      .wb_promotion_transaction_fault("graph_component_rows", component = component)
    }, page = stage$budgets$partition_rows, bytes = stage$budgets$partition_bytes)
  .wb_graph_sources_assert(bundle, stage$con, "staged", stage$budgets)
  .wb_graph_disk_admit(bundle$con, stage$budgets, baseline)
  artifact_id
}

.wb_graph_sources_assert <- function(bundle, con, artifact_id, budgets, selected_binding_ids = NULL) {
  .wb_graph_scan(con, artifact_id, "bindings", function(rows) {
    for (json in rows$record_json) {
      binding <- .wb_graph_parse(json); binding$binding_ordinal <- NULL
      if (!is.null(selected_binding_ids) && !binding$binding_id %in% unlist(selected_binding_ids)) next
      .wb_graph_source_authorize(bundle, binding, budgets)
      query <- .wb_graph_source_axis_query(bundle, binding$source_ref, binding$axis_kind)
      .wb_graph_scan(con, artifact_id, "binding_mappings", function(mappings) {
        for (text in mappings$record_json) {
          mapping <- .wb_graph_parse(text)
          found <- DBI::dbGetQuery(bundle$con, paste0("SELECT 1 FROM (", query$sql,
            ") WHERE axis_id=? LIMIT 1;"), params = c(query$params, list(mapping$axis_id)))
          .wb_graph_require(nrow(found) == 1L, "GRAPH_SOURCE_AUTHORITY_INVALID",
            "Mapped axis member is absent from its authenticated source.")
        }
      }, page = budgets$partition_rows, bytes = budgets$partition_bytes,
        predicate = "AND json_extract(record_json,'$.binding_id')=?",
        params = list(binding$binding_id))
    }
  }, page = budgets$partition_rows, bytes = budgets$partition_bytes)
  invisible(TRUE)
}
