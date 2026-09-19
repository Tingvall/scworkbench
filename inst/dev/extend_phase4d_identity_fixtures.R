#!/usr/bin/env Rscript

development_library <- Sys.getenv("PHASE4D_R_LIBRARY", unset = "")
if (nzchar(development_library)) .libPaths(c(development_library, .libPaths()))
root <- normalizePath(file.path(dirname(sub("^--file=", "",
  commandArgs(FALSE)[grepl("^--file=", commandArgs(FALSE))])), "..", ".."),
  winslash = "/", mustWork = TRUE)
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

entry <- list(path = "model.uwot", size = 12L, sha256 = hex("1"))
tree <- list(schema =
    "scworkbench.operation_pack.contained_model_tree_manifest.v1",
  engine = "uwot", model_type = "uwot_umap", primary_path = "model.uwot",
  file_count = 1L, total_size = 12L, entries = list(entry))
tree_id <- scoped(tree$schema, "manifest excluding manifest_identity", tree)
tree_value <- tree; tree_value$manifest_identity <- tree_id
payload_preimage <- list(contained_model_tree_manifest_identity =
    list(scheme = tree_id$scheme, sha256 = tree_id$sha256),
  entry_payload_identities = list(plain(
    "scworkbench.operation_pack.payload_file.v1", entry)))
payload_id <- plain("scworkbench.operation_pack.payload_manifest.v2",
  payload_preimage)
space_binding <- list(input_name = "space",
  input_descriptor_identity = id(
    "scworkbench.operation_pack.input_descriptor.v2", "2"),
  selected_dimension_count = 3L,
  selected_dimension_order_identity = id(
    "scworkbench.dimension_order.v1", "3"))
space_binding_id <- plain(
  "scworkbench.operation_pack.model_source_space.v1", space_binding)
write <- list(schema =
    "scworkbench.operation_pack.contained_model_write_grant.v1",
  output = "model", engine = "uwot", model_type = "uwot_umap",
  primary_path = "model.uwot", relative_root =
    "outputs/model/model_tree", source_space = c(space_binding, list(
      content_identity = id("scworkbench.space.content.v1", "4"),
      cell_order_identity = id("scworkbench.cell_order.v1", "5"),
      dimensions = list(4L, 3L))), paired_space_output = list(
      name = "space_2d", allocated_id = "umap.pca",
      expected_dimensions = list(4L, 2L),
      expected_cell_order_identity = id("scworkbench.cell_order.v1", "5")),
  limits = list(maximum_file_count = 32L,
    maximum_total_bytes = 1073741824L))
write_id <- scoped(write$schema, "grant excluding write_grant_identity", write)
linkage <- list(engine = "uwot", model_type = "uwot_umap",
  source_space_id = "pca", selected_dimension_count = 3L,
  selected_dimension_order_identity = space_binding$
    selected_dimension_order_identity)
linkage_id <- scoped("scworkbench.operation_pack.model_linkage.v1",
  "linkage excluding linkage_identity", linkage)
read <- list(schema =
    "scworkbench.operation_pack.contained_model_read_grant.v1",
  name = "fitted_model", input_name = "model",
  reader = "read_contained_model_payload", engine = "uwot",
  model_type = "uwot_umap", input_descriptor_identity = id(
    "scworkbench.operation_pack.input_descriptor.v2", "6"),
  model_content_identity = id("scworkbench.model_ref.content.v1", "7"),
  model_linkage_identity = list(scheme = linkage_id$scheme,
    sha256 = linkage_id$sha256), contained_payload_identity = id(
      "scworkbench.operation_pack.contained_payload.v2", "8"),
  payload_manifest_identity = payload_id, tree_manifest = tree_value,
  source_space_binding = space_binding,
  relative_root = "model_payload_reads/fitted_model/tree",
  access = "verified_private_copy_read_only_v1",
  call_discipline = "exactly_once")
read_id <- scoped(read$schema, "grant excluding grant_identity", read)
absent <- list(state = "absent", registry_absence_identity = id(
    "scworkbench.operation_pack.registry_absence.v1", "9"),
  transition_source_state_identity = id(
    "scworkbench.scientific_state.v1", "a"))
present <- list(state = "present", transition_source_state_identity = id(
    "scworkbench.scientific_state.v1", "a"), registry_identity = id(
      "scworkbench.operation_pack.materialization_registry.v1", "b"),
  content_identity = id("scworkbench.space.content.v1", "c"),
  payload_manifest_identity = id(
    "scworkbench.operation_pack.materialization_payload_manifest.v1", "d"),
  provenance_identity = id(
    "scworkbench.operation_pack.materialization_provenance.v1", "e"),
  lifecycle_identity = id(
    "scworkbench.operation_pack.materialization_lifecycle.v1", "f"),
  cell_order_identity = id("scworkbench.cell_order.v1", "1"),
  coordinate_dimensions = 2L)
space_grant <- function(source, preimage, mode) list(schema =
    "scworkbench.operation_pack.space_2d_publication_grant.v1",
  output = "space_2d", promotion_group = "umap",
  closure_outputs = list("model", "space_2d"), target_kind = "space_2d",
  target_id = "umap.pca", mode = mode,
  conflict_policy = if (mode == "add") "require_absent_v1" else
    "merge_exact_preimage_v1", overwrite_existing_cells = mode != "add",
  selected_cells = list(count = 4L, order_identity = id(
    "scworkbench.cell_order.v1", "5"), membership_identity = id(
      "scworkbench.cell_membership.v1", "6")),
  recipient_cell_axis_identity = id("scworkbench.cell_order.v1", "5"),
  expected_final_cell_order_identity = id("scworkbench.cell_order.v1", "5"),
  source_model_binding = source, preimage = preimage)
sibling <- space_grant(list(source = "sibling_output", name = "model",
  allocated_id = "model_fixture", engine = "uwot",
  model_type = "uwot_umap",
  source_space_binding_identity = space_binding_id), absent, "add")
sibling_id <- scoped(sibling$schema,
  "grant excluding publication_grant_identity", sibling)
input <- space_grant(list(source = "input", name = "model",
  engine = "uwot", model_type = "uwot_umap",
  model_linkage_identity = list(scheme = linkage_id$scheme,
    sha256 = linkage_id$sha256), contained_payload_identity = id(
      "scworkbench.operation_pack.contained_payload.v2", "8")), present,
  "selected_cell_merge")
input$closure_outputs <- list("projection_membership", "space_2d")
input$promotion_group <- "projection"
input_id <- scoped(input$schema,
  "grant excluding publication_grant_identity", input)
tree_observation <- list(engine = "uwot", model_type = "uwot_umap",
  primary_path = "model.uwot", file_count = 1L, total_size = 12L,
  tree_manifest_identity = list(scheme = tree_id$scheme,
    sha256 = tree_id$sha256), payload_manifest_identity = payload_id,
  source_space_binding_identity = space_binding_id,
  paired_space_observed_descriptor_identity = id(
    "scworkbench.operation_pack.observed_output.v3", "2"),
  status = "validated_not_published")
tree_observation_id <- scoped(
  "scworkbench.operation_pack.contained_model_tree_observation.v1",
  "observation excluding observation_identity", tree_observation)
read_observation <- list(schema =
    "scworkbench.operation_pack.observed_contained_model_read.v1",
  name = "fitted_model", grant_identity = list(scheme = read_id$scheme,
    sha256 = read_id$sha256), input_descriptor_identity =
    read$input_descriptor_identity, model_linkage_identity =
    read$model_linkage_identity, payload_manifest_identity = payload_id,
  engine = "uwot", model_type = "uwot_umap", use_count = 1L,
  integrity_status = "unchanged")
read_observation_id <- scoped(read_observation$schema,
  "observation excluding observation_identity", read_observation)
publication_observation <- list(schema =
    "scworkbench.operation_pack.observed_space_2d_publication.v1",
  output = "space_2d", publication_grant_identity = list(
    scheme = input_id$scheme, sha256 = input_id$sha256),
  mode = "selected_cell_merge", target_id = "umap.pca",
  source_model_binding_identity = plain(
    "scworkbench.operation_pack.model_binding.v1",
    input$source_model_binding), selected_cell_order_identity =
    input$selected_cells$order_identity, expected_final_cell_order_identity =
    input$expected_final_cell_order_identity,
  status = "validated_not_published")
publication_observation_id <- scoped(publication_observation$schema,
  "observation excluding observation_identity", publication_observation)

phase4d <- list(
  case("contained_model_tree_manifest", tree, "manifest_identity", tree_id),
  case("contained_model_payload_manifest", payload_preimage, "identity",
    payload_id),
  case("contained_model_write_grant", write, "write_grant_identity", write_id),
  case("contained_model_read_grant", read, "grant_identity", read_id),
  case("space_2d_publication_sibling_add", sibling,
    "publication_grant_identity", sibling_id),
  case("space_2d_publication_input_merge", input,
    "publication_grant_identity", input_id),
  case("contained_model_tree_observation", tree_observation,
    "observation_identity", tree_observation_id),
  case("contained_model_read_observation", read_observation,
    "observation_identity", read_observation_id),
  case("space_2d_publication_observation", publication_observation,
    "observation_identity", publication_observation_id))
names4d <- vapply(phase4d, `[[`, character(1), "name")
fixture$cases <- c(Filter(function(x) !as.character(x$name) %in% names4d,
  fixture$cases), phase4d)
jsonlite::write_json(fixture, path, auto_unbox = TRUE, null = "null",
  digits = NA)
