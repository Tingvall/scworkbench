test_long_running_session_promotion_guidance_contract <- function() {
  guides <- c(
    "inst/onboarding/AGENT_ENGINEER_GUIDE.md",
    "inst/onboarding/PLAYBOOK.md"
  )
  for (guide in guides) {
    lines <- readLines(guide, warn = FALSE)
    text <- paste(lines, collapse = "\n")
    stopifnot(grepl("## Long-running operation safety|### Long-running operation safety", text))
    stopifnot(grepl("structured `wb_run`", text, fixed = TRUE))
    stopifnot(grepl("wb_session_promote_current", text, fixed = TRUE))

    starts <- which(lines == "```r")
    stopifnot(length(starts) >= 1L)
    end <- which(lines == "```")
    end <- end[end > starts[[1L]]][[1L]]
    code <- paste(lines[(starts[[1L]] + 1L):(end - 1L)], collapse = "\n")
    stopifnot(!inherits(try(parse(text = code), silent = TRUE), "try-error"))
  }
  TRUE
}
