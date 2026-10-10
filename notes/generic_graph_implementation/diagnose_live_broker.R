library(scworkbench)
capture_graph_broker <- function() {
  frames <- sys.frames()
  for (frame in frames) {
    if (!exists("stage", frame, inherits = FALSE)) next
    stage <- get("stage", frame)
    if (!is.character(stage) || length(stage) != 1L || !dir.exists(stage)) next
    request_path <- file.path(stage, "request.json")
    if (!file.exists(request_path)) next
    request <- jsonlite::read_json(request_path, simplifyVector = FALSE)
    cat("FAILING_REQUEST\n")
    print(request$operation)
    print(request$operation_id)
    for (filename in c("broker-error.json", "receipt.json")) {
      path <- file.path(stage, filename)
      if (!file.exists(path)) next
      record <- jsonlite::read_json(path, simplifyVector = FALSE)
      cat("DIAGNOSTIC", filename, "\n")
      print(record$error %||% record)
    }
    if (exists("broker", frame, inherits = FALSE)) {
      broker <- get("broker", frame)
      cat("BROKER_STDERR\n")
      print(tryCatch(broker$read_all_error_lines(), error = conditionMessage))
    }
    if (exists("python_stderr", frame, inherits = FALSE)) {
      cat("PYTHON_STDERR\n")
      print(get("python_stderr", frame))
    }
  }
}
`%||%` <- function(x, y) if (is.null(x)) y else x
trace(".wb_operation_pack_v2_error", tracer = quote(capture_graph_broker()),
  where = asNamespace("scworkbench"), print = FALSE)
source("tests/test_graph_abi4_python_live_contract.R")
stopifnot(test_graph_abi4_python_live_broker_contract())
