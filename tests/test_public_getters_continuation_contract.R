test_public_getters_continuation_contract <- function() {
  root <- tempfile("public-continuation-")
  dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  source(file.path("inst", "examples", "public_getters_and_continuation.R"), local = TRUE)
  result <- public_getters_and_continuation(file.path(root, "bundle"), file.path(root, "sessions"))
  stopifnot(result$primitive$kind == "cell_vector", is.numeric(result$values),
    identical(names(result$values), paste0("c", 1:12)),
    identical(unname(result$values), as.numeric(1:12)),
    is.data.frame(result$metadata), is.data.frame(result$table),
    is.character(result$sets), "set:high_score" %in% result$sets,
    identical(result$members, paste0("c", 7:12)),
    is.numeric(result$feature_values), identical(names(result$feature_values), paste0("c", 1:12)))
  b <- wb_open_bundle(result$bundle_dir)
  on.exit(wb_close_bundle(b), add = TRUE)
  terminal <- result$first$session
  # Reopen the terminal workspace rather than reusing a closed process handle.
  terminal <- wb_session_open(terminal$durable$workspace)
  errors <- list(
    tryCatch(wb_session_run_op(terminal, b, "metadata_cell_vector"), error = identity),
    tryCatch(wb_session_promote_current(b, terminal), error = identity),
    tryCatch(wb_session_resume(b, terminal$durable$workspace), error = identity))
  stopifnot(all(vapply(errors, inherits, logical(1), "error")),
    all(vapply(errors, function(e) grepl("wb_session_create(bundle)", conditionMessage(e), fixed = TRUE), logical(1))),
    identical(wb_session_finalize(terminal)$durable$state, "promoted"))
  wrong <- tryCatch(wb_cell_vector_load(b, vector_id = "score"), error = identity)
  stopifnot(inherits(wrong, "error"), grepl("wb_list_cell_vectors()$vector_id", conditionMessage(wrong), fixed = TRUE),
    grepl("wb_meta", conditionMessage(wrong), fixed = TRUE))
  TRUE
}
