.wb_graph_retained_identities <- function(bundle, artifact_id, budgets = list()) {
  budgets <- .wb_graph_effective_budgets(bundle$con, budgets)
  .wb_assert_observational_schema(bundle,
    c("artifact_graph_meta", "artifact_graph_rows"), "graph inspection")
  observed <- .wb_graph_sql_identities(bundle$con, artifact_id, .wb_graph_budgets(budgets))
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
  observed
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
