# Bundle concepts

A bundle is the portable analysis unit: SQLite metadata plus payload files,
artifacts, and provenance. Open a bundle through the public API and validate it
before use.

```r
b <- wb_open_bundle("path/to/bundle")
on.exit(wb_close_bundle(b), add = TRUE)
wb_validate_bundle(b)
wb_manifest(b)
```

Getters are the storage boundary. Use `wb_cells()`, `wb_meta()`, `wb_matrices()`,
and `wb_spaces()` rather than reading SQLite or payload paths directly.
