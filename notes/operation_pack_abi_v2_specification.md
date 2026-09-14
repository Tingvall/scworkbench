# Operation-pack ABI v2 canonical specification

Status: **PROPOSED, NON-RUNTIME PLANNING ARTIFACT**. Nothing in this document
activates an ABI, migrates an operation, or changes a retained identity.

Scworkbench source: `368c864126b2e60880a81fab8dc0abbd34cf27a9`.
Python source: `d2e0587950973cf7eeacfc46b2829397cf84f079` plus Quill's
specification commit `eb5334a7bec73490ccfbf106f83ba91b1ab39fb8` and handoff
commit `8f73acebe833606e5d733988cb3d253720fcd333`.

## 1. Normative vocabulary and authority

“MUST”, “MUST NOT”, “SHOULD”, and “MAY” are normative. The engine is the sole
authority for durable scientific state. A pack supplies operation definitions
and methods. It never owns bundle layout, durable IDs, mutation, publication,
provenance, replay resolution, or validation.

ABI v2 has three deliberately independent version domains:

| Domain | Frozen v2 value | Meaning |
|---|---|---|
| Manifest/pack ABI | `schema_version=scworkbench.operation_pack.v2`; `pack_abi_version="2"` | Definition and capability contract |
| Process transport | `pybench-op-v3` | Closed request/receipt wire contract; also used as the logical envelope for the R adapter |
| Scientific state | engine-declared scheme and schema digest | Bundle identities and durable object schemas; not versioned by packs |

These values are never substituted for one another. An ABI-v2 engine accepts a
pack only when the manifest declares the exact closed ABI interval
`minimum="2", maximum="2"`. Python packs must additionally declare the exact
closed process interval `pybench-op-v3` through `pybench-op-v3`. The engine's
own version must lie in the manifest's half-open package-version interval
`[minimum, maximum_exclusive)` under the engine's package-version comparator.
Invalid or empty ranges fail before registration.

ABI v1 (`scworkbench.operation_pack.v1`, protocol `1`) remains a separate
activation route with its existing identities and capabilities. There is no
implicit v1-to-v2 upgrade, fallback, cross-registration, or identity rewrite.

## 2. Canonical JSON and identities

ABI v2 reuses exactly
`scworkbench.operation_pack.canonical_json.v1`; it does not fork that byte
contract. Canonical output is UTF-8 with no BOM, insignificant whitespace, or
trailing newline. Object keys sort by unsigned UTF-8 bytes; array order is
preserved; duplicate keys and invalid UTF-8 fail. Strings and the restricted
decimal domain follow `inst/protocol/operation-pack-canonical-json-v1.md`.
Notably, `1`, `1.0`, and `1e0` all encode as `1e0`, and negative zero encodes
as `0`. SHA-256 is lowercase hexadecimal over the exact canonical bytes.

Definitions are structurally normalized before hashing: required defaults are
inserted; absent optional maps become empty maps; object order is irrelevant;
declared arrays retain semantic order. Runtime-derived fields, local paths,
registration order, and internal cached digests are excluded. Identity is
therefore independent of installation and activation order.

The manifest does not contain a digest of itself or of its enclosing
distribution. Core computes `manifest_source_sha256` from the original bytes,
the normalized manifest identity from normalized content, every operation
definition identity from its normalized definition, and pack/distribution
content identity from the installed artifact. These derived values enter
activation, request and receipt records, avoiding recursive self-hashes.

The following domains have frozen names and separately stored SHA-256 values; a
digest from one domain cannot satisfy another:

| Domain | Scheme/scope |
|---|---|
| Original installed manifest bytes | `scworkbench.operation_pack.manifest_source.bytes.v1` over exact bytes |
| Normalized manifest | `scworkbench.operation_pack.manifest.v2` over normalized manifest |
| Normalized operation definition | `scworkbench.operation_pack.definition.v2` over one normalized operation |
| Installed pack/distribution content | `scworkbench.operation_pack.content.v1` over the core-defined sorted relative-file manifest |
| Dependency requirement set | `scworkbench.operation_pack.dependencies.v2` |
| Preflight result | `scworkbench.operation_pack.preflight.v2` |
| Resolved input set | `scworkbench.operation_pack.inputs.v2`; individual objects retain their core scientific-content schemes |
| Capability | `scworkbench.operation_pack.capability.v2` |
| Request | `scworkbench.operation_pack.transition_request.v2`, excluding `request_identity` |
| Output payload/metadata | core kind-specific content scheme plus `scworkbench.operation_pack.payload_manifest.v2` and `scworkbench.operation_pack.semantic_metadata.v2` |
| Mutation audit | `scworkbench.operation_pack.mutation_manifest.v2` |
| Runtime | `scworkbench.operation_pack.runtime.v2` |
| Receipt | `scworkbench.operation_pack.transition_receipt.v2`, excluding `receipt_identity` |

The pack identity is SHA-256 of canonical
`{scheme:"scworkbench.operation_pack.pack.v2",manifest_sha256,namespace,package,backend,entry_point,operation_definition_sha256,pack_content_sha256}`;
`operation_definition_sha256` is an object keyed by fully qualified operation
name. The normalized manifest digest includes all declared content but no
derived digest. The definition digest includes one operation definition but no
derived digest. Requirement, preflight, input-set, capability, request,
payload-manifest, semantic-metadata, mutation, runtime and receipt digests each
cover their complete closed object, excluding only their own identity member
where the schema names that exclusion.

Python discovery MUST authenticate the original installed manifest source
bytes, not an R-reserialized temporary copy. Both the source digest and the
normalized manifest identity bind activation. A mismatch fails before any
handler or catalog row is registered and leaves catalog state unchanged.

## 3. Manifest and declared outputs

The proposed closed manifest schema is
`notes/operation_pack_abi_v2_manifest.schema.proposed.json`. Unknown fields are
rejected at every closed contract object. The operation's fully qualified name,
definition digest, inputs, JSON parameter schema, operation-level dependencies,
outputs, promotion closure, and replay comparator are immutable definition
content.

Every declared output has exactly one category:

| Category | Meaning | Publication owner |
|---|---|---|
| `materialization` | Named matrix or space state that becomes a durable getter-visible registry entry | Core only |
| `terminal_artifact` | Promotable typed primitive or contained model | Core only |
| `core_registry_request` | Validated proposal for a core registry mutation, presently only cell-set admission | Core only |

All outputs in one `promotion_group` are a required atomic closure. The pack
cannot omit, rename, add, or independently publish siblings. Materializations
are not directly promotable; their declared terminal witnesses carry the
promotion/replay closure. Terminal outputs are directly promotable only as the
declared group closure.

Packs cannot introduce primitive kinds. ABI v2 recognizes `matrix`, `space`,
`space_2d`, `cell_vector`, `cell_vector_family`, `feature_table`, `obs_table`,
`model_ref`, `relation_family`, `path_2d_family`, and `space_path_family`, plus
the non-primitive request kind `cell_set_admission`.

## 4. Capability boundary and storage profiles

The core resolves typed inputs and allocates every output ID before dispatch.
The pack receives an opaque, single-use, lease-bound capability and named
readers/writers only. It receives no bundle root, SQLite path/connection,
registry handle, provenance handle, publication destination, or arbitrary file
writer. Canonical descriptors use stage-relative paths; the local stage root is
out-of-band and never enters identity or receipt content.

Frozen writer/profile pairs are:

| Writer | Permitted profile/kind |
|---|---|
| `write_matrix` | `matrix_ordinary_v1` or `matrix_backed_chunked_v1`; `matrix` |
| `write_space` | `space_dense_v1` or `space_file_backed_hdf5_v1`; `space` |
| `write_space_2d` | `space_2d_dense_v1`; `space_2d` |
| `write_model_ref` | `model_ref_contained_tree_v1`; `model_ref` |
| `write_terminal_primitive` | `terminal_primitive_v1`; existing non-path terminal primitives |
| `write_path_2d_family` | `path_2d_family_v1`; `path_2d_family` |
| `write_space_path_family` | `space_path_family_v1`; `space_path_family` |
| `request_cell_set_admission` | `cell_set_admission_v1`; cell-set proposal only |

Path-family serialization therefore **does require explicit typed writers**.
This closes containment, row-order, semantic-metadata, and payload-identity
auditing without inventing a new primitive. The writers must normalize rows by
the durable primitive's canonical key tuple and preserve original semantic
order as an explicit order identity where order is scientific.

Readers return immutable typed views plus dimensions, content identity,
cell/feature order identities, ancestry, payload identity, and (for models)
matrix/space linkage. The pack cannot replace these descriptors.

## 5. Request, receipt, and independent audit

The proposed request and receipt schemas are respectively:

- `notes/operation_pack_abi_v2_transition_request.schema.proposed.json`
- `notes/operation_pack_abi_v2_transition_receipt.schema.proposed.json`

The request binds transition/session/run/checkpoint generation; operation,
manifest, definition, and pack identities; scientific-state schema; reader and
writer APIs; preflight; all resolved inputs; effective parameters; the exact
output grants; and the single-use capability. Each cell- or feature-indexed
input carries the applicable order digest. Every input carries dimensions,
content identity, and ancestry; models additionally carry linkage and contained
payload identity.

A successful receipt is an exact set match to declared required outputs and
registry requests. Each staged output repeats its allocated ID, category, kind,
profile, content identity, dimensions, applicable order identities, ancestry,
model linkage, payload-manifest identity, and semantic-metadata identity. It
also binds the request, capability, preflight, complete mutation manifest, and
path-free runtime attestation. The core recomputes all claims from the private
stage; receipt assertion is never proof by itself.

An error receipt has no success outputs or mutation claims. It gives a stable
code, phase, retryability, redacted diagnostic, and whether runtime attestation
was established. Process death or a missing receipt is diagnosed by the core;
the absence of an error receipt never authorizes publication.

R and Python adapters create the same field set, canonical bytes, validation
sequence, and receipt semantics. The only permitted field-level differences in
the worked success receipts are `runtime_attestation.backend`,
`runtime_attestation.entry_point`, and the identities that genuinely derive
from different installed software. R may execute in-process, but it still uses
an isolated private stage and returns the same logical receipt before audit.

## 6. Dependencies and preflight

Dependencies are operation-level, not inferred from the ambient installation.
R package and normalized Python distribution names carry an explicit closed
version object, required/optional disposition, and non-mutating import probe.
Its `scheme` is exactly `r_package_version_constraint_v1` or
`pep440_specifier_v1`; `specifier` is a whitespace-free comma conjunction in
the named ecosystem grammar and its textual bytes are identity-bearing. System
libraries analogously use `core_system_version_constraint_v1`. An
optional dependency has a parameter selector; if selected it is required, and
if unselected its available/unavailable disposition is recorded but does not
fail execution. Where policy freezes an artifact, its approved content digest
is also required.

System dependencies use only the core allowlist:
`dynamic_library_symbol`, `executable_version`, or `pkg_config_version`.
Device requirements use `core_device_availability_v1`. Probes are isolated,
read-only, bounded, and run before dispatch. Preflight MUST NOT install,
download, resolve from the network, mutate an environment, or invoke a pack
supplied shell string. Network policy is `deny` throughout execution.

The canonical requirement set and complete dispositions form the preflight
identity. Required missing dependencies yield
`OPERATION_PACK_DEPENDENCY_MISSING`; incompatible installed versions or frozen
content yield `OPERATION_PACK_DEPENDENCY_INCOMPATIBLE`; failed system/device or
policy probes yield `OPERATION_PACK_PREFLIGHT_FAILED`. All occur before runner
dispatch and leave no stage residue.

## 7. Atomic transition

The normative lifecycle and recovery rules are in
`notes/operation_pack_abi_v2_state_machine.md`. In summary, the core prepares a
private generation, dispatches one capability, validates a closed receipt,
independently audits staged state, publishes all payloads/rows/provenance as one
journaled transition, reopens through a fresh getter handle, and only then
accepts the transition. No pack can commit or promote.

All failures before publication discard the generation. A publication failure
restores every created, replaced, deleted, or nested destination and all
registry/provenance preimages. Interrupted recovery recognizes one complete
commit by its transition marker and audited receipt identity or restores all;
it never chooses an arbitrary partial state. Reopen failure rolls back the
publication. Promotion is a later core-owned transaction; its failure restores
the recipient while retaining the valid staged transition for retry.

## 8. Promotion, reopen, inspection, and replay

Promotion expands a requested terminal to its manifest-declared closure and
publishes the entire closure and complete provenance/receipt set atomically.
Finalized reopen recomputes content, alignment, ancestry, model linkage,
payload containment, and receipt bindings through public getters. Recipient
validation applies the same laws.

Finalized outputs are self-describing core primitives. Inspection, validation,
certificate/provenance traversal, and getter loading MUST work without the
originating pack. Replay is different: it requires the exact recorded manifest,
definition, pack/distribution, ABI, dependencies, and compatible runtime.
Absent pack returns `OPERATION_PACK_REQUIRED`; substituted or incompatible
pack returns `OPERATION_PACK_INCOMPATIBLE`, both before staging.

## 9. Worked catalog coverage

These are non-executable specification fixtures. The schemas contain a complete
Python `scvi_train` request and matching receipts.

### R multi-output: `scwbrepresentation::pca_fit`

Core grants `write_space(space_pca, space_file_backed_hdf5_v1)` plus terminal
writers for `loadings`, `variance`, and `fit_summary`, all in one group. The R
adapter returns four staged descriptors. Audit verifies feature and cell order,
dimensions, exact terminal values, the space payload, and a mutation manifest;
publication and reopen expose all four or none.

### Python matrix/space/model: `scwblatent::scvi_train`

The request example grants a file-backed latent `space`, contained `model_ref`,
and `fit_summary`. The input matrix's feature and cell identities are bound.
PyBench may write only under the three relative roots. Core verifies the model
tree, latent order, matrix/model/space linkage, training summary, runtime and
dependency attestation, and exact mutation closure before atomic publication.

### Mixed materialization plus terminal: `scwbrna::matrix_log_normalize`

Core allocates a matrix materialization and summary terminal in one group.
`summary` is the materialization witness. Promotion of the summary carries the
matrix lineage; direct promotion of the matrix is not permitted. Ordinary and
backed matrix profiles are selected by the definition and request, never by an
undeclared runner choice.

### Core registry request: `scwbgeneprograms::winner_cell_sets`

The pack emits one `cell_set_admission` proposal per declared winner plus the
manifest terminal. Core validates names, exact membership, membership order,
duplicates, universe containment, allocated IDs, and exact proposal count. It
publishes admitted sets and the manifest together; the pack never touches the
cell-set registry.

### Terminal-only v1 coexistence

`scwbstatistics::cell_vector_assoc` remains eligible for v1 packaging while v2
exists. Its two terminals (`assoc_summary`, `group_stats`) keep their existing
definition and v1 pack identity. A future explicit v2 manifest would receive a
new v2 definition identity and cannot replace retained v1 history.
`cell_vector_assoc` and `cell_vector_association` are distinct operations:
their names, inputs, outputs, parameters, definitions, fixtures, and identities
remain separate. Neither is an alias for the other.

## 10. All 60 operations

The one-row-per-operation adjudication is
`notes/operation_pack_abi_v2_conformance_matrix.csv`.

- 11 `requires_v2_atomic_multi_output`: `matrix_log_normalize`, `pca_fit`,
  `umap_fit`, `slingshot_fit`, `slingshot_adopt`, `monocle3_fit`, `peakvi_fit`,
  `scvi_train`, `peakvi_project`, `model_bound_latent_union`, `palantir_fit`.
- One materialization-only case: `umap_transform` (its output is already a
  durable `space_2d` terminal; v2 supplies typed materialization staging and
  atomic publication, with no sibling registry mutation).
- One core-capability case: `winner_cell_sets`.
- Four retained core-only operations: `feature_set_import`,
  `feature_set_namespace_transfer`, `cell_set_derive`, and
  `metadata_cell_vector`. They are not pack candidates and do not consume ABI
  v2 capabilities.
- One conformance-only operation: `py_protocol_hello`; it is never a scientific
  migration candidate.
- 42 v1-shaped operations: no new capability is required, but extraction still
  requires an explicit pack, operation-level dependency/preflight declarations,
  equivalence fixtures, pack-free reopen, exact-pack replay, and missing-pack
  rejection.

The Phase 0 migration matrix has current anchors for 59 operations.
`knn_pseudobulk` has the sole `fixture_gap`; its migration is blocked until the
Phase 2 old-core/new-pack equivalence fixture exists. That is an implementation
gate, not an ABI design gap.

## 11. Error taxonomy and conformance

The closed receipt schema freezes the stable error codes. Detection ownership,
phase, zero-residue proof, and a future fixture are enumerated in the
conformance matrix. The required failure law is universal: a rejected
transition leaves the committed source/recipient, catalog, registry,
provenance, payload tree, active/head state, and published receipt set exactly
at their pre-transition identities; a consumed or abandoned private generation
may be removed.

Positive fixtures cover each writer/profile, R/Python parity, reordered-key
identity, atomic multi-output publication, cell-set admission, reopen,
promotion, replay, and pack-free inspection. Adversarial fixtures cover types,
alignment/order/dimensions/ancestry, missing/incompatible software, containment,
undeclared mutations/outputs, receipts, process death at every boundary,
partial writes, model linkage, reopen/promotion failure, and replay mismatch.

## 12. Implementation sequencing (not activation)

1. Freeze the three proposed JSON schemas and cross-language fixtures after
   Sable audit.
2. Implement core request/capability/audit/publication first, behind no public
   activation.
3. Implement matching R and PyBench v3 adapters and run the conformance corpus.
4. Add v1/v2 coexistence and history tests before any pack extraction.
5. Migrate one low-risk terminal-only operation, then each special capability
   class; never bulk-migrate merely because a pack exists.

No schema or migration issue remains open in this proposal. Per-operation
dependency minimums and missing equivalence fixtures are intentionally future
implementation evidence and must be resolved before the affected pack ships.
