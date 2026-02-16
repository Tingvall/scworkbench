.wb_op_dispatch_registry <- function() {
  ops <- .wb_ops()
  setNames(lapply(ops, function(op) op$runner), names(ops))
}

.wb_get_op_runner <- function(op_name) {
  op <- .wb_op(op_name)
  fn <- op$runner
  .wb_assert(is.function(fn), paste0("No runner registered for op: ", op_name))
  fn
}

#' @keywords internal
.wb_validate_op_dispatch_registry <- function() {
  ops <- .wb_ops()
  for (op_name in names(ops)) {
    fn <- ops[[op_name]]$runner
    .wb_assert(is.function(fn), paste0("Runner for op '", op_name, "' is not a function"))
    fml <- names(formals(fn))
    .wb_assert(all(c("bundle", "resolved", "effective_cells", "inputs") %in% fml),
               paste0("Runner for op '", op_name, "' missing required formals"))
  }
  invisible(TRUE)
}

