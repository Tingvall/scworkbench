.wb_assert <- function(ok, msg) {
  if (!isTRUE(ok)) stop(msg, call. = FALSE)
  invisible(TRUE)
}

.wb_require_pkg <- function(pkg, why) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    stop("Missing suggested package '", pkg, "'. Needed for: ", why, call. = FALSE)
  }
}
