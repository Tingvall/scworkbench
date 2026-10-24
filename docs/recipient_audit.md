# Recipient audit

Finalize a recipient bundle before transfer, then inspect it through a read-only
handle. Audit does not mutate the recipient.

Promoted primitives, source records, run contracts, and pack definitions remain
inspectable without the producing pack. Pack-free inspection is not pack-free
execution or replay. New computation requires the compatible activated pack
and runtime; source/version equality alone does not prove instance compatibility.
Inspect models without deserialization unless trust is explicitly accepted.

```r
stopifnot(wb_finalize_recipient_bundle(b)$ready)
wb_close_bundle(b)
# Transfer the finalized bundle once to recipient_path.
recipient <- wb_open_bundle(recipient_path, read_only = TRUE, validate = FALSE)
report <- wb_bundle_validation_report(recipient_path, level = "recipient")
stopifnot(report$ok)
# report$completed_levels already includes structural, content and recipient.
# Retain this report and inspect its diagnostics/content_coverage directly.
```

`validate=FALSE` avoids an implicit full report before the explicit structured
report. Read-only open still checks schema, residue and transition/receipt
invariants; it is not an unchecked-storage shortcut. Finalization coordinates
SQLite/readiness and is not a full content verdict. Use the directory path for
validation/readiness APIs and the handle for typed getters.

Keep the recipient handle open for the inspection below and close it with
`wb_close_bundle(recipient)` when finished.

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
