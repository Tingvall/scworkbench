# Ephemeral run object (lives in client session)
#' (Advanced) Create a New In-Session Run Object
#'
#' Intended for controlled client/integration construction. Use
#' [wb_session_run_op()] for ordinary operation execution.
#'
#' @param op_name Registered operation name.
#' @param inputs Named operation inputs.
#' @param params Named operation parameters.
#' @param outputs Named primitive outputs.
#' @param notes Optional run notes.
#' @return A `wb_run` object.
#' @export
wb_new_run <- function(op_name, inputs = list(), params = list(), outputs = list(), notes = NULL) {
  run <- list(
    run_id = paste0("run_", paste(sample(c(letters, 0:9), 12, TRUE), collapse = "")),
    op_name = op_name,
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    inputs = inputs,
    params = params,
    outputs = outputs,
    notes = notes
  )
  class(run) <- "wb_run"
  run
}

#' (Advanced) Check Whether an Object Is a wb_run
#'
#' @param x Object to test.
#' @return `TRUE` when `x` is a `wb_run`.
#' @export
wb_is_run <- function(x) inherits(x, "wb_run")
