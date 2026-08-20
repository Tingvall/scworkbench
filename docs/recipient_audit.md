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

For newly imported bundles, `wb_entity_certificate()` exposes one authoritative
producer for each imported matrix, space, and metadata field. Aggregate
container-import runs remain visible in `wb_prov_bundle_dag()` but do not claim
the same matrix or space a second time. Non-core metadata certificates verify a
tagged bundle-local baseline and expose compatible-update history; recipient
validation recomputes it without accessing unavailable external source files.
