test_strict_operation_input_validation_contract <- function() {
  catalog <- scworkbench:::.wb_op_catalog()

  expect_error <- function(expr, pattern = NULL) {
    err <- try(force(expr), silent = TRUE)
    stopifnot(inherits(err, "try-error"))
    if (!is.null(pattern)) stopifnot(grepl(pattern, as.character(err), fixed = TRUE))
    invisible(err)
  }

  valid_value <- function(p) {
    if ("default" %in% names(p) && !is.null(p$default)) return(p$default)
    tp <- as.character(p$type)[1]
    if (identical(tp, "choice")) return(as.character(p$choices)[1])
    if (tp %in% c("int", "dbl", "number")) return(p$min %||% 1)
    if (tp %in% c("int_range", "int_vec")) return(as.integer(p$min %||% 1))
    if (tp %in% c("bool", "logical")) return(TRUE)
    if (tp %in% c("string", "path", "cell_set", "metadata_field")) return("x")
    if (tp %in% c("string_vec", "string_array", "cell_ids", "metadata_field_array")) return("x")
    if (identical(tp, "string_vec_or_list")) return(list(signature = "x"))
    if (identical(tp, "cell_ids_or_set")) return("set:core")
    if (identical(tp, "list_or_cell_set")) return(list(cells = "x"))
    if (identical(tp, "list")) return(list(x = 1))
    stop("No generated valid value for type: ", tp)
  }

  wrong_value <- function(type) {
    if (type %in% c("int", "int_range", "int_vec", "dbl", "number")) return("not_numeric")
    if (type %in% c("bool", "logical")) return(1L)
    if (type %in% c("string", "path", "cell_set", "choice", "string_vec", "string_array",
                    "cell_ids", "metadata_field", "metadata_field_array", "string_vec_or_list",
                    "cell_ids_or_set", "list_or_cell_set")) return(1L)
    if (identical(type, "list")) return("not_a_list")
    stop("No generated wrong value for type: ", type)
  }

  session_for <- function(op_name) {
    s <- wb_session_new()
    req <- names(scworkbench:::.wb_op(op_name)$requires %||% list())
    for (nm in req) s$active[[nm]] <- "catalog-validation-placeholder"
    s
  }

  required_params <- function(op_name, omit = NULL) {
    out <- list()
    for (p in catalog[[op_name]]$params %||% list()) {
      if (isTRUE(p$required) && !identical(as.character(p$name)[1], omit)) out[[p$name]] <- valid_value(p)
    }
    out
  }

  # Unknown names are rejected before execution and close typos are actionable.
  typo <- expect_error(
    scworkbench:::.wb_validate_op_inputs_contract("hvg_select", list(n_feature = 10L), session_for("hvg_select")),
    "Unknown input 'n_feature'"
  )
  stopifnot(grepl("Did you mean 'n_features'?", as.character(typo), fixed = TRUE))

  for (op_name in names(catalog)) {
    op <- scworkbench:::.wb_op(op_name)
    params <- catalog[[op_name]]$params %||% list()
    session <- session_for(op_name)

    # Every declared required typed input is checked before the runner.
    for (nm in names(op$requires %||% list())) {
      s_missing <- session
      s_missing$active[[nm]] <- NULL
      expect_error(
        scworkbench:::.wb_validate_op_inputs_contract(op_name, required_params(op_name), s_missing),
        paste0("Missing required input '", nm, "'")
      )
    }

    # Every required parameter is executable metadata rather than UI-only prose.
    for (p in params) if (isTRUE(p$required)) {
      expect_error(
        scworkbench:::.wb_validate_op_inputs_contract(op_name, required_params(op_name, p$name), session),
        paste0("Missing required parameter '", p$name, "'")
      )
    }

    for (p in params) {
      nm <- as.character(p$name)[1]
      tp <- as.character(p$type)[1]
      base <- required_params(op_name)

      # Wrong types are generated and rejected for every catalog parameter.
      bad <- base
      bad[[nm]] <- wrong_value(tp)
      expect_error(scworkbench:::.wb_validate_op_inputs_contract(op_name, bad, session))

      if (tp %in% c("string", "path", "cell_set", "choice", "metadata_field")) {
        empty <- base
        empty[[nm]] <- ""
        expect_error(scworkbench:::.wb_validate_op_inputs_contract(op_name, empty, session), "empty")
      }
      if (tp %in% c("string_vec", "string_array", "cell_ids", "cell_ids_or_set", "metadata_field_array")) {
        empty <- base
        empty[[nm]] <- character(0)
        expect_error(scworkbench:::.wb_validate_op_inputs_contract(op_name, empty, session), "non-empty")
      }
      if (tp %in% c("string_vec_or_list", "list_or_cell_set", "list")) {
        empty <- base
        empty[[nm]] <- list()
        expect_error(scworkbench:::.wb_validate_op_inputs_contract(op_name, empty, session), "non-empty")
      }

      # Every valid generated parameter canonicalizes through the same path used at runtime.
      good <- base
      good[[nm]] <- valid_value(p)
      checked <- scworkbench:::.wb_validate_op_inputs_contract(op_name, good, session)
      stopifnot(is.list(checked$inputs), is.list(checked$params))
      if (tp %in% c("int", "int_range", "int_vec")) stopifnot(is.integer(checked$inputs[[nm]]))

      if (tp %in% c("int", "int_range", "int_vec")) {
        fractional <- base
        fractional[[nm]] <- 1.5
        expect_error(scworkbench:::.wb_validate_op_inputs_contract(op_name, fractional, session), "mathematically integral")
      }
      if (tp %in% c("int", "int_range", "int_vec", "dbl", "number") && !isTRUE(p$allow_non_finite)) {
        nonfinite <- base
        nonfinite[[nm]] <- Inf
        expect_error(scworkbench:::.wb_validate_op_inputs_contract(op_name, nonfinite, session), "finite")
      }
      if (!is.null(p$min)) {
        below <- base
        below[[nm]] <- if (tp %in% c("int", "int_range", "int_vec")) as.integer(p$min - 1) else p$min - 1
        expect_error(scworkbench:::.wb_validate_op_inputs_contract(op_name, below, session), paste0(">= ", p$min))
      }
      if (!is.null(p$max)) {
        above <- base
        above[[nm]] <- if (tp %in% c("int", "int_range", "int_vec")) as.integer(p$max + 1) else p$max + 1
        expect_error(scworkbench:::.wb_validate_op_inputs_contract(op_name, above, session), paste0("<= ", p$max))
      }
      if (identical(tp, "choice")) {
        bad_choice <- base
        bad_choice[[nm]] <- "__not_a_declared_choice__"
        expect_error(scworkbench:::.wb_validate_op_inputs_contract(op_name, bad_choice, session), "must be one of")
      }
      if (identical(tp, "cell_ids_or_set")) {
        bad_ref <- base
        bad_ref[[nm]] <- list(ref_type = "run", run_id = "run_x")
        expect_error(scworkbench:::.wb_validate_op_inputs_contract(op_name, bad_ref, session), "must contain exactly")
      }
    }

    # Every typed input, required or optional, rejects malformed references.
    typed <- c(op$requires %||% list(), op$optional_requires %||% list())
    for (nm in names(typed)) {
      bad <- required_params(op_name)
      bad[[nm]] <- list(ref_type = "run", run_id = "run_x")
      expect_error(scworkbench:::.wb_validate_op_inputs_contract(op_name, bad, session), "must contain exactly")
    }

    # Returned primitive cardinality is exact: no missing or undeclared outputs.
    expect_error(scworkbench:::.wb_validate_op_outputs(op_name, list(undeclared = TRUE)), "output cardinality mismatch")
  }

  # Non-empty and canonical provenance-sensitive engine controls are strict too.
  expect_error(scworkbench:::.wb_validate_op_inputs_contract("cell_suffix_label", list(cell_ids = character()), wb_session_new()), "non-empty")
  expect_error(scworkbench:::.wb_validate_op_inputs_contract("cell_suffix_label", list(min_cells = 1.2), wb_session_new()), "mathematically integral")
  canonical <- scworkbench:::.wb_validate_op_inputs_contract("hvg_select", list(n_features = 12), session_for("hvg_select"))
  stopifnot(identical(canonical$inputs$n_features, 12L), identical(canonical$params$n_features, 12L))

  TRUE
}
