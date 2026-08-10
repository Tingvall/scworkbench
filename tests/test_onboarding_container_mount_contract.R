test_onboarding_container_mount_contract <- function() {
  operator <- paste(
    readLines("inst/onboarding/AGENT_OPERATOR_GUIDE.md", warn = FALSE),
    collapse = "\n"
  )
  playbook <- paste(
    readLines("inst/onboarding/PLAYBOOK.md", warn = FALSE),
    collapse = "\n"
  )
  recipes <- paste(
    readLines("inst/onboarding/RECIPES.md", warn = FALSE),
    collapse = "\n"
  )
  lock_protocol <- paste(
    readLines("docs/bundle_writer_lock.md", warn = FALSE),
    collapse = "\n"
  )

  for (text in list(operator, playbook, recipes, lock_protocol)) {
    stopifnot(grepl("parent", text, ignore.case = TRUE))
    stopifnot(grepl("sibling", text, ignore.case = TRUE))
  }

  stopifnot(grepl("--bind BUNDLE_DIR:/bundle", playbook, fixed = TRUE))
  stopifnot(grepl("owner_status=absent", operator, fixed = TRUE))
  stopifnot(grepl("do not run stale-lock recovery", operator, fixed = TRUE))
  stopifnot(grepl(":/bundle:ro", recipes, fixed = TRUE))
  stopifnot(grepl("mount-topology error", lock_protocol, fixed = TRUE))
  TRUE
}
