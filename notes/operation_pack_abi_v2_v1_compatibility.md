# ABI v1 coexistence and retained-history policy

Status: **PROPOSED, NON-RUNTIME PLANNING ARTIFACT**.

Inputs: scworkbench `368c864126b2e60880a81fab8dc0abbd34cf27a9`;
Quill specification `eb5334a7bec73490ccfbf106f83ba91b1ab39fb8` and handoff
`8f73acebe833606e5d733988cb3d253720fcd333`; Sable audit
`f05ce0923d2b9bfbd7cfd8447208a674fb21319a`; Meridian-9 audit target
`385860ff591de57ef59939a3aa62d2b811201c2e`.

## Coexistence law

ABI v1 and v2 are parallel, explicit protocols. Loading v2 support does not
normalize, rehash, reinterpret, register, or rewrite a v1 manifest, operation
definition, catalog component, run, snapshot, artifact, receipt, or bundle.

| Concern | ABI v1 | ABI v2 proposal |
|---|---|---|
| Manifest | `scworkbench.operation_pack.v1` | `scworkbench.operation_pack.v2` |
| Pack ABI field | `protocol_version="1"` | `pack_abi_version="2"` |
| Canonical JSON | accepted `scworkbench.operation_pack.canonical_json.v1` | the same byte scheme |
| Capability | existing terminal-shaped registration | closed typed readers, private staged writers, atomic transition |
| Python transport | `pybench-op-v2` where used | exact `pybench-op-v3` |
| Identity namespace | v1 manifest/definition/pack domains | new v2 manifest/definition/pack domains |
| Historical resolution | exact recorded v1 pack or retained core implementation | exact recorded v2 pack/runtime |

Sharing the canonical JSON byte scheme does not share a definition identity:
the schema, ABI fields, output declarations, dependency declarations, and
capability contract are hashed definition content. An otherwise equivalent v2
operation therefore has a distinct identity from v1.

## Negotiation and activation

1. Parse the original installed manifest under the schema it explicitly names.
2. Authenticate original source bytes and normalized identity.
3. Select only that schema's validator and activation path.
4. Require the exact ABI/process ranges for that path.
5. Register only after all manifest, definition, distribution, dependency and
   entry-point identities agree.

There is no “highest available ABI” substitution for a retained identity. A v1
pack cannot receive a v2 capability, and a v2 pack cannot be downgraded to v1.
Same-name registrations from different ABI/definition identities are conflicts,
not aliases. Failure leaves catalog state byte-for-byte/identity-for-identity at
its pre-activation state.

## Existing-v1 admission floor

The accepted v1 validator in `R/operation_packs.R` is the minimum, not a legacy
exception. V2 preserves or strengthens its admission laws:

| V1 invariant | V2 treatment |
|---|---|
| Qualified operation uses the manifest namespace prefix | Strengthened to exact `namespace::short_name`, so a mismatched suffix also fails |
| Operation names are unique | Short and qualified names are independently unique before identity computation |
| Required/optional input names are unique | Array-form input names are explicitly unique within each operation |
| Promotable names are unique declared outputs | Every terminal key has an exact group-derived closure; every materialization/request has a terminal witness |
| Replay policies cover every declared output exactly | Preserved, plus policy validity is constrained by category and primitive kind |
| Invalid definitions do not become registrations | Preserved through a complete private candidate and one atomic handler/catalog publication |

Deliberate representation differences remain fail-closed. V1 uses its closed
typed parameter-declaration list; v2 uses a natively meta-validated Draft
2020-12 schema plus a closed language-neutral keyword profile. V2 array-form
outputs add unique allocation keys and promotion groups. These structures are
never translated implicitly between ABIs, and their distinct canonical
definitions receive distinct identities. V2 therefore cannot admit a name,
input, output, closure, replay map, parameter contract, or partial catalog state
that v1 would have rejected merely because the wire representation changed.

## Historical unqualified core operations

Runs that recorded an unqualified core operation remain bound to that exact
retained core definition and implementation identity. A future namespaced pack
with the same short name is not a replay candidate. Resolution must either:

- execute the exact retained core implementation when the historical identity
  is available and qualified; or
- fail closed with an explicit unavailable/incompatible historical-operation
  diagnosis before staging.

Migration never edits historical operation names, versions, definitions,
provenance, receipts, or content hashes. A new pack execution creates a new run
and new provenance edge; equivalence evidence may link it to a baseline but may
not replace the baseline.

## Migration gates

An operation may move only after its row in
`notes/operation_pack_abi_v2_conformance_matrix.csv` has executable old-core vs
new-pack evidence for resolved inputs, effective parameters, output comparator,
promotion closure, finalized pack-free reopen, exact-pack replay, absent/wrong
pack pre-dispatch rejection, and zero-residue failure behavior.

The 42 `v1_ready_with_packaging_work` rows need no new writer capability, but
they still require packaging, explicit operation-level dependencies, runtime
preflight and equivalence evidence. They may ship first as v1 packs and later
adopt v2 only through a new v2 manifest/definition identity.

ABI v2 has no root dependency inheritance. Each new operation definition owns
its complete requirement array. That rule also applies to dynamically named
providers: for `chromvar`, core resolves `matrix.genome_provider` from the exact
retained matrix identity, validates and probes the open-ended R package name
offline, and identity-binds the installed provider evidence before dispatch.
This new declaration does not reinterpret any retained v1 or unqualified-core
run.

The 11 atomic multi-output operations, `umap_transform`, and
`winner_cell_sets` cannot be extracted until the required v2 capability is live
and conformant. Four `core_only` operations remain in core. `py_protocol_hello`
is a synthetic conformance fixture and never migrates scientific history.

The sole Phase 0 fixture gap is `knn_pseudobulk`; its migration remains blocked
until a bounded comparator fixture exists. This does not justify changing its
accepted core identity.

## Names that remain distinct

`cell_vector_assoc` and `cell_vector_association` are not compatibility aliases.
The former accepts a continuous and a grouping vector and emits association and
group-statistic tables. The latter accepts two typed vectors and emits typed
summary/detail tables after method dispatch. Their names, signatures, outputs,
definitions, baseline fixtures and future pack identities remain independent.

## Recipient and replay behavior

Finalized objects are core-owned. Getters, recipient validation, provenance,
certificates, and inspection must succeed without any v1 or v2 pack installed.
Replay always resolves the exact recorded identity:

- absent exact pack: `OPERATION_PACK_REQUIRED` before staging;
- same name with wrong manifest/ABI/definition/distribution/runtime:
  `OPERATION_PACK_INCOMPATIBLE` before staging;
- exact compatible pack: execute as a new transition and compare by the
  recorded terminal policies.

No compatibility adapter may silently deserialize a retained object through a
new pack or rewrite it to a newer durable schema.

## Proof that this proposal changes no v1 identity

The proposal adds only eight files under `notes/`. It does not alter
`inst/protocol/operation-pack-v1.schema.json`,
`inst/protocol/operation-pack-canonical-json-v1.md`,
`R/operation_packs.R`, any fixture, or any catalog. Adoption therefore has zero
runtime effect until a separately reviewed implementation changes live files.
