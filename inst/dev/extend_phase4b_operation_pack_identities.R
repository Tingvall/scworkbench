path <- file.path("inst", "protocol", "fixtures", "operation-pack-v3",
  "identities.json")
fixture <- jsonlite::read_json(path, simplifyVector = FALSE)
fixture$cases <- Filter(function(x) !x$name %in% c(
  "session_cell_axis_snapshot", "matrix_feature_annotations_snapshot",
  "bounded_grouped_cardinality", "observed_bounded_grouped_cardinality"),
  fixture$cases)
id <- function(scheme, value, scope = NULL) {
  out <- list(scheme = scheme)
  if (!is.null(scope)) out$scope <- scope
  out$sha256 <- digest::digest(
    scworkbench:::.wb_operation_pack_canonical_json(value),
    algo = "sha256", serialize = FALSE)
  out
}
case <- function(name, preimage, field, scheme, scope) {
  identity <- id(scheme, preimage, scope)
  value <- preimage; value[[field]] <- identity
  list(name = name, preimage = preimage, identity = identity, value = value)
}
cells <- fixture$authoritative_axes$cells
features <- fixture$authoritative_axes$features
cell_order <- id("scworkbench.cell_order.v1", cells)
feature_order <- id("scworkbench.feature_order.v1", features)
plain <- function(scheme, seed) id(scheme, list(seed = seed))
session <- list(schema = "scworkbench.session_cell_axis.snapshot.v1",
  selection_policy = "effective_session_cells_v1",
  coverage_policy = "exact_complete_order_v1", session_id = "session_fixture",
  run_id = "run_fixture", checkpoint_generation = "7",
  transition_source_state_identity = plain(
    "scworkbench.scientific_state.v1", "state"),
  cell_count = 3L, cell_id = cells, cell_order_identity = cell_order)
annotation_rows <- Map(function(feature, type) list(feature_id = feature,
  values = list(feature_type = type)), features,
  list("gene", NULL, "gene"))
annotation <- list(
  schema = "scworkbench.matrix_feature_annotations.snapshot.v1",
  matrix_input = "matrix", matrix_id = "RNA",
  input_descriptor_identity = plain(
    "scworkbench.operation_pack.input_descriptor.v2", "input"),
  input_content_identity = plain("scworkbench.primitive.matrix.v1", "matrix"),
  feature_count = 3L, feature_order_identity = feature_order,
  fields = list("feature_type"), rows = unname(annotation_rows))
resolution <- list(source = "declared_bounded_key_groups_v1",
  required_keys = list("total", "detected"), optional_groups = list(
    list(name = "mito", keys = list("mito_count", "mito_percent")),
    list(name = "ribo", keys = list("ribo_count", "ribo_percent"))),
  selection_owner = "operation_pack_v1", group_order = "manifest_order_v1")
grant <- list(
  schema = "scworkbench.operation_pack.output_cardinality_grant.v1",
  output = "metrics", kind = "cell_vector_family",
  policy = "authenticated_output_axes_v1",
  shape = "bounded_grouped_cell_key_cartesian",
  row_order = "key_major_then_cell_v1", missing_values = "forbidden",
  cell_axis_source = list(input_name = "matrix",
    input_descriptor_identity = plain(
      "scworkbench.operation_pack.input_descriptor.v2", "input"),
    derivation = "effective_cells_v1"), cell_axis_count = 3L,
  cell_axis_order_identity = cell_order, key_axis_resolution = resolution,
  minimum_key_count = 2L, maximum_key_count = 6L,
  minimum_row_count = 6L, maximum_row_count = 18L)
grant_identity <- id("scworkbench.operation_pack.output_cardinality_grant.v1",
  grant, "grant excluding cardinality_grant_identity")
observed <- list(
  schema = "scworkbench.operation_pack.observed_output_cardinality.v1",
  cardinality_grant_identity = grant_identity,
  shape = "bounded_grouped_cell_key_cartesian", observed_row_count = 12L,
  observed_cell_axis_count = 3L,
  observed_cell_axis_order_identity = cell_order,
  observed_key_axis_count = 4L,
  observed_key_axis_order_identity = id("scworkbench.row_order.v1",
    list("total", "detected", "mito_count", "mito_percent")),
  observed_row_order_identity = plain("scworkbench.row_order.v1", "rows"),
  missing_count = 0L, semantic_validation = "passed",
  observed_key_axis = list("total", "detected", "mito_count", "mito_percent"),
  selected_optional_groups = list("mito"),
  selected_optional_groups_identity = id(
    "scworkbench.operation_pack.selected_optional_groups.v1", list("mito")))
fixture$cases <- c(fixture$cases, list(
  case("session_cell_axis_snapshot", session, "content_identity",
    "scworkbench.session_cell_axis.snapshot.v1",
    "canonical session cell-axis snapshot"),
  case("matrix_feature_annotations_snapshot", annotation, "content_identity",
    "scworkbench.matrix_feature_annotations.snapshot.v1",
    "canonical matrix feature annotations"),
  case("bounded_grouped_cardinality", grant, "cardinality_grant_identity",
    "scworkbench.operation_pack.output_cardinality_grant.v1",
    "grant excluding cardinality_grant_identity"),
  case("observed_bounded_grouped_cardinality", observed,
    "observed_cardinality_identity",
    "scworkbench.operation_pack.observed_output_cardinality.v1",
    "observation excluding observed_cardinality_identity")))
writeChar(scworkbench:::.wb_operation_pack_canonical_json(fixture), path,
  eos = NULL, useBytes = TRUE)
