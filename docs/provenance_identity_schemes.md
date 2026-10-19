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
| Named cell-set membership | `scworkbench.cell-set-membership.sorted-cell-id.canonical-json.v1` | SHA-256 over sorted unique cell IDs; source and operation-effective counts are recorded separately |
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

H5AD conversion adds `scworkbench.nested_ingestion.v1` composition metadata to
the immutable source declaration. Its checksummed H5AD parent is authoritative;
the converted SingleCellExperiment is a `CONVERTS_TO` in-memory child. Both
source nodes feed the concrete imported-entity producers, while the report run
remains evidence rather than a competing producer.

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

## Informational runtime provenance

New persisted run and durable-session fingerprints use
`scworkbench.runtime_attestation.v2`. Their BPCells `version` is installed
package metadata selected by ordinary R package discovery, without loading its
namespace. An installed but unloadable package can therefore have a recorded
version. `native_provenance` remains its installed DESCRIPTION `RemoteSha`
claim. Neither field proves loadability, execution, or the identity of a loaded
native image. The namespace list is a separate fresh observation of namespaces
already loaded when each fingerprint is constructed; its version fields retain
their existing installed-metadata interpretation.

Operation identity, explicitly supplied operation-pack runtime evidence, image
binding and environment provenance are still collected for each invocation.
No first-run fingerprint or namespace list is reused across operations.
ABI request/receipt runtime attestations and promotion package-inventory fields
are unchanged; this v2 label distinguishes the persisted informational meaning,
not a scientific content or identity-scheme migration.

Historical `scworkbench.runtime_attestation.v1` records keep their original
BPCells loadability-probe interpretation and bytes. Read-only provenance and
certificate inspection and durable recovery accept them without relabeling or
rewriting them. New v2 records may coexist with historical v1 evidence.
