test_documentation_source_package_curation_contract <- function() {
  root <- normalizePath(".", winslash = "/", mustWork = TRUE)
  source(file.path(root, "inst/dev/documentation_policy.R"))
  policy <- scwb_documentation_policy(root)
  manifest <- jsonlite::read_json(file.path(root, "docs/public_documentation_manifest.json"), simplifyVector = TRUE)
  entries <- manifest$entries
  stopifnot(!anyDuplicated(entries$path), all(file.exists(file.path(root, entries$path))))
  stopifnot(identical(sort(entries$path), sort(vapply(policy$entries, `[[`, character(1), "path"))))
  stopifnot(all(entries$class %in% c("public_canonical", "generated_public_reference")))
  public_text <- entries$path[grepl(
    "([.](md|json|cff)$|(^|/)LICENSE([.]md)?$|^inst/CITATION$)",
    entries$path
  )]
  public_text <- setdiff(public_text, c(
    "docs/public_documentation_manifest.json", "inst/documentation_manifest.json"
  ))
  for (path in public_text) {
    text <- paste(readLines(file.path(root, path), warn = FALSE), collapse = "\n")
    stopifnot(!any(vapply(policy$forbidden_public_text_patterns, grepl, logical(1),
                          x = text, perl = TRUE)))
  }
  index <- paste(readLines(file.path(root, "docs/getting_started.md"), warn = FALSE), collapse = "\n")
  required <- c("bundle_concepts.md", "ingestion.md", "sessions_and_ops.md", "promotion_and_provenance.md", "recipient_audit.md", "python_bridge.md", "extension_engineering.md")
  stopifnot(all(vapply(required, grepl, logical(1), x = index, fixed = TRUE)))
  markdown <- entries$path[grepl("[.]md$", entries$path)]
  for (path in markdown) {
    text <- paste(readLines(file.path(root, path), warn = FALSE), collapse = "\n")
    links <- regmatches(text, gregexpr("\\]\\(([^)#]+)(?:#[^)]*)?\\)", text, perl = TRUE))[[1L]]
    if (!length(links)) next
    targets <- sub("^.*\\]\\(([^)#]+).*$", "\\1", links, perl = TRUE)
    targets <- targets[!grepl("^[a-z]+://", targets, ignore.case = TRUE)]
    resolved <- file.path(dirname(path), targets)
    stopifnot(all(file.exists(file.path(root, resolved))))
  }
  TRUE
}
