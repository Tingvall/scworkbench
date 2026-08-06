test_documentation_source_package_curation_contract <- function() {
  root <- normalizePath(".", winslash = "/", mustWork = TRUE)
  source(file.path(root, "inst/dev/documentation_policy.R"))
  policy <- scwb_documentation_policy(root)
  manifest <- jsonlite::read_json(file.path(root, "docs/public_documentation_manifest.json"), simplifyVector = TRUE)
  entries <- manifest$entries
  stopifnot(!anyDuplicated(entries$path), all(file.exists(file.path(root, entries$path))))
  stopifnot(identical(sort(entries$path), sort(vapply(policy$entries, `[[`, character(1), "path"))))
  stopifnot(all(entries$class %in% c("public_canonical", "generated_public_reference")))
  public_text <- entries$path[grepl("^(README[.]md|docs/|inst/onboarding/)", entries$path) & grepl("[.](md|json)$", entries$path)]
  forbidden <- c("/home/dirk", "/scratch", "pybench-op-v1", "params = list", ".backup")
  for (path in public_text) {
    text <- paste(readLines(file.path(root, path), warn = FALSE), collapse = "\n")
    stopifnot(!any(vapply(forbidden, grepl, logical(1), x = text, fixed = TRUE)))
  }
  index <- paste(readLines(file.path(root, "docs/getting_started.md"), warn = FALSE), collapse = "\n")
  required <- c("bundle_concepts.md", "ingestion.md", "sessions_and_ops.md", "promotion_and_provenance.md", "recipient_audit.md", "python_bridge.md", "extension_engineering.md")
  stopifnot(all(vapply(required, grepl, logical(1), x = index, fixed = TRUE)))
  TRUE
}
