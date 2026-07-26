test_fullstack_monocle3_dependency_closure_contract <- function() {
  source("inst/ci/fullstack_r_dependency_lock.R", local = TRUE)
  lock <- read_fullstack_r_dependency_lock("containers/apptainer/fullstack_r_dependencies.dcf")
  snapshot <- "inst/ci/monocle3_4f4239a_dependency_snapshot.dcf"

  direct <- fullstack_validate_monocle3_closure(lock, snapshot)
  stopifnot("assertthat" %in% direct, "grr" %in% direct, "speedglm" %in% direct)
  stopifnot(identical(lock$GitHubMonocle3GitHubPrerequisites[["grr"]],
                      "cran/grr@3e7a63ef9b62dec659792d0da5eba6f51ee586eb"))

  incomplete <- lock
  incomplete$GitHubMonocle3CRANPrerequisites <- setdiff(
    incomplete$GitHubMonocle3CRANPrerequisites, "assertthat"
  )
  failed <- tryCatch({
    fullstack_validate_monocle3_closure(incomplete, snapshot)
    FALSE
  }, error = function(error) grepl("undeclared direct dependency source\\(s\\): assertthat", conditionMessage(error)))
  stopifnot(isTRUE(failed))
  TRUE
}
