#!/usr/bin/env Rscript

root <- normalizePath(file.path(dirname(sub("^--file=", "",
  commandArgs(FALSE)[grepl("^--file=", commandArgs(FALSE))])), "..", ".."),
  winslash = "/", mustWork = TRUE)
protocol <- file.path(root, "inst", "protocol")
`%||%` <- function(x, y) if (is.null(x)) y else x
read <- function(name) jsonlite::read_json(file.path(protocol, name),
  simplifyVector = FALSE)
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
nonempty <- string(minLength = 1L)
identity <- ref("identity")
self_identity <- object(c("scheme", "scope", "sha256"), list(
  scheme = nonempty, scope = nonempty,
  sha256 = string(pattern = "^[a-f0-9]{64}$")))
nullable_identity <- list(oneOf = list(identity, list(type = "null")))
nullable_object <- list(oneOf = list(list(type = "object", minProperties = 1L),
  list(type = "null")))
cell_ids <- array(nonempty, uniqueItems = TRUE, maxItems = 10000000L)

# Manifest -------------------------------------------------------------------
manifest <- read("operation-pack-v3.schema.json")
defs <- manifest[["$defs"]]
key_axis <- defs$dimension_policy$oneOf[[which(vapply(
  defs$dimension_policy$oneOf, function(x) identical(
    x$properties$policy$const, "authenticated_output_axes_v1"),
  logical(1)))]]$properties$key_axis
selector <- list(oneOf = list(
  object(c("mode", "key"), list(mode = list(const = "literal"),
    key = nonempty)),
  object(c("mode", "parameter"), list(mode = list(const =
    "operation_parameter"), parameter = name)),
  object(c("mode", "field"), list(mode = list(const =
    "collection_item_field"), field = name)),
  object(c("mode", "prefix_parameter", "literal_suffix"), list(
    mode = list(const = "parameter_prefix_plus_literal_suffix"),
    prefix_parameter = name, literal_suffix = nonempty))))
source <- list(oneOf = list(
  object(c("mode", "input", "projection", "family_key_selector"), list(
    mode = list(const = "static_input_axis"), input = name,
    projection = list(enum = list("cell_vector_axis_v1",
      "family_key_cell_axis_v1")), family_key_selector = list(oneOf = list(
        selector, list(type = "null"))))),
  object(c("mode", "collection", "slot", "projection",
      "family_key_selector"), list(mode = list(const =
        "g4_collection_member_axis"), collection = name, slot = name,
      projection = list(enum = list("cell_vector_axis_v1",
        "family_key_cell_axis_v1")), family_key_selector = list(oneOf = list(
          selector, list(type = "null")))))))
linked <- list(oneOf = list(
  object(c("name", "shape", "row_order", "missing_values"), list(
    name = name, shape = list(const = "one_per_cell"),
    row_order = list(const = "sealed_cell_axis_order_v1"),
    missing_values = list(enum = list("allowed", "forbidden")))),
  object(c("name", "shape", "row_order", "missing_values", "key_axis"),
    list(name = name, shape = list(enum = list("cell_key_cartesian",
      "bounded_grouped_cell_key_cartesian")), row_order = list(const =
        "key_major_then_sealed_cell_v1"), missing_values = list(enum = list(
          "allowed", "forbidden")), key_axis = key_axis))))
limits <- object(c("minimum_cells", "maximum_cells", "maximum_source_axes",
  "maximum_source_memberships", "maximum_linked_outputs"), list(
    minimum_cells = integer(minimum = 1L, maximum = 10000000L),
    maximum_cells = integer(minimum = 1L, maximum = 10000000L),
    maximum_source_axes = integer(minimum = 1L, maximum = 64L),
    maximum_source_memberships = integer(minimum = 1L, maximum = 20000000L),
    maximum_linked_outputs = integer(minimum = 1L, maximum = 16L)))
axis <- object(c("schema", "name", "derivation_mode", "source",
  "linked_outputs", "limits", "call_discipline", "closure_policy",
  "declaration_identity"), list(schema = list(const =
    "scworkbench.operation_pack.derived_cell_output_axis.v1"), name = name,
    derivation_mode = list(enum = list("ordered_unique_subset_v1",
      "declared_ordered_unique_union_v1")), source = source,
    linked_outputs = array(linked, minItems = 1L, maxItems = 16L),
    limits = limits, call_discipline = list(const =
      "declare_once_seal_before_linked_output_v1"), closure_policy = list(
        const = "all_linked_outputs_and_axis_observation_required_v1"),
    declaration_identity = self_identity))
defs$operation$properties$derived_cell_output_axes <- array(axis,
  minItems = 1L, maxItems = 4L)
manifest[["$defs"]] <- defs
write(manifest, "operation-pack-v3.schema.json")

# Request --------------------------------------------------------------------
request <- read("operation-pack-transition-request-v3.schema.json")
rdefs <- request[["$defs"]]
static_ref <- object(c("source_mode", "input_name",
  "input_descriptor_identity", "primitive_kind", "projection",
  "source_axis_selector_identity", "source_cell_count",
  "source_cell_order_identity", "source_axis_reference_identity"), list(
    source_mode = list(const = "static_input_axis"), input_name = name,
    input_descriptor_identity = identity, primitive_kind = list(enum = list(
      "cell_vector", "cell_vector_family")), projection = list(enum = list(
        "cell_vector_axis_v1", "family_key_cell_axis_v1")),
    source_axis_selector_identity = nullable_identity,
    source_cell_count = integer(minimum = 1L, maximum = 10000000L),
    source_cell_order_identity = identity,
    source_axis_reference_identity = self_identity))
member_ref <- object(c("source_mode", "collection_name",
  "collection_identity", "resolved_ordinal", "item_identity", "slot_name",
  "slot_reference_identity", "primitive_descriptor_identity",
  "primitive_kind", "projection", "source_axis_selector_identity",
  "source_cell_count", "source_cell_order_identity",
  "source_axis_reference_identity"), list(source_mode = list(const =
    "g4_collection_member_axis"), collection_name = name,
    collection_identity = identity, resolved_ordinal = integer(minimum = 1L,
      maximum = 64L), item_identity = identity, slot_name = name,
    slot_reference_identity = identity, primitive_descriptor_identity = identity,
    primitive_kind = list(enum = list("cell_vector", "cell_vector_family")),
    projection = list(enum = list("cell_vector_axis_v1",
      "family_key_cell_axis_v1")), source_axis_selector_identity =
        nullable_identity, source_cell_count = integer(minimum = 1L,
          maximum = 10000000L), source_cell_order_identity = identity,
    source_axis_reference_identity = self_identity))
rdefs$derived_cell_source_axis_reference <- list(oneOf = list(static_ref,
  member_ref))
aggregate <- object(c("derivation_mode", "source_axis_count",
  "source_membership_count", "ordered_source_axis_reference_identities",
  "source_axis_aggregate_identity"), list(derivation_mode = list(enum = list(
    "ordered_unique_subset_v1", "declared_ordered_unique_union_v1")),
    source_axis_count = integer(minimum = 1L, maximum = 64L),
    source_membership_count = integer(minimum = 1L, maximum = 20000000L),
    ordered_source_axis_reference_identities = array(identity, minItems = 1L,
      maxItems = 64L), source_axis_aggregate_identity = self_identity))
closure_item <- object(c("name", "allocated_id", "kind",
  "ordinary_output_grant_identity", "shape", "row_order", "missing_values",
  "resolved_key_axis_policy_identity_or_null", "promotion_group"), list(
    name = name, allocated_id = ref("id"), kind = list(enum = list(
      "cell_vector", "cell_vector_family")), ordinary_output_grant_identity =
      identity, shape = list(enum = list("one_per_cell", "cell_key_cartesian",
        "bounded_grouped_cell_key_cartesian")), row_order = list(enum = list(
          "sealed_cell_axis_order_v1", "key_major_then_sealed_cell_v1")),
    missing_values = list(enum = list("allowed", "forbidden")),
    resolved_key_axis_policy_identity_or_null = nullable_identity,
    promotion_group = nonempty))
closure <- object(c("manifest_declaration_identity", "linked_outputs",
  "closure_policy", "linked_output_closure_identity"), list(
    manifest_declaration_identity = identity,
    linked_outputs = array(closure_item, minItems = 1L, maxItems = 16L),
    closure_policy = list(const =
      "all_linked_outputs_and_axis_observation_required_v1"),
    linked_output_closure_identity = self_identity))
grant <- object(c("schema", "name", "derivation_mode",
  "manifest_declaration_identity", "source_axes", "source_axis_aggregate",
  "linked_output_closure", "limits", "call_discipline", "closure_policy",
  "grant_identity"), list(schema = list(const =
    "scworkbench.operation_pack.authenticated_derived_cell_output_axis_grant.v1"),
    name = name, derivation_mode = list(enum = list(
      "ordered_unique_subset_v1", "declared_ordered_unique_union_v1")),
    manifest_declaration_identity = identity,
    source_axes = array(ref("derived_cell_source_axis_reference"), minItems = 1L,
      maxItems = 64L), source_axis_aggregate = aggregate,
    linked_output_closure = closure, limits = limits,
    call_discipline = list(const = "declare_once_seal_before_linked_output_v1"),
    closure_policy = list(const =
      "all_linked_outputs_and_axis_observation_required_v1"),
    grant_identity = self_identity))
member_selection <- object(c("source_axis_reference_identity",
  "resolved_ordinal", "selected_cell_ids"), list(
    source_axis_reference_identity = identity,
    resolved_ordinal = integer(minimum = 1L, maximum = 64L),
    selected_cell_ids = cell_ids))
rdefs$derived_cell_output_axis_declaration <- object(c("schema",
  "grant_identity", "derivation_mode", "member_selections",
  "final_cell_ids", "pack_declaration_identity"), list(schema = list(const =
    "scworkbench.operation_pack.derived_cell_output_axis_declaration.v1"),
    grant_identity = identity, derivation_mode = list(enum = list(
      "ordered_unique_subset_v1", "declared_ordered_unique_union_v1")),
    member_selections = list(oneOf = list(array(member_selection,
      minItems = 1L, maxItems = 64L), list(type = "null"))),
    final_cell_ids = cell_ids, pack_declaration_identity = self_identity))
resolved_feature_group <- object(c("key", "features_input",
  "features_matched", "features_missing"), list(key = nonempty,
    features_input = array(nonempty, uniqueItems = TRUE),
    features_matched = array(nonempty, uniqueItems = TRUE),
    features_missing = array(nonempty, uniqueItems = TRUE)))
key_resolution <- list(oneOf = list(
  object(c("source", "groups_parameter", "matrix_input",
    "matrix_input_descriptor_identity", "matrix_feature_axis_identity",
    "name_prefix_parameter", "name_prefix_value", "matching",
    "normalization", "generated_names", "missing_feature_policy",
    "empty_group_policy", "zero_key_policy", "groups"), list(
      source = list(const = "resolved_parameter_feature_groups_v1"),
      groups_parameter = name, matrix_input = name,
      matrix_input_descriptor_identity = identity,
      matrix_feature_axis_identity = identity, name_prefix_parameter = name,
      name_prefix_value = nonempty, matching = list(const =
        "exact_feature_id_v1"), normalization = list(const =
          "ordered_unique_features_v1"), generated_names = list(const =
            "legacy_module_group_names_v1"), missing_feature_policy = list(
              enum = list("drop", "error")), empty_group_policy = list(enum =
                list("drop", "error")), zero_key_policy = list(enum = list(
                  "allow", "error")), groups = array(resolved_feature_group,
                    uniqueItems = TRUE))),
  object(c("source", "input", "input_descriptor_identity",
    "selector_parameter", "selector_value", "no_selector_order",
    "selector_order", "unknown_key_policy", "zero_key_policy", "keys"),
    list(source = list(const = "input_keys_with_optional_selector_v1"),
      input = name, input_descriptor_identity = identity,
      selector_parameter = list(oneOf = list(name, list(type = "null"))),
      selector_value = list(oneOf = list(array(nonempty, uniqueItems = TRUE),
        list(type = "null"))), no_selector_order = list(const =
          "first_occurrence_v1"), selector_order = list(const =
            "normalized_parameter_order_v1"), unknown_key_policy = list(
              const = "error"), zero_key_policy = list(enum = list("allow",
                "error")), keys = array(nonempty, uniqueItems = TRUE))),
  object(c("source", "base_keys", "prefix_parameter", "prefix_value",
    "keys"), list(source = list(const =
      "declared_keys_with_optional_prefix_v1"), base_keys = array(nonempty,
        uniqueItems = TRUE), prefix_parameter = name, prefix_value = string(),
      keys = array(nonempty, uniqueItems = TRUE))),
  object(c("source", "required_keys", "optional_groups", "selection_owner",
    "group_order"), list(source = list(const =
      "declared_bounded_key_groups_v1"), required_keys = array(nonempty,
        uniqueItems = TRUE), optional_groups = array(object(c("name", "keys"),
          list(name = name, keys = array(nonempty, minItems = 1L,
            uniqueItems = TRUE))), uniqueItems = TRUE), selection_owner = list(
              const = "writer_observed_v1"), group_order = list(const =
                "manifest_order_v1")))))
resolved_policy <- object(c("declaration", "keys", "resolution"), list(
  declaration = key_axis, keys = array(nonempty, uniqueItems = TRUE),
  resolution = key_resolution))
linked_policy <- object(c("schema", "manifest_declaration_identity",
  "derived_axis_name", "shape", "row_order", "missing_values",
  "resolved_key_axis_policy_identity_or_null", "resolved_key_axis",
  "resolved_keys"), list(schema = list(const =
    "scworkbench.operation_pack.derived_cell_linked_output_policy.v1"),
    manifest_declaration_identity = identity, derived_axis_name = name,
    shape = list(enum = list("one_per_cell", "cell_key_cartesian",
      "bounded_grouped_cell_key_cartesian")), row_order = list(enum = list(
        "sealed_cell_axis_order_v1", "key_major_then_sealed_cell_v1")),
    missing_values = list(enum = list("allowed", "forbidden")),
    resolved_key_axis_policy_identity_or_null = nullable_identity,
    resolved_key_axis = list(oneOf = list(resolved_policy,
      list(type = "null"))), resolved_keys = list(oneOf = list(
        array(nonempty, uniqueItems = TRUE), list(type = "null")))))
rdefs$derived_cell_output_axis_grant <- grant
rdefs$derived_cell_linked_output_policy <- linked_policy
request$properties$derived_cell_output_axis_grants <- array(
  ref("derived_cell_output_axis_grant"), minItems = 1L, maxItems = 4L)
rdefs$capability$properties$derived_cell_output_axis_grant_identities <- array(
  identity, minItems = 1L, maxItems = 4L)
for (i in seq_along(rdefs$output_descriptor$oneOf)) if (as.character(
    rdefs$output_descriptor$oneOf[[i]]$properties$kind$const %||% "") %in%
    c("cell_vector", "cell_vector_family")) {
  rdefs$output_descriptor$oneOf[[i]]$properties$
    derived_cell_output_axis_policy <- ref("derived_cell_linked_output_policy")
  rdefs$output_descriptor$oneOf[[i]]$properties$expected_cell_order_identity <-
    nullable_identity
}
request[["$defs"]] <- rdefs
write(request, "operation-pack-transition-request-v3.schema.json")

# Receipt --------------------------------------------------------------------
receipt <- read("operation-pack-transition-receipt-v3.schema.json")
odefs <- receipt[["$defs"]]
derivation_base <- list(pack_declaration_identity = identity,
  grant_identity = identity,
  derivation_mode = list(enum = list("ordered_unique_subset_v1",
    "declared_ordered_unique_union_v1")),
  selected_axis_order_identities = array(identity, minItems = 1L,
    maxItems = 64L), final_cell_count = integer(minimum = 1L,
      maximum = 10000000L), final_cell_order_identity = identity,
  derivation_identity = self_identity)
odefs$derived_cell_axis_derivation <- list(oneOf = list(
  object(c("pack_declaration_identity", "grant_identity", "derivation_mode",
    "selected_axis_order_identities", "final_cell_count",
    "final_cell_order_identity", "source_ordered_subset_status",
    "selected_count", "derivation_identity"), c(derivation_base, list(
      source_ordered_subset_status = list(const = "passed"),
      selected_count = integer(minimum = 1L, maximum = 10000000L)))),
  object(c("pack_declaration_identity", "grant_identity", "derivation_mode",
    "selected_axis_order_identities", "final_cell_count",
    "final_cell_order_identity", "member_subset_status",
    "union_membership_equality_status", "distinct_selected_membership_count",
    "aggregate_selected_count", "overlap_collapse_count",
    "derivation_identity"), c(derivation_base, list(
      member_subset_status = list(const = "passed"),
      union_membership_equality_status = list(const = "passed"),
      distinct_selected_membership_count = integer(minimum = 1L,
        maximum = 10000000L), aggregate_selected_count = integer(minimum = 1L,
          maximum = 20000000L), overlap_collapse_count = integer(minimum = 0L,
            maximum = 20000000L))))))
odefs$sealed_derived_cell_axis <- object(c("schema", "grant_identity",
  "pack_declaration_identity", "derivation_identity",
  "source_axis_aggregate_identity", "linked_output_closure_identity",
  "final_cell_count", "final_cell_order_identity", "status",
  "sealed_axis_identity"), list(schema = list(const =
    "scworkbench.operation_pack.sealed_derived_cell_axis.v1"),
    grant_identity = identity, pack_declaration_identity = identity,
    derivation_identity = identity, source_axis_aggregate_identity = identity,
    linked_output_closure_identity = identity,
    final_cell_count = integer(minimum = 1L, maximum = 10000000L),
    final_cell_order_identity = identity, status = list(const = "sealed"),
    sealed_axis_identity = self_identity))
sealed_grant <- object(c("schema", "ordinary_output_grant_identity",
  "manifest_declaration_identity", "pack_declaration_identity",
  "derived_axis_grant_identity", "sealed_axis_identity", "output", "kind",
  "shape", "row_order", "missing_values",
  "resolved_key_axis_policy_identity_or_null", "cell_axis_count",
  "cell_axis_order_identity", "expected_dimensions",
  "sealed_cardinality_grant_identity"), list(schema = list(const =
    "scworkbench.operation_pack.sealed_output_cardinality_grant.v1"),
    ordinary_output_grant_identity = identity,
    manifest_declaration_identity = identity,
    pack_declaration_identity = identity, derived_axis_grant_identity = identity,
    sealed_axis_identity = identity, output = name, kind = list(enum = list(
      "cell_vector", "cell_vector_family")), shape = list(enum = list(
        "one_per_cell", "cell_key_cartesian",
        "bounded_grouped_cell_key_cartesian")), row_order = list(enum = list(
          "sealed_cell_axis_order_v1", "key_major_then_sealed_cell_v1")),
    missing_values = list(enum = list("allowed", "forbidden")),
    resolved_key_axis_policy_identity_or_null = nullable_identity,
    cell_axis_count = integer(minimum = 1L, maximum = 10000000L),
    cell_axis_order_identity = identity,
    expected_dimensions = array(integer(minimum = 0L), minItems = 1L,
      maxItems = 2L), expected_row_count = integer(minimum = 0L),
    row_order_identity = identity, key_axis_count = integer(minimum = 0L),
    key_axis = array(nonempty, uniqueItems = TRUE),
    key_axis_resolution = resolved_policy,
    key_axis_order_identity = identity, minimum_key_count = integer(minimum = 0L),
    maximum_key_count = integer(minimum = 0L),
    minimum_row_count = integer(minimum = 0L),
    maximum_row_count = integer(minimum = 0L),
    sealed_cardinality_grant_identity = self_identity))
observed_cardinality <- object(c("schema",
  "sealed_cardinality_grant_identity", "shape", "observed_row_count",
  "observed_cell_axis_count", "observed_cell_axis_order_identity",
  "observed_row_order_identity", "missing_count", "semantic_validation",
  "sealed_axis_identity", "observed_sealed_cardinality_identity"), list(
    schema = list(const =
      "scworkbench.operation_pack.observed_sealed_output_cardinality.v1"),
    sealed_cardinality_grant_identity = self_identity,
    shape = list(enum = list("one_per_cell", "cell_key_cartesian",
      "bounded_grouped_cell_key_cartesian")),
    observed_row_count = integer(minimum = 0L),
    observed_cell_axis_count = integer(minimum = 1L),
    observed_cell_axis_order_identity = identity,
    observed_key_axis_count = integer(minimum = 0L),
    observed_key_axis_order_identity = identity,
    observed_row_order_identity = identity, missing_count = integer(minimum = 0L),
    semantic_validation = list(const = "passed"),
    observed_key_axis = array(nonempty, uniqueItems = TRUE),
    selected_optional_groups = array(nonempty, uniqueItems = TRUE),
    selected_optional_groups_identity = identity,
    sealed_axis_identity = identity,
    observed_sealed_cardinality_identity = self_identity))
linked_observation <- object(c("name", "ordinary_output_grant_identity",
  "sealed_cardinality_observation_identity", "observed_descriptor_identity",
  "content_identity", "observed_sealed_cell_axis_identity"), list(name = name,
    ordinary_output_grant_identity = identity,
    sealed_cardinality_observation_identity = identity,
    observed_descriptor_identity = identity, content_identity = identity,
    observed_sealed_cell_axis_identity = identity))
axis_observation <- object(c("schema", "grant_identity",
  "source_axis_aggregate_identity", "pack_declaration_identity",
  "derivation_identity", "sealed_axis_identity", "declaration_count",
  "seal_status", "derivation_mode", "source_axis_count",
  "source_membership_count", "aggregate_selected_count",
  "overlap_collapse_count", "final_cell_count", "final_cell_order_identity",
  "linked_output_closure_identity", "linked_outputs",
  "exact_linked_output_coverage", "semantic_validation",
  "observation_identity"), list(schema = list(const =
    "scworkbench.operation_pack.derived_cell_output_axis_observation.v1"),
    grant_identity = identity, source_axis_aggregate_identity = identity,
    pack_declaration_identity = identity, derivation_identity = identity,
    sealed_axis_identity = identity, declaration_count = list(const = 1L),
    seal_status = list(const = "sealed"), derivation_mode = list(enum = list(
      "ordered_unique_subset_v1", "declared_ordered_unique_union_v1")),
    source_axis_count = integer(minimum = 1L, maximum = 64L),
    source_membership_count = integer(minimum = 1L, maximum = 20000000L),
    aggregate_selected_count = integer(minimum = 1L, maximum = 20000000L),
    overlap_collapse_count = integer(minimum = 0L, maximum = 20000000L),
    final_cell_count = integer(minimum = 1L, maximum = 10000000L),
    final_cell_order_identity = identity,
    linked_output_closure_identity = identity,
    linked_outputs = array(linked_observation, minItems = 1L, maxItems = 16L),
    exact_linked_output_coverage = list(const = "passed"),
    semantic_validation = list(const = "passed"),
    observation_identity = self_identity))
odefs$sealed_output_cardinality_grant <- sealed_grant
odefs$observed_sealed_output_cardinality <- observed_cardinality
odefs$derived_cell_output_axis_observation <- axis_observation
receipt$properties$derived_cell_output_axis_observations <- array(
  ref("derived_cell_output_axis_observation"), minItems = 1L, maxItems = 4L)
for (i in seq_along(odefs$observed_output_descriptor$oneOf)) if (as.character(
    odefs$observed_output_descriptor$oneOf[[i]]$properties$kind$const %||% "")
    %in% c("cell_vector", "cell_vector_family")) {
  props <- odefs$observed_output_descriptor$oneOf[[i]]$properties
  props$sealed_axis_identity <- identity
  props$sealed_output_cardinality_grant <-
    ref("sealed_output_cardinality_grant")
  props$observed_sealed_output_cardinality <-
    ref("observed_sealed_output_cardinality")
  odefs$observed_output_descriptor$oneOf[[i]]$properties <- props
}
receipt[["$defs"]] <- odefs
write(receipt, "operation-pack-transition-receipt-v3.schema.json")
