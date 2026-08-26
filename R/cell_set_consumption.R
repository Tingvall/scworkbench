# Canonical typed provenance for durable named cell-set consumption.

.wb_cell_set_resolution_schema <- function() "scworkbench.cell_set_resolution.v1"

.wb_cell_set_membership_scheme <- function() {
  unname(.wb_content_identity_schemes()[["cell_set_membership"]])
}

.wb_cell_set_membership_identity <- function(cell_ids) {
  ids <- sort(unique(as.character(cell_ids %||% character(0))), method = "radix")
  ids <- ids[!is.na(ids) & nzchar(ids)]
  list(
    content_sha256 = .wb_prov_sha256_object(list(
      schema = .wb_cell_set_membership_scheme(),
      cell_ids = ids
    )),
    content_identity_scheme = .wb_cell_set_membership_scheme(),
    count = as.integer(length(ids))
  )
}

.wb_cell_set_resolution_abort <- function(code, message, ...) {
  fields <- list(...)
  cond <- structure(
    c(list(message = paste0(code, ": ", message), call = NULL, code = code), fields),
    class = c("wb_cell_set_resolution_error", "scworkbench_error", "error", "condition")
  )
  stop(cond)
}

.wb_named_cell_set_canonical_id <- function(bundle, token, required = FALSE,
                                             binding_name = "cell_set") {
  if (!is.character(token) || length(token) != 1L || is.na(token) || !nzchar(token)) {
    return(NULL)
  }
  token <- as.character(token)[1]
  if (identical(token, "all")) return(NULL)
  available <- as.character(wb_cell_sets(bundle))
  if (token %in% available) return(token)
  retained <- as.character(wb_cell_sets(bundle, include_history = TRUE))
  if (token %in% retained && .wb_table_exists(bundle$con, "entity_lifecycle")) {
    lifecycle <- wb_entity_lifecycle(bundle, "cell_set", token, include_history = TRUE)
    # Ephemeral registry state is intentionally executable: promotion of a run
    # that consumes/selects it is what turns it into a durable current claim.
    # Terminal history remains inspectable but is never silently reactivated.
    if (nrow(lifecycle) == 1L && identical(as.character(lifecycle$lifecycle_state[1]), "ephemeral")) {
      return(token)
    }
  }
  if (isTRUE(required) || startsWith(token, "set:") || identical(token, "core")) {
    .wb_cell_set_resolution_abort(
      "CELL_SET_RESOLUTION_MISSING",
      paste0("Named cell set '", token, "' for binding '", binding_name,
             "' is not a current durable membership-backed set."),
      binding_name = binding_name, cell_set = token
    )
  }
  NULL
}

.wb_named_cell_set_selectors <- function(bundle, op_name, inputs) {
  inputs <- inputs %||% list()
  out <- list()
  add <- function(binding_name, token, parameter_type, path = binding_name,
                  intersection = TRUE, required = FALSE) {
    id <- .wb_named_cell_set_canonical_id(
      bundle, token, required = required, binding_name = binding_name
    )
    if (is.null(id)) return(invisible(NULL))
    out[[length(out) + 1L]] <<- list(
      binding_name = as.character(binding_name)[1],
      binding_path = as.character(path)[1],
      parameter_type = as.character(parameter_type)[1],
      declared_value = as.character(token)[1],
      entity_id = id,
      intersection = isTRUE(intersection)
    )
    invisible(NULL)
  }

  # The common analysis universe is an engine input even when an operation
  # also declares a same-named catalog parameter.
  add("cell_set", inputs$cell_set %||% "all", "cell_set", "cell_set",
      intersection = TRUE, required = TRUE)

  catalog <- .wb_operation_catalog()
  params <- catalog[[as.character(op_name)[1]]]$params %||% list()
  descriptor_uses_cell_set <- function(value) {
    if (!is.list(value) || is.data.frame(value)) return(TRUE)
    !((!is.null(value$x) && !is.null(value$y)) ||
      !is.null(value$cells) || !is.null(value$cell_ids))
  }
  for (param in params) {
    name <- as.character(param$name %||% "")[1]
    type <- as.character(param$type %||% "")[1]
    if (!nzchar(name) || identical(name, "cell_set") ||
        !type %in% c("cell_set", "cell_ids_or_set", "list_or_cell_set")) next
    value <- inputs[[name]]
    if (is.null(value) || .wb_is_ref_run(value) || .wb_is_ref_artifact(value)) next
    if (identical(type, "cell_set")) {
      add(name, value, type, name, intersection = FALSE, required = TRUE)
    } else if (identical(type, "cell_ids_or_set")) {
      if (is.character(value) && length(value) == 1L) {
        add(name, value, type, name, intersection = TRUE, required = FALSE)
      }
    } else if (identical(type, "list_or_cell_set")) {
      if (is.character(value) && length(value) == 1L) {
        add(name, value, type, name, intersection = FALSE, required = FALSE)
      } else if (is.list(value) && !is.null(value$cell_set) &&
                 descriptor_uses_cell_set(value)) {
        add(name, value$cell_set, type, paste0(name, ".cell_set"),
            intersection = FALSE, required = TRUE)
      }
    }
  }
  # The trajectory endpoint runner gives explicit coordinate/cell descriptors
  # precedence over its start/end convenience set controls. Mirror that
  # operation contract here so ignored convenience values never become false
  # scientific dependencies.
  if (identical(as.character(op_name)[1], "trajectory_space_path_segment")) {
    suppress <- character(0)
    if (!is.null(inputs$start_cell_set)) suppress <- c(suppress, "start_endpoint")
    if (!is.null(inputs$end_cell_set)) suppress <- c(suppress, "end_endpoint")
    if (!is.null(inputs$start_endpoint) &&
        !descriptor_uses_cell_set(inputs$start_endpoint)) suppress <- c(suppress, "start_cell_set")
    if (!is.null(inputs$end_endpoint) &&
        !descriptor_uses_cell_set(inputs$end_endpoint)) suppress <- c(suppress, "end_cell_set")
    if (length(suppress)) {
      out <- out[!vapply(out, function(x) x$binding_name %in% suppress, logical(1))]
    }
  }
  out
}

.wb_named_cell_set_resolutions <- function(bundle, op_name, inputs,
                                            effective_cells) {
  selectors <- .wb_named_cell_set_selectors(bundle, op_name, inputs)
  if (!length(selectors)) return(list())
  effective_universe <- unique(as.character(effective_cells %||% character(0)))
  lapply(selectors, function(selector) {
    source_cells <- as.character(wb_cells(bundle, cell_set = selector$entity_id))
    effective <- if (isTRUE(selector$intersection)) {
      intersect(source_cells, effective_universe)
    } else source_cells
    source_identity <- .wb_cell_set_membership_identity(source_cells)
    effective_identity <- .wb_cell_set_membership_identity(effective)
    list(
      schema = .wb_cell_set_resolution_schema(),
      binding_name = selector$binding_name,
      binding_path = selector$binding_path,
      parameter_type = selector$parameter_type,
      declared_value = selector$declared_value,
      entity_kind = "cell_set",
      entity_id = selector$entity_id,
      relationship_type = "CONSUMES",
      resolution_policy = if (isTRUE(selector$intersection)) {
        "source_membership_intersect_operation_effective_cells"
      } else "source_membership",
      entity_content_sha256 = .wb_registry_entity_content_hash(
        bundle, "cell_set", selector$entity_id
      ),
      entity_content_identity_scheme = unname(.wb_content_identity_schemes()[["registry"]]),
      source_membership_sha256 = source_identity$content_sha256,
      source_membership_identity_scheme = source_identity$content_identity_scheme,
      source_member_count = source_identity$count,
      effective_membership_sha256 = effective_identity$content_sha256,
      effective_membership_identity_scheme = effective_identity$content_identity_scheme,
      effective_member_count = effective_identity$count
    )
  })
}

.wb_cell_set_resolution_records <- function(x) {
  records <- x %||% list()
  if (!is.list(records)) return(list())
  if (length(records) && !is.null(records$schema)) records <- list(records)
  records
}

.wb_verify_cell_set_resolution_records <- function(bundle, records,
                                                    context = "replay") {
  records <- .wb_cell_set_resolution_records(records)
  if (!length(records)) return(invisible(TRUE))
  for (record in records) {
    role <- as.character(record$binding_name %||% "")[1]
    id <- as.character(record$entity_id %||% "")[1]
    expected <- as.character(record$source_membership_sha256 %||% "")[1]
    expected_n <- suppressWarnings(as.integer(record$source_member_count %||% NA_integer_)[1])
    if (!identical(as.character(record$schema %||% "")[1], .wb_cell_set_resolution_schema()) ||
        !nzchar(role) || !nzchar(id) || !grepl("^[0-9a-f]{64}$", expected) ||
        is.na(expected_n) || expected_n < 0L) {
      .wb_cell_set_resolution_abort(
        "CELL_SET_RESOLUTION_RECORD_INVALID",
        paste0("Persisted named-set resolution for ", context, " is malformed."),
        binding_name = role, cell_set = id
      )
    }
    # Replay requires the exact set to be a current, selectable registry input.
    # Retained superseded memberships remain inspectable, but are not silently
    # reactivated as execution inputs.
    present <- id %in% as.character(wb_cell_sets(bundle))
    if (!present) {
      .wb_cell_set_resolution_abort(
        "CELL_SET_RESOLUTION_REQUIRED",
        paste0("Required historical cell set '", id, "' for binding '", role,
               "' is absent from the ", context, " bundle."),
        binding_name = role, cell_set = id
      )
    }
    observed <- .wb_cell_set_membership_identity(wb_cells(bundle, cell_set = id))
    if (!identical(tolower(expected), tolower(observed$content_sha256)) ||
        !identical(expected_n, observed$count)) {
      .wb_cell_set_resolution_abort(
        "CELL_SET_RESOLUTION_MISMATCH",
        paste0("Cell set '", id, "' for binding '", role,
               "' does not match the membership recorded by the historical run."),
        binding_name = role, cell_set = id,
        expected_sha256 = expected, observed_sha256 = observed$content_sha256,
        expected_count = expected_n, observed_count = observed$count
      )
    }
  }
  invisible(TRUE)
}
