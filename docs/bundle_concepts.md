# Bundle concepts

A bundle is the portable analysis unit: SQLite metadata plus payload files,
artifacts, and provenance. Open a bundle through the public API and validate it
before use.

```r
b <- wb_open_bundle("path/to/bundle", read_only = TRUE)
wb_validate_bundle(b$dir)
manifest <- wb_manifest(b)
manifest$counts[c(
  "feature_registry_records",
  "feature_counts_by_matrix",
  "bundle_unique_feature_count"
)]
wb_close_bundle(b)
```

Feature registry records are matrix-scoped. The per-matrix map is the feature
universe summary; the bundle-level unique count is explicitly not applicable
because identifier and modality namespaces are not declared equivalent.

Getters are the storage boundary. Use `wb_cells()`, `wb_meta()`, `wb_matrices()`,
and `wb_spaces()` rather than reading SQLite or payload paths directly.

Scientific methods normally live in operation packs. A bundle is not a pack,
and opening it does not activate a method. Multiple datasets may retain distinct
matrices, cell sets, spaces, and source ancestry in one bundle; only explicit
operations establish integration or model-bound relationships.

An opened handle is committed state. Use session operations and promotion for
analysis, and declared ingestion APIs for imports. Assembly authority from
`wb_init_bundle()` does not survive reopening. See the installed
[system overview](../inst/onboarding/SYSTEM_OVERVIEW.md) for the core/pack boundary.
