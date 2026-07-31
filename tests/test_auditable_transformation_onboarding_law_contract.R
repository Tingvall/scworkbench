test_auditable_transformation_onboarding_law_contract <- function() {
  guides <- c(
    "inst/onboarding/AGENT_OPERATOR_GUIDE.md",
    "inst/onboarding/AGENT_BIOLOGIST_GUIDE.md",
    "inst/onboarding/PLAYBOOK.md"
  )
  canonical_rule <- paste(
    "Every scientifically meaningful transformation, selection, statistical test,",
    "model fit, or derived diagnostic must be performed through a registered",
    "operation or provenance-aware wrangler and leave an auditable trail in the",
    "bundle. Reports may summarize recorded evidence; they may not create",
    "unrecorded scientific results.",
    sep = " "
  )
  for (guide in guides) {
    text <- paste(readLines(guide, warn = FALSE), collapse = "\n")
    normalized <- gsub("[[:space:]]+", " ", text)
    stopifnot(grepl(canonical_rule, normalized, fixed = TRUE))
    stopifnot(grepl("unsupported", text, ignore.case = TRUE))
    stopifnot(grepl("external unrecorded script", normalized, fixed = TRUE))
    stopifnot(grepl("Cosmetic report formatting", text, fixed = TRUE))
  }
  readme <- paste(readLines("inst/onboarding/README.md", warn = FALSE), collapse = "\n")
  stopifnot(grepl("auditable-transformation law", readme, fixed = TRUE))
  TRUE
}
