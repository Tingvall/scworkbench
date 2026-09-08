test_logged_release_gate_contract <- function() {
  root <- normalizePath(".", winslash = "/", mustWork = TRUE)
  helper <- file.path(root, "inst", "ci", "run_logged_gate")
  stopifnot(file.exists(helper))

  fixture <- tempfile("logged gate path with spaces ")
  dir.create(fixture, recursive = TRUE)
  on.exit(unlink(fixture, recursive = TRUE, force = TRUE), add = TRUE)

  invoke <- function(args, stdout = TRUE, stderr = TRUE) {
    result <- suppressWarnings(system2(
      helper,
      vapply(args, shQuote, character(1L)),
      stdout = stdout,
      stderr = stderr
    ))
    status <- attr(result, "status")
    if (is.null(status)) 0L else as.integer(status)
  }
  sidecar <- function(path) scan(path, what = integer(), quiet = TRUE)

  success_log <- file.path(fixture, "successful gate.log")
  success_exit <- file.path(fixture, "successful gate.exit")
  status <- invoke(c(success_log, success_exit, "--", "bash", "-c", "printf 'gate ok\\n'"))
  stopifnot(
    identical(status, 0L),
    identical(readLines(success_log, warn = FALSE), "gate ok"),
    identical(sidecar(success_exit), 0L)
  )

  failure_log <- file.path(fixture, "failed gate.log")
  failure_exit <- file.path(fixture, "failed gate.exit")
  status <- invoke(c(failure_log, failure_exit, "--", "bash", "-c", "printf 'gate failed\\n'; exit 7"))
  stopifnot(identical(status, 7L), identical(sidecar(failure_exit), 7L))
  diagnostic_status <- system2("bash", c("-c", shQuote("printf 'diagnostic ok\\n' >/dev/null")))
  stopifnot(identical(diagnostic_status, 0L), identical(sidecar(failure_exit), 7L))

  signal_log <- file.path(fixture, "signal.log")
  signal_exit <- file.path(fixture, "signal.exit")
  status <- invoke(c(signal_log, signal_exit, "--", "bash", "-c", "kill -TERM $$"))
  stopifnot(status >= 128L, identical(sidecar(signal_exit), status))

  preserved_log <- readBin(failure_log, "raw", n = file.info(failure_log)$size)
  preserved_exit <- readBin(failure_exit, "raw", n = file.info(failure_exit)$size)
  status <- invoke(c(failure_log, failure_exit, "--", "bash", "-c", "exit 0"))
  stopifnot(
    status != 0L,
    identical(readBin(failure_log, "raw", n = file.info(failure_log)$size), preserved_log),
    identical(readBin(failure_exit, "raw", n = file.info(failure_exit)$size), preserved_exit)
  )
  status <- invoke(c("--force", failure_log, failure_exit, "--", "bash", "-c", "printf 'replacement\\n'"))
  stopifnot(
    identical(status, 0L),
    identical(readLines(failure_log, warn = FALSE), "replacement"),
    identical(sidecar(failure_exit), 0L)
  )

  malformed <- list(
    character(),
    c(file.path(fixture, "missing-exit.log")),
    c(file.path(fixture, "missing-dash.log"), file.path(fixture, "missing-dash.exit"), "bash", "true"),
    c(file.path(fixture, "empty.log"), file.path(fixture, "empty.exit"), "--")
  )
  stopifnot(all(vapply(malformed, function(args) invoke(args) != 0L, logical(1))))

  helper_source <- paste(readLines(helper, warn = FALSE), collapse = "\n")
  stopifnot(
    grepl('"$@" 2>&1 | tee "$log_tmp"', helper_source, fixed = TRUE),
    grepl('ln -- "$exit_tmp" "$exit_path"', helper_source, fixed = TRUE),
    !grepl("(^|\\n)[[:space:]]*eval([[:space:]]|$)", helper_source)
  )
  TRUE
}
