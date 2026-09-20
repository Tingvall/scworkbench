#!/usr/bin/env Rscript

root <- normalizePath(file.path(dirname(sub("^--file=", "",
  commandArgs(FALSE)[grepl("^--file=", commandArgs(FALSE))])), "..", ".."),
  winslash = "/", mustWork = TRUE)
protocol <- file.path(root, "inst", "protocol")
read <- function(name) jsonlite::read_json(file.path(protocol, name),
  simplifyVector = FALSE)
write <- function(value, name) jsonlite::write_json(value,
  file.path(protocol, name), auto_unbox = TRUE, pretty = TRUE, null = "null",
  digits = NA)
ref <- function(name) list(`$ref` = paste0("#/$defs/", name))
string <- function(...) c(list(type = "string"), list(...))
integer <- function(...) c(list(type = "integer"), list(...))
number <- function(...) c(list(type = "number"), list(...))
array <- function(items, ...) c(list(type = "array", items = items), list(...))
object <- function(required, properties, ...) c(list(type = "object",
  additionalProperties = FALSE, required = unname(as.list(required)),
  properties = properties), list(...))
name <- string(pattern = "^[a-z][a-z0-9_]*$")

manifest <- read("operation-pack-v3.schema.json")
defs <- manifest[["$defs"]]
selector <- object(c("parameter", "role", "default_all_cells",
  "include_query_parameter"), list(parameter = name,
    role = list(enum = list("query", "candidate")),
    default_all_cells = list(type = "boolean"),
    include_query_parameter = name))
typed_space <- object(c("name", "input", "reader", "kind", "role",
  "selection", "chunk_size_parameter", "call_discipline"), list(
    name = name, input = name, reader = list(const = "read_typed_space"),
    kind = list(const = "space"), role = list(enum = list("query",
      "candidate")), selection = object(c("policy", "parameter"), list(
        policy = list(const = "parameter_cell_selector_v1"),
        parameter = name)), chunk_size_parameter = name,
    call_discipline = list(const = "ordered_partition_exactly_once")))
defs$operation$properties$cell_selector_axes <- array(selector, minItems = 2L)
defs$operation$properties$typed_space_reads <- array(typed_space, minItems = 1L)
sparse_policy <- object(c("output", "policy", "representation",
  "partner_output", "query_space_read", "candidate_space_read",
  "k_parameter"), list(output = name,
    policy = list(const = "authenticated_sparse_membership_v1"),
    representation = list(enum = list("obs_table", "cell_vector_family")),
    partner_output = name, query_space_read = name,
    candidate_space_read = name, k_parameter = name))
pseudobulk_policy <- object(c("output", "policy", "membership_output",
  "query_space_read", "matrix_slice_read", "aggregate_parameter",
  "zero_neighbor_policy"), list(output = name,
    policy = list(const = "authenticated_pseudobulk_v1"),
    membership_output = name, query_space_read = name,
    matrix_slice_read = name, aggregate_parameter = name,
    zero_neighbor_policy = list(const = "zero_rows_forbidden_v1")))
phase4e_policies <- c("authenticated_sparse_membership_v1",
  "authenticated_pseudobulk_v1")
defs$dimension_policy$oneOf <- c(Filter(function(entry) {
  policy <- entry$properties$policy$const
  is.null(policy) || !policy %in% phase4e_policies
}, defs$dimension_policy$oneOf), list(sparse_policy, pseudobulk_policy))
manifest[["$defs"]] <- defs
write(manifest, "operation-pack-v3.schema.json")

request <- read("operation-pack-transition-request-v3.schema.json")
rdefs <- request[["$defs"]]
source <- object(c("input_name", "space_id", "input_descriptor_identity",
  "input_content_identity", "selected_content_identity", "transition_source_state_identity",
  "source_reference_identity"), list(input_name = name,
    space_id = string(minLength = 1L), input_descriptor_identity = ref("identity"),
    input_content_identity = ref("identity"),
    selected_content_identity = ref("identity"),
    transition_source_state_identity = ref("identity"),
    source_reference_identity = ref("self_identity")))
typed_space_grant <- object(c("schema", "name", "input_name", "reader",
  "kind", "role", "selector_parameter", "source_reference", "cells_axis",
  "dimension_count", "requested_chunk_size", "call_discipline", "max_rows",
  "max_columns", "max_elements", "grant_identity"), list(
    schema = list(const = "scworkbench.operation_pack.typed_space_grant.v1"),
    name = name, input_name = name, reader = list(const = "read_typed_space"),
    kind = list(const = "space"), role = list(enum = list("query", "candidate")),
    selector_parameter = name, source_reference = source,
    cells_axis = ref("axis_descriptor"),
    dimension_count = integer(minimum = 1L),
    requested_chunk_size = integer(minimum = 1L),
    call_discipline = list(const = "ordered_partition_exactly_once"),
    max_rows = integer(minimum = 1L), max_columns = integer(minimum = 1L),
    max_elements = number(minimum = 1), grant_identity = ref("self_identity")))
sparse_grant <- object(c("schema", "output", "representation",
  "partner_output", "query_axis_identity", "candidate_axis_identity",
  "query_count", "candidate_count", "maximum_per_query", "row_order",
  "unique_pairs", "finite_nonnegative_values", "grant_identity"), list(
    schema = list(const = "scworkbench.operation_pack.sparse_membership_grant.v1"),
    output = name, representation = list(enum = list("obs_table",
      "cell_vector_family")), partner_output = name,
    query_axis_identity = ref("identity"), candidate_axis_identity = ref("identity"),
    query_count = integer(minimum = 1L), candidate_count = integer(minimum = 1L),
    maximum_per_query = integer(minimum = 1L),
    row_order = list(const = "query_then_rank_v1"),
    unique_pairs = list(const = TRUE), finite_nonnegative_values = list(const = TRUE),
    grant_identity = ref("self_identity")))
pseudobulk_grant <- object(c("schema", "output", "membership_output",
  "query_axis_identity", "feature_axis_identity", "query_cells", "features",
  "aggregate", "zero_neighbor_policy", "row_order", "grant_identity"), list(
    schema = list(const = "scworkbench.operation_pack.pseudobulk_grant.v1"),
    output = name, membership_output = name,
    query_axis_identity = ref("identity"), feature_axis_identity = ref("identity"),
    query_cells = array(string(minLength = 1L), minItems = 1L, uniqueItems = TRUE),
    features = array(string(minLength = 1L), minItems = 1L, uniqueItems = TRUE),
    aggregate = list(enum = list("sum", "mean")),
    zero_neighbor_policy = list(const = "zero_rows_forbidden_v1"),
    row_order = list(const = "query_then_feature_v1"),
    grant_identity = ref("self_identity")))
rdefs$typed_space_grant <- typed_space_grant
rdefs$sparse_membership_grant <- sparse_grant
rdefs$pseudobulk_grant <- pseudobulk_grant
for (i in seq_along(rdefs$output_descriptor$oneOf)) {
  rdefs$output_descriptor$oneOf[[i]]$properties$sparse_membership_grant <-
    ref("sparse_membership_grant")
  rdefs$output_descriptor$oneOf[[i]]$properties$pseudobulk_grant <-
    ref("pseudobulk_grant")
}
rdefs$capability$properties$typed_space_grant_identities <- array(
  ref("identity"), minItems = 1L)
rdefs$capability$properties$reader_grants$items$oneOf <- c(Filter(
  function(entry) {
    reader <- entry$properties$reader$const
    is.null(reader) || !identical(reader, "read_typed_space")
  }, rdefs$capability$properties$reader_grants$items$oneOf), list(object(
    c("typed_space_name", "reader", "grant_identity"), list(
      typed_space_name = name, reader = list(const = "read_typed_space"),
      grant_identity = ref("self_identity")))))
request$properties$typed_space_grants <- array(ref("typed_space_grant"),
  minItems = 1L)
request[["$defs"]] <- rdefs
write(request, "operation-pack-transition-request-v3.schema.json")

receipt <- read("operation-pack-transition-receipt-v3.schema.json")
odefs <- receipt[["$defs"]]
edge <- object(c("query_cell_id", "neighbor_rank", "cell_id", "distance"),
  list(query_cell_id = string(minLength = 1L), neighbor_rank = integer(minimum = 1L),
    cell_id = string(minLength = 1L), distance = number(minimum = 0)))
sparse_observation <- object(c("schema", "grant_identity", "edge_count",
  "edge_ledger", "edge_ledger_identity", "status", "observation_identity"),
  list(schema = list(const = "scworkbench.operation_pack.sparse_membership_observation.v1"),
    grant_identity = ref("identity"), edge_count = integer(minimum = 0L),
    edge_ledger = array(edge), edge_ledger_identity = ref("identity"),
    status = list(const = "validated"), observation_identity = ref("self_identity")))
pseudobulk_observation <- object(c("schema", "grant_identity",
  "edge_ledger_identity", "row_count", "aggregate", "status",
  "observation_identity"), list(schema = list(const =
    "scworkbench.operation_pack.pseudobulk_observation.v1"),
    grant_identity = ref("identity"), edge_ledger_identity = ref("identity"),
    row_count = integer(minimum = 1L), aggregate = list(enum = list("sum", "mean")),
    status = list(const = "validated"), observation_identity = ref("self_identity")))
space_call <- object(c("schema", "grant_identity", "ordinal", "cell_count",
  "cell_order_identity", "dimensions", "semantic_content_identity",
  "space_result_identity", "call_identity"), list(schema = list(const =
    "scworkbench.operation_pack.observed_typed_space_call.v1"),
    grant_identity = ref("identity"), ordinal = integer(minimum = 1L),
    cell_count = integer(minimum = 1L), cell_order_identity = ref("identity"),
    dimensions = array(integer(minimum = 1L), minItems = 2L, maxItems = 2L),
    semantic_content_identity = ref("identity"),
    space_result_identity = ref("identity"), call_identity = ref("self_identity")))
space_usage <- object(c("schema", "request_identity", "capability_identity",
  "operation_definition_identity", "grant_identity", "calls", "call_count",
  "concatenated_cell_order_identity", "coverage_status", "usage_identity"), list(
    schema = list(const = "scworkbench.operation_pack.typed_space_usage.v1"),
    request_identity = ref("identity"), capability_identity = ref("identity"),
    operation_definition_identity = ref("identity"), grant_identity = ref("identity"),
    calls = array(space_call, minItems = 1L), call_count = integer(minimum = 1L),
    concatenated_cell_order_identity = ref("identity"),
    coverage_status = list(const = "exact"), usage_identity = ref("self_identity")))
odefs$sparse_membership_observation <- sparse_observation
odefs$pseudobulk_observation <- pseudobulk_observation
odefs$typed_space_usage <- space_usage
for (i in seq_along(odefs$observed_output_descriptor$oneOf)) {
  odefs$observed_output_descriptor$oneOf[[i]]$properties$observed_sparse_membership <-
    ref("sparse_membership_observation")
  odefs$observed_output_descriptor$oneOf[[i]]$properties$observed_pseudobulk <-
    ref("pseudobulk_observation")
}
receipt$properties$typed_space_usage <- array(ref("typed_space_usage"),
  minItems = 1L)
receipt[["$defs"]] <- odefs
write(receipt, "operation-pack-transition-receipt-v3.schema.json")

cat("PHASE4E OPERATION-PACK SCHEMAS UPDATED\n")
