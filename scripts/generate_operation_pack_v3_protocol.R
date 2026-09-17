#!/usr/bin/env Rscript

# Deterministically canonicalize the frozen ABI-v3 protocol documents and
# regenerate the language-neutral identity corpus. ABI v1/v2 documents are
# deliberately outside this generator and remain byte-frozen.

library(jsonlite)

argv <- commandArgs(FALSE)
script <- sub("^--file=", "", argv[grep("^--file=", argv)][1])
root <- normalizePath(file.path(dirname(script), ".."), mustWork = TRUE)
protocol <- file.path(root, "inst", "protocol")

read_json_file <- function(path) read_json(path, simplifyVector = FALSE)
write_json_file <- function(value, path) {
  bytes <- toJSON(value, auto_unbox = TRUE, pretty = TRUE, null = "null",
    na = "null", digits = NA)
  writeChar(bytes, path, eos = NULL, useBytes = TRUE)
}

schemas <- c("operation-pack-v3.schema.json",
  "operation-pack-transition-request-v3.schema.json",
  "operation-pack-transition-receipt-v3.schema.json")
for (name in schemas) {
  path <- file.path(protocol, name)
  value <- read_json_file(path)
  stopifnot(identical(value$`x-phase3b-design-commit`,
    "483120cdc2a5cbaa60d88a19d05c45f0675cf3fe"))
  write_json_file(value, path)
}

identity_env <- new.env(parent = globalenv())
sys.source(file.path(root, "R", "operation_packs.R"), envir = identity_env)
hash <- function(x) digest::digest(
  identity_env$.wb_operation_pack_canonical_json(x), algo = "sha256",
  serialize = FALSE)
plain <- function(scheme, value) list(scheme = scheme, sha256 = hash(value))
scoped <- function(scheme, scope, value) list(scheme = scheme, scope = scope,
  sha256 = hash(value))
unscoped <- function(identity) list(scheme = identity$scheme,
  sha256 = identity$sha256)
signed <- function(name, scheme, scope, value, field) {
  value[[field]] <- scoped(scheme, scope, value)
  list(name = name, preimage = value[names(value) != field],
    identity = value[[field]], value = value)
}

cells <- c("c2", "c1", "c3")
features <- c("g2", "g1", "g3")
keys <- c("sigB", "sigA")
pairs <- unlist(lapply(keys, function(key) lapply(cells,
  function(cell) list(key = key, cell_id = cell))), recursive = FALSE)
input_id <- plain("scworkbench.operation_pack.input_descriptor.v2",
  list(name = "matrix", cells = as.list(cells),
    features = as.list(features)))
input_content <- plain("scworkbench.matrix.content.v1",
  list(features = as.list(features), cells = as.list(cells)))
cell_order <- plain("scworkbench.cell_order.v1", as.list(cells))
feature_order <- plain("scworkbench.feature_order.v1", as.list(features))
key_order <- plain("scworkbench.row_order.v1", as.list(keys))
row_order <- plain("scworkbench.row_order.v1", pairs)

resolution <- list(source = "resolved_parameter_feature_groups_v1",
  groups_parameter = "features", matrix_input = "matrix",
  matrix_input_descriptor_identity = input_id,
  matrix_feature_axis_identity = feature_order,
  name_prefix_parameter = "name", name_prefix_value = "Module",
  matching = "exact_feature_id_v1",
  normalization = "ordered_unique_features_v1",
  generated_names = "legacy_module_group_names_v1",
  missing_feature_policy = "drop", empty_group_policy = "drop",
  zero_key_policy = "error", groups = list(
    list(key = "sigB", features_input = list("g2", "missing"),
      features_matched = list("g2"), features_missing = list("missing")),
    list(key = "sigA", features_input = list("g1", "g3"),
      features_matched = list("g1", "g3"), features_missing = list())))
cardinality_value <- list(schema =
    "scworkbench.operation_pack.output_cardinality_grant.v1",
  output = "scores", kind = "cell_vector_family",
  policy = "authenticated_output_axes_v1", shape = "cell_key_cartesian",
  row_order = "key_major_then_cell_v1", missing_values = "forbidden",
  cell_axis_source = list(input_name = "matrix",
    input_descriptor_identity = input_id, derivation = "effective_cells_v1"),
  cell_axis_count = 3L, cell_axis_order_identity = cell_order,
  key_axis_count = 2L, key_axis = as.list(keys),
  key_axis_resolution = resolution, key_axis_order_identity = key_order,
  expected_row_count = 6L, row_order_identity = row_order)
cardinality <- signed("cardinality_three_cells_two_keys",
  "scworkbench.operation_pack.output_cardinality_grant.v1",
  "grant excluding cardinality_grant_identity", cardinality_value,
  "cardinality_grant_identity")
observed_value <- list(schema =
    "scworkbench.operation_pack.observed_output_cardinality.v1",
  cardinality_grant_identity = cardinality$identity,
  shape = "cell_key_cartesian", observed_row_count = 6L,
  observed_cell_axis_count = 3L,
  observed_cell_axis_order_identity = cell_order,
  observed_key_axis_count = 2L,
  observed_key_axis_order_identity = key_order,
  observed_row_order_identity = row_order, missing_count = 0L,
  semantic_validation = "passed")
observed <- signed("observed_cardinality_three_cells_two_keys",
  "scworkbench.operation_pack.observed_output_cardinality.v1",
  "observation excluding observed_cardinality_identity", observed_value,
  "observed_cardinality_identity")

axis_case <- function(axis, ids, order_identity) {
  value <- list(schema =
      "scworkbench.operation_pack.typed_slice_axis_manifest.v1",
    axis = axis, count = as.integer(length(ids)), ids = as.list(ids),
    order_identity = order_identity)
  signed(paste0("typed_slice_", axis, "_axis"),
    "scworkbench.operation_pack.typed_slice_axis_manifest.v1",
    "axis manifest excluding manifest_identity", value, "manifest_identity")
}
cell_axis <- axis_case("cells", cells, cell_order)
feature_axis <- axis_case("features", features, feature_order)
source_state <- plain("scworkbench.bundle.source_state.v2",
  list(bundle = "fixture"))
source_value <- list(schema =
    "scworkbench.operation_pack.typed_slice_source_reference.v1",
  input_name = "matrix", input_reference = "matrix:RNA",
  source_kind = "bundle_matrix", matrix_id = "RNA",
  input_descriptor_identity = input_id,
  input_content_identity = input_content,
  transition_source_state_identity = source_state)
source <- signed("typed_slice_bundle_source",
  "scworkbench.operation_pack.typed_slice_source_reference.v1",
  "source reference excluding source_reference_identity", source_value,
  "source_reference_identity")
payload_identity <- function(path, token) scoped(
  "scworkbench.operation_pack.payload_manifest.v2",
  "registry read payload manifest", list(path = path, size = 128,
    sha256 = token))
axis_descriptor <- function(axis_case, token) list(
  axis = axis_case$value$axis, count = axis_case$value$count,
  order_identity = axis_case$value$order_identity,
  axis_manifest_identity = axis_case$identity,
  relative_path = paste0("typed_slice_axes/matrix_chunks/",
    axis_case$value$axis, ".json"),
  payload_manifest_identity = payload_identity(paste0(
    "typed_slice_axes/matrix_chunks/", axis_case$value$axis, ".json"), token))
grant_value <- list(schema = "scworkbench.operation_pack.typed_slice_grant.v1",
  name = "matrix_chunks", input_name = "matrix", kind = "matrix",
  reader = "read_typed_slices", input_descriptor_identity = input_id,
  input_content_identity = input_content, source_reference = source$value,
  supported_axes = list("cells"), chunk_axis = "cells",
  cells_axis = axis_descriptor(cell_axis, paste(rep("c", 64), collapse = "")),
  features_axis = axis_descriptor(feature_axis,
    paste(rep("d", 64), collapse = "")), requested_chunk_size = 2L,
  call_discipline = "ordered_partition_exactly_once",
  empty_selection_policy = "reject", duplicate_policy = "reject",
  max_rows = 3L, max_columns = 2L, max_elements = 6L,
  max_control_bytes = 1048576L, max_response_bytes = 134217728L,
  max_outstanding_responses = 1L)
grant <- signed("typed_slice_cells_grant",
  "scworkbench.operation_pack.typed_slice_grant.v1",
  "grant excluding grant_identity", grant_value, "grant_identity")

semantic <- plain("scworkbench.operation_pack.matrix_slice.content.v1",
  list(schema = "scworkbench.operation_pack.matrix_slice.content.v1",
    kind = "matrix", dimensions = list(3L, 2L),
    feature_id = as.list(features), cell_id = as.list(cells[1:2]),
    entries = list(list(row = 1L, column = 1L, value = 1L),
      list(row = 2L, column = 2L, value = 2L))))
result_value <- list(schema =
    "scworkbench.operation_pack.typed_slice_result.v1",
  source_reference_identity = unscoped(source$identity),
  grant_identity = unscoped(grant$identity), ordinal = 1L, feature_count = 3L,
  feature_order_identity = feature_order, cell_count = 2L,
  cell_order_identity = plain("scworkbench.cell_order.v1",
    as.list(cells[1:2])), dimensions = list(3L, 2L),
  semantic_content_identity = semantic)
result <- signed("typed_slice_result_first_partition",
  "scworkbench.operation_pack.typed_slice_result.v1",
  "slice result excluding slice_result_identity", result_value,
  "slice_result_identity")
call_value <- result$value
call_value$schema <- "scworkbench.operation_pack.observed_typed_slice_call.v1"
call_value$source_reference_identity <- NULL
call <- signed("observed_typed_slice_call_first_partition",
  "scworkbench.operation_pack.observed_typed_slice_call.v1",
  "call excluding call_identity", call_value, "call_identity")
request_id <- plain("scworkbench.operation_pack.transition_request.v3",
  list(request = "fixture"))
capability_id <- plain("scworkbench.operation_pack.capability.v3",
  list(capability = "fixture"))
definition_id <- plain("scworkbench.operation_pack.definition.v3",
  list(operation = "fixture"))
usage_value <- list(schema =
    "scworkbench.operation_pack.typed_slice_usage.v1",
  request_identity = request_id, capability_identity = capability_id,
  operation_definition_identity = definition_id,
  grant_identity = unscoped(grant$identity), requested_chunk_size = 2L,
  calls = list(call$value), call_count = 1L,
  concatenated_chunk_axis_order_identity = plain(
    "scworkbench.cell_order.v1", as.list(cells[1:2])),
  unique_chunk_axis_count = 2L, duplicate_chunk_axis_count = 0L,
  coverage_status = "independent")
usage <- signed("typed_slice_usage_one_independent_call",
  "scworkbench.operation_pack.typed_slice_usage.v1",
  "usage excluding usage_identity", usage_value, "usage_identity")

source_head_value <- list(snapshot_id = "snapshot_source",
  schema_version = "4", head_run_ids = list("run_source"), n_runs = 1L,
  n_artifacts = 1L, commit_id = NULL, replay_status = "verified")
source_head <- signed("source_snapshot_head",
  "scworkbench.provenance.snapshot_head.v1",
  "snapshot head excluding source_snapshot_identity", source_head_value,
  "source_snapshot_identity")
ancestry_value <- list(schema = "scworkbench.artifact_ancestry.snapshot.v1",
  attestation_name = "source_ancestry", input_name = "signal",
  input_descriptor_identity = input_id, reference_kind = "promoted_artifact",
  artifact_id = "artifact_current", artifact_type = "cell_vector_family",
  artifact_lineage_status = "promoted", artifact_content_identity =
    plain("scworkbench.cell_vector_family.content.v1", list(keys = as.list(keys),
      cells = as.list(cells))), source_run_id = "run_source",
  source_run_identity = plain("scworkbench.provenance.run.v1",
    list(run = "source")), source_snapshot_id = "snapshot_source",
  source_snapshot = source_head$value, source_output_name = "signal",
  source_output_content_identity = plain(
    "scworkbench.cell_vector_family.content.v1",
    list(keys = as.list(keys), cells = as.list(cells))),
  lifecycle = list(state = "current", identity = plain(
    "scworkbench.entity.lifecycle.v1", list(artifact = "current")),
    provenance_bound = 1L, incoming_supersedes = list(),
    outgoing_superseded_by = list(), tombstone_state = NULL))
ancestry <- signed("current_artifact_ancestry",
  "scworkbench.artifact_ancestry.snapshot.v1",
  "snapshot excluding snapshot_identity", ancestry_value,
  "snapshot_identity")

fixture <- list(schema = "scworkbench.operation_pack.v3.identity_fixtures.v1",
  canonical_json_scheme = "scworkbench.operation_pack.canonical_json.v1",
  authoritative_axes = list(cells = as.list(cells),
    features = as.list(features), keys = as.list(keys), pairs = pairs),
  cases = list(cardinality, observed, cell_axis, feature_axis, source, grant,
    result, call, usage, source_head, ancestry))
fixture_path <- file.path(protocol, "fixtures", "operation-pack-v3",
  "identities.json")
dir.create(dirname(fixture_path), recursive = TRUE, showWarnings = FALSE)
write_json_file(fixture, fixture_path)
