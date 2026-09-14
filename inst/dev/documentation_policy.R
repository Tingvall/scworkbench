# Canonical policy for public documentation and package-content checks.

scwb_documentation_policy <- function(root = ".") {
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  entry <- function(path,
                    class,
                    audience,
                    status,
                    canonical_source,
                    generator = NULL,
                    source_tarball = TRUE,
                    installed_package = FALSE) {
    list(
      path = path,
      class = class,
      audience = audience,
      status = status,
      canonical_source = canonical_source,
      generator = generator,
      source_tarball = source_tarball,
      installed_package = installed_package,
      installed_relative_path = if (installed_package) sub("^inst/", "", path) else NULL
    )
  }
  canonical <- c(
    "README.md", "NEWS.md", "LICENSE", "LICENSE.md", "CITATION.cff", "inst/CITATION",
    "docs/getting_started.md", "docs/bundle_concepts.md", "docs/ingestion.md",
    "docs/bdev_external_user_workflows.md",
    "docs/sessions_and_ops.md", "docs/promotion_and_provenance.md",
    "docs/typed_cell_set_consumption.md",
    "docs/recipient_audit.md", "docs/python_bridge.md",
    "docs/extension_engineering.md", "docs/operation_packs.md",
    "docs/operation_pack_v2_protocol.md", "docs/source_ownership.md",
    "docs/CONTRIBUTING.md", "docs/SUPPORT.md", "docs/release_process.md",
    "docs/bundle_integrity_validation.md", "docs/bundle_path_containment_and_trust.md", "docs/bundle_state_contract.md", "docs/bundle_writer_lock.md", "docs/entity_lifecycle.md", "docs/durable_resumable_sessions.md", "docs/metadata_field_identity.md", "docs/metadata_cell_vector_diagnostics.md", "docs/pybench_integration_contract.md", "docs/pybench_op_protocol_v2.md", "docs/scvi_train.md", "docs/peakvi_fit.md", "docs/rna_map_ops.md", "docs/tabular_primitives.md", "docs/trajectory_fit_family_contract.md", "docs/trajectory_segment_contract.md", "docs/trajectory_segment_join_contract.md",
    "inst/protocol/operation-pack-v1.schema.json",
    "inst/protocol/operation-pack-canonical-json-v1.md",
    "inst/protocol/operation-pack-v2.schema.json",
    "inst/protocol/operation-pack-transition-request-v2.schema.json",
    "inst/protocol/operation-pack-transition-receipt-v2.schema.json",
    "inst/protocol/pybench-op-v3-python-runtime.schema.json",
    "inst/protocol/pybench-op-v2.schema.json"
  )
  operation_pack_fixtures <- sort(list.files(
    file.path(root, "inst", "protocol", "fixtures", "operation-pack-v1"),
    pattern = "[.]json$", recursive = TRUE, full.names = FALSE
  ))
  canonical <- c(canonical, file.path(
    "inst/protocol/fixtures/operation-pack-v1", operation_pack_fixtures
  ))
  canonical_json_fixtures <- sort(list.files(
    file.path(root, "inst", "protocol", "fixtures", "operation-pack-canonical-json-v1"),
    pattern = "[.]json$", recursive = TRUE, full.names = FALSE
  ))
  canonical <- c(canonical, file.path(
    "inst/protocol/fixtures/operation-pack-canonical-json-v1", canonical_json_fixtures
  ))
  operation_pack_v2_fixtures <- sort(list.files(
    file.path(root, "inst", "protocol", "fixtures", "operation-pack-v2"),
    pattern = "[.](json|csv)$", recursive = TRUE, full.names = FALSE
  ))
  canonical <- c(canonical, file.path(
    "inst/protocol/fixtures/operation-pack-v2", operation_pack_v2_fixtures
  ))
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
    lapply(canonical, function(path) entry(
      path, "public_canonical", "public", "current", path,
      source_tarball = !identical(path, "CITATION.cff"),
      installed_package = grepl("^inst/", path)
    )),
    lapply(onboarding, function(path) entry(
      path, "public_canonical", "operator", "current", path,
      installed_package = TRUE
    )),
    lapply(generated_docs, function(path) entry(
      path,
      "generated_public_reference",
      "public",
      "generated",
      if (grepl("^man/", path)) "R/ roxygen comments" else if (identical(path, "docs/schema_catalog_reference.md")) "R/ schema declarations" else "R/ catalog writers",
      generator = if (grepl("^man/", path)) "devtools::document()" else if (identical(path, "docs/schema_catalog_reference.md")) "inst/dev/generate_schema_catalog.R" else "inst/dev/regenerate_public_docs.R",
      installed_package = identical(path, "inst/documentation_manifest.json")
    ))
  )
  paths <- vapply(entries, `[[`, character(1), "path")
  manifest_paths <- c("docs/public_documentation_manifest.json", "inst/documentation_manifest.json")
  stopifnot(!anyDuplicated(paths), all(file.exists(file.path(root, setdiff(paths, manifest_paths)))))
  list(
    version = 1L,
    entries = entries,
    forbidden_tarball_patterns = c(
      "^archive/", "^coordination/", "(^|/)[.]agents/", "(^|/)[.]codex/",
      "[.]backup$", "[.]sif$", "scworkbench[.]Rcheck/", "^reports/", "^scripts/reports/"
    ),
    forbidden_public_text_patterns = c(
      "/home/dirk", "/scratch", "pybench-op-v1",
      "wb_session_run_op\\([\\s\\S]{0,800}?params[[:space:]]*=",
      "[.]backup", "coordination/(team|handoffs|requests)",
      "\\b(Scout|Forge|Lumen|Quill|Folio|Terra)\\b",
      "License:[[:space:]]*What license", "[Ll]icense is not finalized"
    )
  )
}

scwb_write_documentation_manifest <- function(root = ".") {
  policy <- scwb_documentation_policy(root)
  text <- jsonlite::toJSON(policy, auto_unbox = TRUE, pretty = TRUE, null = "null")
  paths <- file.path(normalizePath(root, winslash = "/", mustWork = TRUE), c("docs/public_documentation_manifest.json", "inst/documentation_manifest.json"))
  for (path in paths) writeLines(text, path, useBytes = TRUE)
  invisible(paths)
}
