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
