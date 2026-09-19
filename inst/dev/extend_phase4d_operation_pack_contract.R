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
relative <- string(pattern = "^(?!/)(?!.*(?:^|/)\\.\\.(?:/|$))(?!.*\\\\)[A-Za-z0-9._/-]+$")

manifest <- read("operation-pack-v3.schema.json")
defs <- manifest[["$defs"]]
model_policy <- object(c("policy", "engine", "model_type", "primary_path",
  "source_space_input", "paired_space_output", "dimensions_parameter",
  "file_order", "maximum_file_count", "maximum_total_bytes"), list(
    policy = list(const = "staged_contained_model_tree_v1"),
    engine = string(minLength = 1L), model_type = string(minLength = 1L),
    primary_path = relative, source_space_input = name,
    paired_space_output = name, dimensions_parameter = name,
    file_order = list(const = "utf8_path_lexicographic_v1"),
    maximum_file_count = integer(minimum = 1L),
    maximum_total_bytes = integer(minimum = 1L)))
for (i in seq_along(defs$output$oneOf)) {
  branch <- defs$output$oneOf[[i]]
  if (identical(branch$properties$kind$const, "model_ref")) {
    branch$properties$contained_model_policy <- model_policy
    defs$output$oneOf[[i]] <- branch
  }
}
contained_read <- object(c("name", "input", "reader", "engine",
  "model_type", "source_space_input", "dimensions_parameter", "access",
  "call_discipline"), list(name = name, input = name,
    reader = list(const = "read_contained_model_payload"),
    engine = string(minLength = 1L), model_type = string(minLength = 1L),
    source_space_input = name, dimensions_parameter = name,
    access = list(const = "verified_private_copy_read_only_v1"),
    call_discipline = list(const = "exactly_once")))
defs$operation$properties$contained_model_reads <- array(contained_read,
  minItems = 1L)
current_publication <- defs$operation$properties$publication_policies$items
legacy_publication <- if (!is.null(current_publication$oneOf))
  current_publication$oneOf[[1L]] else current_publication
space_mode <- list(oneOf = list(
  object(c("policy"), list(policy = list(const = "add_only_v1"))),
  object(c("policy", "overwrite_parameter"), list(policy = list(
    const = "selected_merge_or_full_replace_v1"),
    overwrite_parameter = name))))
model_binding <- object(c("source", "name"), list(source = list(enum =
  list("input", "sibling_output")), name = name))
space_publication <- object(c("output", "policy", "target_kind",
  "target_id_parameter", "mode", "cell_axis_input", "model_binding",
  "transaction_scope"), list(output = name, policy = list(const =
    "authenticated_space_2d_publication_v1"), target_kind = list(const =
    "space_2d"), target_id_parameter = name, mode = space_mode,
    cell_axis_input = name, model_binding = model_binding,
    transaction_scope = list(const = "promotion_group_v1")))
defs$operation$properties$publication_policies$items <- list(oneOf = list(
  legacy_publication, space_publication))
binding_arms <- defs$parameter_binding$oneOf
binding_arms <- Filter(function(x) !as.character(
  x$properties$policy$const %||% "") %in% c(
    "input_id_with_literal_affix_v1", "model_space_id_v1"), binding_arms)
defs$parameter_binding$oneOf <- c(binding_arms, list(
  object(c("parameter", "policy", "input", "affix"), list(
    parameter = name, policy = list(const = "input_id_with_literal_affix_v1"),
    input = name, affix = string(minLength = 1L))),
  object(c("parameter", "policy", "input"), list(
    parameter = name, policy = list(const = "model_space_id_v1"),
    input = name))))
manifest[["$defs"]] <- defs
write(manifest, "operation-pack-v3.schema.json")

request <- read("operation-pack-transition-request-v3.schema.json")
rdefs <- request[["$defs"]]
entry <- object(c("path", "size", "sha256"), list(path = relative,
  size = integer(minimum = 1L), sha256 = ref("sha256")))
tree <- object(c("schema", "engine", "model_type", "primary_path",
  "file_count", "total_size", "entries", "manifest_identity"), list(
    schema = list(const = "scworkbench.operation_pack.contained_model_tree_manifest.v1"),
    engine = string(minLength = 1L), model_type = string(minLength = 1L),
    primary_path = relative, file_count = integer(minimum = 1L),
    total_size = integer(minimum = 1L), entries = array(entry, minItems = 1L),
    manifest_identity = ref("self_identity")))
source_space <- object(c("input_name", "input_descriptor_identity",
  "content_identity", "cell_order_identity", "dimensions",
  "selected_dimension_count", "selected_dimension_order_identity"), list(
    input_name = name, input_descriptor_identity = ref("identity"),
    content_identity = ref("identity"), cell_order_identity = ref("identity"),
    dimensions = ref("dimensions_2"), selected_dimension_count = integer(minimum = 1L),
    selected_dimension_order_identity = ref("identity")))
paired_space <- object(c("name", "allocated_id", "expected_dimensions",
  "expected_cell_order_identity"), list(name = name, allocated_id = ref("id"),
    expected_dimensions = ref("dimensions_2"),
    expected_cell_order_identity = ref("identity")))
write_grant <- object(c("schema", "output", "engine", "model_type",
  "primary_path", "relative_root", "source_space", "paired_space_output",
  "limits", "write_grant_identity"), list(schema = list(const =
    "scworkbench.operation_pack.contained_model_write_grant.v1"), output = name,
    engine = string(minLength = 1L), model_type = string(minLength = 1L),
    primary_path = relative, relative_root = relative,
    source_space = source_space, paired_space_output = paired_space,
    limits = object(c("maximum_file_count", "maximum_total_bytes"), list(
      maximum_file_count = integer(minimum = 1L),
      maximum_total_bytes = integer(minimum = 1L))),
    write_grant_identity = ref("self_identity")))
source_binding <- object(c("input_name", "input_descriptor_identity",
  "selected_dimension_count", "selected_dimension_order_identity"), list(
    input_name = name, input_descriptor_identity = ref("identity"),
    selected_dimension_count = integer(minimum = 1L),
    selected_dimension_order_identity = ref("identity")))
read_grant <- object(c("schema", "name", "input_name", "reader", "engine",
  "model_type", "input_descriptor_identity", "model_content_identity",
  "model_linkage_identity", "contained_payload_identity",
  "payload_manifest_identity", "tree_manifest", "source_space_binding",
  "relative_root", "access", "call_discipline", "grant_identity"), list(
    schema = list(const = "scworkbench.operation_pack.contained_model_read_grant.v1"),
    name = name, input_name = name,
    reader = list(const = "read_contained_model_payload"),
    engine = string(minLength = 1L), model_type = string(minLength = 1L),
    input_descriptor_identity = ref("identity"),
    model_content_identity = ref("identity"),
    model_linkage_identity = ref("identity"),
    contained_payload_identity = ref("identity"),
    payload_manifest_identity = ref("identity"), tree_manifest = tree,
    source_space_binding = source_binding, relative_root = relative,
    access = list(const = "verified_private_copy_read_only_v1"),
    call_discipline = list(const = "exactly_once"),
    grant_identity = ref("self_identity")))
selected_cells <- object(c("count", "order_identity", "membership_identity"),
  list(count = integer(minimum = 1L), order_identity = ref("identity"),
    membership_identity = ref("identity")))
model_bind <- list(oneOf = list(
  object(c("source", "name", "engine", "model_type",
    "model_linkage_identity", "contained_payload_identity"), list(
      source = list(const = "input"), name = name,
      engine = string(minLength = 1L), model_type = string(minLength = 1L),
      model_linkage_identity = ref("identity"),
      contained_payload_identity = ref("identity"))),
  object(c("source", "name", "allocated_id", "engine", "model_type",
    "source_space_binding_identity"), list(
      source = list(const = "sibling_output"), name = name,
      allocated_id = ref("id"), engine = string(minLength = 1L),
      model_type = string(minLength = 1L),
      source_space_binding_identity = ref("identity")))))
space_grant <- object(c("schema", "output", "promotion_group",
  "closure_outputs", "target_kind", "target_id", "mode", "conflict_policy",
  "overwrite_existing_cells", "selected_cells", "recipient_cell_axis_identity",
  "expected_final_cell_order_identity", "source_model_binding", "preimage",
  "publication_grant_identity"), list(schema = list(const =
    "scworkbench.operation_pack.space_2d_publication_grant.v1"), output = name,
    promotion_group = name, closure_outputs = array(name, minItems = 1L,
      uniqueItems = TRUE), target_kind = list(const = "space_2d"),
    target_id = ref("id"), mode = list(enum = list("add", "selected_cell_merge",
      "full_replace")), conflict_policy = list(enum = list("require_absent_v1",
      "merge_exact_preimage_v1", "replace_exact_preimage_v1")),
    overwrite_existing_cells = list(type = "boolean"),
    selected_cells = selected_cells,
    recipient_cell_axis_identity = ref("identity"),
    expected_final_cell_order_identity = ref("identity"),
    source_model_binding = model_bind,
    preimage = list(type = "object", minProperties = 2L),
    publication_grant_identity = ref("self_identity")))
rdefs$contained_model_tree_manifest <- tree
rdefs$contained_model_write_grant <- write_grant
rdefs$contained_model_read_grant <- read_grant
rdefs$space_2d_publication_grant <- space_grant
for (i in seq_along(rdefs$output_descriptor$oneOf)) {
  if (identical(rdefs$output_descriptor$oneOf[[i]]$properties$kind$const,
      "model_ref")) rdefs$output_descriptor$oneOf[[i]]$properties$
        contained_model_write_grant <- ref("contained_model_write_grant")
}
legacy_grant <- if (!is.null(rdefs$materialization_publication_grant$oneOf))
  rdefs$materialization_publication_grant$oneOf[[1L]] else
    rdefs$materialization_publication_grant
rdefs$materialization_publication_grant <- list(oneOf = list(
  legacy_grant, ref("space_2d_publication_grant")))
rdefs$capability$properties$model_payload_grant_identities <- array(
  ref("identity"), minItems = 1L)
model_reader_arm <- object(c("model_payload_name", "reader",
  "grant_identity"), list(model_payload_name = name,
    reader = list(const = "read_contained_model_payload"),
    grant_identity = ref("self_identity")))
reader_arms <- rdefs$capability$properties$reader_grants$items$oneOf
reader_arms <- Filter(function(x) is.null(x$properties$model_payload_name),
  reader_arms)
rdefs$capability$properties$reader_grants$items$oneOf <- c(reader_arms,
  list(model_reader_arm))
request$properties$model_payload_grants <- array(ref(
  "contained_model_read_grant"), minItems = 1L)
request[["$defs"]] <- rdefs
write(request, "operation-pack-transition-request-v3.schema.json")

receipt <- read("operation-pack-transition-receipt-v3.schema.json")
odefs <- receipt[["$defs"]]
tree_observation <- object(c("engine", "model_type", "primary_path",
  "file_count", "total_size", "tree_manifest_identity",
  "payload_manifest_identity", "source_space_binding_identity",
  "paired_space_observed_descriptor_identity", "status",
  "observation_identity"), list(engine = string(minLength = 1L),
    model_type = string(minLength = 1L), primary_path = relative,
    file_count = integer(minimum = 1L), total_size = integer(minimum = 1L),
    tree_manifest_identity = ref("identity"),
    payload_manifest_identity = ref("identity"),
    source_space_binding_identity = ref("identity"),
    paired_space_observed_descriptor_identity = ref("identity"),
    status = list(const = "validated_not_published"),
    observation_identity = ref("self_identity")))
read_observation <- object(c("schema", "name", "grant_identity",
  "input_descriptor_identity", "model_linkage_identity",
  "payload_manifest_identity", "engine", "model_type", "use_count",
  "integrity_status", "observation_identity"), list(schema = list(const =
    "scworkbench.operation_pack.observed_contained_model_read.v1"), name = name,
    grant_identity = ref("identity"), input_descriptor_identity = ref("identity"),
    model_linkage_identity = ref("identity"), payload_manifest_identity = ref("identity"),
    engine = string(minLength = 1L), model_type = string(minLength = 1L),
    use_count = list(const = 1L), integrity_status = list(const = "unchanged"),
    observation_identity = ref("self_identity")))
space_observation <- object(c("schema", "publication_grant_identity", "mode",
  "preimage_identity", "source_model_binding_identity",
  "candidate_observed_descriptor_identity", "selected_cell_order_identity",
  "expected_final_cell_order_identity", "closure_output_identities", "status",
  "observation_identity"), list(schema = list(const =
    "scworkbench.operation_pack.observed_space_2d_publication.v1"),
    publication_grant_identity = ref("identity"), mode = list(enum = list(
      "add", "selected_cell_merge", "full_replace")),
    preimage_identity = ref("identity"), source_model_binding_identity = ref("identity"),
    candidate_observed_descriptor_identity = ref("identity"),
    selected_cell_order_identity = ref("identity"),
    expected_final_cell_order_identity = ref("identity"),
    closure_output_identities = array(object(c("name",
      "observed_descriptor_identity"), list(name = name,
        observed_descriptor_identity = ref("identity"))), minItems = 1L),
    status = list(const = "validated_not_published"),
    observation_identity = ref("self_identity")))
odefs$contained_model_tree_observation <- tree_observation
odefs$contained_model_read_observation <- read_observation
odefs$space_2d_publication_observation <- space_observation
for (i in seq_along(odefs$observed_output_descriptor$oneOf)) {
  if (identical(odefs$observed_output_descriptor$oneOf[[i]]$properties$kind$const,
      "model_ref")) odefs$observed_output_descriptor$oneOf[[i]]$properties$
        contained_model_tree <- ref("contained_model_tree_observation")
}
legacy_observation <- if (!is.null(odefs$publication_observation$oneOf))
  odefs$publication_observation$oneOf[[1L]] else
    odefs$publication_observation
odefs$publication_observation <- list(oneOf = list(
  legacy_observation, ref("space_2d_publication_observation")))
receipt$properties$model_payload_reads <- array(ref(
  "contained_model_read_observation"), minItems = 1L)
receipt[["$defs"]] <- odefs
write(receipt, "operation-pack-transition-receipt-v3.schema.json")

cat("PHASE4D OPERATION-PACK SCHEMAS UPDATED\n")
