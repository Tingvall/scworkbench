test_operation_pack_v3_reference_coverage_contract <- function() {
  schema <- jsonlite::read_json(file.path("inst", "protocol",
    "operation-pack-v3.schema.json"), simplifyVector = FALSE)
  validate <- getFromNamespace(".wb_json_schema_validate_2020", "scworkbench")
  input_schema <- schema[["$defs"]]$input
  declared <- list(name = "neighbors", kind = "obs_table", required = TRUE,
    alignment = "none", effective_cell_coverage = "reference_only")
  stopifnot(isTRUE(validate(declared, input_schema)$ok))

  wrong_value <- declared
  wrong_value$effective_cell_coverage <- "cell_indexed"
  wrong_kind <- declared
  wrong_kind$kind <- "space"
  wrong_kind$alignment <- "cell_ordered"
  stopifnot(!isTRUE(validate(wrong_value, input_schema)$ok),
    !isTRUE(validate(wrong_kind, input_schema)$ok))

  model <- list(name = "calibration", kind = "model_ref", required = TRUE,
    alignment = "model_linked", effective_cell_coverage = "reference_only")
  stopifnot(isTRUE(validate(model, input_schema)$ok))

  fixture <- jsonlite::read_json(file.path("tests", "fixtures",
    "operation-pack-v3-reference", "inst", "scworkbench",
    "operation-pack.json"), simplifyVector = FALSE)
  operation <- fixture$operations[[1L]]
  operation$inputs[[1L]] <- declared
  catalog <- getFromNamespace(".wb_operation_pack_v3_catalog_definition",
    "scworkbench")
  definition <- catalog(operation)
  stopifnot(identical(definition$coverage$neighbors, "reference_only"),
    identical(definition$v3_definition$inputs[[1L]]$effective_cell_coverage,
      "reference_only"))

  ordinary <- operation
  ordinary$inputs[[1L]]$effective_cell_coverage <- NULL
  stopifnot(is.null(catalog(ordinary)$coverage$neighbors))

  optional <- operation
  optional$inputs[[1L]]$required <- FALSE
  rejected <- tryCatch(getFromNamespace(
    ".wb_operation_pack_v3_reference_coverage_inputs", "scworkbench")(
      optional, optional$qualified_name), error = identity)
  stopifnot(inherits(rejected, "wb_operation_pack_v3_error"),
    grepl("required, alignment-none obs_table", conditionMessage(rejected),
      fixed = TRUE))

  model_operation <- operation
  model_operation$inputs[[1L]] <- model
  model_operation$self_linked_contained_model_reads <- list(list(
    input = "calibration"))
  stopifnot(identical(getFromNamespace(
    ".wb_operation_pack_v3_reference_coverage_inputs", "scworkbench")(
      model_operation, model_operation$qualified_name), "calibration"))
  model_operation$self_linked_contained_model_reads <- NULL
  stopifnot(inherits(tryCatch(getFromNamespace(
    ".wb_operation_pack_v3_reference_coverage_inputs", "scworkbench")(
      model_operation, model_operation$qualified_name), error = identity),
    "wb_operation_pack_v3_error"))
  TRUE
}
