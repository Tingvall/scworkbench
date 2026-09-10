test_docker_release_engineering_contract <- function() {
  root <- normalizePath(".", winslash = "/", mustWork = TRUE)
  docker_root <- file.path(root, "containers", "docker")
  required <- c(
    "Dockerfile", "derive_cpu_lock.py", "render_install_script.py",
    "prepare_build_context.sh", "build_fullstack.sh",
    "qualify_fullstack_release.sh", "run_local.sh", "Makevars",
    "runtime.dcf", "README.md"
  )
  stopifnot(all(file.exists(file.path(docker_root, required))))

  dockerfile <- paste(readLines(file.path(docker_root, "Dockerfile"), warn = FALSE), collapse = "\n")
  stopifnot(
    grepl("sha256:359702d482e70e343d2a436731b7c6deffd1ec184a1f1700de5d64b0c97cacba", dockerfile, fixed = TRUE),
    grepl("SCWORKBENCH_RUNTIME_ARCH=${TARGETARCH}", dockerfile, fixed = TRUE),
    grepl("SCWORKBENCH_BUILD_NCPUS=${BUILD_NCPUS}", dockerfile, fixed = TRUE),
    grepl("R_MAKEVARS_USER=/opt/scworkbench-runtime/Makevars", dockerfile, fixed = TRUE),
    grepl("ENTRYPOINT [\"/bin/bash\"]", dockerfile, fixed = TRUE),
    !grepl("scworkbenchShiny", dockerfile, fixed = TRUE),
    !grepl("run-scworkbench-shiny", dockerfile, fixed = TRUE)
  )

  makevars <- readLines(file.path(docker_root, "Makevars"), warn = FALSE)
  stopifnot(any(grepl("^CXX11STD = -std=gnu\\+\\+14$", makevars)))

  metadata <- read.dcf(file.path(docker_root, "runtime.dcf"))
  field <- function(name) unname(metadata[1L, name])
  stopifnot(
    identical(field("Profile"), "full-cpu"),
    identical(
      field("BaseImageIndexDigest"),
      "sha256:359702d482e70e343d2a436731b7c6deffd1ec184a1f1700de5d64b0c97cacba"
    ),
    identical(
      field("SourcePythonLockSHA256"),
      "183e8723406d547b7d6897a64450110fed9be4732fc1545617138e3042d9d416"
    )
  )

  cpu_lock <- tempfile(fileext = ".lock")
  on.exit(unlink(cpu_lock), add = TRUE)
  status <- system2(
    "python3",
    c(
      file.path(docker_root, "derive_cpu_lock.py"),
      file.path(root, "containers", "apptainer", "fullstack_python_requirements.lock"),
      cpu_lock
    ),
    stdout = TRUE,
    stderr = TRUE
  )
  stopifnot(is.null(attr(status, "status")), file.exists(cpu_lock))
  lock <- readLines(cpu_lock, warn = FALSE)
  stopifnot(
    "torch==2.6.0+cpu" %in% lock,
    "--extra-index-url https://download.pytorch.org/whl/cpu" %in% lock,
    !any(grepl("^(nvidia-|triton==)|cu124", lock))
  )
  lock_sha <- sub("[[:space:]].*$", "", system2("sha256sum", cpu_lock, stdout = TRUE)[[1L]])
  stopifnot(identical(lock_sha, field("DerivedPythonLockSHA256")))

  install_script <- tempfile(fileext = ".sh")
  on.exit(unlink(install_script), add = TRUE)
  status <- system2(
    "python3",
    c(
      file.path(docker_root, "render_install_script.py"),
      file.path(root, "containers", "apptainer", "scworkbench_fullstack.def"),
      install_script
    )
  )
  stopifnot(identical(status, 0L))
  install <- paste(readLines(install_script, warn = FALSE), collapse = "\n")
  stopifnot(
    grepl("containers/docker/fullstack_python_requirements.cpu.lock", install, fixed = TRUE),
    !grepl("containers/apptainer/fullstack_python_requirements.lock", install, fixed = TRUE),
    grepl("runtime_kind", install, fixed = TRUE)
  )

  run_local <- paste(readLines(file.path(docker_root, "run_local.sh"), warn = FALSE), collapse = "\n")
  stopifnot(
    grepl('${PROJECT_DIR}:/work', run_local, fixed = TRUE),
    grepl("--workdir /work", run_local, fixed = TRUE),
    !grepl("--publish", run_local, fixed = TRUE),
    !grepl("3838", run_local, fixed = TRUE),
    !grepl("run-scworkbench-shiny", run_local, fixed = TRUE)
  )

  context_script <- paste(
    readLines(file.path(docker_root, "prepare_build_context.sh"), warn = FALSE),
    collapse = "\n"
  )
  stopifnot(
    !grepl("scworkbenchShiny", context_script, fixed = TRUE),
    !grepl("scwb-agent", context_script, fixed = TRUE),
    grepl("--exclude '.git'", context_script, fixed = TRUE),
    grepl("check_container_source_hygiene[.]sh", context_script),
    grepl("validate_container_runtime_licenses[.]py", install)
  )

  for (script in c(
    "prepare_build_context.sh", "build_fullstack.sh",
    "qualify_fullstack_release.sh", "run_local.sh"
  )) {
    stopifnot(identical(system2("bash", c("-n", file.path(docker_root, script))), 0L))
  }
  TRUE
}
