test_post_migration_documentation_contract <- function() {
  root <- normalizePath(Sys.getenv("SCWORKBENCH_SOURCE_ROOT", unset = "."),
                        winslash = "/", mustWork = TRUE)
  read_doc <- function(path) paste(readLines(file.path(root, path), warn = FALSE),
                                 collapse = "\n")
  overview <- read_doc("inst/onboarding/SYSTEM_OVERVIEW.md")
  profile <- jsonlite::read_json(file.path(root, "inst/standard_profile/profile.json"))
  for (pack in profile$packs) {
    rows <- readLines(file.path(root, "inst/onboarding/SYSTEM_OVERVIEW.md"))
    row <- rows[startsWith(rows, paste0("| ", pack$package, " |"))]
    stopifnot(length(row) == 1L)
    fields <- trimws(strsplit(row, "|", fixed = TRUE)[[1L]])
    stopifnot(identical(as.integer(fields[[4L]]), as.integer(pack$operation_count)))
  }
  stopifnot(sum(vapply(profile$packs, function(pack) pack$operation_count,
                      numeric(1))) == profile$packed_operation_count)
  for (op in profile$core_operations) {
    stopifnot(grepl(paste0("`", op, "`"), overview, fixed = TRUE))
  }
  kinds <- c("matrix", "space", "space_2d", "cell_vector", "cell_vector_family",
             "relation_family", "feature_table", "obs_table", "model_ref",
             "path_2d_family", "space_path_family")
  for (path in c("inst/onboarding/SYSTEM_OVERVIEW.md", "README.md", "AGENTS.md")) {
    text <- read_doc(path)
    stopifnot(all(vapply(kinds, function(kind) {
      grepl(paste0("`", kind, "`"), text, fixed = TRUE)
    }, logical(1))))
  }
  manifest <- jsonlite::read_json(file.path(root, "inst/documentation_manifest.json"))
  paths <- vapply(manifest$entries, `[[`, character(1), "path")
  stopifnot("inst/onboarding/SYSTEM_OVERVIEW.md" %in% paths)
  sessions <- read_doc("docs/sessions_and_ops.md")
  stopifnot(grepl('op_name = "metadata_cell_vector"', sessions, fixed = TRUE),
            !grepl("cells_counts_by", sessions, fixed = TRUE))
  stopifnot(grepl("pybench-op-v4", read_doc("docs/python_bridge.md"), fixed = TRUE),
            grepl("operation_pack_sdk.md", read_doc("docs/getting_started.md"), fixed = TRUE),
            grepl("SYSTEM_OVERVIEW.md", read_doc("inst/onboarding/README.md"), fixed = TRUE))
  source(file.path(root, "inst/dev/audit_agent_documentation.R"), local = TRUE)
  audit <- scwb_audit_agent_documentation(root)
  project_label <- paste0("b", "dev")
  stopifnot(!any(grepl(project_label, audit$paths, ignore.case = TRUE)),
            !any(vapply(audit$paths, function(path) {
              grepl(project_label, read_doc(path), ignore.case = TRUE)
            }, logical(1))))
  stopifnot(length(audit$paths) >= 70L, audit$r_blocks >= 60L,
            audit$api_calls >= 150L, nrow(audit$issues) == 0L)
  TRUE
}
