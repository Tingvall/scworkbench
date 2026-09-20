#!/usr/bin/env Rscript

root <- normalizePath(file.path(dirname(sub("^--file=", "",
  commandArgs(FALSE)[grepl("^--file=", commandArgs(FALSE))])), "..", ".."),
  winslash = "/", mustWork = TRUE)
pkgload::load_all(root, quiet = TRUE)
path <- file.path(root, "tests", "fixtures", "operation-pack-v3-phase5",
  "inst", "scworkbench", "operation-pack.json")
x <- jsonlite::read_json(path, simplifyVector = FALSE)
scoped <- function(scheme, scope, value)
  scworkbench:::.wb_operation_pack_v2_identity_scoped(scheme, scope, value)
declaration <- list(schema =
    "scworkbench.operation_pack.supported_external_state_adoption.v1",
  name = "adoption", state_input = "candidate",
  source_parameter = "external_source_ref",
  allowed_state_types = list(list(engine = "fixture",
    model_type = "external_state")),
  allowed_source_byte_states = list("bytes_verified",
    "bytes_not_inspected", "bytes_unavailable"), model_output = "model",
  required_closure_outputs = list("summary"), primary_path = "model.bin",
  maximum_file_count = 8L, maximum_total_bytes = 1048576L,
  maximum_cell_count = 1000L,
  call_discipline = "adoption_state_exactly_once",
  output_tree_policy = "exact_admitted_tree_identity",
  execution_semantics = "supported_external_state_adoption_without_refit_v1")
declaration$declaration_identity <- scoped(declaration$schema,
  "supported external state adoption declaration excluding declaration_identity",
  declaration)
operation <- list(name = "adopt_external_state",
  qualified_name = "scwbv3phase5::adopt_external_state",
  title = "Generic external-state adoption fixture",
  description = paste("Adopts an authenticated external model tree through",
    "the path-free generic G3 capability."), runner = ".adopt_external_state",
  inputs = list(
    list(name = "source", kind = "space", required = TRUE,
      alignment = "cell_ordered"),
    list(name = "candidate", kind = "external_state_candidate",
      required = TRUE, alignment = "none")),
  params_schema = list(type = "object", properties = list(
    dims = list(type = "array", items = list(type = "integer", minimum = 1L),
      minItems = 1L, uniqueItems = TRUE),
    external_source_ref = list(type = "object", additionalProperties = FALSE,
      required = list("source_id", "snapshot_id", "run_id"), properties = list(
        source_id = list(type = "string", minLength = 1L),
        snapshot_id = list(type = "string", minLength = 1L),
        run_id = list(type = "string", minLength = 1L)))),
    required = list("dims", "external_source_ref"),
    additionalProperties = FALSE),
  dimension_policies = list(list(output = "summary",
    policy = "authenticated_output_axes_v1", shape = "one_per_cell",
    cell_axis = list(source = "effective_cells_v1", input = "source"),
    row_order = "input_cell_order_v1", missing_values = "forbidden")),
  outputs = list(
    list(name = "model", category = "terminal_artifact", kind = "model_ref",
      storage_profile = "model_ref_contained_tree_v1",
      allocated_id_key = "model_id", required = TRUE,
      promotion_group = "adoption",
      contained_model_sibling_closure_policy = list(policy =
          "staged_contained_model_sibling_closure_v1", engine = "fixture",
        model_type = "external_state", primary_path = "model.bin",
        source_space_input = "source", dimensions_parameter = "dims",
        required_sibling_terminals = list("summary"),
        file_order = "utf8_path_lexicographic_v1", maximum_file_count = 8L,
        maximum_total_bytes = 1048576L)),
    list(name = "summary", category = "terminal_artifact",
      kind = "cell_vector", storage_profile = "terminal_primitive_v1",
      allocated_id_key = "summary_id", required = TRUE,
      promotion_group = "adoption", value_kind = "categorical")),
  dependencies = list(),
  promotion_closure = list(model = list("model", "summary"),
    summary = list("model", "summary")),
  replay_equivalence = list(model = "loadable_reference",
    summary = "exact_canonical_value"),
  supported_external_state_adoptions = list(declaration))
x$operations <- c(Filter(function(op) !identical(op$qualified_name,
  operation$qualified_name), x$operations), list(operation))
jsonlite::write_json(x, path, auto_unbox = TRUE, pretty = TRUE,
  null = "null", digits = NA)
