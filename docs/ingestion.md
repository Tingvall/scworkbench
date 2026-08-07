# Ingestion

See [source declarations and preflight](source_ingestion.md) for the canonical
offline checksum/declaration workflow and source-scope taxonomy. Strict public
and external file identities fail before any bundle or staging write.

Use the registered ingestion APIs for supported source formats. Inspect the
interface and validation report before applying an ingest plan; do not create
bundle registry rows by direct SQL.

```r
wb_ingest_validate(plan, bundle = b)
wb_ingest_apply(plan, bundle = b)
```

`wb_bundle_from_10x_mtx()`, `wb_bundle_from_h5ad()`, `wb_bundle_from_sce()`,
and `wb_bundle_from_seurat()` create bundles through the same durable contract.
