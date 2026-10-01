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

Bundle creation and source authentication are core responsibilities, not a
pack storage shortcut. Importing Seurat does not imply that every embedded
fitted model is adopted or replay-qualified. Inspect the imported primitives;
external fitted state requires an explicitly supported adoption boundary.
Format-specific dependencies must be installed for the requested import, but
installing Signac does not activate an ATAC operation pack.

H5AD ingestion is a nested conversion: the verified H5AD remains the
authoritative source and the converted SingleCellExperiment is a mediated
in-memory child in the same declaration. Imported matrices, spaces, metadata,
and feature metadata retain that ancestry. Ingest reports are evidence only;
setting `emit_report_artifact = FALSE` omits the report, not source provenance.
