#!/usr/bin/env Rscript

root <- normalizePath(file.path(dirname(sub("^--file=", "",
  commandArgs(FALSE)[grepl("^--file=", commandArgs(FALSE))])), "..", ".."),
  winslash = "/", mustWork = TRUE)
pkgload::load_all(root, quiet = TRUE)
path <- file.path(root, "tests", "fixtures", "operation-pack-v3-phase5",
  "inst", "scworkbench", "operation-pack.json")
x <- jsonlite::read_json(path, simplifyVector = FALSE)
scoped <- scworkbench:::.wb_operation_pack_v2_identity_scoped
axis_declaration <- function(name, mode, source, linked, maximum_axes = 1L) {
  value <- list(schema =
      "scworkbench.operation_pack.derived_cell_output_axis.v1",
    name = name, derivation_mode = mode, source = source,
    linked_outputs = linked, limits = list(minimum_cells = 1L,
      maximum_cells = 1000L, maximum_source_axes = maximum_axes,
      maximum_source_memberships = 10000L,
      maximum_linked_outputs = length(linked)),
    call_discipline = "declare_once_seal_before_linked_output_v1",
    closure_policy =
      "all_linked_outputs_and_axis_observation_required_v1")
  value$declaration_identity <- scoped(value$schema,
    "derived cell output axis declaration excluding declaration_identity",
    value)
  value
}
vector_link <- function(name) list(name = name, shape = "one_per_cell",
  row_order = "sealed_cell_axis_order_v1", missing_values = "forbidden")
family_link <- function(name) list(name = name, shape = "cell_key_cartesian",
  row_order = "key_major_then_sealed_cell_v1", missing_values = "forbidden",
  key_axis = list(source = "declared_keys_with_optional_prefix_v1",
    keys = list("score", "confidence"), prefix_parameter = "key_prefix"))

subset_axis <- axis_declaration("derived", "ordered_unique_subset_v1",
  list(mode = "static_input_axis", input = "source",
    projection = "cell_vector_axis_v1", family_key_selector = NULL),
  list(vector_link("vector"), family_link("family")))
subset <- list(name = "derived_subset",
  qualified_name = "scwbv3phase5::derived_subset",
  title = "Generic G7 subset fixture",
  description = "Declares a source-relative derived cell axis.",
  runner = ".derived_subset",
  inputs = list(list(name = "source", kind = "cell_vector", required = TRUE,
    alignment = "cell_ordered")), params_schema = list(type = "object",
    additionalProperties = FALSE, required = list("selected_cells",
      "key_prefix"), properties = list(selected_cells = list(type = "array",
        minItems = 1L, uniqueItems = TRUE,
        items = list(type = "string", minLength = 1L)),
      key_prefix = list(type = "string"),
      fault_after_first_output = list(type = "boolean"),
      omit_declaration = list(type = "boolean"),
      repeat_declaration = list(type = "boolean"))),
  outputs = list(list(name = "vector", category = "terminal_artifact",
      kind = "cell_vector", storage_profile = "terminal_primitive_v1",
      allocated_id_key = "vector_id", required = TRUE,
      promotion_group = "derived", value_kind = "continuous"),
    list(name = "family", category = "terminal_artifact",
      kind = "cell_vector_family", storage_profile = "terminal_primitive_v1",
      allocated_id_key = "family_id", required = TRUE,
      promotion_group = "derived", value_kind = "continuous")),
  dependencies = list(), promotion_closure = list(
    vector = list("family", "vector"), family = list("family", "vector")),
  replay_equivalence = list(vector = "exact_canonical_value",
    family = "exact_canonical_value"),
  derived_cell_output_axes = list(subset_axis))

union_axis <- axis_declaration("derived",
  "declared_ordered_unique_union_v1",
  list(mode = "g4_collection_member_axis", collection = "sources",
    slot = "axis", projection = "cell_vector_axis_v1",
    family_key_selector = NULL), list(vector_link("vector")), 8L)
union <- list(name = "derived_union",
  qualified_name = "scwbv3phase5::derived_union",
  title = "Generic G7 union fixture",
  description = "Declares an exact ordered union from authenticated members.",
  runner = ".derived_union", inputs = list(),
  params_schema = list(type = "object", additionalProperties = FALSE,
    required = list("items", "member_selections", "final_cells"),
    properties = list(items = list(type = "array", minItems = 1L,
        maxItems = 8L, items = list(type = "object")),
      member_selections = list(type = "array", minItems = 1L,
        maxItems = 8L, items = list(type = "array", uniqueItems = TRUE,
          items = list(type = "string", minLength = 1L))),
      final_cells = list(type = "array", minItems = 1L, uniqueItems = TRUE,
        items = list(type = "string", minLength = 1L)))),
  outputs = list(list(name = "vector", category = "terminal_artifact",
    kind = "cell_vector", storage_profile = "terminal_primitive_v1",
    allocated_id_key = "vector_id", required = TRUE,
    promotion_group = "derived", value_kind = "continuous")),
  dependencies = list(), promotion_closure = list(vector = list("vector")),
  replay_equivalence = list(vector = "exact_canonical_value"),
  artifact_collection_reads = list(list(name = "sources", parameter = "items",
    reader = "read_retained_artifact_collection_item",
    minimum_items = 1L, maximum_items = 8L, item_key_field = "name",
    order_field = "order", reference_slots = list(list(slot = "axis",
      field = "axis_ref", required = TRUE, allowed_kinds = list("cell_vector"),
      activation = "always", lifecycle_policy = "require_current",
      ancestry_policy = "require_content_verified_producer")),
    maximum_references = 8L,
    maximum_single_payload_bytes = 1048576L,
    maximum_total_payload_bytes = 8388608L,
    call_discipline = "resolved_ordinal_slot_exactly_once")),
  derived_cell_output_axes = list(union_axis))

names_new <- c(subset$qualified_name, union$qualified_name)
x$operations <- c(Filter(function(op) !op$qualified_name %in% names_new,
  x$operations), list(subset, union))
jsonlite::write_json(x, path, auto_unbox = TRUE, pretty = TRUE, null = "null",
  digits = NA)
