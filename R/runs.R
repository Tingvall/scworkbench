# Ephemeral run object (lives in client session)
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

wb_is_run <- function(x) inherits(x, "wb_run")
