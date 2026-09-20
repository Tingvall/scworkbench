#!/usr/bin/env Rscript

development_library <- Sys.getenv("PHASE5_R_LIBRARY", unset = "")
if (nzchar(development_library)) .libPaths(c(development_library, .libPaths()))
root <- normalizePath(file.path(dirname(sub("^--file=", "",
  commandArgs(FALSE)[grepl("^--file=", commandArgs(FALSE))])), "..", ".."),
  winslash = "/", mustWork = TRUE)
pkgload::load_all(root, quiet = TRUE)
path <- file.path(root, "inst", "protocol", "fixtures",
  "operation-pack-v3", "identities.json")
fixture <- jsonlite::read_json(path, simplifyVector = FALSE)
plain <- function(scheme, value) getFromNamespace(
  ".wb_operation_pack_v2_identity_plain", "scworkbench")(scheme, value)
scoped <- function(scheme, scope, value) getFromNamespace(
  ".wb_operation_pack_v2_identity_scoped", "scworkbench")(scheme, scope,
    value)
case <- function(name, preimage, field, identity) {
  value <- preimage; value[[field]] <- identity
  list(name = name, preimage = preimage, identity = identity, value = value)
}
hex <- function(x) paste(rep(x, 64L), collapse = "")
id <- function(scheme, x) list(scheme = scheme, sha256 = hex(x))
mk <- function(name, scheme, value, field = "identity",
    scope = paste0(name, " excluding ", field)) {
  identity <- scoped(scheme, scope, value)
  case(name, value, field, identity)
}

linkage <- list(engine = "palantir", model_type = "palantir_fit",
  source_space_id = "pca", source_space_content_identity = id(
    "scworkbench.space.content.v1", "1"), fitted_cell_order_identity = id(
      "scworkbench.cell_order.v1", "2"), selected_dimension_count = 3L,
  selected_dimension_order_identity = id(
    "scworkbench.dimension_order.v1", "3"), source_snapshot_id = "snap_1")
linkage_id <- scoped("scworkbench.operation_pack.model_source_linkage.v2",
  "linkage excluding linkage_identity", linkage)
linkage_value <- linkage; linkage_value$linkage_identity <- linkage_id
tree <- list(schema =
    "scworkbench.operation_pack.contained_model_tree_manifest.v1",
  engine = "palantir", model_type = "palantir_fit",
  primary_path = "model.pkl", file_count = 1L, total_size = 12L,
  entries = list(list(path = "model.pkl", size = 12L, sha256 = hex("4"))))
tree_id <- scoped(tree$schema, "manifest excluding manifest_identity", tree)
tree_value <- tree; tree_value$manifest_identity <- tree_id
payload_id <- plain("scworkbench.operation_pack.payload_manifest.v2",
  list(tree_manifest_identity = tree_id))
declaration <- list(name = "fit_model", input = "model",
  reader = "read_self_linked_contained_model_payload",
  allowed_models = list(list(engine = "palantir",
    model_type = "palantir_fit")), linkage_policy =
      "authenticated_existing_source_and_cell_linkage_v1",
  maximum_file_count = 32L, maximum_total_bytes = 1073741824L,
  call_discipline = "exactly_once")
declaration_id <- plain(
  "scworkbench.operation_pack.self_linked_contained_model_read.v1",
  declaration)
self_grant <- list(schema =
    "scworkbench.operation_pack.self_linked_contained_model_read_grant.v1",
  name = "fit_model", input_name = "model",
  reader = "read_self_linked_contained_model_payload",
  declaration_identity = declaration_id,
  selected_model = list(engine = "palantir", model_type = "palantir_fit"),
  input_descriptor_identity = id(
    "scworkbench.operation_pack.input_descriptor.v2", "5"),
  model_content_identity = id("scworkbench.model_ref.content.v1", "6"),
  model_source_linkage = linkage_value,
  model_source_linkage_identity = linkage_id[c("scheme", "sha256")],
  contained_payload_identity = id(
    "scworkbench.operation_pack.contained_payload.v2", "7"),
  payload_manifest_identity = payload_id, tree_manifest = tree_value,
  limits = list(maximum_file_count = 32L,
    maximum_total_bytes = 1073741824L),
  relative_root = "model_payload_reads/fit_model/tree",
  access = "verified_private_copy_read_only_v1",
  call_discipline = "exactly_once")
self_grant_id <- scoped(self_grant$schema,
  "grant excluding grant_identity", self_grant)
self_linkage_id <- linkage_id[c("scheme", "sha256")]
self_observation <- list(schema =
    "scworkbench.operation_pack.observed_self_linked_contained_model_read.v1",
  name = "fit_model", grant_identity = self_grant_id,
  input_descriptor_identity = self_grant$input_descriptor_identity,
  model_source_linkage_identity = self_linkage_id,
  tree_manifest_identity = tree_id,
  payload_manifest_identity = payload_id,
  engine = "palantir", model_type = "palantir_fit", use_count = 1L,
  integrity_status = "unchanged")

sibling_items <- list(
  list(name = "pseudotime", allocated_id = "art_1", kind = "cell_vector",
    grant_identity = id("scworkbench.operation_pack.output_grant.v3", "8"),
    replay_policy = "exact_canonical_value",
    expected_cell_order_identity_if_cell_indexed = linkage$
      fitted_cell_order_identity),
  list(name = "entropy", allocated_id = "art_2", kind = "cell_vector",
    grant_identity = id("scworkbench.operation_pack.output_grant.v3", "9"),
    replay_policy = "exact_canonical_value",
    expected_cell_order_identity_if_cell_indexed = linkage$
      fitted_cell_order_identity))
closure_preimage <- list(model_output = "model",
  model_grant_identity = id("scworkbench.operation_pack.output_grant.v3", "a"),
  model_source_linkage_identity = linkage_id,
  promotion_group = "fit", siblings = lapply(sibling_items, function(x)
    x[c("name", "grant_identity", "replay_policy")]))
closure_id <- plain("scworkbench.operation_pack.model_sibling_closure.v1",
  closure_preimage)
source_space <- list(input_name = "fit_space",
  input_descriptor_identity = id(
    "scworkbench.operation_pack.input_descriptor.v2", "b"),
  content_identity = linkage$source_space_content_identity,
  cell_order_identity = linkage$fitted_cell_order_identity,
  dimensions = list(4L, 3L), selected_dimension_count = 3L,
  selected_dimension_order_identity = linkage$
    selected_dimension_order_identity)
sibling_grant <- list(schema =
    "scworkbench.operation_pack.contained_model_sibling_write_grant.v1",
  output = "model", engine = "palantir", model_type = "palantir_fit",
  primary_path = "model.pkl", relative_root = "outputs/model/model_tree",
  source_space = source_space, model_source_linkage = linkage_value,
  required_sibling_terminals = sibling_items,
  model_sibling_closure_identity = closure_id,
  limits = list(maximum_file_count = 32L,
    maximum_total_bytes = 1073741824L))
sibling_grant_id <- scoped(sibling_grant$schema,
  "grant excluding write_grant_identity", sibling_grant)
sibling_observation <- list(schema =
    "scworkbench.operation_pack.contained_model_sibling_tree_observation.v1",
  write_grant_identity = sibling_grant_id, tree_manifest = tree_value,
  tree_manifest_identity = tree_id, payload_manifest_identity = payload_id,
  model_source_linkage_identity = linkage_id,
  ordered_sibling_observed_descriptor_identities = list(
    id("scworkbench.operation_pack.observed_output.v3", "c"),
    id("scworkbench.operation_pack.observed_output.v3", "d")),
  model_sibling_closure_identity = closure_id,
  loadability_status = "contained_tree_authenticated")

reference <- list(slot = "pseudotime", artifact_id = "art_1",
  output_name = "pseudotime", kind = "cell_vector_family",
  content_identity = id("scworkbench.cell_vector_family.content.v1", "e"),
  lifecycle_identity = id("scworkbench.artifact.lifecycle.v1", "f"),
  ancestry_identity = id("scworkbench.artifact.ancestry.v1", "1"),
  payload_manifest_identity = id(
    "scworkbench.operation_pack.payload_manifest.v2", "2"))
reference_id <- plain("scworkbench.retained_artifact_reference.v1", reference)
reference_value <- reference; reference_value$reference_identity <- reference_id
item <- list(parameter_ordinal = 2L, resolved_ordinal = 1L,
  item_key = "segment_a", order_value = 1,
  references = list(reference_value))
item_id <- plain("scworkbench.retained_artifact_collection_item.v1", item)
item_value <- item; item_value$item_identity <- item_id
collection <- list(purpose = "segments", entries = list(list(
  resolved_ordinal = 1L, item_key = "segment_a", item_identity = item_id)))
collection_id <- plain("scworkbench.retained_artifact_collection.v1",
  collection)
artifact_grant <- list(schema =
    "scworkbench.operation_pack.retained_artifact_collection_grant.v1",
  name = "segments", parameter = "segments",
  reader = "read_retained_artifact_collection_item",
  limits = list(maximum_items = 64L, maximum_references = 256L,
    maximum_single_payload_bytes = 268435456L,
    maximum_total_payload_bytes = 1073741824L),
  collection_identity = collection_id, items = list(item_value),
  call_discipline = "resolved_ordinal_slot_exactly_once")
artifact_grant_id <- scoped(artifact_grant$schema,
  "grant excluding grant_identity", artifact_grant)

source <- list(source_kind = "named_cell_set", source_name = "start",
  parameter_selector_identity = NULL,
  source_membership_identity = id("scworkbench.cell_set.membership.v1", "3"),
  bundle_cell_universe_identity = id("scworkbench.cell_order.v1", "4"))
source_id <- plain("scworkbench.named_cell_axis.source.v1", source)
selection <- list(source_identity = source_id,
  space_descriptor_identity = id(
    "scworkbench.operation_pack.input_descriptor.v2", "5"),
  projection_policy = "bundle_membership_intersect_space_axis_v1",
  source_count = 3L, selected_count = 2L,
  excluded_by_projection_count = 1L, selected_cell_id = list("c2", "c1"),
  cell_order_identity = plain("scworkbench.cell_order.v1",
    list("c2", "c1")))
selection_id <- plain("scworkbench.named_cell_axis.selection.v1", selection)
axis <- list(name = "start", role = "checkpoint", source_identity = source_id,
  selection_identity = selection_id, cell_count = 2L,
  cell_order_identity = selection$cell_order_identity,
  cell_id = list("c2", "c1"))
axis_id <- plain("scworkbench.named_cell_axis.v1", axis)
axis_collection <- list(purpose = "checkpoints", entries = list(list(
  ordinal = 1L, name = "start", role = "checkpoint",
  axis_identity = axis_id)))
axis_collection_id <- plain(
  "scworkbench.named_cell_axis_collection.v1", axis_collection)
axis_grant <- list(schema =
    "scworkbench.operation_pack.named_cell_axis_collection_grant.v1",
  name = "checkpoints", parameter = "checkpoint_sets",
  space_input = "space", space_descriptor_identity = selection$
    space_descriptor_identity, collection_identity = axis_collection_id,
  axes = list(list(ordinal = 1L, name = "start", role = "checkpoint",
    source_count = 3L, selected_count = 2L,
    excluded_by_projection_count = 1L, source_identity = source_id,
    selection_identity = selection_id,
    cell_order_identity = selection$cell_order_identity,
    axis_identity = axis_id, payload_manifest_identity = id(
      "scworkbench.operation_pack.payload_manifest.v2", "6"))),
  quality_observations = list(pairwise_overlap_counts = list(),
    minimum_selected_count = 2L, maximum_selected_count = 2L,
    selected_count_ratio = 1), limits = list(maximum_axes = 64L,
      maximum_cells_per_axis = 10000000L,
      maximum_total_memberships = 20000000L),
  call_discipline = "axis_ordinal_exactly_once")
axis_grant_id <- scoped(axis_grant$schema,
  "grant excluding grant_identity", axis_grant)

display <- list(space_id = "umap", space_descriptor_identity = id(
    "scworkbench.operation_pack.input_descriptor.v2", "7"),
  space_content_identity = id("scworkbench.space.content.v1", "8"),
  dimension_count = 2L, cell_count = 3L,
  cell_order_identity = id("scworkbench.cell_order.v1", "9"),
  payload_manifest_identity = id(
    "scworkbench.operation_pack.payload_manifest.v2", "a"))
display_id <- plain("scworkbench.operation_pack.optional_display_space.v1",
  display)
display_grant <- list(schema =
    "scworkbench.operation_pack.optional_display_axis_group_grant.v1",
  name = "endpoint_qc", group_key = "operation", scope = "operation",
  source_collection_item_identity = NULL, display_space = display,
  endpoint_axes = list(list(ordinal = 1L, role = "start", name = "start",
    source_kind = "named_cell_set", source_identity = source_id,
    selection_identity = selection_id,
    cell_order_identity = selection$cell_order_identity,
    axis_identity = axis_id, payload_manifest_identity = id(
      "scworkbench.operation_pack.payload_manifest.v2", "b"))),
  limits = list(maximum_display_cells = 10000000L,
    maximum_cells_per_endpoint_axis = 10000000L,
    maximum_total_endpoint_memberships = 20000000L),
  call_discipline = "display_partition_then_endpoint_ordinal_exactly_once")
display_grant_id <- scoped(display_grant$schema,
  "grant excluding grant_identity", display_grant)

phase5 <- list(
  case("model_source_linkage_v2", linkage, "linkage_identity", linkage_id),
  mk("self_linked_model_read_declaration",
    "scworkbench.operation_pack.self_linked_contained_model_read.v1",
    declaration, "declaration_identity"),
  case("self_linked_model_read_grant", self_grant, "grant_identity",
    self_grant_id),
  mk("self_linked_model_read_observation",
    self_observation$schema, self_observation, "observation_identity"),
  mk("model_sibling_closure", "scworkbench.operation_pack.model_sibling_closure.v1",
    closure_preimage, "closure_identity"),
  case("contained_model_sibling_write_grant", sibling_grant,
    "write_grant_identity", sibling_grant_id),
  mk("contained_model_sibling_tree_observation", sibling_observation$schema,
    sibling_observation, "observation_identity"),
  case("retained_artifact_reference", reference, "reference_identity",
    reference_id),
  case("retained_artifact_collection_item", item, "item_identity", item_id),
  mk("retained_artifact_collection", "scworkbench.retained_artifact_collection.v1",
    collection, "collection_identity"),
  case("retained_artifact_collection_grant", artifact_grant,
    "grant_identity", artifact_grant_id),
  mk("retained_artifact_collection_result",
    "scworkbench.operation_pack.retained_artifact_collection_result.v1",
    list(grant_identity = artifact_grant_id, resolved_ordinal = 1L,
      slot = "pseudotime", reference_identity = reference_id,
      content_identity = reference$content_identity), "result_identity"),
  case("named_cell_axis_source", source, "source_identity", source_id),
  case("named_cell_axis_selection", selection, "selection_identity",
    selection_id),
  case("named_cell_axis", axis, "axis_identity", axis_id),
  case("named_cell_axis_collection", axis_collection, "collection_identity",
    axis_collection_id),
  case("named_cell_axis_collection_grant", axis_grant, "grant_identity",
    axis_grant_id),
  case("optional_display_space", display, "display_identity", display_id),
  case("optional_display_axis_group_grant", display_grant, "grant_identity",
    display_grant_id))
names5 <- vapply(phase5, `[[`, character(1), "name")
fixture$cases <- c(Filter(function(x) !as.character(x$name) %in% names5,
  fixture$cases), phase5)
jsonlite::write_json(fixture, path, auto_unbox = TRUE, null = "null",
  digits = NA)
