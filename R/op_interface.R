# R/op_interface.R

.wb_op_interface_registry <- function() {
  cat <- .wb_operation_catalog()
  execution_ops <- .wb_ops()
  lapply(cat, function(x) {
    inputs <- x$inputs %||% list()
    declared_inputs <- c(x$requires %||% list(), x$optional_requires %||% list())
    coverage_modes <- x$coverage %||% list()
    for (nm in names(declared_inputs)) {
      item <- inputs[[nm]] %||% list()
      kind <- as.character(item$kind %||% declared_inputs[[nm]])[1]
      mode <- as.character(coverage_modes[[nm]] %||% "cell_indexed")[1]
      item$effective_cell_coverage <- if (identical(mode, "reference_only")) {
        "reference_only"
      } else if (identical(mode, "model_associated_unless_query_space")) {
        "model_associated_unless_query_space"
      } else if (kind %in% c("path_2d_family")) {
        "none"
      } else if (kind %in% c("feature_table", "obs_table")) {
        "cell_id_column_when_present"
      } else if (kind == "space_path_family") {
        "associated_space"
      } else {
        "cell_indexed"
      }
      inputs[[nm]] <- item
    }
    produces <- x$interface_produces %||% list()
    declared <- x$produces %||% list()
    terminals <- as.character(x$promotable %||% character(0))
    replay_equivalence <- execution_ops[[as.character(x$op_name)]]$replay_equivalence %||% list()
    for (nm in names(declared)) {
      item <- produces[[nm]] %||% list()
      item$output_name <- nm
      item$primitive_kind <- as.character(item$kind %||% declared[[nm]])[1]
      item$durability_role <- if (nm %in% terminals) "terminal_artifact" else "materialization"
      item$promotable_directly <- nm %in% terminals
      item$materialized_by_terminals <- if (nm %in% terminals) nm else terminals
      item$replay_equivalence <- as.character(replay_equivalence[[nm]] %||% "not_comparable")[1]
      produces[[nm]] <- item
    }
    params <- lapply(x$params %||% list(), function(p) {
      p$required <- isTRUE(p$required)
      p$nullable <- isTRUE(p$nullable) || ("default" %in% names(p) && is.null(p$default) && !isTRUE(p$required))
      p$allow_non_finite <- isTRUE(p$allow_non_finite)
      p$strict_integer <- as.character(p$type %||% "")[1] %in% c("int", "int_range", "int_vec")
      p$non_empty <- as.character(p$type %||% "")[1] %in% c(
        "string", "path", "cell_set", "choice", "string_vec", "string_array",
        "cell_ids", "string_vec_or_list", "cell_ids_or_set", "list_or_cell_set", "list"
      )
      p
    })
    rec <- list(
      op_name = as.character(x$op_name),
      title = as.character(x$title %||% ""),
      description = as.character(x$description %||% ""),
      intent = as.character(x$intent %||% character(0)),
      inputs = inputs,
      controls = .wb_op_engine_input_specs(),
      params = params,
      produces = produces,
      replay_equivalence = replay_equivalence,
      chunking = x$chunking %||% NULL
    )
    if (!is.null(x$source_pack)) rec$source_pack <- x$source_pack
    if (!is.null(x$definition_sha256)) rec$operation_definition_sha256 <- x$definition_sha256
    rec
  })
}


#' List available ops (UI/agent interface)
#'
#' @return Character vector of registered operation names. Use
#'   [wb_op_interface()] for typed inputs, parameters, and outputs.
#' @export
wb_list_ops <- function() {
  names(.wb_op_interface_registry())
}

#' High-level op interface spec (for UIs and agents)
#'
#' JSON-serializable description of inputs/params/outputs.
#' Dynamically injects cell_set choices based on bundle contents.
#'
#' @param op_name Operation name
#' @param bundle Optional scworkbench_bundle (needed for set:* choices)
#'
#' @return A JSON-serializable interface list containing title, intent, typed
#'   inputs, parameters, declared primitive outputs, and chunking metadata.
#' @export
wb_op_interface <- function(op_name, bundle = NULL) {
  op_name <- .wb_operation_name_resolve(op_name)
  operation_short_name <- sub("^.*::", "", op_name)
  reg <- .wb_op_interface_registry()

  if (!op_name %in% names(reg)) {
    stop("Unknown op: ", op_name, call. = FALSE)
  }

  spec <- reg[[op_name]]

  # ensure inputs list exists
  if (is.null(spec$inputs)) spec$inputs <- list()

  # ---- kill legacy umap_transform fields (old spec) ----
  if (identical(operation_short_name, "umap_transform")) {

    # If old input block exists, remove it (we use model_space_id instead)
    spec$inputs$model_space <- NULL
    # Hide optional manual override from default client interfaces.
    # Engine still supports override in runner for expert/internal use.
    spec$inputs$in_space_id <- NULL

    # If an old param named "model_space" exists, remove it
    if (!is.null(spec$params) && length(spec$params)) {
      keep <- vapply(spec$params, function(p) !identical(p$name, "model_space"), logical(1))
      spec$params <- spec$params[keep]
    }
  }


  # ---- inject / normalize cell_set ----
  if (is.null(spec$inputs$cell_set)) {
    spec$inputs$cell_set <- list()
  }

  # dynamic choices
  sets <- c("core", "all")
  if (!is.null(bundle)) {
    sets <- unique(c(sets, wb_cell_sets(bundle)))
  }

  spec$inputs$cell_set$type     <- "select"
  spec$inputs$cell_set$label    <- "Cell set"
  spec$inputs$cell_set$choices  <- sets

  # The executor default is part of the public contract.
  if (is.null(spec$inputs$cell_set$default)) {
    spec$inputs$cell_set$default <- .wb_op_engine_input_specs()$cell_set$default
  }
  spec$inputs$cell_set$value_type <- "cell_set"
  spec$inputs$cell_set$required <- FALSE
  spec$inputs$cell_set$non_empty <- TRUE

  # ---- op-specific dynamic inputs (bundle-aware) ----
  if (!is.null(bundle) && identical(operation_short_name, "umap_transform")) {

    # 1) model choices: spaces that have a stored model
    model_spaces <- character(0)
    if (.wb_table_exists(bundle$con, "space_models")) {
      model_spaces <- DBI::dbGetQuery(
        bundle$con,
        "SELECT space_id FROM space_models ORDER BY created_at DESC;"
      )$space_id
      model_spaces <- as.character(model_spaces)
    }

    if (is.null(spec$inputs$model)) spec$inputs$model <- list()
    spec$inputs$model$type     <- "select"
    spec$inputs$model$label    <- "Model"
    spec$inputs$model$required <- TRUE
    spec$inputs$model$choices  <- model_spaces

    if (is.null(spec$inputs$model$default)) {
      spec$inputs$model$default <- if (length(model_spaces)) model_spaces[1] else ""
    }
    if (!length(model_spaces) && is.null(spec$inputs$model$help)) {
      spec$inputs$model$help <- paste0(
        "No stored space models found in this bundle. Run ",
        "scwbrepresentation::umap_fit from an activated representation pack first."
      )
    }

  }

  spec
}



.wb_validate_op_interface <- function(spec) {
  .wb_assert(!is.null(spec$op_name) && nzchar(spec$op_name), "spec missing op_name")
  .wb_assert(is.list(spec$inputs), "spec$inputs must be a list")
  .wb_assert(is.list(spec$controls), "spec$controls must be a list")
  .wb_assert(is.list(spec$params), "spec$params must be a list")
  .wb_assert(is.list(spec$produces), "spec$produces must be a list")
  if (length(spec$params)) {
    param_names <- vapply(spec$params, function(p) as.character(p$name %||% "")[1], character(1))
    .wb_assert(all(nzchar(param_names)) && !anyDuplicated(param_names), "spec$params must have unique non-empty names")
    for (p in spec$params) {
      .wb_assert(nzchar(as.character(p$type %||% "")[1]), paste0("parameter '", p$name, "' missing type"))
      if (!is.null(p$choices)) .wb_assert(length(p$choices) > 0L && !anyNA(p$choices), paste0("parameter '", p$name, "' choices invalid"))
      if (!is.null(p$min) && !is.null(p$max)) .wb_assert(p$min <= p$max, paste0("parameter '", p$name, "' has min > max"))
    }
  }
  if (!is.null(spec$chunking)) {
    .wb_assert(is.list(spec$chunking), "spec$chunking must be NULL or a list")
    axis <- spec$chunking$axis %||% NULL
    if (!is.null(axis)) {
      .wb_assert(
        is.character(axis) && length(axis) == 1 && axis %in% c("cells", "features", "groups", "lineages"),
        "spec$chunking$axis must be one of: cells, features, groups, lineages"
      )
    }
  }
  invisible(TRUE)
}

#' @keywords internal
.wb_validate_op_interface_registry <- function() {
  reg <- .wb_op_interface_registry()
  .wb_assert(is.list(reg) && length(reg) > 0, "op interface registry is empty")
  for (nm in names(reg)) {
    spec <- reg[[nm]]
    .wb_validate_op_interface(spec)
    .wb_assert(identical(as.character(spec$op_name), as.character(nm)),
               paste0("op interface key/op_name mismatch: key='", nm, "', op_name='", spec$op_name, "'"))
    out <- spec$produces %||% list()
    if (length(out)) {
      .wb_assert(!is.null(names(out)) && all(nzchar(names(out))),
                 paste0("op interface '", nm, "' produces must be a named list"))
      for (onm in names(out)) {
        k <- out[[onm]]$kind %||% NA_character_
        .wb_assert(is.character(k) && length(k) == 1 && nzchar(k),
                   paste0("op interface '", nm, "' output '", onm, "' missing kind"))
      }
    }
  }
  invisible(TRUE)
}
