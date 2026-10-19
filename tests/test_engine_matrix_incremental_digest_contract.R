.matrix_digest_helper <- function(name) get(name, asNamespace("scworkbench"))
.matrix_digest_call <- function(name, ...) .Call(.matrix_digest_helper(paste0("C_scwb_matrix_digest_", name)), ...)
.matrix_digest_error <- function(code) inherits(tryCatch(force(code), error = identity), "error")
.matrix_digest_fallback <- function() {
  fn <- .matrix_digest_helper(".wb_operation_pack_matrix_stream_identity")
  env <- new.env(parent = environment(fn))
  env$.wb_operation_pack_matrix_digest_open <- function() NULL
  environment(fn) <- env
  fn
}

test_engine_matrix_incremental_digest_exact_preimage_contract <- function() {
  source_helper <- .matrix_digest_helper(".wb_operation_pack_matrix_stream_identity")
  fallback <- .matrix_digest_fallback()
  matrices <- list(matrix(c(0, -0, NA, NaN, 1.25, -3, 1e-307, 1e308, pi,
    1234567890, 1e-9, 42), 3L), matrix(c(TRUE, FALSE, NA, TRUE), 2L),
    matrix(numeric(), 0L, 3L), matrix(numeric(), 3L, 0L), matrix(0, 2L, 2L))
  for (values in matrices) {
    features <- paste0("雪_feature_", seq_len(nrow(values)), "\\\"")
    cells <- paste0("cell_", rev(seq_len(ncol(values))), "\n")
    if (!nrow(values)) features <- character()
    if (!ncol(values)) cells <- character()
    expected <- fallback(features, cells, function(columns) values[, columns, drop = FALSE], 2L)
    for (size in c(1L, 2L, 128L)) {
      seen <- integer()
      actual <- source_helper(features, cells, function(columns) {
        stopifnot(length(columns) <= size)
        seen <<- c(seen, columns)
        values[, columns, drop = FALSE]
      }, size)
      stopifnot(identical(actual, expected), identical(seen, seq_len(ncol(values))))
    }
  }
  TRUE
}

test_engine_matrix_incremental_digest_lifecycle_contract <- function() {
  pointer <- .matrix_digest_helper(".wb_operation_pack_matrix_digest_open")()
  if (is.null(pointer)) return(TRUE) # Old path is the supported portable fallback.
  on.exit(.matrix_digest_call("close", pointer), add = TRUE)
  .matrix_digest_call("update", pointer, charToRaw("abc"))
  stopifnot(identical(.matrix_digest_call("finish", pointer),
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
    .matrix_digest_error(.matrix_digest_call("finish", pointer)),
    .matrix_digest_error(.matrix_digest_call("update", pointer, raw())),
    is.null(.matrix_digest_call("close", pointer)),
    is.null(.matrix_digest_call("open", "/nonexistent/scwb-openssl-provider.so")),
    is.null(.matrix_digest_call("open", "not-an-absolute-provider")))
  TRUE
}

test_engine_matrix_incremental_digest_error_cleanup_contract <- function() {
  original <- .matrix_digest_helper(".wb_operation_pack_matrix_digest_open")
  for (interrupt in c(FALSE, TRUE)) {
    fn <- .matrix_digest_helper(".wb_operation_pack_matrix_stream_identity")
    env <- new.env(parent = environment(fn)); pointer <- NULL
    env$.wb_operation_pack_matrix_digest_open <- function() {
      pointer <<- original()
      pointer
    }
    environment(fn) <- env
    calls <- 0L
    outcome <- tryCatch(fn("feature", c("c2", "c10"), function(columns) {
      calls <<- calls + 1L
      if (calls == 2L) {
        if (interrupt) stop(structure(list(message = "injected interrupt", call = NULL),
          class = c("interrupt", "condition")))
        stop("injected reader failure")
      }
      matrix(1, 1L, 1L)
    }, 1L), error = identity, interrupt = identity)
    stopifnot(inherits(outcome, if (interrupt) "interrupt" else "error"), calls == 2L)
    if (!is.null(pointer)) stopifnot(.matrix_digest_error(
      .matrix_digest_call("update", pointer, charToRaw("late"))))
  }
  TRUE
}

test_engine_matrix_incremental_digest_invalid_payload_contract <- function() {
  original <- .matrix_digest_helper(".wb_operation_pack_matrix_stream_identity")
  fallback <- .matrix_digest_fallback()
  for (values in list(matrix(Inf, 1L), matrix(-Inf, 1L), matrix(1, 2L))) {
    observe <- function(fn) tryCatch(fn("feature", "cell", function(columns) values, 1L), error = conditionMessage)
    stopifnot(identical(observe(original), observe(fallback)), is.character(observe(original)))
  }
  TRUE
}

test_engine_matrix_incremental_digest_bounded_native_append_contract <- function() {
  open <- .matrix_digest_helper(".wb_operation_pack_matrix_digest_open")
  pointer <- open()
  if (is.null(pointer)) return(TRUE)
  on.exit(.matrix_digest_call("close", pointer), add = TRUE)
  .matrix_digest_call("update", pointer, charToRaw("["))
  .Call(.matrix_digest_helper("C_scwb_matrix_slice_append"), pointer,
    c(2L, 10L), c(1L, 1L), c(1.25, -3), TRUE)
  .matrix_digest_call("update", pointer, charToRaw("]"))
  expected <- '[{"column":1e0,"row":2e0,"value":1.25e0},{"column":1e0,"row":1e1,"value":-3e0}]'
  stopifnot(identical(.matrix_digest_call("finish", pointer),
    unclass(as.character(openssl::sha256(charToRaw(expected))))))
  TRUE
}
