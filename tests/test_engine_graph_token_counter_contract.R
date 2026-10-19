# Literal df8db854cbc0311a5f8e809a88993c758887ca7d token hash; symbol only renamed.
.engine_token_old_df8 <- function(emitter, budgets, scratch_path = NULL) {
  token_file <- tempfile("scwb_graph_identity_")
  on.exit(if (file.exists(token_file)) unlink(token_file), add = TRUE)
  sink <- file(token_file, "wb"); count <- bit64::as.integer64(0)
  observed <- bit64::as.integer64(0)
  emit <- function(value) {
    bytes <- charToRaw(enc2utf8(value))
    count <<- count + bit64::as.integer64(length(bytes))
    .wb_graph_require(!is.na(count) && count <= .wb_graph_i64(budgets$token_bytes),
      "GRAPH_RESOURCE_EXCEEDED", "Identity token spill budget exceeded.")
    writeBin(bytes, sink)
    if (count - observed >= min(1048576, as.numeric(budgets$token_bytes))) {
      flush(sink); .wb_graph_spill_admit(budgets, scratch_path)
      observed <<- count
    }
  }
  tryCatch({emitter(emit); flush(sink); .wb_graph_spill_admit(budgets, scratch_path)},
    finally = close(sink))
  input <- file(token_file, "rb")
  tryCatch(unclass(as.character(openssl::sha256(input))), finally = close(input))
}
.engine_token_policy <- function(quota = "1048576") {
  p <- scworkbench:::.wb_graph_budgets(list(memory_bytes = "8388608", sqlite_cache_kib = 128L,
    partition_bytes = 65536L, partition_rows = 128L, collect_bytes = 1048576L))
  p$token_bytes <- quota; p
}
.engine_token_run <- function(emitter, policy, old = FALSE, fault = NULL, scratch = NULL) {
  ns <- asNamespace("scworkbench"); i64_calls <- 0L; admissions <- 0L
  original_i64 <- get(".wb_graph_i64", ns); original_admit <- get(".wb_graph_spill_admit", ns)
  scope <- new.env(parent = ns)
  scope$.wb_graph_i64 <- function(value) {i64_calls <<- i64_calls + 1L; original_i64(value)}
  scope$.wb_graph_spill_admit <- function(budgets, scratch_path = NULL) {
    admissions <<- admissions + 1L
    if (!is.null(fault)) fault(admissions, scratch_path)
    original_admit(budgets, scratch_path) # Actual authority/resource guard, never TRUE stub.
  }
  fun <- if (old) .engine_token_old_df8 else get(".wb_graph_token_hash", ns)
  environment(fun) <- scope
  files <- function() sort(list.files(tempdir(), pattern = "^scwb_graph_(identity|tokens)_", full.names = TRUE))
  before <- files(); fd <- if (dir.exists("/proc/self/fd")) length(list.files("/proc/self/fd")) else NULL
  warnings <- character()
  value <- tryCatch(withCallingHandlers(fun(emitter, policy, scratch), warning = function(warning) {
    warnings <<- c(warnings, conditionMessage(warning)); invokeRestart("muffleWarning")
  }), error = identity)
  stopifnot(identical(before, files()), is.null(fd) || length(list.files("/proc/self/fd")) == fd)
  list(value = if (inherits(value, "error")) conditionMessage(value) else value,
    error = inherits(value, "error"), i64_calls = i64_calls,
    admissions = admissions, warnings = warnings)
}
.engine_token_compare <- function(emitter_factory, quota, ...) {
  old <- .engine_token_run(emitter_factory(), .engine_token_policy(quota), old = TRUE, ...)
  new <- .engine_token_run(emitter_factory(), .engine_token_policy(quota), ...)
  stopifnot(identical(old[c("value", "error", "admissions", "warnings")],
    new[c("value", "error", "admissions", "warnings")]))
  invisible(list(old = old, new = new))
}

test_engine_graph_token_counter_bytes_quotas_and_error_order_contract <- function() {
  for (tokens in list(character(), "", c("", ""), "a", c("[", '"雪"', ",", '"é"', "]"),
      c("quote\"", "slash\\", "line\n", "\r", ""))) {
    bytes <- charToRaw(enc2utf8(paste(tokens, collapse = "")))
    factory <- local({x <- tokens; function() function(emit) for (value in x) emit(value)})
    for (quota in unique(as.character(c(length(bytes), max(0, length(bytes) - 1L), length(bytes) + 1L)))) {
      result <- .engine_token_compare(factory, quota)
      if (!result$new$error) stopifnot(identical(result$new$value,
        digest::digest(bytes, algo = "sha256", serialize = FALSE)))
    }
  }
  for (old in c(TRUE, FALSE)) {
    reads <- 0L; p <- list2env(.engine_token_policy(), parent = emptyenv()); rm("token_bytes", envir = p)
    makeActiveBinding("token_bytes", function(value) {reads <<- reads + 1L; stop("QUOTA_FORCED")}, p)
    # Invalid bytes must fail before quota access, as in the exact old helper.
    result <- .engine_token_run(function(emit) emit(list("invalid")), p, old)
    stopifnot(result$error, reads == 0L)
    # Empty emitter still reaches real final admission, which may read policy.
    result <- .engine_token_run(function(emit) stop("EMITTER_FIRST"), p, old)
    stopifnot(result$error, identical(result$value, "EMITTER_FIRST"), reads == 0L)
  }
  TRUE
}

test_engine_graph_token_counter_caught_failure_state_contract <- function() {
  for (quota in c("0", "1", "3")) {
    traces <- list()
    for (old in c(TRUE, FALSE)) {
      events <- character()
      result <- .engine_token_run(function(emit) {
        for (value in c("a", "LONG_OVER_LIMIT", "", "b", "")) {
          error <- tryCatch({emit(value); NULL}, error = identity)
          events <<- c(events, if (is.null(error)) "ok" else conditionMessage(error))
        }
      }, .engine_token_policy(quota), old)
      traces[[if (old) "old" else "new"]] <- list(result = result[c("value", "error", "admissions", "warnings")], events = events)
    }
    stopifnot(identical(traces$old, traces$new))
  }
  TRUE
}

test_engine_graph_token_counter_spill_fault_growth_and_cleanup_contract <- function() {
  # Quota-sized first write triggers an actual flush/admission. Catching its
  # injected failure does not advance observed; empty/short retry must re-admit.
  for (old in c(TRUE, FALSE)) {
    events <- character(); injected <- FALSE
    result <- .engine_token_run(function(emit) {
      for (value in c("abcd", "", "")) {
        error <- tryCatch({emit(value); NULL}, error = identity)
        events <<- c(events, if (is.null(error)) "ok" else conditionMessage(error))
      }
    }, .engine_token_policy("4"), old, fault = function(call, path) {
      if (!injected) {injected <<- TRUE; stop("SPILL_INJECTED_AFTER_WRITE")}
    })
    stopifnot(!result$error, identical(events, c("SPILL_INJECTED_AFTER_WRITE", "ok", "ok")), result$admissions == 3L)
  }
  scratch <- tempfile("token_growth_"); writeBin(raw(1L), scratch)
  on.exit(unlink(scratch), add = TRUE)
  records <- list()
  for (old in c(TRUE, FALSE)) {
    writeBin(raw(1L), scratch)
    records[[if (old) "old" else "new"]] <- .engine_token_run(function(emit) {
      emit("a"); writeBin(raw(17L), scratch); emit("")
    }, .engine_token_policy("8"), old, scratch = scratch)
  }
  stopifnot(records$old$error, records$new$error,
    grepl("GRAPH_RESOURCE_EXCEEDED", records$new$value, fixed = TRUE),
    identical(records$old[c("value", "error", "admissions", "warnings")], records$new[c("value", "error", "admissions", "warnings")]))
  TRUE
}

test_engine_graph_token_counter_fallback_carriers_and_side_effects_contract <- function() {
  factory <- function(type, effects) {
    p <- .engine_token_policy()
    if (type == "attributed_quota") attr(p$token_bytes, "extra") <- TRUE
    if (type == "S3_policy") class(p) <- "engine_unknown_token_policy"
    if (type == "attributed_policy") attr(p, "extra") <- TRUE
    if (type == "environment") {
      p <- list2env(p, parent = emptyenv()); rm("token_bytes", envir = p)
      makeActiveBinding("token_bytes", function(value) {effects$reads <- effects$reads + 1L; "1048576"}, p)
    }
    p
  }
  for (type in c("attributed_quota", "S3_policy", "attributed_policy", "environment")) {
    records <- list()
    for (old in c(TRUE, FALSE)) {
      effects <- new.env(parent = emptyenv()); effects$reads <- 0L
      value <- .engine_token_run(function(emit) for (x in c("a", "", "雪", "z")) emit(x), factory(type, effects), old)
      records[[if (old) "old" else "new"]] <- c(value, list(reads = effects$reads))
    }
    stopifnot(identical(records$old, records$new), records$new$i64_calls == 4L)
  }
  TRUE
}

test_engine_graph_token_counter_int64_limits_and_arithmetic_oracle_contract <- function() {
  for (quota in c("9007199254740990", "9007199254740991", "9007199254740992", "9223372036854775807")) {
    result <- .engine_token_compare(function() function(emit) for (x in c("", "a", "雪", "")) emit(x), quota)
    stopifnot(!result$new$error, !length(result$new$warnings), result$new$i64_calls == 1L)
  }
  # Independent cutoff arithmetic oracle only: no actual petabyte allocation,
  # real stream crossing2^53 or int64-overflow execution is claimed here.
  cutoff <- 9007199254740991
  for (start in c(cutoff - 1, cutoff, cutoff + 1)) for (increment in c(0, 1, 2, 2147483647)) {
    exact <- bit64::as.integer64(format(start, digits = 22, scientific = FALSE, trim = TRUE)) + bit64::as.integer64(increment)
    accepted <- increment <= cutoff - start
    if (accepted) stopifnot(identical(bit64::as.integer64(start + increment), exact)) else
      stopifnot(exact > bit64::as.integer64("9007199254740991"))
  }
  TRUE
}

test_engine_graph_token_counter_actual_i64_and_integer64_add_calls_contract <- function() {
  # Temporary S3 method instrumentation, restored before leaving the test.
  original <- getS3method("+", "integer64"); additions <- 0L
  registerS3method("+", "integer64", function(e1, e2) {
    additions <<- additions + 1L; original(e1, e2)
  }, envir = asNamespace("base"))
  on.exit(registerS3method("+", "integer64", original, envir = asNamespace("base")), add = TRUE)
  emitter <- function(emit) for (x in c("a", "", "b", "c", "", "d")) emit(x)
  additions <- 0L; old <- .engine_token_run(emitter, .engine_token_policy(), old = TRUE); old_additions <- additions
  additions <- 0L; new <- .engine_token_run(emitter, .engine_token_policy()); new_additions <- additions
  stopifnot(identical(old$value, new$value), old$i64_calls == 6L, new$i64_calls == 1L,
    old_additions == 6L, new_additions == 1L)
  p <- .engine_token_policy(); attr(p, "extra") <- TRUE
  additions <- 0L; fallback <- .engine_token_run(emitter, p)
  stopifnot(fallback$i64_calls == 6L, additions == 6L)
  additions <- 0L; huge <- .engine_token_run(emitter, .engine_token_policy("9223372036854775807"))
  stopifnot(huge$i64_calls == 1L, additions == 6L, !length(huge$warnings))
  TRUE
}
