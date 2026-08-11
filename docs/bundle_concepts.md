# Bundle concepts

A bundle is the portable analysis unit: SQLite metadata plus payload files,
artifacts, and provenance. Open a bundle through the public API and validate it
before use.

```r
b <- wb_open_bundle("path/to/bundle")
on.exit(wb_close_bundle(b), add = TRUE)
wb_validate_bundle(b$dir)
manifest <- wb_manifest(b)
manifest$counts[c(
  "feature_registry_records",
  "feature_counts_by_matrix",
  "bundle_unique_feature_count"
)]
```

Feature registry records are matrix-scoped. The per-matrix map is the feature
universe summary; the bundle-level unique count is explicitly not applicable
because identifier and modality namespaces are not declared equivalent.

Getters are the storage boundary. Use `wb_cells()`, `wb_meta()`, `wb_matrices()`,
and `wb_spaces()` rather than reading SQLite or payload paths directly.
