# R/op_interface.R

.wb_op_interface_registry <- function() {
  cat <- .wb_op_catalog()
  lapply(cat, function(x) {
    list(
      op_name = as.character(x$op_name),
      title = as.character(x$title %||% ""),
      description = as.character(x$description %||% ""),
      intent = as.character(x$intent %||% character(0)),
      inputs = x$inputs %||% list(),
      params = x$params %||% list(),
      produces = x$interface_produces %||% list()
    )
  })
}


#' List available ops (UI/agent interface)
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
#' @export
wb_op_interface <- function(op_name, bundle = NULL) {
  op_name <- as.character(op_name)
  reg <- .wb_op_interface_registry()

  if (!op_name %in% names(reg)) {
    stop("Unknown op: ", op_name, call. = FALSE)
  }

  spec <- reg[[op_name]]

  # ensure inputs list exists
  if (is.null(spec$inputs)) spec$inputs <- list()

  # ---- kill legacy umap_transform fields (old spec) ----
  if (identical(op_name, "umap_transform")) {

    # If old input block exists, remove it (we use model_space_id instead)
    spec$inputs$model_space <- NULL

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

  # default varies by op (sensible semantics)
  if (is.null(spec$inputs$cell_set$default)) {
    spec$inputs$cell_set$default <- switch(
      op_name,
      umap_transform = "set:",
      "core"
    )
  }

  # ---- op-specific dynamic inputs (bundle-aware) ----
  if (!is.null(bundle) && identical(op_name, "umap_transform")) {

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
      spec$inputs$model$help <- "No stored space models found in this bundle. Run umap_fit first."
    }

    # 2) in_space_id choices: any space in bundle (high-D input space)
    sp <- wb_spaces(bundle)
    in_spaces <- as.character(sp$space_id)

    if (is.null(spec$inputs$in_space_id)) spec$inputs$in_space_id <- list()
    spec$inputs$in_space_id$type     <- "select"
    spec$inputs$in_space_id$label    <- "Input space (high-D space_id)"
    spec$inputs$in_space_id$required <- FALSE
    spec$inputs$in_space_id$choices  <- in_spaces

    if (is.null(spec$inputs$in_space_id$default)) {
      spec$inputs$in_space_id$default <- if ("lsi" %in% in_spaces) "lsi" else if (length(in_spaces)) in_spaces[1] else ""
    }
  }

  spec
}



.wb_validate_op_interface <- function(spec) {
  .wb_assert(!is.null(spec$op_name) && nzchar(spec$op_name), "spec missing op_name")
  .wb_assert(is.list(spec$inputs), "spec$inputs must be a list")
  .wb_assert(is.list(spec$params), "spec$params must be a list")
  .wb_assert(is.list(spec$produces), "spec$produces must be a list")
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
