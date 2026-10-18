# Development-only ledger checks. Discovery verifies decisions; it never makes
# ownership decisions or classifies a newly discovered test automatically.
.phase8_validate_engine_additions <- function(rows, already_classified) {
  fields <- c("ledger_version", "test_identity", "source_path", "owner",
    "disposition", "justification", "ownership_decision_commit", "source_checkpoint_commit")
  if (!is.data.frame(rows) || !identical(names(rows), fields) || anyNA(rows) ||
      anyDuplicated(rows$test_identity) || any(rows$test_identity %in% already_classified) ||
      any(rows$ledger_version != "engine_execution_v1") ||
      any(rows$owner != "core_engine") || any(rows$disposition != "retain_core") ||
      any(!nzchar(rows$test_identity)) || any(!nzchar(rows$source_path)) ||
      any(!nzchar(rows$justification)) ||
      any(!grepl("^[0-9a-f]{40}$", rows$ownership_decision_commit)) ||
      any(!grepl("^[0-9a-f]{40}$", rows$source_checkpoint_commit)))
    stop("Invalid or overlapping explicit engine test ownership ledger")
  invisible(TRUE)
}

.phase8_assert_classified_discovery <- function(discovered, classified) {
  if (anyDuplicated(discovered) || anyDuplicated(classified))
    stop("Duplicate test identity in discovery or ownership decisions")
  unknown <- setdiff(discovered, classified)
  missing <- setdiff(classified, discovered)
  if (length(unknown)) stop("Unclassified current test: ", paste(unknown, collapse = ", "))
  if (length(missing)) stop("Classified current test absent from discovery: ", paste(missing, collapse = ", "))
  invisible(TRUE)
}
