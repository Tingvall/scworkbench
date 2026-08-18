# Checksummed cell-metadata import

Use `wb_metadata_import()` to add ordinary externally supplied per-cell facts
from a CSV or TSV to an existing bundle. The cell-ID column is always named
explicitly. The importer verifies a structured `wb_source_input()` declaration
and full file SHA-256, aligns exact cell IDs, resolves stable metadata-field
identities, writes through the canonical scalable metadata writer, and records
one durable ingestion run and loadable evidence artifact.

scworkbench preserves lineage from declared bundle inputs onward. It verifies
the imported metadata file, alignment, field identities, and downstream
filtering, but does not claim to have executed the external process that
produced the metadata values.

The claim-supporting route is:

```text
checksummed metadata table
  -> metadata import
  -> registered metadata field
  -> metadata_cell_vector when reusable scientific identity is needed
  -> selector recipe
  -> durable named cell set
  -> downstream registered operation
```

Ordinary source facts may remain metadata. Claim-supporting computed fields
should be materialized as typed vectors before broad downstream reuse. A
capsule is terminal evidence, not an intermediate metadata-import mechanism.
External-method scripts and parameters remain the supplier's responsibility
unless the method becomes an engine op. Direct SQLite mutation is never an
acceptable import route.

CSV uses comma separation and TSV/TAB uses tab separation according to the
filename extension; arbitrary content sniffing is not performed. Empty fields
and the exact token `NA` parse as missing. `fields=NULL` retains source column
order. Explicit `fields` are order-preserving and must be unique and
unambiguous. `field_refs` are position-aligned stable identities for explicit
compatible updates.

Unknown imported cell IDs fail by default. `unknown_cell_policy="warn_drop"`
is an explicit opt-in that emits a warning and records counts plus at most 100
rejected row identities. Known bundle cells absent from a partial table are
reported as `unsupplied_known`; they are not an alignment error and existing
values are not cleared.

`validate_only=TRUE` performs source preflight, checksum verification, parsing,
alignment, coercion checks, and field-action planning without acquiring the
writer lock or changing SQLite, WAL, manifest, or filesystem inventory. An
accepted import publishes registry changes, values, provenance, report
artifact, and field bindings in one SQLite transaction under the exclusive
writer lock, then atomically refreshes the bundle manifest.
