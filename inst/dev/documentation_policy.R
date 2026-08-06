# Canonical policy for public documentation and package-content checks.

scwb_documentation_policy <- function(root = ".") {
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  canonical <- c(
    "README.md", "LICENSE", "LICENSE.md", "CITATION.cff",
    "docs/getting_started.md", "docs/bundle_concepts.md", "docs/ingestion.md",
    "docs/sessions_and_ops.md", "docs/promotion_and_provenance.md",
    "docs/recipient_audit.md", "docs/python_bridge.md",
    "docs/extension_engineering.md", "docs/source_ownership.md",
    "inst/protocol/pybench-op-v2.schema.json"
  )
  onboarding <- sort(list.files(file.path(root, "inst", "onboarding"), recursive = TRUE,
                                full.names = FALSE, all.files = FALSE))
  onboarding <- file.path("inst/onboarding", onboarding)
  generated_docs <- sort(c(
    list.files(file.path(root, "docs"), pattern = "(^.*_catalog_reference[.]md$|^.*_catalog_semantic[.]json$|^.*_semantics_(reference[.]md|catalog[.]json)$|^semantic_(catalog(_audit)?|compatibility_graph)[.]json$|^semantic_catalog_reference[.]md$|^schema_catalog_reference[.]md$)", full.names = FALSE),
    list.files(file.path(root, "docs", "semantic_graphs"), recursive = TRUE, full.names = FALSE)
  ))
  generated_docs <- unique(c(
    file.path("docs", generated_docs[!grepl("^semantic_graphs/", generated_docs)]),
    file.path("docs/semantic_graphs", list.files(file.path(root, "docs", "semantic_graphs"), recursive = TRUE, full.names = FALSE)),
    "docs/public_documentation_manifest.json",
    "inst/documentation_manifest.json",
    file.path("man", list.files(file.path(root, "man"), pattern = "[.]Rd$", full.names = FALSE))
  ))
  generated_docs <- sort(generated_docs[file.exists(file.path(root, generated_docs))])
  entries <- c(
    lapply(canonical, function(path) list(path = path, class = "public_canonical", audience = "public", status = "current", canonical_source = path, generator = NULL, source_tarball = TRUE, installed_package = grepl("^inst/", path))),
    lapply(onboarding, function(path) list(path = path, class = "public_canonical", audience = "operator", status = "current", canonical_source = path, generator = NULL, source_tarball = TRUE, installed_package = TRUE)),
    lapply(generated_docs, function(path) list(path = path, class = "generated_public_reference", audience = "public", status = "generated", canonical_source = if (grepl("^man/", path)) "R/ roxygen comments" else if (identical(path, "docs/schema_catalog_reference.md")) "R/ schema declarations" else "R/ catalog writers", generator = if (grepl("^man/", path)) "devtools::document()" else if (identical(path, "docs/schema_catalog_reference.md")) "inst/dev/generate_schema_catalog.R" else "inst/dev/regenerate_public_docs.R", source_tarball = TRUE, installed_package = identical(path, "inst/documentation_manifest.json")))
  )
  paths <- vapply(entries, `[[`, character(1), "path")
  manifest_paths <- c("docs/public_documentation_manifest.json", "inst/documentation_manifest.json")
  stopifnot(!anyDuplicated(paths), all(file.exists(file.path(root, setdiff(paths, manifest_paths)))))
  list(version = 1L, entries = entries,
       forbidden_tarball_patterns = c("^archive/", "^coordination/", "(^|/)[.]agents/", "(^|/)[.]codex/", "[.]backup$", "[.]sif$", "scworkbench[.]Rcheck/", "^reports/", "^scripts/reports/"))
}

scwb_write_documentation_manifest <- function(root = ".") {
  policy <- scwb_documentation_policy(root)
  text <- jsonlite::toJSON(policy, auto_unbox = TRUE, pretty = TRUE, null = "null")
  paths <- file.path(normalizePath(root, winslash = "/", mustWork = TRUE), c("docs/public_documentation_manifest.json", "inst/documentation_manifest.json"))
  for (path in paths) writeLines(text, path, useBytes = TRUE)
  invisible(paths)
}
