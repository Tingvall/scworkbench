#!/usr/bin/env Rscript

root <- normalizePath(file.path(dirname(sub("^--file=", "",
  commandArgs(FALSE)[grepl("^--file=", commandArgs(FALSE))])), "..", ".."),
  winslash = "/", mustWork = TRUE)
pkgload::load_all(root, quiet = TRUE)
path <- file.path(root, "inst", "protocol", "fixtures",
  "operation-pack-v3", "identities.json")
fixture <- jsonlite::read_json(path, simplifyVector = FALSE)
plain <- scworkbench:::.wb_operation_pack_v2_identity_plain
scoped <- scworkbench:::.wb_operation_pack_v2_identity_scoped
unscoped <- scworkbench:::.wb_operation_pack_v3_unscoped_identity
hex <- function(x) paste(rep(x, 64L), collapse = "")
id <- function(scheme, x) list(scheme = scheme, sha256 = hex(x))
case <- function(name, value, field) {
  identity <- value[[field]]; preimage <- value; preimage[[field]] <- NULL
  list(name = name, preimage = preimage, identity = identity, value = value)
}
self <- function(value, field, scheme, scope) {
  value[[field]] <- scoped(scheme, scope, value)
  value
}

declaration <- list(schema =
    "scworkbench.operation_pack.derived_cell_output_axis.v1",
  name = "derived", derivation_mode = "ordered_unique_subset_v1",
  source = list(mode = "static_input_axis", input = "source",
    projection = "cell_vector_axis_v1", family_key_selector = NULL),
  linked_outputs = list(list(name = "vector", shape = "one_per_cell",
    row_order = "sealed_cell_axis_order_v1", missing_values = "forbidden")),
  limits = list(minimum_cells = 1L, maximum_cells = 1000L,
    maximum_source_axes = 1L, maximum_source_memberships = 1000L,
    maximum_linked_outputs = 1L),
  call_discipline = "declare_once_seal_before_linked_output_v1",
  closure_policy = "all_linked_outputs_and_axis_observation_required_v1")
declaration <- self(declaration, "declaration_identity", declaration$schema,
  "derived cell output axis declaration excluding declaration_identity")
source <- list(source_mode = "static_input_axis", input_name = "source",
  input_descriptor_identity = id(
    "scworkbench.operation_pack.input_descriptor.v2", "1"),
  primitive_kind = "cell_vector", projection = "cell_vector_axis_v1",
  source_axis_selector_identity = NULL, source_cell_count = 3L,
  source_cell_order_identity = plain("scworkbench.cell_order.v1",
    list("cell_2", "cell_10", "cell_1")))
source <- self(source, "source_axis_reference_identity",
  "scworkbench.operation_pack.derived_cell_source_axis_reference.v1",
  "derived cell source axis reference excluding source_axis_reference_identity")
aggregate <- list(derivation_mode = "ordered_unique_subset_v1",
  source_axis_count = 1L, source_membership_count = 3L,
  ordered_source_axis_reference_identities = list(unscoped(
    source$source_axis_reference_identity)))
aggregate <- self(aggregate, "source_axis_aggregate_identity",
  "scworkbench.operation_pack.derived_cell_source_axis_aggregate.v1",
  "derived cell source axis aggregate excluding source_axis_aggregate_identity")
output_grant <- id("scworkbench.operation_pack.output_grant.v3", "2")
closure <- list(manifest_declaration_identity = unscoped(
    declaration$declaration_identity), linked_outputs = list(list(
      name = "vector", allocated_id = "vector-1", kind = "cell_vector",
      ordinary_output_grant_identity = output_grant, shape = "one_per_cell",
      row_order = "sealed_cell_axis_order_v1", missing_values = "forbidden",
      resolved_key_axis_policy_identity_or_null = NULL,
      promotion_group = "derived")), closure_policy =
    "all_linked_outputs_and_axis_observation_required_v1")
closure <- self(closure, "linked_output_closure_identity",
  "scworkbench.operation_pack.derived_cell_linked_output_closure.v1",
  "linked output closure excluding linked_output_closure_identity")
grant <- list(schema =
    "scworkbench.operation_pack.authenticated_derived_cell_output_axis_grant.v1",
  name = "derived", derivation_mode = "ordered_unique_subset_v1",
  manifest_declaration_identity = unscoped(declaration$declaration_identity),
  source_axes = list(source), source_axis_aggregate = aggregate,
  linked_output_closure = closure, limits = declaration$limits,
  call_discipline = declaration$call_discipline,
  closure_policy = declaration$closure_policy)
grant <- self(grant, "grant_identity", grant$schema,
  "grant excluding grant_identity")
pack_declaration <- scworkbench::wb_derived_cell_output_axis_declaration(grant,
  c("cell_2", "cell_1"))
request <- list(derived_cell_output_axis_grants = list(grant))
attr(request, "operation_pack_v3_derived_axis_state") <- list(derived = list(
  cells = list(c("cell_2", "cell_10", "cell_1")), selectors = list(NULL),
  references = list(source)))
sealed <- scworkbench:::.wb_operation_pack_v3_g7_seal(request,
  list(pack_declaration))[[1L]]
output <- list(name = "vector", descriptor = list(kind = "cell_vector",
  grant_identity = list(scheme = output_grant$scheme,
    scope = "descriptor excluding grant_identity", sha256 = output_grant$sha256),
  derived_cell_output_axis_policy = list(schema =
      "scworkbench.operation_pack.derived_cell_linked_output_policy.v1",
    manifest_declaration_identity = unscoped(declaration$declaration_identity),
    derived_axis_name = "derived", shape = "one_per_cell",
    row_order = "sealed_cell_axis_order_v1", missing_values = "forbidden",
    resolved_key_axis_policy_identity_or_null = NULL,
    resolved_key_axis = NULL, resolved_keys = NULL)))
sealed_cardinality <- scworkbench:::.wb_operation_pack_v3_g7_sealed_cardinality(
  output, sealed)
observed_cardinality <-
  scworkbench:::.wb_operation_pack_v3_g7_observe_cardinality(
    scworkbench::wb_prim_cell_vector(c(cell_2 = 1, cell_1 = 2),
      value_type = "continuous"), sealed_cardinality)

content_record <- function(value) {
  observed <- scworkbench:::.wb_prov_payload_identity(NULL, value)
  list(kind = value$kind, cell_id = unname(as.list(value$cell_id)),
    content_identity = list(scheme = observed$content_identity_scheme,
      sha256 = observed$content_sha256))
}
payload_record <- function(name, content_identity, cells) {
  value <- list(output = name, content_identity = content_identity,
    cell_order_identity = plain("scworkbench.cell_order.v1",
      unname(as.list(cells))))
  value$payload_manifest_identity <- plain(
    "scworkbench.operation_pack.payload_manifest.v2", value)
  value
}
base_observed <- function(output, value, content, payload) list(name =
  output$name, allocated_id = output$allocated_id, descriptor = list(
    category = "terminal_artifact", kind = output$descriptor$kind,
    storage_profile = "terminal_primitive_v1",
    writer = "write_terminal_primitive",
    grant_identity = output$descriptor$grant_identity,
    dimensions = unname(as.list(
      scworkbench:::.wb_operation_pack_v2_dimensions(value,
        output$descriptor$kind))), alignment = "cell_ordered",
    ancestry_identity = id("scworkbench.operation_pack.ancestry.v1", "6"),
    model_linkage = list(mode = "none"),
    content_identity = content$content_identity,
    payload_manifest_identity = payload$payload_manifest_identity,
    semantic_metadata_identity = id(
      "scworkbench.operation_pack.semantic_metadata.v2", "7"),
    semantic_validation = list(constraints_identity = plain(
      "scworkbench.operation_pack.semantic_constraints.v2",
      output$descriptor$semantic_constraints), status = "passed"),
    cell_order_identity = plain("scworkbench.cell_order.v1",
      unname(as.list(value$cell_id)))))
apply_chain <- function(grant_value, seal_value, outputs, values) {
  request_value <- list(outputs = outputs,
    derived_cell_output_axis_grants = list(grant_value))
  contents <- Map(content_record, values)
  payloads <- Map(function(output, content, value) payload_record(output$name,
    content$content_identity, value$cell_id), outputs, contents, values)
  observed <- Map(base_observed, outputs, values, contents, payloads)
  writes <- stats::setNames(lapply(values, function(value) list(value = value)),
    vapply(outputs, `[[`, character(1), "name"))
  applied <- scworkbench:::.wb_operation_pack_v3_g7_apply_outputs(
    request_value, observed, writes, list(derived = seal_value))
  list(contents = contents, payloads = payloads, observed = applied$observed,
    observation = applied$observations[[1L]])
}
transition_projection <- function(grant_value, outputs, observation = NULL,
    observed = NULL) {
  request_value <- list(schema =
      "scworkbench.operation_pack.transition_request.v3",
    outputs = outputs,
    derived_cell_output_axis_grants = list(grant_value))
  request_value$request_identity <- scoped(request_value$schema,
    "request excluding request_identity", request_value)
  if (is.null(observation)) return(list(request = request_value))
  receipt_value <- list(schema =
      "scworkbench.operation_pack.transition_receipt.v3",
    request_identity = unscoped(request_value$request_identity),
    outputs = observed,
    derived_cell_output_axis_observations = list(observation))
  receipt_value$receipt_identity <- scoped(receipt_value$schema,
    "receipt excluding receipt_identity", receipt_value)
  list(request = request_value, receipt = receipt_value)
}

subset_value <- scworkbench::wb_prim_cell_vector(c(cell_2 = 1, cell_1 = 2),
  value_type = "continuous")
subset_chain <- apply_chain(grant, sealed, list(output), list(subset_value))
subset_transition <- transition_projection(grant, list(output),
  subset_chain$observation, subset_chain$observed)

union_selector <- function(descriptor, key, field = "lineage_key") {
  value <- list(primitive_descriptor_identity = descriptor,
    projection = "family_key_cell_axis_v1",
    selector_mode = "collection_item_field",
    selector_source = list(field = field, value = key), resolved_key = key)
  self(value, "source_axis_selector_identity",
    "scworkbench.operation_pack.derived_cell_axis_selector.v1",
    "derived cell axis selector excluding source_axis_selector_identity")
}
union_reference <- function(ordinal, cells, digit, selector) {
  value <- list(source_mode = "g4_collection_member_axis",
    collection_name = "sources",
    collection_identity = id("scworkbench.retained_artifact_collection.v1",
      "3"), resolved_ordinal = as.integer(ordinal),
    item_identity = id("scworkbench.retained_artifact_collection_item.v1",
      digit), slot_name = "axis",
    slot_reference_identity = id("scworkbench.retained_artifact_reference.v1",
      digit), primitive_descriptor_identity = id(
        "scworkbench.operation_pack.input_descriptor.v2", digit),
    primitive_kind = "cell_vector_family",
    projection = "family_key_cell_axis_v1",
    source_axis_selector_identity = unscoped(
      selector$source_axis_selector_identity),
    source_cell_count = as.integer(length(cells)),
    source_cell_order_identity = plain("scworkbench.cell_order.v1",
      unname(as.list(cells))))
  self(value, "source_axis_reference_identity",
    "scworkbench.operation_pack.derived_cell_source_axis_reference.v1",
    "derived cell source axis reference excluding source_axis_reference_identity")
}
selector_a <- union_selector(id(
  "scworkbench.operation_pack.input_descriptor.v2", "4"), "left")
selector_b <- union_selector(id(
  "scworkbench.operation_pack.input_descriptor.v2", "5"), "right")
refs <- list(union_reference(1L, c("cell_2", "cell_10"), "4", selector_a),
  union_reference(2L, c("cell_1", "cell_2"), "5", selector_b))
union_aggregate <- list(derivation_mode =
    "declared_ordered_unique_union_v1", source_axis_count = 2L,
  source_membership_count = 4L,
  ordered_source_axis_reference_identities = lapply(refs, function(x)
    unscoped(x$source_axis_reference_identity)))
union_aggregate <- self(union_aggregate, "source_axis_aggregate_identity",
  "scworkbench.operation_pack.derived_cell_source_axis_aggregate.v1",
  "derived cell source axis aggregate excluding source_axis_aggregate_identity")
union_declaration <- list(schema =
    "scworkbench.operation_pack.derived_cell_output_axis.v1",
  name = "derived", derivation_mode = "declared_ordered_unique_union_v1",
  source = list(mode = "g4_collection_member_axis", collection = "sources",
    slot = "axis", projection = "family_key_cell_axis_v1",
    family_key_selector = list(mode = "collection_item_field",
      field = "lineage_key")),
  linked_outputs = list(
    list(name = "vector", shape = "one_per_cell",
      row_order = "sealed_cell_axis_order_v1", missing_values = "forbidden"),
    list(name = "family", shape = "cell_key_cartesian",
      row_order = "key_major_then_sealed_cell_v1",
      missing_values = "forbidden", key_axis = list(source =
        "declared_keys_with_optional_prefix_v1", keys = list("score",
          "confidence"), prefix_parameter = "prefix"))),
  limits = list(minimum_cells = 1L, maximum_cells = 1000L,
    maximum_source_axes = 2L, maximum_source_memberships = 1000L,
    maximum_linked_outputs = 2L),
  call_discipline = "declare_once_seal_before_linked_output_v1",
  closure_policy = "all_linked_outputs_and_axis_observation_required_v1")
union_declaration <- self(union_declaration, "declaration_identity",
  union_declaration$schema,
  "derived cell output axis declaration excluding declaration_identity")

vector_policy <- list(schema =
    "scworkbench.operation_pack.derived_cell_linked_output_policy.v1",
  manifest_declaration_identity = unscoped(
    union_declaration$declaration_identity), derived_axis_name = "derived",
  shape = "one_per_cell", row_order = "sealed_cell_axis_order_v1",
  missing_values = "forbidden",
  resolved_key_axis_policy_identity_or_null = NULL,
  resolved_key_axis = NULL, resolved_keys = NULL)
key_resolution <- list(declaration = union_declaration$linked_outputs[[2L]]$
    key_axis, keys = list("score", "confidence"), resolution = list(source =
      "declared_keys_with_optional_prefix_v1", base_keys = list("score",
        "confidence"), prefix_parameter = "prefix", prefix_value = "",
      keys = list("score", "confidence")))
family_policy <- list(schema =
    "scworkbench.operation_pack.derived_cell_linked_output_policy.v1",
  manifest_declaration_identity = unscoped(
    union_declaration$declaration_identity), derived_axis_name = "derived",
  shape = "cell_key_cartesian",
  row_order = "key_major_then_sealed_cell_v1", missing_values = "forbidden",
  resolved_key_axis_policy_identity_or_null = plain(
    "scworkbench.operation_pack.resolved_key_axis_policy.v1", key_resolution),
  resolved_key_axis = key_resolution,
  resolved_keys = list("score", "confidence"))
ordinary_output <- function(name, id_value, kind, policy) {
  descriptor <- list(category = "terminal_artifact", kind = kind,
    storage_profile = "terminal_primitive_v1",
    writer = "write_terminal_primitive",
    relative_root = paste0("outputs/", name),
    expected_dimensions = if (kind == "cell_vector") list(0L) else
      list(0L, 3L), expected_cell_order_identity = NULL,
    expected_alignment = "cell_ordered",
    expected_ancestry_identity = id(
      "scworkbench.operation_pack.ancestry.v1", "6"),
    expected_model_linkage = list(mode = "none"),
    semantic_constraints = list(value_kind = "continuous",
      missing_values = "forbidden"),
    derived_cell_output_axis_policy = policy)
  descriptor$grant_identity <- scoped(
    "scworkbench.operation_pack.output_grant.v3",
    "descriptor excluding grant_identity", descriptor)
  list(name = name, allocated_id = id_value, descriptor = descriptor)
}
union_outputs <- list(ordinary_output("vector", "vector-1", "cell_vector",
  vector_policy), ordinary_output("family", "family-1",
    "cell_vector_family", family_policy))
union_closure <- list(manifest_declaration_identity = unscoped(
    union_declaration$declaration_identity), linked_outputs = Map(
      function(output, item) list(name = output$name,
        allocated_id = output$allocated_id, kind = output$descriptor$kind,
        ordinary_output_grant_identity = unscoped(
          output$descriptor$grant_identity), shape = item$shape,
        row_order = item$row_order, missing_values = item$missing_values,
        resolved_key_axis_policy_identity_or_null = output$descriptor$
          derived_cell_output_axis_policy$
            resolved_key_axis_policy_identity_or_null,
        promotion_group = "derived"), union_outputs,
      union_declaration$linked_outputs), closure_policy =
        union_declaration$closure_policy)
union_closure <- self(union_closure, "linked_output_closure_identity",
  "scworkbench.operation_pack.derived_cell_linked_output_closure.v1",
  "linked output closure excluding linked_output_closure_identity")
union_grant <- list(schema =
    "scworkbench.operation_pack.authenticated_derived_cell_output_axis_grant.v1",
  name = "derived", derivation_mode = "declared_ordered_unique_union_v1",
  manifest_declaration_identity = unscoped(
    union_declaration$declaration_identity), source_axes = refs,
  source_axis_aggregate = union_aggregate,
  linked_output_closure = union_closure, limits = union_declaration$limits,
  call_discipline = union_declaration$call_discipline,
  closure_policy = union_declaration$closure_policy)
union_grant <- self(union_grant, "grant_identity", union_grant$schema,
  "grant excluding grant_identity")
union_a <- scworkbench::wb_derived_cell_output_axis_declaration(union_grant,
  c("cell_1", "cell_10", "cell_2"),
  list(c("cell_2", "cell_10"), c("cell_1", "cell_2")))
union_b <- scworkbench::wb_derived_cell_output_axis_declaration(union_grant,
  c("cell_2", "cell_1", "cell_10"),
  list(c("cell_2", "cell_10"), c("cell_1", "cell_2")))

build_union_chain <- function(pack_declaration) {
  request_value <- list(derived_cell_output_axis_grants = list(union_grant))
  attr(request_value, "operation_pack_v3_derived_axis_state") <- list(
    derived = list(cells = list(c("cell_2", "cell_10"),
      c("cell_1", "cell_2")), selectors = list(selector_a, selector_b),
      references = refs))
  seal_value <- scworkbench:::.wb_operation_pack_v3_g7_seal(request_value,
    list(pack_declaration))[[1L]]
  cells <- seal_value$cells
  values <- list(scworkbench::wb_prim_cell_vector(
      stats::setNames(seq_along(cells), cells), value_type = "continuous"),
    scworkbench::wb_prim_cell_vector_family(
      rep(c("score", "confidence"), each = length(cells)),
      rep(cells, 2L), seq_len(2L * length(cells))))
  applied <- apply_chain(union_grant, seal_value, union_outputs, values)
  transition <- transition_projection(union_grant, union_outputs,
    applied$observation, applied$observed)
  cardinalities <- Map(function(output)
    scworkbench:::.wb_operation_pack_v3_g7_sealed_cardinality(output,
      seal_value), union_outputs)
  observed_cardinalities <- Map(function(value, cardinality)
    scworkbench:::.wb_operation_pack_v3_g7_observe_cardinality(value,
      cardinality), values, cardinalities)
  list(sealed = seal_value, values = values, applied = applied,
    cardinalities = cardinalities,
    observed_cardinalities = observed_cardinalities,
    transition = transition)
}
union_chain_a <- build_union_chain(union_a)
union_chain_b <- build_union_chain(union_b)

effective_spec <- list(source = "resolved_effective_parameter_key_v1",
  parameter_candidates = list("primary_key", "fallback_key"),
  null_policy = "first_non_null_v1", invalid_value_policy = "error")
effective_override_spec <- c(effective_spec, list(input_presence_override =
  list(present = "lineage_weights", absent = "confidence",
    use_parameter = "fallback_key")))
effective_policy <- function(spec, inputs, primary, fallback) {
  candidates <- as.character(unlist(spec$parameter_candidates,
    use.names = FALSE))
  params <- stats::setNames(vector("list", length(candidates)), candidates)
  params[[candidates[[1L]]]] <- primary
  if (length(candidates) == 2L) params[[candidates[[2L]]]] <- fallback
  resolved <- scworkbench:::.wb_operation_pack_v3_g7_key_axis(spec, inputs,
    params, list())
  list(value = resolved$resolution, identity = resolved$identity)
}
effective <- list(
  primary = effective_policy(effective_spec, list(), "custom", "L1"),
  null_fallback = effective_policy(effective_spec, list(), NULL, "L1"),
  schema_default = effective_policy(list(source =
      "resolved_effective_parameter_key_v1", parameter_candidates = list(
        "composite_key"), null_policy = "first_non_null_v1",
      invalid_value_policy = "error"), list(), "composite_L1", NULL),
  override = effective_policy(effective_override_spec,
    list(lineage_weights = TRUE), "custom", "L1"),
  same_key_no_presence = effective_policy(effective_override_spec, list(),
    "same", "same"),
  same_key_with_presence = effective_policy(effective_override_spec,
    list(lineage_weights = TRUE), "same", "same"))
effective_case <- function(name, item) list(name = name,
  preimage = item$value, identity = item$identity, value = item$value)

new <- list(case("g7_manifest_declaration", declaration,
    "declaration_identity"),
  case("g7_subset_source_reference", source,
    "source_axis_reference_identity"),
  case("g7_subset_source_aggregate", aggregate,
    "source_axis_aggregate_identity"),
  case("g7_linked_output_closure", closure,
    "linked_output_closure_identity"),
  case("g7_subset_grant", grant, "grant_identity"),
  case("g7_subset_pack_declaration", pack_declaration,
    "pack_declaration_identity"),
  case("g7_subset_derivation", sealed$derivation, "derivation_identity"),
  case("g7_subset_sealed_axis", sealed$seal, "sealed_axis_identity"),
  case("g7_subset_sealed_cardinality", sealed_cardinality,
    "sealed_cardinality_grant_identity"),
  case("g7_subset_observed_sealed_cardinality", observed_cardinality,
    "observed_sealed_cardinality_identity"),
  case("g7_subset_observed_descriptor",
    subset_chain$observed[[1L]]$descriptor, "observed_descriptor_identity"),
  case("g7_subset_axis_observation", subset_chain$observation,
    "observation_identity"),
  case("g7_subset_request", subset_transition$request, "request_identity"),
  case("g7_subset_receipt", subset_transition$receipt, "receipt_identity"),
  case("g7_union_manifest_declaration", union_declaration,
    "declaration_identity"),
  case("g7_union_selector_left", selector_a,
    "source_axis_selector_identity"),
  case("g7_union_selector_right", selector_b,
    "source_axis_selector_identity"),
  case("g7_union_source_reference_left", refs[[1L]],
    "source_axis_reference_identity"),
  case("g7_union_source_reference_right", refs[[2L]],
    "source_axis_reference_identity"),
  case("g7_union_source_aggregate", union_aggregate,
    "source_axis_aggregate_identity"),
  case("g7_union_vector_output_grant", union_outputs[[1L]]$descriptor,
    "grant_identity"),
  case("g7_union_family_output_grant", union_outputs[[2L]]$descriptor,
    "grant_identity"),
  case("g7_union_linked_output_closure", union_closure,
    "linked_output_closure_identity"),
  case("g7_union_grant", union_grant, "grant_identity"),
  case("g7_union_nonlexicographic_declaration", union_a,
    "pack_declaration_identity"),
  case("g7_union_alternate_order_declaration", union_b,
    "pack_declaration_identity"),
  case("g7_union_nonlexicographic_derivation",
    union_chain_a$sealed$derivation, "derivation_identity"),
  case("g7_union_alternate_order_derivation",
    union_chain_b$sealed$derivation, "derivation_identity"),
  case("g7_union_nonlexicographic_sealed_axis", union_chain_a$sealed$seal,
    "sealed_axis_identity"),
  case("g7_union_alternate_order_sealed_axis", union_chain_b$sealed$seal,
    "sealed_axis_identity"),
  case("g7_union_nonlexicographic_vector_cardinality",
    union_chain_a$cardinalities[[1L]], "sealed_cardinality_grant_identity"),
  case("g7_union_alternate_order_vector_cardinality",
    union_chain_b$cardinalities[[1L]], "sealed_cardinality_grant_identity"),
  case("g7_union_nonlexicographic_family_cardinality",
    union_chain_a$cardinalities[[2L]], "sealed_cardinality_grant_identity"),
  case("g7_union_alternate_order_family_cardinality",
    union_chain_b$cardinalities[[2L]], "sealed_cardinality_grant_identity"),
  case("g7_union_nonlexicographic_vector_observed_cardinality",
    union_chain_a$observed_cardinalities[[1L]],
    "observed_sealed_cardinality_identity"),
  case("g7_union_alternate_order_vector_observed_cardinality",
    union_chain_b$observed_cardinalities[[1L]],
    "observed_sealed_cardinality_identity"),
  case("g7_union_nonlexicographic_family_observed_cardinality",
    union_chain_a$observed_cardinalities[[2L]],
    "observed_sealed_cardinality_identity"),
  case("g7_union_alternate_order_family_observed_cardinality",
    union_chain_b$observed_cardinalities[[2L]],
    "observed_sealed_cardinality_identity"),
  case("g7_union_nonlexicographic_vector_descriptor",
    union_chain_a$applied$observed[[1L]]$descriptor,
    "observed_descriptor_identity"),
  case("g7_union_alternate_order_vector_descriptor",
    union_chain_b$applied$observed[[1L]]$descriptor,
    "observed_descriptor_identity"),
  case("g7_union_nonlexicographic_family_descriptor",
    union_chain_a$applied$observed[[2L]]$descriptor,
    "observed_descriptor_identity"),
  case("g7_union_alternate_order_family_descriptor",
    union_chain_b$applied$observed[[2L]]$descriptor,
    "observed_descriptor_identity"),
  case("g7_union_nonlexicographic_axis_observation",
    union_chain_a$applied$observation, "observation_identity"),
  case("g7_union_alternate_order_axis_observation",
    union_chain_b$applied$observation, "observation_identity"),
  case("g7_union_request", union_chain_a$transition$request,
    "request_identity"),
  case("g7_union_nonlexicographic_receipt",
    union_chain_a$transition$receipt, "receipt_identity"),
  case("g7_union_alternate_order_receipt", union_chain_b$transition$receipt,
    "receipt_identity"),
  effective_case("g7_effective_key_primary", effective$primary),
  effective_case("g7_effective_key_null_fallback", effective$null_fallback),
  effective_case("g7_effective_key_schema_default", effective$schema_default),
  effective_case("g7_effective_key_override", effective$override),
  effective_case("g7_effective_key_same_no_presence",
    effective$same_key_no_presence),
  effective_case("g7_effective_key_same_with_presence",
    effective$same_key_with_presence))
fixture$cases <- c(Filter(function(x) !startsWith(x$name, "g7_"),
  fixture$cases), new)
fixture$g7_positive_examples <- list(subset = list(declaration = declaration,
  grant = grant, pack_declaration = pack_declaration,
  sealed_axis = sealed$seal, observation = subset_chain$observation),
  union_nonlexicographic = list(manifest_declaration = union_declaration,
    grant = union_grant,
    member_axes = list(list("cell_2", "cell_10"),
      list("cell_1", "cell_2")), declared_final_order = list("cell_1",
        "cell_10", "cell_2"), declaration = union_a,
    sealed_axis = union_chain_a$sealed$seal,
    linked_values = lapply(union_chain_a$values, unclass),
    observation = union_chain_a$applied$observation,
    request = union_chain_a$transition$request,
    receipt = union_chain_a$transition$receipt),
  union_alternate_order = list(declared_final_order = list("cell_2",
    "cell_1", "cell_10"), declaration = union_b,
    sealed_axis = union_chain_b$sealed$seal,
    linked_values = lapply(union_chain_b$values, unclass),
    observation = union_chain_b$applied$observation,
    receipt = union_chain_b$transition$receipt))
fixture$g7_effective_key_positive_examples <- effective
fixture$g7_effective_key_negative_examples <- list(
  list(name = "duplicate_candidates", expected = "reject_manifest",
    declaration = within(effective_spec, parameter_candidates <- list(
      "primary_key", "primary_key"))),
  list(name = "too_many_candidates", expected = "reject_manifest",
    declaration = within(effective_spec, parameter_candidates <- list(
      "primary_key", "fallback_key", "third_key"))),
  list(name = "empty_candidate", expected = "reject_manifest",
    declaration = within(effective_spec, parameter_candidates <- list(""))),
  list(name = "ambiguous_override_inputs", expected = "reject_manifest",
    declaration = within(effective_override_spec,
      input_presence_override <- list(present = "confidence",
        absent = "confidence", use_parameter = "fallback_key"))),
  list(name = "empty_effective_value", expected = "reject_resolution",
    declaration = effective_spec, effective_parameters = list(
      primary_key = "", fallback_key = "L1"), input_presence = list()),
  list(name = "self_rehashed_wrong_branch", expected = "reject_receipt",
    declaration = effective_override_spec, effective_parameters = list(
      primary_key = "custom", fallback_key = "L1"), input_presence = list(
        lineage_weights = TRUE), substituted_key = "custom"))
jsonlite::write_json(fixture, path, auto_unbox = TRUE, pretty = TRUE,
  null = "null", digits = NA)
