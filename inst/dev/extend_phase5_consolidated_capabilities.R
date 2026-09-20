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
`%||%` <- function(x, y) if (is.null(x)) y else x
ref <- function(name) list(`$ref` = paste0("#/$defs/", name))
string <- function(...) c(list(type = "string"), list(...))
integer <- function(...) c(list(type = "integer"), list(...))
number <- function(...) c(list(type = "number"), list(...))
array <- function(items, ...) c(list(type = "array", items = items), list(...))
object <- function(required, properties, ...) c(list(type = "object",
  additionalProperties = FALSE, required = unname(as.list(required)),
  properties = properties), list(...))
name <- string(pattern = "^[a-z][a-z0-9_]*$")
nonempty <- string(minLength = 1L)
nullable_name <- list(oneOf = list(name, list(type = "null")))
identity_array <- function() array(ref("identity"), minItems = 1L)

# Manifest declarations ----------------------------------------------------
manifest <- read("operation-pack-v3.schema.json")
defs <- manifest[["$defs"]]

model_pair <- object(c("engine", "model_type"), list(
  engine = nonempty, model_type = nonempty))
self_read <- object(c("name", "input", "reader", "allowed_models",
  "linkage_policy", "maximum_file_count", "maximum_total_bytes",
  "call_discipline"), list(name = name, input = name,
    reader = list(const = "read_self_linked_contained_model_payload"),
    allowed_models = array(model_pair, minItems = 1L, uniqueItems = TRUE),
    linkage_policy = list(const =
      "authenticated_existing_source_and_cell_linkage_v1"),
    maximum_file_count = integer(minimum = 1L, maximum = 32L),
    maximum_total_bytes = integer(minimum = 1L, maximum = 1073741824),
    call_discipline = list(const = "exactly_once")))
defs$operation$properties$self_linked_contained_model_reads <- array(
  self_read, minItems = 1L)

slot <- object(c("slot", "field", "required", "allowed_kinds",
  "activation", "lifecycle_policy", "ancestry_policy"), list(
    slot = name, field = name, required = list(type = "boolean"),
    allowed_kinds = array(list(enum = list("matrix", "space", "space_2d",
      "cell_vector", "cell_vector_family", "feature_table", "obs_table",
      "model_ref", "path_2d_family", "space_path_family")), minItems = 1L,
      uniqueItems = TRUE), activation = list(enum = list("always",
        "when_present")), lifecycle_policy = list(const = "require_current"),
    ancestry_policy = list(const = "require_content_verified_producer")))
artifact_read <- object(c("name", "parameter", "reader", "item_key_field",
  "order_field", "minimum_items", "maximum_items", "reference_slots",
  "maximum_references", "maximum_single_payload_bytes",
  "maximum_total_payload_bytes", "call_discipline"), list(name = name,
    parameter = name, reader = list(const =
      "read_retained_artifact_collection_item"), item_key_field = name,
    order_field = name, minimum_items = integer(minimum = 1L, maximum = 64L),
    maximum_items = integer(minimum = 1L, maximum = 64L),
    reference_slots = array(slot, minItems = 1L, maxItems = 8L),
    maximum_references = integer(minimum = 1L, maximum = 256L),
    maximum_single_payload_bytes = integer(minimum = 1L, maximum = 268435456),
    maximum_total_payload_bytes = integer(minimum = 1L, maximum = 1073741824),
    call_discipline = list(const = "resolved_ordinal_slot_exactly_once")))
defs$operation$properties$artifact_collection_reads <- array(artifact_read,
  minItems = 1L, maxItems = 8L)

axis_collection <- object(c("name", "parameter", "space_input", "reader",
  "minimum_axes", "maximum_axes", "minimum_cells_per_axis",
  "maximum_cells_per_axis", "maximum_total_memberships",
  "projection_policy", "call_discipline"), list(name = name,
    parameter = name, space_input = name,
    reader = list(const = "read_named_cell_axis"),
    minimum_axes = integer(minimum = 1L, maximum = 64L),
    maximum_axes = integer(minimum = 1L, maximum = 64L),
    minimum_cells_per_axis = integer(minimum = 1L, maximum = 10000000),
    maximum_cells_per_axis = integer(minimum = 1L, maximum = 10000000),
    maximum_total_memberships = integer(minimum = 1L, maximum = 20000000),
    projection_policy = list(const =
      "bundle_membership_intersect_space_axis_v1"),
    call_discipline = list(const = "axis_ordinal_exactly_once")))
defs$operation$properties$named_cell_axis_collections <- array(
  axis_collection, minItems = 1L, maxItems = 4L)

selector <- object(c("endpoint_parameter", "top_level_cell_set_parameter"),
  list(endpoint_parameter = name,
    top_level_cell_set_parameter = nullable_name))
display_selector <- object(c("operation_parameter", "item_field"), list(
  operation_parameter = name, item_field = nullable_name))
display_group <- object(c("name", "scope", "collection_read", "activation",
  "display_space_selector", "endpoint_roles", "dimension_count",
  "maximum_groups", "maximum_display_cells",
  "maximum_cells_per_endpoint_axis", "maximum_total_endpoint_memberships",
  "call_discipline"), list(name = name, scope = list(enum = list(
    "operation", "collection_item")), collection_read = nullable_name,
    activation = object(c("start", "end"), list(start = selector,
      end = selector)), display_space_selector = display_selector,
    endpoint_roles = list(type = "array", prefixItems = list(
      list(const = "start"), list(const = "end")), minItems = 2L,
      maxItems = 2L), dimension_count = list(const = 2L),
    maximum_groups = integer(minimum = 1L, maximum = 64L),
    maximum_display_cells = integer(minimum = 1L, maximum = 10000000),
    maximum_cells_per_endpoint_axis = integer(minimum = 1L,
      maximum = 10000000), maximum_total_endpoint_memberships = integer(
      minimum = 1L, maximum = 20000000), call_discipline = list(const =
        "display_partition_then_endpoint_ordinal_exactly_once")))
defs$operation$properties$optional_display_axis_groups <- array(display_group,
  minItems = 1L)

sibling_policy <- object(c("policy", "engine", "model_type", "primary_path",
  "source_space_input", "dimensions_parameter", "required_sibling_terminals",
  "file_order", "maximum_file_count", "maximum_total_bytes"), list(
    policy = list(const = "staged_contained_model_sibling_closure_v1"),
    engine = nonempty, model_type = nonempty,
    primary_path = string(pattern =
      "^(?!/)(?!.*(?:^|/)\\.\\.(?:/|$))(?!.*\\\\)[A-Za-z0-9._/-]+$"),
    source_space_input = name,
    dimensions_parameter = list(oneOf = list(name, list(type = "null"))),
    required_sibling_terminals = array(name, minItems = 1L,
      uniqueItems = TRUE),
    file_order = list(const = "utf8_path_lexicographic_v1"),
    maximum_file_count = integer(minimum = 1L, maximum = 32L),
    maximum_total_bytes = integer(minimum = 1L, maximum = 1073741824)))
for (i in seq_along(defs$output$oneOf)) if (identical(
    defs$output$oneOf[[i]]$properties$kind$const, "model_ref"))
  defs$output$oneOf[[i]]$properties$contained_model_sibling_closure_policy <-
    sibling_policy
manifest[["$defs"]] <- defs
write(manifest, "operation-pack-v3.schema.json")

# Request grants -----------------------------------------------------------
request <- read("operation-pack-transition-request-v3.schema.json")
rdefs <- request[["$defs"]]
limits_model <- object(c("maximum_file_count", "maximum_total_bytes"), list(
  maximum_file_count = integer(minimum = 1L, maximum = 32L),
  maximum_total_bytes = integer(minimum = 1L, maximum = 1073741824)))
linkage <- object(c("engine", "model_type", "source_space_id",
  "source_space_content_identity", "fitted_cell_order_identity",
  "selected_dimension_count", "selected_dimension_order_identity",
  "source_snapshot_id", "linkage_identity"), list(engine = nonempty,
    model_type = nonempty, source_space_id = nonempty,
    source_space_content_identity = ref("identity"),
    fitted_cell_order_identity = ref("identity"),
    selected_dimension_count = integer(minimum = 1L),
    selected_dimension_order_identity = ref("identity"),
    source_snapshot_id = nonempty, linkage_identity = ref("self_identity")))
rdefs$model_source_linkage_v2 <- linkage
self_grant <- object(c("schema", "name", "input_name", "reader",
  "declaration_identity", "selected_model", "input_descriptor_identity",
  "model_content_identity", "model_source_linkage",
  "model_source_linkage_identity", "contained_payload_identity",
  "payload_manifest_identity", "tree_manifest", "limits", "relative_root",
  "access", "call_discipline", "grant_identity"), list(schema = list(
    const = "scworkbench.operation_pack.self_linked_contained_model_read_grant.v1"),
    name = name, input_name = name, reader = list(const =
      "read_self_linked_contained_model_payload"),
    declaration_identity = ref("identity"), selected_model = model_pair,
    input_descriptor_identity = ref("identity"),
    model_content_identity = ref("identity"), model_source_linkage = linkage,
    model_source_linkage_identity = ref("identity"),
    contained_payload_identity = ref("identity"),
    payload_manifest_identity = ref("identity"),
    tree_manifest = ref("contained_model_tree_manifest"), limits = limits_model,
    relative_root = ref("relative_root"),
    access = list(const = "verified_private_copy_read_only_v1"),
    call_discipline = list(const = "exactly_once"),
    grant_identity = ref("self_identity")))
rdefs$self_linked_contained_model_read_grant <- self_grant

sibling <- object(c("name", "allocated_id", "kind", "grant_identity",
  "replay_policy", "expected_cell_order_identity_if_cell_indexed"), list(
    name = name, allocated_id = ref("id"), kind = nonempty,
    grant_identity = ref("identity"), replay_policy = nonempty,
    expected_cell_order_identity_if_cell_indexed = list(oneOf = list(
      ref("identity"), list(type = "null")))))
sibling_write <- object(c("schema", "output", "engine", "model_type",
  "primary_path", "relative_root", "source_space", "model_source_linkage",
  "required_sibling_terminals", "model_sibling_closure_identity", "limits",
  "write_grant_identity"), list(schema = list(const =
    "scworkbench.operation_pack.contained_model_sibling_write_grant.v1"),
    output = name, engine = nonempty, model_type = nonempty,
    primary_path = nonempty, relative_root = ref("relative_root"),
    source_space = rdefs$contained_model_write_grant$properties$source_space,
    model_source_linkage = linkage,
    required_sibling_terminals = array(sibling, minItems = 1L),
    model_sibling_closure_identity = ref("identity"), limits = limits_model,
    write_grant_identity = ref("self_identity")))
rdefs$contained_model_sibling_write_grant <- sibling_write

artifact_ref <- object(c("slot", "artifact_id", "output_name", "kind",
  "content_identity", "lifecycle_identity", "ancestry_identity",
  "payload_manifest_identity", "reference_identity"), list(slot = name,
    artifact_id = nonempty, output_name = name, kind = nonempty,
    content_identity = ref("identity"), lifecycle_identity = ref("identity"),
    ancestry_identity = ref("identity"), payload_manifest_identity = ref("identity"),
    reference_identity = ref("identity")))
artifact_item <- object(c("parameter_ordinal", "resolved_ordinal", "item_key",
  "order_value", "references", "item_identity"), list(
    parameter_ordinal = integer(minimum = 1L),
    resolved_ordinal = integer(minimum = 1L), item_key = nonempty,
    order_value = number(), references = array(artifact_ref, minItems = 1L),
    item_identity = ref("identity")))
artifact_grant <- object(c("schema", "name", "parameter", "reader", "limits",
  "collection_identity", "items", "call_discipline", "grant_identity"), list(
    schema = list(const =
      "scworkbench.operation_pack.retained_artifact_collection_grant.v1"),
    name = name, parameter = name, reader = list(const =
      "read_retained_artifact_collection_item"), limits = list(type = "object"),
    collection_identity = ref("identity"), items = array(artifact_item,
      minItems = 1L), call_discipline = list(const =
        "resolved_ordinal_slot_exactly_once"),
    grant_identity = ref("self_identity")))
rdefs$retained_artifact_collection_grant <- artifact_grant

axis_descriptor <- object(c("ordinal", "name", "role", "source_count",
  "selected_count", "excluded_by_projection_count", "source_identity",
  "selection_identity", "cell_order_identity", "axis_identity",
  "payload_manifest_identity"), list(ordinal = integer(minimum = 1L),
    name = nonempty, role = nonempty, source_count = integer(minimum = 1L),
    selected_count = integer(minimum = 1L),
    excluded_by_projection_count = integer(minimum = 0L),
    source_identity = ref("identity"), selection_identity = ref("identity"),
    cell_order_identity = ref("identity"), axis_identity = ref("identity"),
    payload_manifest_identity = ref("identity")))
axis_grant <- object(c("schema", "name", "parameter", "space_input",
  "space_descriptor_identity", "collection_identity", "axes",
  "quality_observations", "limits", "call_discipline", "grant_identity"),
  list(schema = list(const =
      "scworkbench.operation_pack.named_cell_axis_collection_grant.v1"),
    name = name, parameter = name, space_input = name,
    space_descriptor_identity = ref("identity"),
    collection_identity = ref("identity"),
    axes = array(axis_descriptor, minItems = 1L),
    quality_observations = list(type = "object"), limits = list(type = "object"),
    call_discipline = list(const = "axis_ordinal_exactly_once"),
    grant_identity = ref("self_identity")))
rdefs$named_cell_axis_collection_grant <- axis_grant

display_descriptor <- object(c("space_id", "space_descriptor_identity",
  "space_content_identity", "dimension_count", "cell_count",
  "cell_order_identity", "payload_manifest_identity"), list(
    space_id = nonempty, space_descriptor_identity = ref("identity"),
    space_content_identity = ref("identity"), dimension_count = list(const = 2L),
    cell_count = integer(minimum = 1L), cell_order_identity = ref("identity"),
    payload_manifest_identity = ref("identity")))
endpoint_descriptor <- object(c("ordinal", "role", "name", "source_kind",
  "source_identity", "selection_identity", "cell_order_identity",
  "axis_identity", "payload_manifest_identity"), list(
    ordinal = integer(minimum = 1L, maximum = 2L),
    role = list(enum = list("start", "end")), name = nonempty,
    source_kind = list(enum = list("named_cell_set", "literal_parameter_cells")),
    source_identity = ref("identity"), selection_identity = ref("identity"),
    cell_order_identity = ref("identity"), axis_identity = ref("identity"),
    payload_manifest_identity = ref("identity")))
display_grant <- object(c("schema", "name", "group_key", "scope",
  "source_collection_item_identity", "display_space", "endpoint_axes",
  "limits", "call_discipline", "grant_identity"), list(schema = list(
    const = "scworkbench.operation_pack.optional_display_axis_group_grant.v1"),
    name = name, group_key = nonempty,
    scope = list(enum = list("operation", "collection_item")),
    source_collection_item_identity = list(oneOf = list(ref("identity"),
      list(type = "null"))), display_space = display_descriptor,
    endpoint_axes = array(endpoint_descriptor, minItems = 1L, maxItems = 2L),
    limits = list(type = "object"), call_discipline = list(const =
      "display_partition_then_endpoint_ordinal_exactly_once"),
    grant_identity = ref("self_identity")))
rdefs$optional_display_axis_group_grant <- display_grant

for (i in seq_along(rdefs$output_descriptor$oneOf)) if (identical(
    rdefs$output_descriptor$oneOf[[i]]$properties$kind$const, "model_ref"))
  rdefs$output_descriptor$oneOf[[i]]$properties$
    contained_model_sibling_write_grant <- ref(
      "contained_model_sibling_write_grant")
request$properties$self_linked_model_payload_grants <- array(ref(
  "self_linked_contained_model_read_grant"), minItems = 1L)
request$properties$artifact_collection_grants <- array(ref(
  "retained_artifact_collection_grant"), minItems = 1L)
request$properties$named_cell_axis_collection_grants <- array(ref(
  "named_cell_axis_collection_grant"), minItems = 1L)
request$properties$optional_display_axis_group_grants <- array(ref(
  "optional_display_axis_group_grant"), minItems = 1L)

cap <- rdefs$capability$properties
for (field in c("self_linked_model_payload_grant_identities",
    "artifact_collection_grant_identities",
    "named_cell_axis_collection_grant_identities",
    "optional_display_axis_group_grant_identities")) cap[[field]] <-
      identity_array()
new_reader <- function(key, reader) object(c(key, "reader", "grant_identity"),
  setNames(list(name, list(const = reader), ref("self_identity")),
    c(key, "reader", "grant_identity")))
arms <- cap$reader_grants$items$oneOf
phase5_readers <- c("read_self_linked_contained_model_payload",
  "read_retained_artifact_collection_item", "read_named_cell_axis",
  "read_optional_display_space", "read_optional_endpoint_axis",
  "read_optional_display_axis_group")
arms <- Filter(function(entry) !as.character(entry$properties$reader$const %||%
  "")[1] %in% phase5_readers, arms)
arms <- c(arms, list(
  new_reader("self_linked_model_payload_name",
    "read_self_linked_contained_model_payload"),
  new_reader("artifact_collection_name",
    "read_retained_artifact_collection_item"),
  new_reader("named_cell_axis_collection_name", "read_named_cell_axis"),
  new_reader("optional_display_axis_group_name",
    "read_optional_display_space"),
  new_reader("optional_endpoint_axis_group_name",
    "read_optional_endpoint_axis")))
cap$reader_grants$items$oneOf <- arms
rdefs$capability$properties <- cap
request[["$defs"]] <- rdefs
write(request, "operation-pack-transition-request-v3.schema.json")

# Receipt observations -----------------------------------------------------
receipt <- read("operation-pack-transition-receipt-v3.schema.json")
odefs <- receipt[["$defs"]]
self_observation <- object(c("schema", "name", "grant_identity",
  "input_descriptor_identity", "model_source_linkage_identity",
  "tree_manifest_identity", "payload_manifest_identity", "engine",
  "model_type", "use_count", "integrity_status", "observation_identity"),
  list(schema = list(const =
      "scworkbench.operation_pack.observed_self_linked_contained_model_read.v1"),
    name = name, grant_identity = ref("identity"),
    input_descriptor_identity = ref("identity"),
    model_source_linkage_identity = ref("identity"),
    tree_manifest_identity = ref("identity"),
    payload_manifest_identity = ref("identity"), engine = nonempty,
    model_type = nonempty, use_count = list(const = 1L),
    integrity_status = list(const = "unchanged"),
    observation_identity = ref("self_identity")))
odefs$self_linked_contained_model_read_observation <- self_observation
sibling_observation <- object(c("schema", "write_grant_identity",
  "tree_manifest", "tree_manifest_identity", "payload_manifest_identity",
  "model_source_linkage_identity",
  "ordered_sibling_observed_descriptor_identities",
  "model_sibling_closure_identity", "loadability_status",
  "observation_identity"), list(schema = list(const =
    "scworkbench.operation_pack.contained_model_sibling_tree_observation.v1"),
    write_grant_identity = ref("identity"),
    tree_manifest = ref("contained_model_tree_manifest"),
    tree_manifest_identity = ref("identity"),
    payload_manifest_identity = ref("identity"),
    model_source_linkage_identity = ref("identity"),
    ordered_sibling_observed_descriptor_identities = identity_array(),
    model_sibling_closure_identity = ref("identity"),
    loadability_status = list(const = "contained_tree_authenticated"),
    observation_identity = ref("self_identity")))
odefs$contained_model_sibling_tree_observation <- sibling_observation

usage <- function(schema, extra) object(c("schema", "request_identity",
  "capability_identity", "operation_definition_identity", "grant_identity",
  names(extra), "usage_identity"), c(list(schema = list(const = schema),
    request_identity = ref("identity"), capability_identity = ref("identity"),
    operation_definition_identity = ref("identity"),
    grant_identity = ref("identity")), extra,
    list(usage_identity = ref("self_identity"))))
artifact_call <- object(c("resolved_ordinal", "slot", "reference_identity",
  "result_identity"), list(resolved_ordinal = integer(minimum = 1L),
    slot = name, reference_identity = ref("identity"),
    result_identity = ref("identity")))
artifact_usage <- usage(
  "scworkbench.operation_pack.retained_artifact_collection_usage.v1", list(
    calls = array(artifact_call, minItems = 1L),
    call_count = integer(minimum = 1L),
    concatenated_reference_order_identity = ref("identity"),
    coverage_status = list(const = "exact")))
axis_call <- object(c("ordinal", "axis_identity", "result_identity"), list(
  ordinal = integer(minimum = 1L), axis_identity = ref("identity"),
  result_identity = ref("identity")))
axis_usage <- usage(
  "scworkbench.operation_pack.named_cell_axis_collection_usage.v1", list(
    calls = array(axis_call, minItems = 1L),
    call_count = integer(minimum = 1L),
    collection_order_identity = ref("identity"),
    coverage_status = list(const = "exact")))
display_usage <- usage(
  "scworkbench.operation_pack.optional_display_axis_group_usage.v1", list(
    display_calls = array(ref("identity"), minItems = 1L),
    endpoint_calls = array(ref("identity"), minItems = 1L),
    display_coverage_status = list(const = "exact"),
    endpoint_coverage_status = list(const = "exact")))
odefs$retained_artifact_collection_usage <- artifact_usage
odefs$named_cell_axis_collection_usage <- axis_usage
odefs$optional_display_axis_group_usage <- display_usage
for (i in seq_along(odefs$observed_output_descriptor$oneOf)) if (identical(
    odefs$observed_output_descriptor$oneOf[[i]]$properties$kind$const,
    "model_ref")) odefs$observed_output_descriptor$oneOf[[i]]$properties$
      contained_model_sibling_tree <- ref(
        "contained_model_sibling_tree_observation")
receipt$properties$self_linked_model_payload_reads <- array(ref(
  "self_linked_contained_model_read_observation"), minItems = 1L)
receipt$properties$artifact_collection_usage <- array(ref(
  "retained_artifact_collection_usage"), minItems = 1L)
receipt$properties$named_cell_axis_collection_usage <- array(ref(
  "named_cell_axis_collection_usage"), minItems = 1L)
receipt$properties$optional_display_axis_group_usage <- array(ref(
  "optional_display_axis_group_usage"), minItems = 1L)
receipt[["$defs"]] <- odefs
write(receipt, "operation-pack-transition-receipt-v3.schema.json")

cat("PHASE5 CONSOLIDATED CAPABILITY SCHEMAS UPDATED\n")
