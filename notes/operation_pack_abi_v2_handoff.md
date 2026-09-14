# Operation-pack ABI v2 Forge handoff — Meridian-9 Amendment 03

READY FOR MERIDIAN-9 RE-AUDIT

Status: **PROPOSED, NON-RUNTIME PLANNING ARTIFACT**.

## Checkpoints and scope

- Branch: `feat/operation-pack-abi-v2-spec-forge-20260914`
- Required parent: `385860ff591de57ef59939a3aa62d2b811201c2e`
- Amendment 03 specification commit: `4e4e43b065a90d9b077292e7c4ca2f4113ddf3be`
- Phase 0 base: `368c864126b2e60880a81fab8dc0abbd34cf27a9`
- Quill specification: `eb5334a7bec73490ccfbf106f83ba91b1ab39fb8`
- Quill handoff: `8f73acebe833606e5d733988cb3d253720fcd333`
- Meridian-9 audited target: `385860ff591de57ef59939a3aa62d2b811201c2e`
- The closure commit containing this handoff is reported externally because a
  commit cannot contain its own identity.
- Remote action: none. Push, merge, tag and publication are prohibited.

Amendment 03 changes the specification, state-machine note, v1-compatibility
note, manifest schema annotations/examples/recipes, conformance ledger and this
handoff. The complete Phase 0-to-descendant diff remains inside the original
eight planning records. No implementation, live protocol, tests, package
metadata, scientific operation, bundle, evidence, manuscript, container, SIF
or release artifact changed.

## Normative admission closure

The language-neutral semantic contract is
`scworkbench.operation_pack.manifest_semantic_admission.v1`. Activation now has
one mandatory order before any live handler, operation, alias or catalog row is
installed:

1. strict parse of original bytes, including duplicate-object-key rejection;
2. native Draft 2020-12 outer-manifest validation;
3. deterministic relational semantic admission;
4. embedded parameter-schema dialect/meta-schema/profile validation;
5. normalization and manifest/definition/pack identity computation;
6. distribution, original-source and entry-point authentication;
7. complete private candidate-catalog construction;
8. one atomic candidate-catalog/handler publication.

Stages 1–7 cannot mutate live catalog state. A stage-8 failure restores the
serialized handler, operation, alias and lookup-index preimages. Phase 2 must
capture those identities before every injected failure and prove exact equality,
absence of every candidate name/handler, unchanged old lookups, and no valid
prefix registration from a multi-operation pack.

The contract names 15 stable admission/pipeline error codes. The nine mandatory
mutations use eight distinct deterministic codes because both qualified-name
mutations correctly share
`OPERATION_PACK_MANIFEST_QUALIFIED_NAME_MISMATCH`. Detection follows pipeline
stage, manifest operation order and rule order; reported name sets are
ASCII-byte sorted, never map-iteration ordered.

## Relational rules

- `qualified_name` is exactly `manifest.namespace + "::" + operation.name`.
  Short and qualified operation names are independently unique.
- Input names, output names, allocation keys, dependency IDs and every other
  identity-bearing name-keyed collection are unique in their scope. There is no
  shared allocation exception.
- Promotion-closure keys are terminal-output names, never group names. Every
  terminal is exactly one key whose sorted member list is the complete set of
  outputs in its `promotion_group`. Every group has a terminal witness;
  materializations and registry requests are members, never keys. A
  materialization's `materialized_by_terminals` is the exact sorted terminal set
  for its group.
- Replay keys are exactly the output-name set. Policy validity is closed by
  category/kind: ordinary scientific values use `exact_canonical_value`, 2D
  spaces may use `cell_aligned_embedding`, models use `loadable_reference`, and
  cell-set admissions use `exact_membership_and_order`. `not_comparable` is
  reserved but inadmissible for every current promotable v2 output.
- Strict parsing and semantic admission reject raw or normalized duplicate
  logical keys; invalid definitions never reach identity computation.

The manifest now commits two positive examples: the retained one-operation
`chromvar` example and a valid two-operation example with distinct names,
inputs, outputs, allocation keys, promotion groups, replay maps and three total
outputs. Both publish atomically in the temporary admission harness.

## Parameter-schema contract

- Dialect: exact `https://json-schema.org/draft/2020-12/schema`.
- Profile:
  `scworkbench.operation_pack.params_schema.draft2020_12_closed_v1`.
- An absent root `$schema` means that exact dialect, remains absent in canonical
  identity bytes, and never invokes dialect guessing.
- An explicit root `$schema` must equal the frozen URI.
- Each object-root schema passes native Draft 2020-12 meta-validation, then a
  recursive closed keyword profile. Nested boolean schemas are supported.
- Only local `#/$defs/...` references are allowed. Remote refs, nested dialects,
  unknown keywords, unsupported format/pattern engines, invalid defaults and
  duplicate `required` names fail before identity computation.

Python performed native Draft 2020-12 meta-validation and the closed-profile
check. The independent R path parsed the identical manifest and applied the
same frozen dialect/profile meta-rules to all three committed embedded schemas.
No package installation or network access occurred.

## Mandatory mutation disposition

| Recipe | Stage | Stable result |
|---|---|---|
| `SEM-QUALIFIED-NAMESPACE-MISMATCH` | semantic admission | `OPERATION_PACK_MANIFEST_QUALIFIED_NAME_MISMATCH` |
| `SEM-QUALIFIED-SUFFIX-MISMATCH` | semantic admission | `OPERATION_PACK_MANIFEST_QUALIFIED_NAME_MISMATCH` |
| `SEM-DUPLICATE-OPERATION` | semantic admission | `OPERATION_PACK_MANIFEST_OPERATION_DUPLICATE` |
| `SEM-DUPLICATE-INPUT` | semantic admission | `OPERATION_PACK_MANIFEST_INPUT_DUPLICATE` |
| `SEM-DUPLICATE-OUTPUT` | semantic admission | `OPERATION_PACK_MANIFEST_OUTPUT_DUPLICATE` |
| `SEM-DUPLICATE-ALLOCATED-ID-KEY` | semantic admission | `OPERATION_PACK_MANIFEST_ALLOCATION_KEY_DUPLICATE` |
| `SEM-PROMOTION-GHOST` | semantic admission | `OPERATION_PACK_MANIFEST_PROMOTION_CLOSURE_INVALID` |
| `SEM-REPLAY-GHOST` | semantic admission | `OPERATION_PACK_MANIFEST_REPLAY_EQUIVALENCE_INVALID` |
| `SEM-PARAM-SCHEMA-INVALID` | parameter schema | `OPERATION_PACK_PARAM_SCHEMA_INVALID` |

All nine outer-schema-valid mutations failed before candidate publication with
zero simulated catalog/handler residue. F079–F087 and C15–C23 record these cases,
their detector, code, phase and Phase 2 preimage assertions.

## Counts and preserved contracts

- Outer positive examples: manifest 2, request 2, receipt 3 (7 total).
- Structural negative recipes: manifest 12, request 15, receipt 8 (35 total;
  24 concrete and 11 exhaustive).
- Semantic manifest recipes: 9/9 rejected.
- Manifest/request tuple equality remains exact: 11 input and 15 output tuples.
- Exhaustive invalid manifest tuples remain rejected: 66 input and 345 output.
- Required-field removals remain rejected: 44 input and 105 output.
- Ledger: 60 unique operations, 87 unique faults, 6 dynamic-provider cases and
  23 semantic rules. F001–F078 and C01–C14 are field-identical to the required
  parent; F079–F087 and C15–C23 are the only additions. Classifications remain
  42 / 11 / 1 / 1 / 4 / 1.
- All prior Sable closures remain intact: dynamic `chromvar`, typed request and
  receipt descriptors, scVI three-output closure, operation-owned dependencies,
  tuple equivalence and correct focused-test names.

The complete ledger path rule splits the `positive_fixture`,
`adversarial_fixture`, and `source_anchor` fields on semicolons, removes empty
values and every value beginning `future:`, and deduplicates the rest. It yields
120 unique paths; all 120 resolve against the pinned scworkbench or Quill
worktree.

## Identity results

The request and receipt schemas/examples are byte-identical to Amendment 02,
and their 30 self-identities still recompute independently in Python and R. The
existing `chromvar` manifest example is unchanged. Canonical fixture hashes for
the two valid manifests and their definitions agree across languages:

```text
921228acccc7d7e5cd851fbe24678c9a9698dad617cd9d865aa332f79f21f36a  manifest[0]
5072fbdffb10673ee89e38c433ebb04d956d5930b56d11ddafc086cffdb6647e  manifest[0].chromvar
348c724e1494ba31470145dd115879bc9ae13b1c2a82e7189d8e92099f816d83  manifest[1]
22e2d011c8ae32a25f0f68a9d5cc0eac9872ff2b78bb40cee68845772bca8bdf  manifest[1].normalize
d6953d8277da79b5c63d65d8406cc747e6a3c4bfbb793aa6d49169a2d14dbc9e  manifest[1].cluster
```

Proposed schema file digests:

```text
1d4858dfd5cbdfd681ecfe07e119cc8f652b10116a42a88ee6fa832ec760e481  notes/operation_pack_abi_v2_manifest.schema.proposed.json
0a14ad57ed8c48c16e9300355c31f7f1dd8cd2e82cf3c1998975a1c12ac2b61d  notes/operation_pack_abi_v2_transition_request.schema.proposed.json
8baba38a83eb3e5cc3ed0eb3628288a18deff7fc0f1b27e0c67fcb2686d228ad  notes/operation_pack_abi_v2_transition_receipt.schema.proposed.json
```

## Literal validation results

Native outer-schema and tuple validation:

```text
PASS outer manifest: Draft2020 positive=2 concrete_negative=8 exhaustive_recipes=4
PASS outer transition_request: Draft2020 positive=2 concrete_negative=11 exhaustive_recipes=4
PASS outer transition_receipt: Draft2020 positive=3 concrete_negative=5 exhaustive_recipes=3
PASS tuple equality: manifest/request input=11 output=15 projections exact
PASS manifest input: legal=11 invalid=66 missing_required=44 unknown_branch=11
PASS manifest output: legal=15 invalid=345 missing_required=105 unknown_branch=15
```

Temporary untracked Python admission harness:

```sh
PYTHONPATH=/home/dirk/Projects/.pybench-worktrees/operation-pack-abi-v2-python-spec-quill-20260914/src \
  /home/dirk/Projects/pybench/.venv/bin/python \
  /tmp/forge_operation_pack_abi_v2_amendment03_validate.py \
  /home/dirk/Projects/.scworkbench-worktrees/operation-pack-abi-v2-spec-forge-20260914
```

Result:

```text
PASS positive manifest 0: operations=1 outputs=1 atomic_publish=1
PASS positive manifest 1: operations=2 outputs=3 atomic_publish=1
PASS semantic rejection SEM-QUALIFIED-NAMESPACE-MISMATCH: stage=semantic_admission code=OPERATION_PACK_MANIFEST_QUALIFIED_NAME_MISMATCH catalog_residue=0 handler_residue=0
PASS semantic rejection SEM-QUALIFIED-SUFFIX-MISMATCH: stage=semantic_admission code=OPERATION_PACK_MANIFEST_QUALIFIED_NAME_MISMATCH catalog_residue=0 handler_residue=0
PASS semantic rejection SEM-DUPLICATE-OPERATION: stage=semantic_admission code=OPERATION_PACK_MANIFEST_OPERATION_DUPLICATE catalog_residue=0 handler_residue=0
PASS semantic rejection SEM-DUPLICATE-INPUT: stage=semantic_admission code=OPERATION_PACK_MANIFEST_INPUT_DUPLICATE catalog_residue=0 handler_residue=0
PASS semantic rejection SEM-DUPLICATE-OUTPUT: stage=semantic_admission code=OPERATION_PACK_MANIFEST_OUTPUT_DUPLICATE catalog_residue=0 handler_residue=0
PASS semantic rejection SEM-DUPLICATE-ALLOCATED-ID-KEY: stage=semantic_admission code=OPERATION_PACK_MANIFEST_ALLOCATION_KEY_DUPLICATE catalog_residue=0 handler_residue=0
PASS semantic rejection SEM-PROMOTION-GHOST: stage=semantic_admission code=OPERATION_PACK_MANIFEST_PROMOTION_CLOSURE_INVALID catalog_residue=0 handler_residue=0
PASS semantic rejection SEM-REPLAY-GHOST: stage=semantic_admission code=OPERATION_PACK_MANIFEST_REPLAY_EQUIVALENCE_INVALID catalog_residue=0 handler_residue=0
PASS semantic rejection SEM-PARAM-SCHEMA-INVALID: stage=parameter_schema code=OPERATION_PACK_PARAM_SCHEMA_INVALID catalog_residue=0 handler_residue=0
PASS parameter-schema rejection: OPERATION_PACK_PARAM_SCHEMA_DIALECT_UNSUPPORTED
PASS parameter-schema rejection: OPERATION_PACK_PARAM_SCHEMA_PROFILE_UNSUPPORTED
PASS normative semantic admission harness: contract=scworkbench.operation_pack.manifest_semantic_admission.v1 profile=scworkbench.operation_pack.params_schema.draft2020_12_closed_v1 invalid=9 residue=0
```

R parameter-profile command and result:

```sh
Rscript /tmp/forge_operation_pack_abi_v2_amendment03_params.R \
  /home/dirk/Projects/.scworkbench-worktrees/operation-pack-abi-v2-spec-forge-20260914
```

```text
PASS R frozen parameter-schema dialect/profile meta-validation: examples=3 explicit_dialect=1 absent_dialect=2
PASS R invalid embedded parameter schema rejection: OPERATION_PACK_PARAM_SCHEMA_INVALID
```

The actual focused R contracts passed:

```text
PASS tests/test_operation_pack_canonical_identity_contract.R::test_operation_pack_canonical_json_v1_contract
PASS tests/test_op_catalog_semantic_contract.R::test_op_catalog_semantic_contract
```

V1 floor inspection confirmed namespace, operation/input uniqueness, promotable
membership, replay coverage and private registration. Accepted live protocol
bytes remain unchanged and byte-identical to Quill:

```text
39112be67f3d022725d8dc57a569d7bfd94ea0242f1421be4d2d479be56795bb  inst/protocol/operation-pack-v1.schema.json
7fa992ab7dcb8b07f9d75621b4a5eb27cd29c21edac33ad962e6c1393999361e  inst/protocol/operation-pack-canonical-json-v1.md
d5e80b58e4f18b37d0e906e7dac127fd17fbb88ea56dd83926406691303b655b  inst/protocol/pybench-op-v2.schema.json
```

Final `git diff --check`, eight-file maximum allowlist and clean-worktree checks
passed on the closure commit.

## Routing

Return this descendant directly to Meridian-9 for focused re-audit. Phase 2,
implementation, operation migration, pack repositories and runtime
qualification remain unauthorized until the complete Phase 1 specification is
accepted.
