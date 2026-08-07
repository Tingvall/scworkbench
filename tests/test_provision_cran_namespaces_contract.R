test_provision_cran_namespaces_dependency_order_contract <- function() {
  source("inst/ci/provision_cran_namespaces.R", local = TRUE)
  state <- new.env(parent = emptyenv())
  state$versions <- stats::setNames(character(), character())
  attempts <- character()

  installed_names <- function() names(state$versions)
  installed_version <- function(package) unname(state$versions[[package]])
  remove_one <- function(package) state$versions <- state$versions[names(state$versions) != package]
  install_one <- function(package, expected, repo) {
    attempts <<- c(attempts, package)
    if (identical(package, "biglm") && !"DBI" %in% names(state$versions)) {
      stop("dependency 'DBI' is not available")
    }
    state$versions[[package]] <- expected
    invisible(NULL)
  }

  result <- provision_cran_namespaces(
    packages = c("biglm", "DBI"),
    repo = "https://example.invalid",
    retries = 1L,
    target_versions = c(biglm = "0.9.3", DBI = "1.3.0"),
    install_one = install_one,
    installed_names = installed_names,
    installed_version = installed_version,
    remove_one = remove_one,
    sleep_fun = function(seconds) invisible(NULL)
  )

  stopifnot(
    identical(attempts, c("biglm", "DBI", "biglm")),
    identical(as.character(result$package), c("biglm", "DBI")),
    identical(as.character(result$version), c("0.9.3", "1.3.0")),
    identical(unname(state$versions[c("biglm", "DBI")]), c("0.9.3", "1.3.0"))
  )
  TRUE
}
