# Operation-pack ABI v3 protocol relationship

Operation-pack ABI v3 is the explicit successor contract for bounded output
axes, authenticated typed matrix slices, and core-attested artifact ancestry. Its
closed manifest, request, and receipt schemas are installed as
`operation-pack-v3.schema.json`,
`operation-pack-transition-request-v3.schema.json`, and
`operation-pack-transition-receipt-v3.schema.json`. A pack opts into v3 by
declaring `scworkbench.operation_pack.v3` and ABI `3`; v1 and v2 documents,
identities, parsers, and process protocols are unchanged.

All language-neutral identity preimages use
`scworkbench.operation_pack.canonical_json.v1`. Top-level self identities carry
their exact `scope`; nested references use the closed `{scheme, sha256}`
projection wherever the schemas name the generic identity tuple. The fixture
corpus at `inst/protocol/fixtures/operation-pack-v3/identities.json` is the
authoritative cross-language byte and identity checkpoint. R and Python must
copy the four shared protocol files byte-for-byte.

## Authenticated output axes

`authenticated_output_axes_v1` replaces an unrestricted dynamic-family size
with one of two exact policies:

- `cell_key_cartesian` grants a key-major Cartesian product of an authenticated
  effective cell axis and an ordered key axis. Keys are resolved either from a
  declared feature-group parameter against a declared matrix or from the
  first-occurrence key order of a declared input family, optionally narrowed
  by a validated selector.
- `one_per_cell` grants exactly one cell-vector row for every first-seen
  distinct cell in a declared long-form family input.

The request binds counts, ordered-axis identities, the exact expected row
count, missing-value policy, and row-order identity. Staging, receipt audit,
reopen, recipient validation, and replay reject missing, extra, duplicate, or
reordered rows and keys. Zero-key behavior is declared per policy; it is never
an unrestricted sentinel.

## Generic typed-slice reader

A v3 `typed_slice_reads` declaration binds a matrix source, selected cell and
feature axes, supported slicing axes, a positive chunk-size parameter, exact
resource ceilings, and either ordered exactly-once or independent-call
discipline. Packs choose their own partitions with `wb_partition_axis()` and
publish complete scientific terminals through ordinary typed writers. Core
does not schedule scientific work, merge pack results, or compute summaries.

R readers delegate every call directly to `wb_slice()`. Python readers use a
supervised, transition-local R broker that alone holds the bundle binding and
returns one bounded sparse Matrix Market response at a time. The Python
process never receives a full backed matrix or a storage path. Tokens,
transport hashes, acknowledgements, and spool paths are ephemeral; durable
request and receipt evidence retains the source/grant identities and the
transport-neutral semantic identity of every canonical getter result.

For a bundle-backed matrix, the grant's content identity is computed from the
exact stage-visible fragment tree that `wb_slice()` reads. Core validates
committed-leaf links and hashes their bytes, while stage-only predecessor
fragments are hashed in place. The same identity and registry state are
rechecked before and after every R typed-slice read, including supervised
Python broker reads, and again before publication. A changed local payload
cannot be authorized by updating a
local checksum sidecar; the observed fragment bytes must still match the
identity sealed in the request and receipt.

`wb_slice_chunks()` exposes the same lazy bounded delivery to ordinary R
clients. Historical replay retains the effective selections, requested chunk
size, limits, ordered calls, coverage, and identities, so a later global
resource default cannot silently repartition an accepted run.

## Core-attested artifact ancestry

A manifest `provenance_reads` declaration grants a private, no-argument,
single-use `read_artifact_ancestry` capability only when its declared typed
input was resolved from a promoted artifact. Core authenticates the exact
artifact, content-verified producer output, source run, provenance snapshot
and head, and current lifecycle state. Superseded or tombstoned sources are
rejected. The pack receives a typed copy of the closed snapshot, never a bundle
path, database handle, or arbitrary query capability.

Core rechecks the source before dispatch and immediately before transition
publication. Promotion rechecks retained ancestry against the destination
bundle, and pack-free recipient validation repeats the current-source check.
Wrong, stale, forged, undeclared, missing, duplicate, or mutated ancestry
evidence fails without transition or analytical residue.

## Consolidated generic capabilities

G1 grants exactly one private read of an already-promoted contained model.
The grant authenticates an exact engine/model-type allowlist, the durable
model/source linkage, fitted cell and selected-dimension order, the complete
model-tree manifest, and the payload manifest. Core verifies the source-space
payload bytes and privately copied tree before dispatch and again before
publication. A declaration may grant at most 32 files and 1 GiB.

G2 grants a contained-model writer whose closure contains an ordered set of
required sibling terminals without requiring a paired 2D output. The model
tree, source linkage, sibling grant identities, cell-axis bindings, and replay
policies form one authenticated closure. Every sibling must be present and
valid before the transition directory is published; the model and all sibling
evidence therefore become visible together or not at all. The same 32-file,
1-GiB tree ceilings apply. Promoted model linkage and trees remain loadable
after relocation without a pack installation.

G3 admits one caller-prepared external model tree without fitting it again.
The public `wb_supported_external_state_candidate()` constructor copies named
raw entries into a private core-owned candidate, authenticates the complete
tree and payload identities, and binds the exact fitted cell order. A manifest
may declare at most one adoption and must authorize the selected engine/model
type, byte-evidence states, tree limits, G2 model output, and complete ordered
output closure. The runner receives one path-free reader returning bounded
entry bytes and one G2 writer that accepts those bytes; it receives no host
path, candidate token, bundle, database, or publication authority.

Source-byte evidence has three closed states. `bytes_verified` records equal
declared and observed content identities. `bytes_not_inspected` means policy
deliberately did not read an external path. `bytes_unavailable` means bytes
were absent at the approved boundary and is admitted only when the manifest
explicitly lists that state. Any checksum actually observed to differ is
always rejected. The request also authenticates one exact current source
snapshot, the candidate tree and payload, the G2 sibling-writer identity, its
model-source linkage, and the ordered closure. The receipt separately retains
the pack's source-association and no-refit attestations. Core proves tree
preservation and requires the published model tree to be byte-identical to the
candidate; it does not reinterpret either pack attestation as a core proof.
Adoption evidence remains distinct from fit, model loading, and replay after
promotion and relocation. G3 is currently an R-runtime capability; PyBench
mirrors the schemas and canonical fixtures and independently reproduces every
identity, but exposes no Python adoption executor.

G4 resolves up to eight ordered retained-artifact collections. Each collection
contains at most 64 items, eight declared slots per item, 256 references, 256
MiB per staged payload, and 1 GiB in total. The parameter ordinal and resolved
ordinal are both retained. Each activated ordinal/slot reader is exactly once;
missing, repeated, reordered, wrong-kind, stale-lifecycle, or unauthenticated
ancestry reads fail closed. Model references in this capability are metadata
projections: contained-model bytes remain exclusively under G1.

G5 resolves up to four ordered named-cell-axis collections with at most 64
axes, 10 million selected cells per axis, and 20 million memberships overall.
The request records the named-set source identity, bundle-universe identity,
projection exclusions, selected order, pairwise overlaps, and collection
identity. Packs read each axis ordinal exactly once.

G6 uses the same named-axis identity helper for optional display-space and
endpoint groups. Activation is parameter-resolved, absence is explicit, and
each active group authenticates a two-dimensional display partition followed
by ordered endpoint axes. At most 64 groups, 10 million display cells, 10
million cells per endpoint, and 20 million endpoint memberships are granted.
Display and endpoint readers are distinct; substitution or reordering is
rejected.

All six capabilities are opt-in. Their source identities and privately staged
payloads are revalidated immediately before atomic transition publication.
Injected publication failure, payload mutation, incomplete use, or receipt
disagreement removes the pending transition and leaves no analytical or
capability-evidence residue.

G7 is an R-runtime-only, path-free capability for operations whose scientific
method determines an output cell axis during execution. It does not give a pack
bundle, SQL, registry, filesystem, or state-authority access. A manifest uses
the closed `derived_cell_output_axes` declaration and selects one generic mode:

- `ordered_unique_subset_v1` is a nonempty, source-relative ordered subset of
  one authenticated cell-vector axis (or one selected family-key axis).
- `declared_ordered_unique_union_v1` validates an ordered unique subaxis from
  every authenticated G4 member, then requires the pack-declared final axis to
  be unique and have exactly the selected union membership. Core preserves the
  declared final order verbatim; it never sorts or derives a competing order.

An individual union member selection may be empty in v1. The aggregate
selection and final axis must remain nonempty. Every nonempty member selection
must preserve its authenticated source order.

The identity chain is acyclic: manifest declaration, selector and source
references, source aggregate, ordinary output grants, linked-output closure,
provisional G7 grant, transient pack declaration, derivation, sealed axis,
seal-derived cardinality grants and observations, then the receipt observation.
The existing `output_cardinality_grant.v1` scheme is unchanged. G7 adds
`sealed_output_cardinality_grant.v1` and
`observed_sealed_output_cardinality.v1` after the final axis is known.

An R runner receives immutable grants in
`context$derived_cell_output_axis_grants` and returns the private
`derived_cell_output_axis_declarations` channel. Use
`wb_derived_cell_output_axis_declaration()` to construct its closed record.
Core seals the declaration before admitting linked output values from the same
result envelope. Linked vectors are exactly one row per sealed cell. Linked
families retain the existing family-key resolution and exact key-major
Cartesian row order. Every linked descriptor, content identity, observation,
and receipt entry binds the same seal and complete transition closure.

Limits are four declarations per operation, 64 source axes per declaration,
10 million final cells, 20 million inspected memberships, 16 linked outputs
per declaration, and 32 linked outputs per operation. Declarations are exactly
once; sources are revalidated before dispatch and publication. Any source,
declaration, linked-output, receipt, or publication failure leaves no durable
transition residue. A valid G7 seal authenticates derivation and alignment,
not biological validity or a human operator.

### Derived fitted-cell axes for contained models

An R pack whose fitting method excludes cells from an authenticated source
space may declare one `derived_fitted_axis_policy` on its G2 model output.
Core authenticates the complete durable parent separately from the session
projection, accepts exactly one nonempty source-relative ordered subset before
any linked write, and seals that fitted axis. The pack chooses the cells and
order; core does not interpret filtering criteria.

The seal binds the contained model linkage and every declared cell-indexed
sibling. Ordinary siblings use exact fitted-axis coverage. A manifest may opt
a `cell_vector_family` into `per_key_source_relative_subset_v1`; every emitted
key is then nonempty and bounded, and contains a unique source-relative
subsequence of fitted cells. All declared siblings and keys are receipt-bound,
so partial closure cannot publish.

The immutable model tree contains
`.scworkbench/selected-axis-v1.json`, a canonical UTF-8 sidecar with exact
session and fitted identifiers plus parent/session/seal bindings. The sidecar
contains no self-hash. Its relative path, exact-byte SHA-256, and domain
identity live in linkage v3. Linkage excludes the final tree identity; model
content binds linkage and tree without a cycle. On G1 reopen, core verifies
the unchanged full parent, sidecar bytes, session relationship, fitted order,
and selected coordinates. Relocation therefore needs no workspace path.

Initial ceilings are one million selected cells, 64 MiB across session and
fitted UTF-8 identifiers, 1,024 bytes per identifier, and 64 family keys; a
manifest may lower them. This capability is R-runtime-only. PyBench mirrors
the shared schemas and identities but rejects a Python pack that declares it
before activation or mutation.

### Independent sparse cell-vector families

`standalone_sparse_cell_family_v1` is a separate, R-only opt-in policy for
one required terminal `cell_vector_family`. It is not a G2 model sibling or
a G7-derived axis. Its source is either an authenticated typed space input or
one verified G1 self-linked model read. G1 v2 binds the full source-space
snapshot and cell order; G1 v3 binds the selected fitted-axis seal and
sidecar. Neither route gives the pack a bundle or filesystem authority.

The immutable request contains a provisional grant, exposed read-only in
`context$standalone_sparse_cell_family_grants`, not writer authority.
Before the family write, the runner calls the private
`writers$declare_sparse_cell_family_layout(output, ordered_keys,
per_key_cells)` exactly once. Core verifies each nonempty, unique key's
source-relative ordered cell subset, seals the declared key-major row pairs,
and issues a process-local writer grant. A failed declaration attempt consumes
that authority; catching its error cannot authorize a second declaration.
The declared key order is preserved
verbatim. Pair identities hash ordered `{key, cell_id}` objects, so separator
characters in either identifier cannot alias a different pair sequence.
There is no dense padding or synthetic zero row.

The sealed dimensions are `[sum(per_key_cells lengths), 3]`. Values must be
finite numeric entries with the declared semantic value type. Core compares
the exact staged key/cell/value rows,
primitive content, staged file bytes,
output descriptor and receipt observation with the seal, then repeats those
checks on fresh reopen. The source is reauthenticated at grant, declaration,
write, and immediately before publication; recipient validation checks the
retained source and payload without executing the pack. The defaults cap the
source at one million cells, the family at 64 keys and one million rows,
each identifier at 1,024 UTF-8 bytes, and declaration identifiers together
at 64 MiB. Manifests may lower these limits. Any mismatch or publication
fault leaves no durable transition or analytical residue. This structural
authority does not judge whether the method chose biologically complete
keys or rows.

### Sealed exact-order relation families

`sealed_relation_family_v1` is an R-only opt-in policy for one required
terminal `relation_family`. Its cell axis comes from an authenticated typed
space or matrix input, or from a G2 derived fitted axis. A typed input binds
the ordered cells in the request. A G2 request binds the model selector and
parent/G2 grant first; it binds fitted cells only after G2 sealing. The
provisional request grant cannot write a relation.

The runner calls `writers$declare_relation_family_rows(output, ordered_keys,
row_chunks, numeric_fields)` exactly once before the terminal write. Each
chunk contains ordered `{key, cell_id}` pairs. Core seals the exact pair order
and first-occurrence key order, allows one cell under multiple keys, and
rejects duplicate pairs, foreign cells, empty relations, missing or nonfinite
numeric fields, and any altered output order. The policy imposes no sorting,
key-major, source-relative, or Cartesian-completeness rule. The declaration
issues a one-shot writer grant. A failed attempt consumes declaration
authority.

The ceilings are one million source cells, 1,024 keys, one million rows,
1,024 raw UTF-8 bytes per identifier, 64 MiB of encoded identifier bytes
across source cells, keys, and pair occurrences, and 8,192 pairs per chunk;
manifests may lower them. Source, staged payload, receipt, and promoted SQL
rows are checked against the seal. The promoted relation's optional payload
descriptor binds its content identity so later `wb_art_load()` checks numeric
values and field presence as well as row order. Existing relation content
identity schemes and older descriptors remain valid. Python mirrors the
shared schema and identity fixtures but rejects this policy at manifest
admission and request staging.

## Backends and durable lifecycle

R v3 packs retain the opaque `function(readers, writers, params, context)`
runner interface. Python v3 packs use the
installed `pybench-operation-pack-v4` process protocol. Python publishes the
same shared receipt plus a separately audited Python-owned runtime sidecar;
the sidecar is not a fifth shared file.

Both backends reuse the accepted v2 private staging and atomic directory
publication lifecycle. Complete request, receipt, output, registry-read,
ancestry-read, typed-slice, and runtime evidence is audited before publication and
again on reopen. Promotion copies an authenticated reopened transition into
the same rollback-capable workspace as its analytical outputs. Finalized
outputs and evidence remain inspectable without the pack installed; continued
execution or replay still requires the exact pack.

The source-tree R fixture at
`tests/fixtures/operation-pack-v3-reference` and PyBench's corresponding
Python fixture are conformance packages only. They are never activated
ambiently and make no scientific-method claim.
