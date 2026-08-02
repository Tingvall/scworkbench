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

.wb_runner_input_fields <- function(fn) {
  found <- character(0)
  walk <- function(x) {
    if (!is.call(x)) return(invisible(NULL))
    if (identical(x[[1]], as.name("$")) && identical(x[[2]], as.name("inputs")) && is.symbol(x[[3]])) {
      found <<- c(found, as.character(x[[3]]))
    }
    if (identical(x[[1]], as.name("[[")) && identical(x[[2]], as.name("inputs")) &&
        length(x) >= 3L && is.character(x[[3]]) && length(x[[3]]) == 1L) {
      found <<- c(found, as.character(x[[3]]))
    }
    lapply(as.list(x), walk)
    invisible(NULL)
  }
  walk(body(fn))
  unique(found)
}

#' @keywords internal
.wb_validate_op_dispatch_registry <- function() {
  ops <- .wb_ops()
  for (op_name in names(ops)) {
    fn <- ops[[op_name]]$runner
    .wb_assert(is.function(fn), paste0("Runner for op '", op_name, "' is not a function"))
    fml <- names(formals(fn))
    expected_formals <- c("bundle", "resolved", "effective_cells", "inputs", "...")
    .wb_assert(identical(fml, expected_formals),
               paste0("Runner for op '", op_name, "' signature drift: expected ", paste(expected_formals, collapse = ", "),
                      "; found ", paste(fml, collapse = ", "), "."))
    used <- .wb_runner_input_fields(fn)
    undeclared <- setdiff(used, .wb_op_allowed_input_names(op_name))
    .wb_assert(!length(undeclared),
               paste0("Runner for op '", op_name, "' reads undeclared inputs: ", paste(undeclared, collapse = ", "), "."))
  }
  invisible(TRUE)
}
