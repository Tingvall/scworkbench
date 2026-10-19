# Literal pre-change helper, not a reconstruction of the candidate fast path.
.space_row_old53 <- function(values, cells) {
  values <- .wb_operation_pack_v3_space_matrix(values)
  .wb_operation_pack_v2_identity_plain(
    "scworkbench.operation_pack.space_slice.content.v1", list(
      schema = "scworkbench.operation_pack.space_slice.content.v1",
      dimensions = unname(as.list(as.integer(dim(values)))),
      cell_id = unname(as.list(as.character(cells))),
      values = lapply(seq_len(nrow(values)), function(i)
        unname(as.list(as.numeric(values[i, ]))))))
}
.space_row_capture <- function(fun, values, cells) {
  ns <- asNamespace("digest"); original <- get("digest", ns)
  observed <- new.env(parent = emptyenv()); observed$bytes <- list()
  wrapper <- function(object, ...) {
    dots <- list(...)
    if (is.character(object) && length(object) == 1L && identical(dots$serialize, FALSE))
      observed$bytes[[length(observed$bytes) + 1L]] <- charToRaw(enc2utf8(object))
    original(object, ...)
  }
  unlockBinding("digest", ns); assign("digest", wrapper, ns); lockBinding("digest", ns)
  on.exit({unlockBinding("digest", ns); assign("digest", original, ns); lockBinding("digest", ns)}, add = TRUE)
  warnings <- character()
  answer <- tryCatch(withCallingHandlers(fun(values, cells), warning = function(w) {
    warnings <<- c(warnings, conditionMessage(w)); invokeRestart("muffleWarning")
  }), error = function(e) list(error = conditionMessage(e), classes = class(e)))
  list(answer = answer, bytes = observed$bytes, warnings = warnings)
}
.space_row_compare <- function(values, cells) {
  old <- .space_row_old53; environment(old) <- asNamespace("scworkbench")
  expected <- .space_row_capture(old, values, cells)
  actual <- .space_row_capture(scworkbench:::.wb_operation_pack_v3_space_content, values, cells)
  stopifnot(identical(actual, expected))
  if (is.null(expected$answer$error)) {
    env <- new.env(parent = asNamespace("scworkbench"))
    sys.source("tests/fixtures/engine_canonical_repaired_oracle.R", env)
    v <- scworkbench:::.wb_operation_pack_v3_space_matrix(values)
    preimage <- list(schema = "scworkbench.operation_pack.space_slice.content.v1",
      dimensions = unname(as.list(as.integer(dim(v)))),
      cell_id = unname(as.list(as.character(cells))),
      values = lapply(seq_len(nrow(v)), function(i) unname(as.list(as.numeric(v[i, ])))))
    bytes <- charToRaw(env$.engine_canonical_repaired_oracle(preimage))
    stopifnot(length(actual$bytes) == 1L, identical(actual$bytes[[1L]], bytes))
  }
  invisible(actual)
}
.space_row_fallback_calls <- function(values, cells) {
  ns <- asNamespace("scworkbench"); original <- get(".wb_operation_pack_v2_identity_plain", ns)
  calls <- 0L
  wrapper <- function(...) {calls <<- calls + 1L; original(...)}
  unlockBinding(".wb_operation_pack_v2_identity_plain", ns)
  assign(".wb_operation_pack_v2_identity_plain", wrapper, ns)
  lockBinding(".wb_operation_pack_v2_identity_plain", ns)
  on.exit({unlockBinding(".wb_operation_pack_v2_identity_plain", ns)
    assign(".wb_operation_pack_v2_identity_plain", original, ns)
    lockBinding(".wb_operation_pack_v2_identity_plain", ns)}, add = TRUE)
  invisible(scworkbench:::.wb_operation_pack_v3_space_content(values, cells))
  calls
}

test_engine_space_row_exact_preimages_shapes_axes_and_native_use_contract <- function() {
  cases <- list(matrix(1:15, 3L), matrix(c(-0, NA, NaN, 1/3, -1e-307, 1e308), 2L),
    matrix(17, 1L, 1L), matrix(numeric(), 0L, 3L), matrix(numeric(), 3L, 0L),
    matrix(numeric(), 0L, 0L), matrix(1:7, 1L), matrix(1:7, 7L))
  for (values in cases) {
    cells <- if (nrow(values)) paste0('cell_"雪\\', rev(seq_len(nrow(values)))) else character()
    rownames(values) <- if (nrow(values)) paste0("unrelated", seq_len(nrow(values))) else character()
    .space_row_compare(values, cells)
  }
  for (cells in list(c("same", "same", ""), c(NA, "null", "NA"), "different_length",
      setNames(c("c3", "c1", "c2"), c("a", "b", "c"))))
    .space_row_compare(matrix(1:6, 3L), cells)
  stopifnot(.space_row_fallback_calls(matrix(1:6, 3L), c("c3", "c1", "c2")) == 0L)
  TRUE
}

test_engine_space_row_coercion_classes_and_errors_contract <- function() {
  ordinary <- matrix(1:6, 3L)
  attributed <- ordinary; attr(attributed, "unused") <- list(label = "not identity-bearing")
  classed <- ordinary; class(classed) <- c("space_contract_matrix", "matrix", "array")
  cases <- list(ordinary > 2, matrix(c("1", "bad", "3", "4"), 2L),
    matrix(1:4 + 1i, 2L), matrix(as.list(1:4), 2L), classed, attributed,
    as.data.frame(ordinary), matrix(c(Inf, -Inf, 1e-308, -1e-308), 2L))
  for (values in cases) suppressWarnings(.space_row_compare(values, paste0("c", seq_len(nrow(values)))))
  bad <- rawToChar(as.raw(255L)); Encoding(bad) <- "bytes"
  .space_row_compare(matrix(1:4, 2L), c(bad, "c2"))
  # Old coercion warnings precede invalid-cell canonical errors; do not lose them.
  .space_row_compare(matrix(c("bad", "1", "2", "3"), 2L), c(bad, "c2"))
  .space_row_compare(list(not = "matrix"), "c1")
  stopifnot(.space_row_fallback_calls(classed, c("c3", "c1", "c2")) == 1L,
    .space_row_fallback_calls(ordinary > 2, c("c3", "c1", "c2")) == 1L)
  TRUE
}

test_engine_space_row_memory_locale_and_missing_native_fallback_contract <- function() {
  saved <- options(); on.exit(options(saved), add = TRUE)
  values <- matrix(seq_len(40L), 10L); cells <- paste0("c", 1:10)
  for (guard in list(.001, NA_real_, Inf, "unknown", list(1), structure(256, class = "guard"))) {
    options(scworkbench.max_dense_materialize_mb = guard)
    .space_row_compare(values, cells)
    stopifnot(.space_row_fallback_calls(values, cells) == 1L)
  }
  options(scworkbench.max_dense_materialize_mb = 256, OutDec = ",")
  .space_row_compare(values, cells)
  stopifnot(.space_row_fallback_calls(values, cells) == 1L)
  options(OutDec = ".")
  # Use the actual installed function body; only capability absence is simulated.
  fun <- scworkbench:::.wb_operation_pack_v3_space_content
  env <- new.env(parent = environment(fun)); env$exists <- function(x, ...) {
    if (identical(x, "C_scwb_canonical_numeric_array")) FALSE else base::exists(x, ...)
  }
  environment(fun) <- env
  old <- .space_row_old53; environment(old) <- asNamespace("scworkbench")
  stopifnot(identical(.space_row_capture(fun, values, cells), .space_row_capture(old, values, cells)))
  TRUE
}

test_engine_space_row_native_and_memory_cap_boundaries_contract <- function() {
  for (n in c(1L, 130000L, 131072L, 131073L)) {
    values <- matrix(as.double(seq_len(n)) / 13, 1L)
    .space_row_compare(values, "cell_1")
  }
  # Native cap and conservative combined-memory admission are independent.
  stopifnot(.space_row_fallback_calls(matrix(rep(1, 131073L), 1L), "c") == 1L,
    .space_row_fallback_calls(matrix(rep(1, 131072L), 1L), "c") == 1L)
  TRUE
}

test_engine_space_row_payload_and_axis_mutations_change_identity_contract <- function() {
  values <- matrix(seq_len(12L) / 13, 3L); cells <- c("c3", "c1", "c2")
  original <- scworkbench:::.wb_operation_pack_v3_space_content(values, cells)
  changed <- values; changed[2L, 3L] <- changed[2L, 3L] + 1
  for (pair in list(list(changed, cells), list(values[3:1, , drop = FALSE], cells[3:1]),
      list(values, rev(cells)), list(values[, 4:1, drop = FALSE], cells))) {
    .space_row_compare(pair[[1L]], pair[[2L]])
    stopifnot(!identical(original,
      scworkbench:::.wb_operation_pack_v3_space_content(pair[[1L]], pair[[2L]])))
  }
  TRUE
}
