.parameter_key_axis_matrix <- function() {
  cells <- c("c2", "c1", "c3")
  structure(list(kind = "matrix", matrix_id = "RNA",
    values = matrix(seq_len(6L), nrow = 2L,
      dimnames = list(c("g1", "g2"), cells)), dimensions = c(2L, 3L),
    cell_id = cells, feature_id = c("g1", "g2"),
    storage_profile = "matrix_ordinary_v1", meta = list()),
    class = "wb_primitive")
}

.parameter_key_axis_state <- function(params = list(
    feature_sets = c("set_b", "set_a"), pseudotime_key = "L1")) {
  matrix <- .parameter_key_axis_matrix()
  declaration <- list(name = "matrix", kind = "matrix", required = TRUE,
    alignment = "cell_and_feature_ordered")
  record <- getFromNamespace(".wb_operation_pack_v2_input_descriptor",
    "scworkbench")("matrix", matrix, declaration)
  policy <- list(output = "adjusted_scores",
    policy = "authenticated_output_axes_v1", shape = "cell_key_cartesian",
    cell_axis = list(source = "effective_cells_v1", input = "matrix"),
    key_axis = list(source = "parameter_keys_with_optional_prefix_v1",
      keys_parameter = "feature_sets", prefix_parameter = "pseudotime_key",
      separator = "::"), row_order = "key_major_then_cell_v1",
    missing_values = "forbidden")
  output <- list(name = "adjusted_scores", kind = "cell_vector_family")
  grant <- getFromNamespace(".wb_operation_pack_v3_cardinality_grant",
    "scworkbench")(policy, output, list(matrix = matrix), params,
      list(matrix = record), effective_cells = matrix$cell_id)
  list(grant = grant, matrix = matrix)
}

test_operation_pack_v3_parameter_key_axis_contract <- function() {
  state <- .parameter_key_axis_state()
  grant <- state$grant
  expected_keys <- c("L1::set_b", "L1::set_a")
  stopifnot(identical(as.character(unlist(grant$key_axis)), expected_keys),
    identical(grant$key_axis_count, 2L),
    identical(grant$expected_row_count, 6L),
    identical(grant$key_axis_resolution$order, "parameter_order_v1"),
    identical(as.character(unlist(grant$key_axis_resolution$
      keys_parameter_value)), c("set_b", "set_a")))

  value <- wb_prim_cell_vector_family(
    rep(expected_keys, each = length(state$matrix$cell_id)),
    rep(state$matrix$cell_id, times = length(expected_keys)),
    seq_len(grant$expected_row_count), value_type = "continuous")
  observed <- getFromNamespace(".wb_operation_pack_v3_observe_cardinality",
    "scworkbench")(value, grant)
  stopifnot(identical(observed$observed_row_count, 6L),
    identical(observed$missing_count, 0L))

  wrong_order <- value
  wrong_order$cell_id[1:2] <- rev(wrong_order$cell_id[1:2])
  missing <- value
  missing$key <- missing$key[-1L]
  missing$cell_id <- missing$cell_id[-1L]
  missing$value <- missing$value[-1L]
  missing$dimensions <- as.integer(length(missing$value))
  stopifnot(inherits(try(getFromNamespace(
      ".wb_operation_pack_v3_observe_cardinality", "scworkbench")(
        wrong_order, grant), silent = TRUE), "try-error"),
    inherits(try(getFromNamespace(
      ".wb_operation_pack_v3_observe_cardinality", "scworkbench")(
        missing, grant), silent = TRUE), "try-error"))

  invalid <- list(character(), c("set_a", "set_a"), c("", "set_a"))
  stopifnot(all(vapply(invalid, function(keys) inherits(try(
    .parameter_key_axis_state(list(feature_sets = keys,
      pseudotime_key = "L1")), silent = TRUE), "try-error"), logical(1))))
  bare <- .parameter_key_axis_state(list(feature_sets = c("set_b", "set_a"),
    pseudotime_key = NULL))$grant
  stopifnot(identical(as.character(unlist(bare$key_axis)),
    c("set_b", "set_a")))
  TRUE
}

test_operation_pack_v3_parameter_key_axis_schema_contract <- function() {
  paths <- file.path("inst", "protocol", c("operation-pack-v3.schema.json",
    "operation-pack-transition-request-v3.schema.json",
    "operation-pack-transition-receipt-v3.schema.json"))
  stopifnot(all(file.exists(paths)), all(vapply(paths, function(path) {
    value <- jsonlite::read_json(path, simplifyVector = FALSE)
    grepl("parameter_keys_with_optional_prefix_v1",
      jsonlite::toJSON(value, auto_unbox = TRUE), fixed = TRUE)
  }, logical(1))))
  TRUE
}
