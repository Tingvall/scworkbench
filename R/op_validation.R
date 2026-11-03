# Central executable validation for operation inputs.

.wb_op_input_alias <- function(name) {
  switch(
    as.character(name)[1],
    space = "space_id",
    space_2d = "space_id",
    matrix = "matrix_id",
    in_space = "in_space_id",
    model_space = "model_space_id",
    NULL
  )
}

.wb_op_engine_input_specs <- function() {
  list(
    cell_set = list(name = "cell_set", type = "cell_set", default = "all", required = FALSE,
                    help = "Named bundle cell set defining the requested cell universe."),
    cell_ids = list(name = "cell_ids", type = "cell_ids", default = NULL, required = FALSE,
                    help = "Optional explicit non-empty cell-id universe overriding cell_set."),
    min_cells = list(name = "min_cells", type = "int", default = 10L, min = 1L, required = FALSE,
                     help = "Minimum effective cell count required before runner execution.")
  )
}

.wb_op_param_records <- function(op_name) {
  resolved_name <- .wb_operation_name_resolve(as.character(op_name)[1])
  op <- .wb_operation_catalog()[[resolved_name]] %||% list()
  params <- op$params %||% list()
  if (!length(params)) return(stats::setNames(list(), character(0)))
  out <- list()
  for (p in params) {
    nm <- as.character(p$name %||% "")[1]
    .wb_assert(nzchar(nm), paste0("Operation '", op_name, "' has a parameter without a name."))
    .wb_assert(is.null(out[[nm]]), paste0("Operation '", op_name, "' declares parameter '", nm, "' more than once."))
    out[[nm]] <- p
  }
  out
}

.wb_op_allowed_input_names <- function(op_name) {
  op <- .wb_op(op_name)
  typed <- unique(c(names(op$requires %||% list()), names(op$optional_requires %||% list())))
  aliases <- unlist(lapply(typed, .wb_op_input_alias), use.names = FALSE)
  unique(c(
    names(.wb_op_param_records(op_name)),
    typed,
    aliases,
    paste0(typed, "_ref"),
    paste0(aliases[nzchar(aliases)], "_ref"),
    names(.wb_op_engine_input_specs())
  ))
}

.wb_op_typo_suggestion <- function(name, choices) {
  choices <- unique(as.character(choices))
  if (!length(choices)) return("")
  d <- as.numeric(utils::adist(name, choices, ignore.case = TRUE))
  best <- which.min(d)
  threshold <- max(1L, min(3L, floor(nchar(name) / 3L)))
  if (!length(best) || d[[best]] > threshold) return("")
  paste0(" Did you mean '", choices[[best]], "'?")
}

.wb_assert_nonempty_character <- function(x, label, scalar = FALSE) {
  .wb_assert(is.character(x), paste0(label, " must be character."))
  if (isTRUE(scalar)) .wb_assert(length(x) == 1L, paste0(label, " must be a single string."))
  .wb_assert(length(x) > 0L, paste0(label, " must be non-empty."))
  .wb_assert(!anyNA(x) && all(nzchar(x)), paste0(label, " must not contain NA or empty strings."))
  x
}

.wb_validate_reference_shape <- function(x, label) {
  .wb_assert(is.list(x), paste0(label, " must be a reference list."))
  ref_type <- as.character(x$ref_type %||% "")[1]
  .wb_assert(ref_type %in% c("run", "artifact"), paste0(label, " has invalid ref_type; expected 'run' or 'artifact'."))
  expected <- if (identical(ref_type, "run")) c("ref_type", "run_id", "output") else c("ref_type", "artifact_id", "output")
  .wb_assert(!is.null(names(x)) && !anyDuplicated(names(x)) && setequal(names(x), expected),
             paste0(label, " must contain exactly: ", paste(expected, collapse = ", "), "."))
  id_name <- if (identical(ref_type, "run")) "run_id" else "artifact_id"
  .wb_assert_nonempty_character(x[[id_name]], paste0(label, "$", id_name), scalar = TRUE)
  .wb_assert_nonempty_character(x$output, paste0(label, "$output"), scalar = TRUE)
  x
}

.wb_validate_typed_input_value <- function(value, name, expected_kind) {
  label <- paste0("inputs$", name)
  if (.wb_is_primitive(value)) {
    .wb_assert_kind(value, expected_kind, where = paste0(" for input '", name, "'"))
    return(value)
  }
  if (is.list(value) && !is.null(value$ref_type)) return(.wb_validate_reference_shape(value, label))
  if (expected_kind %in% c("matrix", "space", "space_2d", "in_space", "model_space", "model_ref")) {
    return(.wb_assert_nonempty_character(value, label, scalar = TRUE))
  }
  if (identical(expected_kind, "cell_vector") && is.atomic(value) && !is.null(names(value))) {
    .wb_assert(length(value) > 0L && !anyNA(names(value)) && all(nzchar(names(value))),
               paste0(label, " named vector must have non-empty cell names."))
    return(value)
  }
  stop(label, " must be a ", expected_kind, " primitive or a valid wb_ref_run()/wb_ref_artifact() reference.", call. = FALSE)
}

.wb_validate_integral <- function(value, label) {
  .wb_assert((is.integer(value) || is.double(value)) && length(value) > 0L && !anyNA(value),
             paste0(label, " must be numeric and mathematically integral."))
  .wb_assert(all(is.finite(value)), paste0(label, " must contain only finite values."))
  .wb_assert(all(value == trunc(value)), paste0(label, " must contain mathematically integral values; fractional doubles are not accepted."))
  .wb_assert(all(value >= -.Machine$integer.max & value <= .Machine$integer.max), paste0(label, " is outside the R integer range."))
  as.integer(value)
}

.wb_validate_param_value <- function(value, param, op_name) {
  nm <- as.character(param$name)[1]
  type <- as.character(param$type %||% "")[1]
  label <- paste0("inputs$", nm)
  apply_numeric_bounds <- TRUE
  .wb_assert(nzchar(type), paste0("Operation '", op_name, "' parameter '", nm, "' has no type."))

  if (is.null(value)) {
    nullable <- isTRUE(param$nullable) || ("default" %in% names(param) && is.null(param$default) && !isTRUE(param$required))
    .wb_assert(nullable, paste0(label, " may not be NULL."))
    return(NULL)
  }

  if (type %in% c("int", "int_range", "int_vec")) {
    value <- .wb_validate_integral(value, label)
    if (identical(type, "int")) .wb_assert(length(value) == 1L, paste0(label, " must be one integer."))
  } else if (type %in% c("dbl", "number")) {
    .wb_assert((is.integer(value) || is.double(value)) && length(value) == 1L && !is.na(value), paste0(label, " must be one numeric value."))
    if (!isTRUE(param$allow_non_finite)) .wb_assert(is.finite(value), paste0(label, " must be finite."))
    value <- as.numeric(value)
  } else if (type %in% c("bool", "logical")) {
    .wb_assert(is.logical(value) && length(value) == 1L && !is.na(value), paste0(label, " must be one non-NA logical value."))
    value <- as.logical(value)
  } else if (identical(type, "bool_or_dbl")) {
    is_logical <- is.logical(value) && length(value) == 1L && !is.na(value)
    is_numeric <- (is.integer(value) || is.double(value)) &&
      length(value) == 1L && !is.na(value) && is.finite(value)
    .wb_assert(is_logical || is_numeric,
      paste0(label, " must be one non-NA logical or finite numeric value."))
    if (is_logical) {
      value <- as.logical(value)
      apply_numeric_bounds <- FALSE
    } else {
      value <- as.numeric(value)
    }
  } else if (type %in% c("string", "path", "cell_set", "choice")) {
    value <- .wb_assert_nonempty_character(value, label, scalar = TRUE)
  } else if (type %in% c("string_vec", "string_array", "cell_ids")) {
    if (isTRUE(param$allow_empty) && is.character(value) && !length(value)) {
      value <- character()
    } else {
      value <- .wb_assert_nonempty_character(value, label)
    }
  } else if (identical(type, "metadata_field")) {
    if (.wb_is_metadata_field_ref(value)) value <- .wb_validate_metadata_field_ref(value, label)
    else value <- .wb_assert_nonempty_character(value, label, scalar = TRUE)
  } else if (identical(type, "metadata_field_array")) {
    if (is.character(value)) {
      value <- .wb_assert_nonempty_character(value, label)
    } else {
      .wb_assert(is.list(value) && length(value) > 0L, paste0(label, " must contain metadata names or references."))
      value <- lapply(seq_along(value), function(i) {
        item <- value[[i]]
        if (.wb_is_metadata_field_ref(item)) .wb_validate_metadata_field_ref(item, paste0(label, "[[", i, "]]"))
        else .wb_assert_nonempty_character(item, paste0(label, "[[", i, "]]"), scalar = TRUE)
      })
    }
  } else if (identical(type, "string_vec_or_list")) {
    if (is.character(value)) {
      value <- .wb_assert_nonempty_character(value, label)
    } else {
      .wb_assert(is.list(value) && length(value) > 0L, paste0(label, " must be a non-empty character vector or list of non-empty character vectors."))
      value_names <- names(value)
      value <- lapply(seq_along(value), function(i) .wb_assert_nonempty_character(value[[i]], paste0(label, "[[", i, "]]")))
      if (!is.null(value_names)) names(value) <- value_names
    }
  } else if (identical(type, "cell_ids_or_set")) {
    if (is.list(value) && !is.null(value$ref_type)) value <- .wb_validate_reference_shape(value, label)
    else value <- .wb_assert_nonempty_character(value, label)
  } else if (identical(type, "list_or_cell_set")) {
    if (is.character(value)) value <- .wb_assert_nonempty_character(value, label)
    else .wb_assert(is.list(value) && length(value) > 0L, paste0(label, " must be a non-empty list or cell-set string."))
  } else if (identical(type, "list")) {
    .wb_assert(is.list(value) && length(value) > 0L, paste0(label, " must be a non-empty list."))
  } else if (identical(type, "entity_ref")) {
    value <- .wb_capsule_normalize_ref(value, label)
  } else {
    stop("Operation '", op_name, "' parameter '", nm, "' has unsupported catalog type '", type, "'.", call. = FALSE)
  }

  if (!is.null(param$choices)) {
    .wb_assert(length(value) == 1L && value %in% param$choices,
               paste0(label, " must be one of: ", paste(param$choices, collapse = ", "), "."))
  }
  if (isTRUE(apply_numeric_bounds) && !is.null(param$min)) .wb_assert(all(value >= param$min), paste0(label, " must be >= ", param$min, "."))
  if (isTRUE(apply_numeric_bounds) && !is.null(param$max)) .wb_assert(all(value <= param$max), paste0(label, " must be <= ", param$max, "."))
  value
}

.wb_validate_op_inputs_contract <- function(op_name, inputs, session = NULL) {
  inputs <- inputs %||% list()
  .wb_assert(is.list(inputs), "inputs must be a named list.")
  .wb_assert(!is.null(names(inputs)) || !length(inputs), "inputs must be a named list.")
  if (length(inputs)) {
    .wb_assert(!anyNA(names(inputs)) && all(nzchar(names(inputs))) && !anyDuplicated(names(inputs)),
               "inputs must have unique, non-empty names.")
  }

  allowed <- .wb_op_allowed_input_names(op_name)
  unknown <- setdiff(names(inputs), allowed)
  if (length(unknown)) {
    bad <- unknown[[1]]
    stop("Unknown input '", bad, "' for op '", op_name, "'.",
         .wb_op_typo_suggestion(bad, allowed), call. = FALSE)
  }

  op <- .wb_op(op_name)
  typed <- c(op$requires %||% list(), op$optional_requires %||% list())
  canonical <- inputs
  for (nm in names(typed)) {
    alias <- .wb_op_input_alias(nm)
    aliases <- c(alias, paste0(nm, "_ref"), if (!is.null(alias)) paste0(alias, "_ref") else NULL)
    supplied <- c(nm, aliases)[vapply(c(nm, aliases), function(x) !is.null(inputs[[x]]), logical(1))]
    .wb_assert(length(supplied) <= 1L, paste0("Input '", nm, "' was supplied more than once via aliases: ", paste(supplied, collapse = ", "), "."))
    if (length(supplied)) {
      canonical[[nm]] <- .wb_validate_typed_input_value(inputs[[supplied]], nm, typed[[nm]])
      for (old in setdiff(supplied, nm)) canonical[[old]] <- NULL
    }
  }

  required <- names(op$requires %||% list())
  if (length(required)) for (nm in required) {
    present <- !is.null(canonical[[nm]]) || (!is.null(session) && .wb_optional_input_present(session, nm, canonical))
    .wb_assert(present, paste0("Missing required input '", nm, "' for op '", op_name, "'."))
  }

  params <- .wb_op_param_records(op_name)
  canonical_params <- list()
  for (nm in names(params)) {
    p <- params[[nm]]
    supplied <- nm %in% names(canonical) && !is.null(canonical[[nm]])
    if (!supplied && isTRUE(p$required)) stop("Missing required parameter '", nm, "' for op '", op_name, "'.", call. = FALSE)
    if (!supplied && "default" %in% names(p) && !is.null(p$default)) {
      canonical[[nm]] <- .wb_validate_param_value(p$default, p, op_name)
      canonical_params[[nm]] <- canonical[[nm]]
    } else if (supplied) {
      canonical[[nm]] <- .wb_validate_param_value(canonical[[nm]], p, op_name)
      canonical_params[[nm]] <- canonical[[nm]]
    } else {
      canonical[[nm]] <- NULL
    }
  }

  for (nm in names(.wb_op_engine_input_specs())) {
    if (nm %in% names(params)) next
    p <- .wb_op_engine_input_specs()[[nm]]
    if (is.null(canonical[[nm]])) {
      canonical[[nm]] <- if (!is.null(p$default)) .wb_validate_param_value(p$default, p, op_name) else NULL
    } else {
      canonical[[nm]] <- .wb_validate_param_value(canonical[[nm]], p, op_name)
    }
  }

  list(inputs = canonical, params = canonical_params)
}

.wb_validate_resolved_op_inputs <- function(op_name, resolved) {
  op <- .wb_op(op_name)
  declared <- c(op$requires %||% list(), op$optional_requires %||% list())
  .wb_assert(!anyDuplicated(names(resolved)), paste0("Op '", op_name, "' resolved duplicate input names."))
  .wb_assert(all(names(resolved) %in% names(declared)), paste0("Op '", op_name, "' resolved undeclared typed inputs."))
  for (nm in names(op$requires %||% list())) .wb_assert(nm %in% names(resolved), paste0("Op '", op_name, "' did not resolve required input '", nm, "'."))
  for (nm in names(resolved)) .wb_assert_kind(resolved[[nm]], declared[[nm]], where = paste0(" for resolved input '", nm, "'"))
  invisible(TRUE)
}

.wb_validate_op_outputs <- function(op_name, outputs) {
  declared <- .wb_op(op_name)$produces %||% list()
  .wb_assert(is.list(outputs) && !is.null(names(outputs)), paste0("Op '", op_name, "' outputs must be a named list."))
  .wb_assert(
    identical(sort(names(outputs)), sort(names(declared))) && length(outputs) == length(declared) && !anyDuplicated(names(outputs)),
    paste0(
      "Op '", op_name, "' output cardinality mismatch: declared [",
      paste(names(declared), collapse = ", "), "] but returned [",
      paste(names(outputs), collapse = ", "), "]."
    )
  )
  for (nm in names(declared)) .wb_assert_kind(outputs[[nm]], declared[[nm]], where = paste0(" for output '", nm, "'"))
  invisible(TRUE)
}

.wb_merge_validated_run_params <- function(runner_params, validated_params) {
  out <- runner_params %||% list()
  .wb_assert(is.list(out), "Runner params must be a list.")
  for (nm in names(validated_params %||% list())) out[[nm]] <- validated_params[[nm]]
  out
}
