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

union_reference <- function(ordinal, cells, digit) {
  value <- list(source_mode = "g4_collection_member_axis",
    collection_name = "sources",
    collection_identity = id("scworkbench.retained_artifact_collection.v1",
      "3"), resolved_ordinal = as.integer(ordinal),
    item_identity = id("scworkbench.retained_artifact_collection_item.v1",
      digit), slot_name = "axis",
    slot_reference_identity = id("scworkbench.retained_artifact_reference.v1",
      digit), primitive_descriptor_identity = id(
        "scworkbench.operation_pack.input_descriptor.v2", digit),
    primitive_kind = "cell_vector", projection = "cell_vector_axis_v1",
    source_axis_selector_identity = NULL,
    source_cell_count = as.integer(length(cells)),
    source_cell_order_identity = plain("scworkbench.cell_order.v1",
      unname(as.list(cells))))
  self(value, "source_axis_reference_identity",
    "scworkbench.operation_pack.derived_cell_source_axis_reference.v1",
    "derived cell source axis reference excluding source_axis_reference_identity")
}
refs <- list(union_reference(1L, c("cell_2", "cell_10"), "4"),
  union_reference(2L, c("cell_1", "cell_2"), "5"))
union_aggregate <- list(derivation_mode =
    "declared_ordered_unique_union_v1", source_axis_count = 2L,
  source_membership_count = 4L,
  ordered_source_axis_reference_identities = lapply(refs, function(x)
    unscoped(x$source_axis_reference_identity)))
union_aggregate <- self(union_aggregate, "source_axis_aggregate_identity",
  "scworkbench.operation_pack.derived_cell_source_axis_aggregate.v1",
  "derived cell source axis aggregate excluding source_axis_aggregate_identity")
union_grant <- grant
union_grant$derivation_mode <- "declared_ordered_unique_union_v1"
union_grant$source_axes <- refs
union_grant$source_axis_aggregate <- union_aggregate
union_grant$limits$maximum_source_axes <- 2L
union_grant$grant_identity <- NULL
union_grant <- self(union_grant, "grant_identity", union_grant$schema,
  "grant excluding grant_identity")
union_a <- scworkbench::wb_derived_cell_output_axis_declaration(union_grant,
  c("cell_1", "cell_10", "cell_2"),
  list(c("cell_2", "cell_10"), c("cell_1", "cell_2")))
union_b <- scworkbench::wb_derived_cell_output_axis_declaration(union_grant,
  c("cell_2", "cell_1", "cell_10"),
  list(c("cell_2", "cell_10"), c("cell_1", "cell_2")))

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
  case("g7_union_source_aggregate", union_aggregate,
    "source_axis_aggregate_identity"),
  case("g7_union_grant", union_grant, "grant_identity"),
  case("g7_union_nonlexicographic_declaration", union_a,
    "pack_declaration_identity"),
  case("g7_union_alternate_order_declaration", union_b,
    "pack_declaration_identity"))
names_new <- vapply(new, `[[`, character(1), "name")
fixture$cases <- c(Filter(function(x) !x$name %in% names_new,
  fixture$cases), new)
fixture$g7_positive_examples <- list(subset = list(declaration = declaration,
  grant = grant, pack_declaration = pack_declaration,
  sealed_axis = sealed$seal), union_nonlexicographic = list(grant = union_grant,
    member_axes = list(list("cell_2", "cell_10"),
      list("cell_1", "cell_2")), declared_final_order = list("cell_1",
        "cell_10", "cell_2"), declaration = union_a),
  union_alternate_order = list(declared_final_order = list("cell_2",
    "cell_1", "cell_10"), declaration = union_b))
jsonlite::write_json(fixture, path, auto_unbox = TRUE, pretty = TRUE,
  null = "null", digits = NA)
