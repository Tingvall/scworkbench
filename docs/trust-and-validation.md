# Trust, bounded execution and validation

Operation packs are trusted scientific software. Native R execution is not a
hostile-code sandbox. A pack declares typed inputs and outputs, requests the
appropriate readers, computes, and emits primitives. Core retains alignment,
source association, declared contracts, provenance and atomic publication.
Packs must not access storage directly or invent their own source authority.
See the [authoring guide](../inst/sdk/operation-packs/GUIDE.md).

## Ordinary execution

Typed matrix readers operate on the admitted ordered feature and cell axes.
For feature-partitioned execution, core may create a disposable physical index
of only the allowed axes before reading blocks. This is a bounded backend
projection, not a new logical matrix or scientific filtering decision. The
scratch representation is removed when the reader closes or preparation fails.
Changing partition count does not require a full source hash for every block.

For trusted R matrix execution, actual consumed source bytes are authenticated
at lifecycle boundaries, including before publication. Between blocks, scoped
registry and file observations help detect accidental changes without rescanning
the whole matrix. These observations are supplementary: timestamps, file sizes
and SQLite change counters are not content identities. This model does not
promise detection of an arbitrary transient filesystem change restored before
the final content check. It does preserve exact selection, ordered coverage,
declared numerical-domain checks, receipts and rollback when a required check
fails.

The Python typed-matrix broker likewise authenticates a stage-visible
source once for its reader lifetime, uses bounded selected-axis reads and
supplementary guards, and retains independent full parent authentication before
publication. This also applies when a request combines graph and matrix grants.
Feature partitions use one selected row index, rather than repeatedly decoding
the same column-major source. Its stored-entry count and index build are
constant preparation passes, separate from content authentication.

Core-generated private Matrix Market projections authenticate their bytes and
axis descriptors before use. An admitted small projection may be cached;
oversized projections use a bounded double-valued BPCells import, with explicit
sort/load buffers and optional row index. They are not first parsed into a
whole R matrix to decide whether spilling is necessary. The existing decimal
transport representation is unchanged. Authenticated axes are retained
separately from physical BPCells names.

Admission covers axis decoding, original physical-axis/native selection maps,
retained readers, native sorting buffers and canonical identity scratch. Mixed
broker connections share the existing R-side graph policy, including the
parent's session-copy reservation. Matrix and graph response carriers are
serviced sequentially. These are bounded-operation resource admissions, not an
OS-enforced process-wide RAM limit or a global quota across R and Python.
Spill capacity must be measurable; concurrent filesystem consumers can still
cause a write to fail. Failure removes owned scratch and aborts publication,
without raising a memory guard. Backend/build-specific resource evidence must
be reported separately from public protocol parity.

Fresh ordinary matrix/space reader blocks use R copy-on-modify rather than a
serialization round trip when their complete envelope, metadata and attributes
contain only ordinary atomic values and lists. Mutable references, external
pointers, reference objects and other nonordinary objects retain the conservative
serialization path. Mutating a returned ordinary block does not mutate the
retained source or another returned block.

Repeated registry observations may reuse a content-derived fingerprint only in
a coherent connection/invocation scope at an unchanged SQLite epoch. Own writes,
other-connection commits and schema changes invalidate that reuse; rollback is
handled conservatively. Connection replacement, restore, migration, resume and
close discard relevant observations. This is not a general payload cache and
does not authenticate matrix, space or model bytes from database counters.

Ordinary schema checks still read the migration ledger on every call. Only a
previously successful foreign-key/nullability verdict can be reused, on the
same connection with exactly unchanged relevant SQLite definitions. TEMP
shadows disable reuse. Explicit schema inspection, migration and deep bundle
validation perform fresh structural checks; graph-policy checks do likewise.

## Fresh outputs and publication

Writers still validate output kinds, dimensions, axes, coverage, numerical
policies and complete linked-output groups. Their seals bind the actual payloads
and declarations. Collision, overwrite, lineage and receipt checks remain part
of publication.

Only a narrow native-R ordinary-RDS case avoids duplicate semantic reconstruction
immediately after the writer has sealed it: ordinary vector/family/path or table
outputs, no registry requests, no matrix/model special manifests, and no ABI4
graph execution. Eligibility is per output: a mixed native-R transition can
reuse an ordinary output seal while its special outputs retain deep checks.
Global receipt, linked-axis/seal and complete-output validation still run.
The final-path RDS bytes are still hashed and verified before return. This is
not a general instruction to trust any seal. Matrix/model manifests, graphs,
registry requests, Python outputs and recovery retain their full persisted
validation paths.

Table publication encodes and inserts row JSON in bounded batches while retaining
the existing row representation and content identity. An ordinary table primitive
still contains its full table in R; bounded publication does not turn that
ordinary-object API into an unlimited streaming input interface.

Canonical encoding reuses only exact invocation-local preimages and validated
key plans. Plain table row tokens are assembled in bounded batches; attributed
or otherwise special values keep the original encoder. This changes neither
canonical JSON's unique-key rule nor content identities. Existing durable table
row JSON precision is unchanged; it must not be described as full-precision
scientific storage merely because encoding became faster.

Promotion acquires destination and staging ownership before checking the selected
payload ledger and copying staged bytes. The stage remains owned through copying
and publication. A busy second lock rejects rather than waiting while holding
another bundle lock. Source/selected-payload failure occurs before artifact
migration or analytical publication. The existing transaction/workspace controls
complete promotion closure and rolls back failed publication.

## Sessions, recovery and transferred bundles

An ordinary durable operation validates the producer groups it actually consumes,
including run references and recognized stage-backed matrix/space IDs. Uncertain
direct file-backed inputs retain conservative broader verification. An unrelated
operation need not rehash every earlier output in the session. Consequently,
corruption in an unused branch may first be reported when that branch is consumed,
selected for promotion, resumed or explicitly validated; it is not silently
declared sound by unrelated work.

Resume verifies the persisted ledger rather than inheriting a live process's
ownership assumptions. Promotion verifies the complete selected ancestor closure,
not just the named terminal. Generation binding, stale-owner rejection, durable
checkpoints and terminal-promotion receipts remain enforced.

Use the existing explicit structural, content and recipient validation levels
for their respective boundaries. Read-only reopen and getters must not migrate,
repair, rewrite identities or alter lifecycle state. Recipient validation checks
the retained portable state; it is not replaced by a prior successful operation.
See [bundle validation](bundle_integrity_validation.md) and
[durable sessions](durable_resumable_sessions.md).

## Scope of performance claims

A fast matrix workflow does not establish engine-wide performance. Ordinary
vectors/tables, file-backed spaces/models, graph cursors and their lifecycle
checks have different costs. Graph partitions already use bounded page and
ordinal checks; complete graph authentication occurs at lifecycle boundaries,
not on every ordinary partition. No graph, special-model or broad registry
performance improvement is implied by the matrix optimizations.

No identity scheme, canonical representation, scientific parameter, supported
backend boundary or public operation interface is changed by these execution
simplifications. Performance reports should distinguish source inspection,
measured component costs and qualified complete workflows, and identify paths
that have not been measured.
