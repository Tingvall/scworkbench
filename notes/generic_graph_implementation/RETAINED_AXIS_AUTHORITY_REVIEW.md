# Focused retained-axis authority amendment for Sable review

This is an implementation detail under the accepted graph design, not a new
primitive identity, axis registry, scientific ordering policy or pack authority.
Core/pack output identities and the existing object-payload descriptor remain
unchanged. No historical bundle is backfilled or silently migrated.

## Proposed fresh-schema row authority

Add `payload_ordinal` to `artifact_labels` and `artifact_pseudotime` in the
fresh supported schema. The ordinal is the zero-based position of the exact
original primitive payload row, NOT cell/lineage lexicographic order. Enforce
integer, nonnegative, artifact-scoped unique ordinals. A complete artifact must
have dense coverage `[0, row_count)`; missing/null, duplicate, fractional,
negative, gapped and reordered authority rejects. Existing cell/key uniqueness
remains independently enforced. For a family, the cell axis is the existing
ordered-unique first occurrence of cell IDs in payload order; repeating a cell
under another family key is lawful, repeating its cell/key row is not.

Promoters insert these rows inside the existing promotion transaction; failures
roll back ordinals, artifact registry, provenance and payload rows together.
Ordinary materializing loaders cross-check ordinal order against the existing
lossless row-order descriptor before reconstructing the same primitive. An
ordinal does not override a contradictory descriptor. No generated artifact ID
or ordinal is added to the primitive's scientific content identity.

## Independent bounded source authentication

An axis grant binds the independently verified retained artifact to its exact
provenance snapshot, primitive content certificate and complete payload closure.
The source-axis membership/order digests stream from the ordinal-indexed rows;
uniqueness and first occurrence use disk SQL, never a full axis array in R.

Because the existing legacy object content digest uses R `serializeJSON`, a
bounded axis scan MUST NOT claim to recompute that digest merely by reading
cells or trusting its stored value. Add an independent core-issued durable row
closure certificate to the artifact provenance at original promotion. Its
domain-separated identity covers all ordinal-ordered scientific payload fields,
semantic type and exact identity-bearing metadata descriptor bytes, independently
of the axis-only digest. Recompute this certificate from actual durable records
before issuing a bound source grant and before publication. Record the exact
certificate preimage/fold scheme and tamper vectors before freezing schemas.
It supplements, never replaces or rewrites the existing content identity.

The substring proposal is superseded after Sable review: SQLite substring and
JSON extraction do not establish bounded memory over a huge legacy descriptor.
Persist the exact metadata UTF-8 bytes as fresh artifact-scoped BLOB chunks of
at most 64 KiB, with dense unique chunk ordinals. These are payload components,
not an axis registry. The source verifier hashes actual chunks without selecting
the legacy provenance JSON. The materializing loader consumes these same bytes
and rejects disagreement with the legacy descriptor; it cannot trust a different
shadow representation. Ordinary loading remains a separately admitted convenience.
Fresh rows lacking independently retained chunk/row authority cannot issue grants.

The closure scheme is
`scworkbench.artifact.ordered-object-payload.canonical-json.v1`. Its canonical
preimage contains exactly `schema` (ordered-object-payload.v1), `kind`,
`value_type`, `content_identity` (the unchanged legacy primitive content scheme
and original digest), `metadata` and `rows`. Metadata contains `present`,
`encoding` (`R.serializeJSON.v1`) and SHA-256 of the exact ordered UTF-8 bytes
(empty bytes when absent; absence is still distinct from present empty metadata).
Rows are in original payload order. Cell-vector rows contain exact decimal-string
`ordinal`, `cell_id`, `label`, `value_type`, `value_num` (finite binary64
little-endian hexadecimal or null). Family rows contain `ordinal`, `cell_id`,
`key`, `value` (finite binary64 little-endian hexadecimal or null). Typed nulls
are not omitted fields; no scientific value, metadata key or row order is normalized.
The canonical preimage streams exact tokens, not per-chunk/table digest roots.

The originally issued certificate is anchored separately in
`prov_run_outputs.retained_payload_identity_json` during the existing promotion
transaction. Artifact-local metadata and self-rehashed source-axis claims cannot
replace it. Every source grant also carries that exact closure identity alongside
axis/snapshot identities and its scoped source authority; actual rows/chunks are
reverified against the independent output evidence before dispatch/publication.
Matrix-bound admission remains fail-closed pending the Controller decision on a
bounded, independently retained matrix-source certificate. The legacy
fragment-tree.v2 identity is not a substitute for recomputing actual numerical
payload and source-axis authority.

## Required focused evidence before family edits are accepted

- Categorical/continuous vector and family pre-promotion/reload identities and
  value types unchanged, including noncanonical row order and nullable values.
- Ordinal/descriptor agreement and scientific row/metadata certificate verified.
- Dense unique ordinal constraints and independently detected bypass/tamper.
- Changed values, metadata, type, dropped/reordered rows and self-rehashed axis
  claims reject against the independently retained provenance certificate.
- Family ordered-unique axis retains native first-occurrence semantics.
- Fault insertion leaves zero residue and retry succeeds.
- Bounded source-axis scans and certificate verification measured at scale.

Disposition: CV/CVF certificates are implemented with focused review-driven
hardening; source authority tests pass. Explicit ABI4 source grants and their
publication binding remain under development. No final qualification is claimed.
Matrix authority is pending a substantive Controller decision and remains rejected.
