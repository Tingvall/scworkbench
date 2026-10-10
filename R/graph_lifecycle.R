.wb_graph_retained_identities <- function(bundle, artifact_id, budgets = list()) {
  .wb_assert_observational_schema(bundle,
    c("artifact_graph_meta", "artifact_graph_rows"), "graph inspection")
  observed <- .wb_graph_sql_identities(bundle$con, artifact_id, .wb_graph_budgets(budgets))
  row <- DBI::dbGetQuery(bundle$con,
    "SELECT * FROM artifact_graph_meta WHERE artifact_id=?;", params = list(artifact_id))
  for (field in c("content_identity", "binding_identity", "descriptor_identity", "descriptor"))
    .wb_graph_require(identical(.wb_operation_pack_canonical_json(observed[[field]]),
      .wb_operation_pack_canonical_json(.wb_graph_parse(row[[paste0(field, "_json")]][[1]]))),
      "GRAPH_CONTENT_IDENTITY_MISMATCH", paste0("Retained graph differs at ", field))
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
  c(list(artifact_id = artifact_id, storage_profile = "graph_sqlite_v1",
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
  if (owned) stage <- .wb_graph_stage_small(prim)
  on.exit(if (owned) .wb_graph_stage_discard(stage), add = TRUE)
  identity <- .wb_graph_sql_identities(stage$con, "staged", stage$budgets)
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
  for (component in .wb_graph_components()) .wb_graph_scan(stage$con, "staged", component,
    function(rows) {
      rows$artifact_id <- artifact_id; rows$component <- component
      rows$row_ordinal <- bit64::as.integer64(rows$row_ordinal)
      DBI::dbAppendTable(bundle$con, "artifact_graph_rows", rows)
      .wb_promotion_transaction_fault("graph_component_rows", component = component)
    }, page = stage$budgets$partition_rows, bytes = stage$budgets$partition_bytes)
  .wb_graph_sources_assert(bundle, stage$con, "staged", stage$budgets)
  artifact_id
}

.wb_graph_sources_assert <- function(bundle, con, artifact_id, budgets) {
  # Source-less standalone graphs need no bundle cell or feature authority.
  if (.wb_graph_count(con, artifact_id, "bindings") != "0")
    .wb_graph_error("GRAPH_SOURCE_AUTHORITY_REQUIRED",
      "Binding source authentication has not been issued.")
  invisible(TRUE)
}
