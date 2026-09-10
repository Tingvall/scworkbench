test_container_release_hygiene_contract <- function() {
  root <- normalizePath(".", winslash = "/", mustWork = TRUE)
  hygiene <- file.path(root, "inst", "ci", "check_container_source_hygiene.sh")
  licenses <- file.path(root, "containers", "licenses")
  validator <- file.path(root, "inst", "ci", "validate_container_runtime_licenses.py")

  stopifnot(file.exists(hygiene), file.exists(validator), dir.exists(licenses))
  stopifnot(identical(system2("bash", c("-n", hygiene)), 0L))
  stopifnot(identical(system2("python3", c(validator, "--license-root", licenses)), 0L))

  license_fixture <- tempfile("container_license_inventory_")
  dir.create(license_fixture)
  on.exit(unlink(license_fixture, recursive = TRUE), add = TRUE)
  file.copy(list.files(licenses, full.names = TRUE), license_fixture, recursive = TRUE)
  cat("tampered\n", file = file.path(license_fixture, "Triton", "LICENSE"), append = TRUE)
  stopifnot(!identical(suppressWarnings(system2(
    "python3", c(validator, "--license-root", license_fixture)
  )), 0L))

  fixture <- tempfile("container_source_hygiene_")
  dir.create(fixture)
  on.exit(unlink(fixture, recursive = TRUE), add = TRUE)
  stopifnot(identical(system2(hygiene, fixture), 0L))

  writeLines("gitdir: /private/developer/worktree", file.path(fixture, ".git"))
  stopifnot(!identical(suppressWarnings(system2(hygiene, fixture)), 0L))
  unlink(file.path(fixture, ".git"))

  dir.create(file.path(fixture, "nested", ".git"), recursive = TRUE)
  stopifnot(!identical(suppressWarnings(system2(hygiene, fixture)), 0L))
  unlink(file.path(fixture, "nested"), recursive = TRUE)

  file.symlink("missing-git-target", file.path(fixture, ".git"))
  stopifnot(!identical(suppressWarnings(system2(hygiene, fixture)), 0L))
  TRUE
}
