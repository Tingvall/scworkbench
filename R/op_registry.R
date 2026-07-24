# Canonical op execution contract lives in .wb_ops() (session_context.R),
# derived from .wb_op_catalog() (op_catalog.R).

#' @keywords internal
.wb_get_op <- function(op_name) {
  .wb_op(op_name)
}


#' List Operations With Titles and Intents
#'
#' @return Data frame with one row per registered operation and compact title,
#'   intent, and output-kind metadata.
#' @export
wb_ops <- function() {
  ops <- names(.wb_ops())
  rows <- lapply(ops, function(op) {
    spec <- try(wb_op_interface(op), silent = TRUE)
    if (inherits(spec, "try-error")) spec <- list()
    data.frame(
      op_name = op,
      title = spec$title %||% "",
      intent = paste(spec$intent %||% character(0), collapse = ","),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

.wb_op_catalog_semantic_clean <- function(x) {
  if (is.null(x)) return(NULL)
  if (is.data.frame(x)) return(lapply(seq_len(nrow(x)), function(i) .wb_op_catalog_semantic_clean(as.list(x[i, , drop = FALSE]))))
  if (is.list(x)) {
    out <- lapply(x, .wb_op_catalog_semantic_clean)
    return(out)
  }
  if (is.factor(x)) return(as.character(x))
  if (length(x) == 0L) return(list())
  if (length(x) == 1L && is.na(x)) return(NULL)
  x
}

.wb_op_catalog_infer_kind <- function(name, rec = list()) {
  nm <- as.character(name %||% "")[1]
  if (identical(nm, "cell_set")) return("select")
  if (grepl("matrix", nm, fixed = TRUE)) return("matrix")
  if (grepl("space", nm, fixed = TRUE)) return("space")
  if (grepl("model", nm, fixed = TRUE)) return("model_ref")
  if (grepl("signal", nm, fixed = TRUE)) return("cell_vector_family")
  if (grepl("vector", nm, fixed = TRUE)) return("cell_vector")
  if (grepl("path", nm, fixed = TRUE)) return("space_path_family")
  as.character(rec$type %||% "")[1]
}

.wb_op_catalog_field_summary <- function(x, include_description = FALSE, kind_fallback = list()) {
  if (!is.list(x) || !length(x)) return(list())
  out <- lapply(names(x), function(nm) {
    rec <- x[[nm]]
    kind <- as.character(rec$kind %||% kind_fallback[[nm]] %||% .wb_op_catalog_infer_kind(nm, rec))[1]
    desc <- as.character(rec$description %||% rec$help %||% "")[1]
    z <- list(name = nm)
    if (nzchar(kind)) z$kind <- kind
    if (!is.null(rec$required)) z$required <- isTRUE(rec$required)
    for (field in c("output_name", "primitive_kind", "durability_role", "promotable_directly", "materialized_by_terminals")) if (!is.null(rec[[field]])) z[[field]] <- rec[[field]]
    if (isTRUE(include_description) && nzchar(desc)) z$description <- desc
    z
  })
  names(out) <- NULL
  out
}

#' Export The Operation Catalog As Semantic Metadata
#'
#' Returns a structured, JSON-friendly description of all registered operations.
#' This is intended for agents, documentation generators, and semantic indexes.
#'
#' @param bundle Optional open `scworkbench_bundle`. When supplied, dynamic
#'   interface choices such as cell sets are included.
#' @return A named list with catalog metadata and one record per op.
#' @export
wb_op_catalog_semantic <- function(bundle = NULL) {
  op_names <- wb_list_ops()
  ops <- lapply(op_names, function(op_name) {
    iface <- wb_op_interface(op_name, bundle = bundle)
    exec <- .wb_get_op(op_name)
    requires <- exec$requires %||% list()
    consumes <- .wb_op_catalog_field_summary(iface$inputs %||% list(), include_description = TRUE, kind_fallback = requires)
    produces <- .wb_op_catalog_field_summary(iface$produces %||% list(), include_description = TRUE)
    list(
      op_name = as.character(iface$op_name %||% op_name)[1],
      title = as.character(iface$title %||% "")[1],
      description = as.character(iface$description %||% "")[1],
      intent = as.character(iface$intent %||% character(0)),
      consumes = consumes,
      produces = produces,
      inputs = iface$inputs %||% list(),
      params = iface$params %||% list(),
      promotable = as.character(exec$promotable %||% character(0)),
      chunking = iface$chunking %||% NULL
    )
  })
  names(ops) <- NULL
  .wb_op_catalog_semantic_clean(list(
    schema_version = "scworkbench.op_catalog.semantic.v1",
    generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    op_count = length(ops),
    ops = ops
  ))
}

.wb_op_catalog_reference_lines <- function(catalog) {
  ops <- catalog$ops %||% list()
  lines <- c(
    "# scworkbench Operation Catalog",
    "",
    "<!-- Generated from wb_op_catalog_semantic(); do not edit op entries by hand. -->",
    "",
    paste0("Generated at: ", as.character(catalog$generated_at %||% "")),
    "",
    paste0("Operation count: ", as.integer(catalog$op_count %||% length(ops))),
    "",
    "This document summarizes registered scworkbench ops for humans, agents, and semantic indexing.",
    "The machine-readable companion is `docs/op_catalog_semantic.json`.",
    ""
  )
  for (op in ops) {
    intent <- paste(as.character(op$intent %||% character(0)), collapse = ", ")
    consumes <- op$consumes %||% list()
    produces <- op$produces %||% list()
    params <- op$params %||% list()
    promotable <- paste(as.character(op$promotable %||% character(0)), collapse = ", ")
    lines <- c(
      lines,
      paste0("## `", as.character(op$op_name %||% "")[1], "`"),
      "",
      paste0("Title: ", as.character(op$title %||% "")[1]),
      "",
      paste0("Intent: ", if (nzchar(intent)) intent else "(none)"),
      "",
      paste0("Description: ", as.character(op$description %||% "")[1]),
      "",
      "Consumes:"
    )
    if (length(consumes)) {
      for (x in consumes) {
        desc <- as.character(x$description %||% "")[1]
        suffix <- if (nzchar(desc)) paste0(" - ", desc) else ""
        lines <- c(lines, paste0("- `", as.character(x$name %||% "")[1], "`: ", as.character(x$kind %||% "")[1], suffix))
      }
    } else {
      lines <- c(lines, "- (none)")
    }
    lines <- c(lines, "", "Produces:")
    if (length(produces)) {
      for (x in produces) {
        desc <- as.character(x$description %||% "")[1]
        suffix <- if (nzchar(desc)) paste0(" - ", desc) else ""
        lines <- c(lines, paste0("- `", as.character(x$name %||% "")[1], "`: ", as.character(x$kind %||% "")[1], suffix))
      }
    } else {
      lines <- c(lines, "- (none)")
    }
    lines <- c(lines, "", paste0("Promotable outputs: ", if (nzchar(promotable)) promotable else "(none)"), "", "Key parameters:")
    if (length(params)) {
      for (p in params) {
        nm <- as.character(p$name %||% "")[1]
        typ <- as.character(p$type %||% "")[1]
        default <- p$default %||% NULL
        default_txt <- if (is.null(default)) "NULL" else paste(as.character(default), collapse = "|")
        help <- as.character(p$help %||% "")[1]
        lines <- c(lines, paste0("- `", nm, "` (", typ, ", default=", default_txt, "): ", help))
      }
    } else {
      lines <- c(lines, "- (none)")
    }
    lines <- c(lines, "")
  }
  lines
}

#' Write Operation Catalog Reference Files
#'
#' Writes a human-readable markdown reference and/or machine-readable JSON
#' export from the canonical op catalog.
#'
#' @param path_md Markdown output path, or `NULL` to skip.
#' @param path_json JSON output path, or `NULL` to skip.
#' @param bundle Optional open `scworkbench_bundle`.
#' @return Invisibly returns the semantic catalog list.
#' @export
wb_write_op_catalog_reference <- function(path_md = "docs/op_catalog_reference.md",
                                          path_json = "docs/op_catalog_semantic.json",
                                          bundle = NULL) {
  catalog <- wb_op_catalog_semantic(bundle = bundle)
  if (!is.null(path_md)) {
    dir.create(dirname(path_md), recursive = TRUE, showWarnings = FALSE)
    writeLines(.wb_op_catalog_reference_lines(catalog), con = path_md, useBytes = TRUE)
  }
  if (!is.null(path_json)) {
    .wb_require_pkg("jsonlite", "op catalog semantic export")
    dir.create(dirname(path_json), recursive = TRUE, showWarnings = FALSE)
    jsonlite::write_json(catalog, path = path_json, auto_unbox = TRUE, pretty = TRUE, null = "null")
  }
  invisible(catalog)
}

#' @keywords internal
.wb_validate_op_contract_alignment <- function() {
  ops <- .wb_ops()
  ui_ops <- .wb_op_interface_registry()

  .wb_assert(setequal(names(ops), names(ui_ops)),
             paste0(
               "Execution ops and interface ops differ. exec-only: ",
               paste(setdiff(names(ops), names(ui_ops)), collapse = ", "),
               " ; interface-only: ",
               paste(setdiff(names(ui_ops), names(ops)), collapse = ", ")
             ))

  for (op_name in names(ops)) {
    op <- ops[[op_name]]
    spec <- ui_ops[[op_name]]
    out_exec <- op$produces %||% list()
    out_ui <- spec$produces %||% list()

    .wb_assert(setequal(names(out_exec), names(out_ui)),
               paste0("Output names mismatch for op '", op_name, "'"))

    for (nm in names(out_exec)) {
      k_exec <- as.character(out_exec[[nm]])
      k_ui <- as.character(out_ui[[nm]]$kind %||% "")
      .wb_assert(identical(k_exec, k_ui),
                 paste0("Output kind mismatch for op '", op_name, "' output '", nm, "': ", k_exec, " vs ", k_ui))
    }

    prom <- op$promotable %||% character(0)
    .wb_assert(all(prom %in% names(out_exec)),
               paste0("promotable outputs must be subset of produces for op '", op_name, "'"))
  }

  invisible(TRUE)
}

`%||%` <- function(x, y) if (is.null(x)) y else x
