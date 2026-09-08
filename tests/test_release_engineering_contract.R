test_release_engineering_contract <- function() {
  root <- normalizePath(".", winslash = "/", mustWork = TRUE)
  required <- c(
    ".gitlab-ci.yml", "NEWS.md", "docs/CONTRIBUTING.md", "docs/SUPPORT.md",
    "docs/release_process.md", "inst/release/composite_release.dcf",
    "inst/release/gate_policy.json", "inst/release/build_source_artifacts.sh",
    "inst/release/assemble_release_evidence.sh",
    "inst/ci/run_logged_gate",
    "containers/apptainer/fullstack_r_versions.lock.csv",
    "containers/apptainer/fullstack_python_requirements.lock"
  )
  stopifnot(all(file.exists(file.path(root, required))))

  description <- read.dcf(file.path(root, "DESCRIPTION"))
  packages <- function(field) {
    trimws(sub("[[:space:]]*\\(.*$", "", strsplit(description[1L, field], ",", fixed = TRUE)[[1L]]))
  }
  imports <- packages("Imports")
  suggests <- packages("Suggests")
  stopifnot("digest" %in% imports, !"Seurat" %in% imports,
            all(c("Seurat", "SeuratObject") %in% suggests),
            !length(intersect(imports, suggests)))

  ci <- paste(readLines(file.path(root, ".gitlab-ci.yml"), warn = FALSE), collapse = "\n")
  jobs <- c(
    "static_release_contract", "canonical_contracts_complete_discovery",
    "source_package_check", "pybench_bounded_protocol", "fullstack_tripwire",
    "existing_sif_qualification", "gpu_scvi_peakvi",
    "large_data_ingestion_analysis"
  )
  ci_lines <- trimws(strsplit(ci, "\n", fixed = TRUE)[[1L]])
  stopifnot(all(paste0(jobs, ":") %in% ci_lines),
            grepl("run_canonical_gate[.]sh", ci),
            grepl("grep -x 'Status: OK'", ci, fixed = TRUE),
            grepl("when: manual", ci, fixed = TRUE),
            grepl("allow_failure: false", ci, fixed = TRUE))

  runner <- paste(readLines(file.path(root, "inst/ci/run_canonical_gate.sh"), warn = FALSE), collapse = "\n")
  stopifnot(grepl("discovered", runner), grepl("executed", runner),
            grepl("skipped failed excluded", runner, fixed = TRUE),
            grepl("accounted", runner))

  requirements <- trimws(readLines(
    file.path(root, "containers/apptainer/fullstack_python_requirements.lock"), warn = FALSE
  ))
  requirements <- requirements[nzchar(requirements) & !startsWith(requirements, "#") &
                                 !startsWith(requirements, "--")]
  stopifnot(length(requirements) > 100L,
            all(grepl("^[A-Za-z0-9_.-]+==[^[:space:]]+$", requirements)))

  r_lock <- utils::read.csv(
    file.path(root, "containers/apptainer/fullstack_r_versions.lock.csv"),
    stringsAsFactors = FALSE
  )
  stopifnot(nrow(r_lock) > 40L, !anyDuplicated(r_lock$package),
            all(c(imports, suggests) %in% r_lock$package))

  definition <- readLines(
    file.path(root, "containers/apptainer/scworkbench_fullstack.def"), warn = FALSE
  )
  stopifnot(any(grepl("^From: .*@sha256:[0-9a-f]{64}$", definition)),
            any(grepl("fullstack_python_requirements[.]lock", definition)),
            any(grepl("[.][.]/pybench/protocol /opt/pybench/protocol", definition)),
            !any(grepl("^[[:space:]]*[.][.]/scworkbenchShiny[[:space:]]", definition)),
            !any(grepl("run-scworkbench-shiny[[:space:]]+/usr/local/bin", definition)))

  build_script <- paste(readLines(
    file.path(root, "containers/apptainer/build_fullstack.sh"), warn = FALSE
  ), collapse = "\n")
  stopifnot(grepl('"${PYBENCH_ROOT}/protocol/"', build_script, fixed = TRUE),
            grepl("protocol/pybench-op-v2[.]schema[.]json", build_script),
            !grepl('"${REPO_ROOT}/../scworkbenchShiny/"', build_script, fixed = TRUE),
            !grepl('"${BUILD_CONTEXT}/scworkbenchShiny"', build_script, fixed = TRUE),
            !grepl('"${BUILD_CONTEXT}/scwb-agent"', build_script, fixed = TRUE))

  fullstack <- paste(readLines(
    file.path(root, "inst/fullstack/check_fullstack_contracts.sh"), warn = FALSE
  ), collapse = "\n")
  stopifnot(
    grepl("scworkbench pybench payload parity", fullstack, fixed = TRUE),
    grepl("generated semantic catalog freshness", fullstack, fixed = TRUE),
    grepl("pybench tests", fullstack, fixed = TRUE),
    grepl('PYBENCH_GOLDEN_BUNDLE="$FULLSTACK_TMP/pybench_golden"', fullstack, fixed = TRUE),
    grepl('cp -a -- "$GOLDEN_BUNDLE" "$PYBENCH_GOLDEN_BUNDLE"', fullstack, fixed = TRUE),
    !grepl("scworkbenchShiny", fullstack, fixed = TRUE),
    !grepl("scwb-agent", fullstack, fixed = TRUE)
  )

  scripts <- c(
    "inst/ci/run_canonical_gate.sh", "inst/ci/run_logged_gate",
    "inst/ci/record_manual_gate.sh",
    "inst/ci/checkout_pinned_pybench.sh", "inst/ci/provision_pinned_pybench.sh",
    "inst/release/build_source_artifacts.sh", "inst/release/assemble_release_evidence.sh"
  )
  for (script in scripts) {
    status <- system2("bash", c("-n", file.path(root, script)))
    stopifnot(identical(status, 0L))
  }

  status <- system2("Rscript", c(file.path(root, "inst/ci/validate_release_metadata.R"), root))
  stopifnot(identical(status, 0L))
  TRUE
}
