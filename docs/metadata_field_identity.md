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

Source names, stable IDs, and physical storage names are separate namespaces.
Data-frame column names always enter through the source-name namespace, even
when they look like `meta:*`, `core:*`, or `__wb_meta_*`. They do not express
update intent. A generated private name probes the complete case-folded SQLite
namespace and advances deterministically until it finds a free physical name.

Bare lookup considers stable-ID, source, display, and storage matches together.
If a spelling identifies different rows, lookup fails with every matching stable
ID. Use `wb_ref_metadata_field()` to select one stable ID explicitly. The
structured reference survives JSON provenance, recipes, generated replay, and
strict replay without becoming an ambiguous bare string.

`cell_id` is always the canonical join key and `dataset_id` is engine-owned.
Imported fields with either name are retained as separately mapped metadata and
can only be selected by stable ID. The bare `cell_id` and `dataset_id` names
always resolve to their core identities.

Use:

```r
fields <- wb_metadata_fields(bundle)
ref <- wb_ref_metadata_field("meta:000003")
field <- wb_metadata_field_resolve(bundle, ref)
values <- wb_meta(bundle, cols = list(
  wb_ref_metadata_field("core:cell_id"), ref
))
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

Ordinary updates reuse a uniquely matching source name. When names collide or a
caller intends to update by stable identity, pass a position-aligned `field_refs`
list to `wb_attach_metadata()`. Each non-NULL entry must be a
`wb_ref_metadata_field()`; NULL entries remain ordinary source-name imports.

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
