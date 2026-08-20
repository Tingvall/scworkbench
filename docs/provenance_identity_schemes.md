# Provenance identity schemes

scworkbench keeps content identity, structural identity, integrity identity,
and display identifiers separate. A digest is not meaningful without its
declared scheme.

| Identity class | Current scheme | Durable use |
|---|---|---|
| Content identity | `scworkbench.content.*.v1` | Byte or canonical-value proof for files, tables, matrices, spaces, objects, and registries |
| Producer-run integrity | `scworkbench.integrity.run.framed-utf8.sha256.v2` | Full SHA-256 over domain-separated, length-framed UTF-8 run fields |
| Operation-contract integrity | `scworkbench.integrity.contract.utf8.sha256.v2` | Full SHA-256 over the canonical UTF-8 contract document |
| Structural primitive fingerprint | `scworkbench.structural.primitive-summary.sha256.v2` | Full SHA-256 over the primitive kind and canonical structural summary |
| Promotion materialization compatibility | `scworkbench.materialization.r-serialize-v3.sha256.v2` | Full SHA-256 over raw R serialization bytes; separate from the materialization file's content SHA-256 |
| Graph/display/reference identifier | `scworkbench.identifier.framed-utf8.sha256.v1` | Domain-separated full SHA-256 identifier with an explicit namespace |
| Historical compatibility | `scworkbench.identity.legacy-hash-text16.v1` | Validation-only interpretation of persisted pre-1.9 16-hex values |

New persisted run, contract, output, structural, and materialization identities
always include their scheme column. Full SHA-256 is retained for every value
that participates in integrity or uniqueness. Knowledge-graph edge and
fallback source IDs are namespaced full-digest identifiers rather than
collision-prone 16-hex checksums.

Hashing uses the native `digest` SHA-256 implementation. Raw payloads are
hashed directly. Canonical text is converted to UTF-8 bytes; multi-field
identities use domain separation and fixed-width byte-length framing. File
content continues through the streaming file identity path. Production
identity calculation has no R per-byte loop or integer-position arithmetic.

Imported non-core metadata uses
`scworkbench.content.metadata-field.cell-id-fold.v1`. It hashes stable field and
registry/type identity first, then folds bounded, `cell_id`-ordered chunks of
explicit missingness and typed stored values. Its current baseline and producer
binding publish atomically; prior compatible-update versions remain certificate
history rather than competing current producers.

Container import orchestration remains an inspectable run and report artifact.
Matrices and spaces are produced only by their concrete assembly runs; the
declared external source is connected directly to those runs, so aggregate
orchestration never creates a second authoritative producer.

## Migration and mixed history

Bundle schema migration 6 adds `run_hash_scheme`, `contract_hash_scheme`,
`output_hash_scheme`, and `structural_fingerprint_scheme` to provenance rows.
It tags existing values with the legacy scheme without changing their bytes.
New snapshots in the same bundle use the current schemes. Provenance getters,
DAG/KG export, birth certificates, replay, deep validation, and recipient
validation accept this mixed history and surface the schemes.

Read-only opening never migrates. A schema-5 bundle must first be opened through
the ordinary writable migration boundary (on a working clone when the source
is immutable). The migration is transactionally backed up and does not rewrite
historical hashes.

Validation fails closed for an absent scheme on a non-legacy digest, an unknown
scheme, a malformed digest, or a digest length that contradicts its scheme.
Legacy recomputation exists only for historical validation. It uses bounded
vector chunks and cannot produce new persisted identities.

## Promotion failure boundary

Materialization identities are calculated inside the commit-private promotion
workspace before publication. A digest failure removes that workspace before a
database transaction begins. A later publication failure rolls back SQLite and
removes both pending and already-renamed payloads. Closing the bundle releases
the writer lock, and the same in-memory or durable session may retry when its
lifecycle permits.
