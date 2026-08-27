# Recipient audit

Finalize a recipient bundle before transfer, then inspect it through a read-only
handle. Audit does not mutate the recipient.

```r
wb_finalize_recipient_bundle(b)
recipient <- wb_open_bundle("path/to/recipient", read_only = TRUE)
on.exit(wb_close_bundle(recipient), add = TRUE)
wb_recipient_readiness(recipient)
wb_validate_bundle(recipient)
```

For an imported H5AD, call `wb_prov_source_inputs(recipient)` to recover the
checksummed external source and its `CONVERTS_TO` SingleCellExperiment child.
The `parent_source_id` and `source_relation` columns reconstruct this ancestry
without an operator report or original workspace. Matrix and space
`wb_entity_certificate()` results include both nodes in `relationships$upstream`.

For newly imported bundles, `wb_entity_certificate()` exposes one authoritative
producer for each imported matrix, space, and metadata field. Aggregate
container-import runs remain visible in `wb_prov_bundle_dag()` but do not claim
the same matrix or space a second time. Non-core metadata certificates verify a
tagged bundle-local baseline and expose compatible-update history; recipient
validation recomputes it without accessing unavailable external source files.
