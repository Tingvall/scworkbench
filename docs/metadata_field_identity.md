# Cell metadata field identity and bulk writes

Cell metadata remains stored on the canonical `cells` table, but callers no
longer treat a physical SQLite column name as the field contract. Every fresh or
migrated bundle has a durable `metadata_fields` registry.

## Identity model

Each field records:

- `source_name`: the exact imported name, including whitespace, punctuation,
  Unicode, and SQL keywords;
- `display_name`: the public label (normally the exact source name);
- `field_id`: an immutable `meta:NNNNNN` identity, or `core:*` for engine fields;
- `storage_name`: the quoted physical SQLite column;
- source position, source type, SQLite type, coercion type, collision decision,
  import identity/source/actor, and JSON evidence.

Names are preserved exactly when SQLite can represent them unambiguously.
Empty names, duplicate or ASCII case-fold-colliding names, and collisions with
existing or engine-owned columns receive deterministic private storage names.
Their source names remain unchanged in the registry. Ambiguous names fail and
list the valid stable IDs; they never select a field by position.

`cell_id` is always the canonical join key and `dataset_id` is engine-owned.
Imported fields with either name are retained as separately mapped metadata and
can only be selected by stable ID. The bare `cell_id` and `dataset_id` names
always resolve to their core identities.

Use:

```r
fields <- wb_metadata_fields(bundle)
field <- wb_metadata_field_resolve(bundle, "meta:000003")
values <- wb_meta(bundle, cols = c("cell_id", field$field_id))
```

`wb_cell_metadata_columns()` extends this mapping with missingness, cardinality,
and display hints for clients.

## Types and updates

Logical/integer fields use SQLite `INTEGER`, doubles use `REAL`, and factors or
characters use `TEXT`. All-missing columns retain their source class. Compatible
updates preserve the registered type: integer/logical/integral-double values may
update `INTEGER`; numeric values may update `REAL`; factor/character values may
update `TEXT`. Lossy or cross-domain coercions are rejected before mutation.
Partial-universe updates are allowed and align strictly by `cell_id`. Duplicate
or unknown cell IDs are rejected. Zero-row input is a no-op.

## Transaction boundary and complexity

Cell definition, generic ingestion, container ingestion, and metadata attachment
all use `.wb_write_cell_metadata()`. It validates the whole input, stages values
under private safe aliases, quotes every identifier with
`DBI::dbQuoteIdentifier()`, binds values, and performs one set-based update per
field. Schema additions, registry rows, and values share one SQLite transaction;
failure leaves none of them visible.

Statement complexity is `O(n_fields)`, not `O(n_cells * n_fields)`. Staging still
materializes the input data frame and temporary SQLite table, so peak memory and
temporary storage scale with the payload size. Import mapping/evidence describes
mechanical ingestion and does not create an unprovenanced scientific primitive;
use `metadata_cell_vector` when a metadata field becomes a reusable scientific
vector.

Existing development bundles migrate to schema version 5 by backfilling exact
current column names. A bundle whose ledger claims version 5 but lacks a complete,
non-conflicting registry is corrupt and deep validation rejects it.
