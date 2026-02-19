# Canonical op execution contract lives in .wb_ops() (session_context.R),
# derived from .wb_op_catalog() (op_catalog.R).

#' @keywords internal
.wb_get_op <- function(op_name) {
  .wb_op(op_name)
}


#' List ops with titles/intents
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
