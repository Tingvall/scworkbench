#!/usr/bin/env Rscript

root <- normalizePath(file.path(dirname(sub("^--file=", "",
  commandArgs(FALSE)[grepl("^--file=", commandArgs(FALSE))])), "..", ".."),
  winslash = "/", mustWork = TRUE)
protocol <- file.path(root, "inst", "protocol")
read <- function(name) jsonlite::read_json(file.path(protocol, name),
  simplifyVector = FALSE)
`%||%` <- function(x, y) if (is.null(x)) y else x
write <- function(value, name) jsonlite::write_json(value,
  file.path(protocol, name), auto_unbox = TRUE, pretty = TRUE, null = "null",
  digits = NA)
ref <- function(name) list(`$ref` = paste0("#/$defs/", name))
string <- function(...) c(list(type = "string"), list(...))
integer <- function(...) c(list(type = "integer"), list(...))
array <- function(items, ...) c(list(type = "array", items = items), list(...))
object <- function(required, properties, ...) c(list(type = "object",
  additionalProperties = FALSE, required = unname(as.list(required)),
  properties = properties), list(...))
name <- string(pattern = "^[a-z][a-z0-9_]*$")
field_name <- string(pattern = "^[A-Za-z][A-Za-z0-9_]*$")

manifest <- read("operation-pack-v3.schema.json")
defs <- manifest[["$defs"]]
fragment_policy <- object(c("policy", "source_input",
  "source_typed_slice_read", "fragment_axis", "feature_coverage",
  "cell_coverage", "source_fragment_binding", "fragment_order",
  "minimum_fragment_count"), list(policy = list(const =
    "staged_matrix_fragments_v1"), source_input = name,
  source_typed_slice_read = name, fragment_axis = list(const = "cells"),
  feature_coverage = list(const = "exact_source_feature_order_v1"),
  cell_coverage = list(const = "exact_source_cell_order_partition_v1"),
  source_fragment_binding = list(const = "single_parent_no_crossing_v1"),
  fragment_order = list(const = "source_fragment_then_part_v1"),
  minimum_fragment_count = integer(minimum = 1L)))
for (i in seq_along(defs$output$oneOf)) {
  branch <- defs$output$oneOf[[i]]
  if (identical(branch$properties$kind$const, "matrix") &&
      identical(branch$properties$storage_profile$const,
        "matrix_backed_chunked_v1")) {
    branch$properties$fragment_policy <- fragment_policy
    defs$output$oneOf[[i]] <- branch
  }
}
publication_policy <- object(c("output", "policy", "target_kind",
  "target_id_parameter", "overwrite_parameter", "transaction_scope"),
  list(output = name, policy = list(const =
      "authenticated_add_or_replace_v1"), target_kind = list(enum =
      list("matrix", "space")), target_id_parameter = name,
    overwrite_parameter = name,
    transaction_scope = list(const = "promotion_group_v1")))
parameter_axis <- object(c("name", "policy", "parameter", "minimum",
  "maximum", "labels"), list(name = name,
  policy = list(const = "integer_parameter_axis_v1"), parameter = name,
  minimum = integer(minimum = 1L), maximum = object(c("source",
    "typed_slice_read", "cell_offset", "feature_offset"), list(
      source = list(const = "typed_slice_rank_upper_bound_v1"),
      typed_slice_read = name, cell_offset = integer(maximum = 0L),
      feature_offset = integer(maximum = 0L))),
  labels = object(c("policy", "prefix"), list(
    policy = list(const = "prefix_one_based_v1"),
    prefix = string(minLength = 1L)))))
# Operation schema is a direct object in the accepted v3 document.
defs$operation$properties$publication_policies <- array(publication_policy,
  minItems = 1L)
defs$operation$properties$parameter_axes <- array(parameter_axis,
  minItems = 1L)
flatten_one_of <- function(value) {
  branches <- value$oneOf %||% list(value)
  unlist(lapply(branches, function(branch) {
    if (!is.null(branch$oneOf)) flatten_one_of(branch) else list(branch)
  }), recursive = FALSE)
}
base_bindings <- Filter(function(branch) {
  policies <- unlist(branch$properties$policy$enum %||%
    branch$properties$policy$const %||% character(), use.names = FALSE)
  any(policies %in% c("cell_ids_or_set_v1", "feature_ids_or_all_v1"))
}, flatten_one_of(defs$parameter_binding))
defs$parameter_binding <- list(oneOf = c(base_bindings, list(
  object(c("parameter", "policy", "input", "numeric_parameter", "affix"),
    list(parameter = name,
      policy = list(const = "input_id_with_numeric_suffix_v1"),
      input = name, numeric_parameter = name,
      affix = string(minLength = 1L))),
  object(c("parameter", "policy", "input", "table_input", "field",
    "selected_field"), list(parameter = name,
      policy = list(const = "feature_ids_from_table_or_matrix_v1"),
      input = name, table_input = name, field = name,
      selected_field = name)))))
defs$retained_parameter$properties$source$enum <- unique(c(
  defs$retained_parameter$properties$source$enum,
  list("effective_parameter_value")))
dimension_name <- name
typed_axis <- object(c("source", "typed_slice_read"), list(
  source = list(const = "typed_slice_read_v1"), typed_slice_read = name))
new_dimensions <- list(
  object(c("output", "policy", "cell_axis", "dimension_axis",
    "row_order", "column_order"), list(output = name,
      policy = list(const = "cell_by_parameter_axis_v1"),
      cell_axis = typed_axis, dimension_axis = dimension_name,
      row_order = list(const = "typed_slice_cell_order_v1"),
      column_order = list(const = "parameter_axis_order_v1"))),
  object(c("output", "policy", "feature_axis", "parameter_axis",
    "row_order", "feature_field", "axis_label_field", "axis_index_field"),
    list(output = name,
      policy = list(const = "feature_parameter_axis_cartesian_v1"),
      feature_axis = typed_axis, parameter_axis = dimension_name,
      row_order = list(const = "parameter_axis_then_feature_v1"),
      feature_field = field_name, axis_label_field = field_name,
      axis_index_field = field_name)),
  object(c("output", "policy", "parameter_axis", "row_order",
    "axis_label_field", "axis_index_field"), list(output = name,
      policy = list(const = "one_per_parameter_axis_v1"),
      parameter_axis = dimension_name,
      row_order = list(const = "parameter_axis_order_v1"),
      axis_label_field = field_name, axis_index_field = field_name)),
  object(c("output", "policy", "parameter_axis", "count_field"),
    list(output = name,
      policy = list(const = "singleton_parameter_echo_v1"),
      parameter_axis = dimension_name, count_field = field_name)))
new_dimension_names <- c("cell_by_parameter_axis_v1",
  "feature_parameter_axis_cartesian_v1", "one_per_parameter_axis_v1",
  "singleton_parameter_echo_v1")
base_dimensions <- Filter(function(branch)
  !as.character(branch$properties$policy$const %||% "") %in%
    new_dimension_names, flatten_one_of(defs$dimension_policy))
defs$dimension_policy <- list(oneOf = c(base_dimensions, new_dimensions))
manifest[["$defs"]] <- defs
write(manifest, "operation-pack-v3.schema.json")

request <- read("operation-pack-transition-request-v3.schema.json")
rdefs <- request[["$defs"]]
preimage <- object(c("state"), list(state = list(enum = list("absent",
  "present"))), minProperties = 2L)
publication_grant <- object(c("schema", "output", "promotion_group",
  "closure_outputs", "target_kind", "target_id", "mode",
  "conflict_policy", "preimage", "publication_grant_identity"), list(
    schema = list(const =
      "scworkbench.operation_pack.materialization_publication_grant.v1"),
    output = name, promotion_group = name,
    closure_outputs = array(name, minItems = 1L, uniqueItems = TRUE),
    target_kind = list(enum = list("matrix", "space")),
    target_id = ref("id"), mode = list(enum = list("add", "replace")),
    conflict_policy = list(enum = list("require_absent_v1",
      "replace_exact_preimage_v1")), preimage = list(type = "object",
      minProperties = 2L), publication_grant_identity = ref("self_identity")))
source_fragment <- object(c("ordinal", "source_fragment_identity",
  "cell_start", "cell_count", "cell_order_identity"), list(
    ordinal = integer(minimum = 1L), source_fragment_identity = ref("identity"),
    cell_start = integer(minimum = 1L), cell_count = integer(minimum = 1L),
    cell_order_identity = ref("identity")))
source_schedule <- object(c("schema", "input_descriptor_identity",
  "matrix_content_identity", "source_fragment_manifest_identity",
  "fragments", "schedule_identity"), list(schema = list(const =
    "scworkbench.operation_pack.source_fragment_schedule.v1"),
  input_descriptor_identity = ref("identity"),
  matrix_content_identity = ref("identity"),
  source_fragment_manifest_identity = ref("identity"),
  fragments = array(source_fragment, minItems = 1L),
  schedule_identity = ref("self_identity")))
matrix_fragment_grant <- object(c("schema", "source_input",
  "typed_slice_grant_identity", "expected_dimensions",
  "feature_order_identity", "cell_order_identity",
  "source_fragment_schedule", "fragment_policy", "grant_identity"), list(
    schema = list(const = "scworkbench.operation_pack.matrix_fragment_grant.v1"),
    source_input = name, typed_slice_grant_identity = ref("identity"),
    expected_dimensions = ref("dimensions_2"),
    feature_order_identity = ref("identity"),
    cell_order_identity = ref("identity"),
    source_fragment_schedule = source_schedule,
    fragment_policy = fragment_policy, grant_identity = ref("self_identity")))
parameter_axis_grant <- object(c("schema", "name", "parameter", "value",
  "minimum", "maximum", "labels", "source", "axis_order_identity",
  "grant_identity"), list(schema = list(const =
    "scworkbench.operation_pack.parameter_axis_grant.v1"), name = name,
  parameter = name, value = integer(minimum = 1L), minimum = integer(),
  maximum = integer(), labels = array(string(minLength = 1L), minItems = 1L,
    uniqueItems = TRUE), source = object(c("typed_slice_grant_identity",
      "cell_axis_count", "feature_axis_count"), list(
        typed_slice_grant_identity = ref("identity"),
        cell_axis_count = integer(minimum = 0L),
        feature_axis_count = integer(minimum = 0L))),
  axis_order_identity = ref("identity"), grant_identity = ref("self_identity")))
rdefs$materialization_publication_grant <- publication_grant
rdefs$source_fragment_schedule <- source_schedule
rdefs$matrix_fragment_grant <- matrix_fragment_grant
rdefs$parameter_axis_grant <- parameter_axis_grant
for (i in seq_along(rdefs$output_descriptor$oneOf)) {
  props <- rdefs$output_descriptor$oneOf[[i]]$properties
  props$publication_grant <- ref("materialization_publication_grant")
  props$matrix_fragment_grant <- ref("matrix_fragment_grant")
  props$parameter_axis_grant_identity <- ref("identity")
  props$expected_dimension_order_identity <- ref("identity")
  rdefs$output_descriptor$oneOf[[i]]$properties <- props
}
rdefs$capability$properties$parameter_axis_grant_identities <-
  array(ref("identity"), minItems = 1L)
request$properties$parameter_axis_grants <- array(
  ref("parameter_axis_grant"), minItems = 1L)
request[["$defs"]] <- rdefs
write(request, "operation-pack-transition-request-v3.schema.json")

receipt <- read("operation-pack-transition-receipt-v3.schema.json")
odefs <- receipt[["$defs"]]
fragment_part <- object(c("ordinal", "source_fragment_ordinal",
  "source_fragment_identity", "part_ordinal", "cell_start", "cell_count",
  "dimensions", "feature_order_identity", "cell_order_identity",
  "content_identity", "payload_manifest_identity"), list(
    ordinal = integer(minimum = 1L),
    source_fragment_ordinal = integer(minimum = 1L),
    source_fragment_identity = ref("identity"),
    part_ordinal = integer(minimum = 1L), cell_start = integer(minimum = 1L),
    cell_count = integer(minimum = 1L), dimensions = list(type = "array",
      minItems = 2L, maxItems = 2L, items = integer(minimum = 1L)),
    feature_order_identity = ref("identity"),
    cell_order_identity = ref("identity"), content_identity = ref("identity"),
    payload_manifest_identity = ref("self_identity")))
fragment_manifest <- object(c("schema", "source_fragment_schedule_identity",
  "dimensions", "feature_order_identity", "cell_order_identity",
  "fragment_count", "fragments", "fragment_manifest_identity"), list(
    schema = list(const =
      "scworkbench.operation_pack.matrix_fragment_manifest.v1"),
    source_fragment_schedule_identity = ref("self_identity"),
    dimensions = list(type = "array", minItems = 2L, maxItems = 2L,
      items = integer(minimum = 1L)),
    feature_order_identity = ref("identity"),
    cell_order_identity = ref("identity"),
    fragment_count = integer(minimum = 1L),
    fragments = array(fragment_part, minItems = 1L),
    fragment_manifest_identity = ref("self_identity")))
observed_axis <- list(type = "object", minProperties = 2L)
observation <- object(c("schema", "publication_grant_identity", "mode",
  "preimage_identity", "output_observed_descriptor_identity",
  "closure_output_identities", "status", "observation_identity"), list(
    schema = list(const =
      "scworkbench.operation_pack.observed_materialization_publication.v1"),
    publication_grant_identity = ref("identity"),
    mode = list(enum = list("add", "replace")),
    preimage_identity = ref("identity"),
    output_observed_descriptor_identity = ref("identity"),
    closure_output_identities = array(object(c("name",
      "observed_descriptor_identity"), list(name = name,
      observed_descriptor_identity = ref("identity"))), minItems = 1L),
    status = list(const = "validated_not_published"),
    observation_identity = ref("self_identity")))
odefs$matrix_fragment_manifest <- fragment_manifest
odefs$publication_observation <- observation
for (i in seq_along(odefs$observed_output_descriptor$oneOf)) {
  props <- odefs$observed_output_descriptor$oneOf[[i]]$properties
  props$observed_parameter_axis <- observed_axis
  props$matrix_fragment_manifest <- ref("matrix_fragment_manifest")
  props$matrix_fragment_manifest_identity <- ref("identity")
  odefs$observed_output_descriptor$oneOf[[i]]$properties <- props
}
receipt$properties$publication_observations <- array(
  ref("publication_observation"), minItems = 1L)
receipt[["$defs"]] <- odefs
write(receipt, "operation-pack-transition-receipt-v3.schema.json")

cat("PHASE4C OPERATION-PACK SCHEMAS UPDATED\n")
