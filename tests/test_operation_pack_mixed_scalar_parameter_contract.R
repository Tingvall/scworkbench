test_operation_pack_mixed_scalar_parameter_contract <- function() {
  project <- getFromNamespace(
    ".wb_operation_pack_v2_catalog_param_type", "scworkbench")
  to_catalog <- getFromNamespace(
    ".wb_operation_pack_v2_params_to_catalog", "scworkbench")
  validate <- getFromNamespace(".wb_validate_param_value", "scworkbench")

  omega_schema <- list(type = c("boolean", "number"), minimum = 0)
  stopifnot(
    identical(project(omega_schema), "bool_or_dbl"),
    identical(project(list(type = c("number", "boolean"))), "bool_or_dbl"),
    identical(project(list(type = c("null", "boolean", "number"))),
      "bool_or_dbl"),
    identical(project(list(type = c("boolean", "integer"))), "int"))

  catalog <- to_catalog(list(
    type = "object",
    properties = list(omega = omega_schema),
    required = "omega",
    additionalProperties = FALSE))
  stopifnot(
    length(catalog) == 1L,
    identical(catalog[[1L]]$name, "omega"),
    identical(catalog[[1L]]$type, "bool_or_dbl"),
    identical(catalog[[1L]]$min, 0),
    isTRUE(catalog[[1L]]$required))

  parameter <- catalog[[1L]]
  stopifnot(
    identical(validate(FALSE, parameter, "fixture::mixed"), FALSE),
    identical(validate(TRUE, parameter, "fixture::mixed"), TRUE),
    identical(validate(0L, parameter, "fixture::mixed"), 0),
    identical(validate(2.5, parameter, "fixture::mixed"), 2.5))

  expect_error <- function(value, pattern) {
    error <- tryCatch(validate(value, parameter, "fixture::mixed"),
      error = identity)
    stopifnot(inherits(error, "error"), grepl(pattern, conditionMessage(error)))
  }
  expect_error(-1, "must be >= 0")
  expect_error(NA, "logical or finite numeric")
  expect_error(NA_real_, "logical or finite numeric")
  expect_error(Inf, "logical or finite numeric")
  expect_error("TRUE", "logical or finite numeric")
  expect_error(c(TRUE, FALSE), "logical or finite numeric")
  TRUE
}
