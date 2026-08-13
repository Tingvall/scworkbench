# Administrative identifier allocation. This service is deliberately isolated
# from R's scientific RNG: it never reads, creates, advances, or restores
# .Random.seed.

.wb_identifier_state <- new.env(parent = emptyenv())
.wb_identifier_state$issued <- new.env(hash = TRUE, parent = emptyenv())

.wb_identifier_error <- function(code, message, purpose = NULL, attempts = NULL) {
  condition <- structure(
    list(
      message = paste0(code, ": ", message),
      call = NULL,
      code = code,
      purpose = purpose,
      attempts = attempts
    ),
    class = c("scworkbench_identifier_error", "error", "condition")
  )
  stop(condition)
}

.wb_secure_entropy <- function(n, purpose = "administrative identifier") {
  n <- as.integer(n)[1L]
  if (is.na(n) || n < 1L) {
    .wb_identifier_error("SCWORKBENCH_IDENTIFIER_ENTROPY_UNAVAILABLE",
                         "entropy byte count must be positive.", purpose)
  }

  # Narrow internal fault-injection seam. No production call accepts entropy.
  hook <- getOption("scworkbench.identifier_entropy_test_hook")
  if (!is.null(hook)) {
    if (!is.function(hook)) {
      .wb_identifier_error("SCWORKBENCH_IDENTIFIER_ENTROPY_UNAVAILABLE",
                           "the internal entropy test hook is invalid.", purpose)
    }
    value <- tryCatch(hook(n = n, purpose = purpose), error = identity)
    if (inherits(value, "error")) {
      .wb_identifier_error("SCWORKBENCH_IDENTIFIER_ENTROPY_UNAVAILABLE",
                           conditionMessage(value), purpose)
    }
    if (is.character(value) && length(value) == 1L && nzchar(value)) return(value)
    if (is.raw(value) && length(value) >= n) return(value[seq_len(n)])
    .wb_identifier_error("SCWORKBENCH_IDENTIFIER_ENTROPY_UNAVAILABLE",
                         "the internal entropy test hook returned invalid bytes.", purpose)
  }

  path <- if (file.exists("/dev/urandom")) "/dev/urandom" else ""
  if (!nzchar(path)) {
    .wb_identifier_error("SCWORKBENCH_IDENTIFIER_ENTROPY_UNAVAILABLE",
                         "no operating-system cryptographic entropy source is available.", purpose)
  }
  con <- tryCatch(file(path, open = "rb", blocking = TRUE, raw = TRUE), error = identity)
  if (inherits(con, "error")) {
    .wb_identifier_error("SCWORKBENCH_IDENTIFIER_ENTROPY_UNAVAILABLE",
                         conditionMessage(con), purpose)
  }
  on.exit(close(con), add = TRUE)
  value <- tryCatch(readBin(con, what = "raw", n = n), error = identity)
  if (inherits(value, "error") || length(value) != n) {
    detail <- if (inherits(value, "error")) conditionMessage(value) else "secure entropy read was short."
    .wb_identifier_error("SCWORKBENCH_IDENTIFIER_ENTROPY_UNAVAILABLE", detail, purpose)
  }
  value
}

.wb_secure_token <- function(n = 12L, alphabet = c(letters, 0:9),
                             purpose = "administrative identifier") {
  n <- as.integer(n)[1L]
  alphabet <- as.character(alphabet)
  .wb_assert(n > 0L && length(alphabet) >= 2L && length(alphabet) <= 256L,
             "Invalid secure-token request.")
  out <- character()
  while (length(out) < n) {
    value <- .wb_secure_entropy(max(32L, (n - length(out)) * 2L), purpose)
    # Test hooks may return a complete printable candidate directly.
    if (is.character(value)) return(substr(value, 1L, n))
    limit <- floor(256L / length(alphabet)) * length(alphabet)
    bytes <- as.integer(value)
    bytes <- bytes[bytes < limit]
    if (length(bytes)) out <- c(out, alphabet[(bytes %% length(alphabet)) + 1L])
  }
  paste0(out[seq_len(n)], collapse = "")
}

.wb_allocate_identifier <- function(prefix = "", n = 12L,
                                    alphabet = c(letters, 0:9),
                                    purpose = "administrative identifier",
                                    occupied = NULL, max_attempts = 16L) {
  max_attempts <- as.integer(max_attempts)[1L]
  .wb_assert(max_attempts > 0L, "identifier max_attempts must be positive.")
  for (attempt in seq_len(max_attempts)) {
    candidate <- paste0(prefix, .wb_secure_token(n, alphabet, purpose))
    recent <- base::exists(candidate, envir = .wb_identifier_state$issued, inherits = FALSE)
    conflict <- recent || (!is.null(occupied) && isTRUE(occupied(candidate)))
    if (conflict) next
    assign(candidate, TRUE, envir = .wb_identifier_state$issued)
    return(candidate)
  }
  .wb_identifier_error(
    "SCWORKBENCH_IDENTIFIER_COLLISION_EXHAUSTED",
    paste0("secure candidates remained occupied after ", max_attempts, " attempts."),
    purpose, max_attempts
  )
}

.wb_db_identifier_exists <- function(con, table, column, candidate) {
  if (is.null(con) || !DBI::dbIsValid(con) || !.wb_table_exists(con, table)) return(FALSE)
  .wb_assert(grepl("^[A-Za-z_][A-Za-z0-9_]*$", table) &&
               grepl("^[A-Za-z_][A-Za-z0-9_]*$", column),
             "Unsafe identifier collision scope.")
  nrow(DBI::dbGetQuery(
    con,
    paste0("SELECT 1 FROM ", table, " WHERE ", column, " = ? LIMIT 1;"),
    params = list(candidate)
  )) > 0L
}

.wb_allocate_db_identifier <- function(con, table, column, prefix, n = 12L,
                                       purpose = paste(table, column)) {
  .wb_allocate_identifier(
    prefix = prefix, n = n, purpose = purpose,
    occupied = function(candidate) .wb_db_identifier_exists(con, table, column, candidate)
  )
}

.wb_assert_preallocated_identifier_available <- function(con, table, column,
                                                         candidate, purpose) {
  if (.wb_db_identifier_exists(con, table, column, candidate)) {
    .wb_identifier_error(
      "SCWORKBENCH_IDENTIFIER_CONFLICT",
      paste0("preallocated identifier already belongs to a different ", purpose, ": ", candidate),
      purpose
    )
  }
  invisible(candidate)
}
