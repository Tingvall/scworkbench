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

  # Removed provenance APIs must not survive in either the shipped source
  # documentation or searchable repository archives. Construct the names in
  # pieces so this regression does not itself become a stale search hit.
  obsolete <- c(
    paste0("wb_art_", "birth_certificate"),
    paste0("wb_art_", "identity_card"),
    paste0("artifact_", "birth_certificate_v1")
  )
  documentation_roots <- c(
    "README.md", "NEWS.md", "DESCRIPTION", "NAMESPACE",
    "R", "docs", "inst", "man", "tests", "vignettes", "archive"
  )
  documentation_roots <- file.path(root, documentation_roots)
  documentation_roots <- documentation_roots[file.exists(documentation_roots)]
  searchable <- unlist(lapply(documentation_roots, function(path) {
    if (!dir.exists(path)) return(path)
    list.files(path, recursive = TRUE, full.names = TRUE, all.files = TRUE)
  }), use.names = FALSE)
  searchable <- searchable[file.info(searchable)$isdir %in% FALSE]
  searchable <- searchable[
    basename(searchable) %in% c("DESCRIPTION", "NAMESPACE") |
      grepl("[.](R|Rd|Rmd|md|json|csv|dot|svg|txt|sh|yml|yaml)$", searchable)
  ]
  stale <- unlist(lapply(searchable, function(path) {
    text <- paste(readLines(path, warn = FALSE), collapse = "\n")
    found <- obsolete[vapply(obsolete, grepl, logical(1), x = text, fixed = TRUE)]
    if (!length(found)) return(character())
    paste0(sub(paste0("^", root, "/"), "", path), ": ", found)
  }), use.names = FALSE)
  if (length(stale)) {
    stop("obsolete provenance API references remain:\n", paste(stale, collapse = "\n"))
  }
  TRUE
}
