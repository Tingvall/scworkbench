# Operation-pack ABI v2 Forge handoff — Sable Amendment 01

READY FOR SABLE RE-AUDIT

Status: **PROPOSED, NON-RUNTIME PLANNING ARTIFACT**.

## Checkpoints and scope

- Branch: `feat/operation-pack-abi-v2-spec-forge-20260914`
- Rejected parent: `1765efef290968a1aaf53e821ce09514471ecd5f`
- Accepted Phase 0 base: `368c864126b2e60880a81fab8dc0abbd34cf27a9`
- Amendment specification commit: `d4ea4bc8819fbb707f83bec780c0626308c40c03`
- Quill specification: `eb5334a7bec73490ccfbf106f83ba91b1ab39fb8`
- Quill handoff: `8f73acebe833606e5d733988cb3d253720fcd333`
- Sable audit: `f05ce0923d2b9bfbd7cfd8447208a674fb21319a`
- This handoff's closure commit is reported externally because a commit cannot
  contain its own identity.
- Remote action: none. The work order prohibits push, merge and tag actions.

The diff from the Phase 0 base remains exactly the authorized eight planning
records:

1. `notes/operation_pack_abi_v2_specification.md`
2. `notes/operation_pack_abi_v2_manifest.schema.proposed.json`
3. `notes/operation_pack_abi_v2_transition_request.schema.proposed.json`
4. `notes/operation_pack_abi_v2_transition_receipt.schema.proposed.json`
5. `notes/operation_pack_abi_v2_state_machine.md`
6. `notes/operation_pack_abi_v2_v1_compatibility.md`
7. `notes/operation_pack_abi_v2_conformance_matrix.csv`
8. `notes/operation_pack_abi_v2_handoff.md`

No R/Python implementation, live protocol, test, package metadata, scientific
operation, bundle, evidence, manuscript, container or SIF changed.

## Sable findings closed

1. The manifest now has one closed, language-neutral
   `dynamic_input_metadata_package` dependency. Core binds the operation input,
   retained input identity, metadata field/value, ecosystem, syntax, allowlisted
   probe, required disposition, installed name/version/artifact and probe
   evidence into request, selected requirements, preflight, capability, runtime
   and receipt identities. It rereads the retained field immediately before
   dispatch. Missing, empty, malformed, unavailable and changed values fail
   offline before analytical execution. `chromvar` restores
   `dynamic_R_runtime_packages` and all four accepted anchors. hg19/mm10 1.4.3
   remain observations, not an allowlist, default or minimum.
2. Request inputs, output grants and receipt outputs are closed type-specific
   descriptor branches. Legal kind/profile/reader-or-writer pairs and applicable
   dimensions, alignment, cell/feature/row order, ancestry, model linkage,
   containment and semantic constraints are inside the canonical wire objects.
   Capability authentication binds pack, distribution, original manifest source,
   definition, entry point and every named reader/writer grant. C01–C14 enumerate
   all additional cross-field identity checks with one fault row each.
3. The Python `scvi_train` request, capability and successful receipt contain
   exactly `space`, `model` and `fit_summary`; the error receipt has no output or
   mutation claims. All self-identities were recomputed from canonical bytes.
   The R `chromvar` fixture is explicitly backend-specific; no cross-backend
   receipt-identity equality is claimed.
4. Dependencies have one owner: each operation's complete declaration. The root
   dependency array was removed. Identical duplicates are structurally rejected;
   conflicting IDs, undeclared selected requirements and ambient augmentation
   are normative C09/C14 failures.
5. The validation record names and invokes the actual canonical identity test,
   separately from the catalog semantic test.

## Schema and reconciliation counts

- Positive schema examples: manifest 1, request 2, receipt 3 (6 total).
- Negative schema recipes: manifest 5, request 15, receipt 8 (28 total).
- Closed descriptor branches: input 11 (13 valid profile tuples), request output
  15, receipt output 14.
- Exhaustive invalid tuples rejected: input 680, request output 2,865, receipt
  output 1,372.
- Missing branch-required fields rejected: input 119, request output 181,
  receipt output 213.
- Ledger: 60 unique operation rows, 71 unique fault rows, 6 dynamic-provider
  cases and 14 semantic-rule rows. Original F001–F050 are field-for-field
  identical to the rejected parent; F051–F071 are Sable Amendment 01 additions.
- Operation classifications remain 42 / 11 / 1 / 1 / 4 / 1:
  `v1_ready_with_packaging_work`, `requires_v2_atomic_multi_output`,
  `requires_v2_materialization`, `requires_core_capability`, `core_only`, and
  `conformance_only` respectively.

The `chromvar` operation row includes its twelve fixed R-package observations,
the open-ended dynamic provider contract, and `R/op_chromvar.R`, `DESCRIPTION`,
`containers/apptainer/fullstack_r_dependencies.dcf`, and
`containers/apptainer/fullstack_r_versions.lock.csv` in addition to its normal
core anchors.

## Computed worked identities

All 30 nested/top-level self-identities in the two requests and three receipts
were independently recomputed by pinned PyBench and scworkbench canonical JSON
v1 implementations.

| Fixture identity | SHA-256 |
|---|---|
| scvi transition | `7d6e84475b85cf91e7a4dee48fd458e685ae6ce3cf0a767e4bd5b36c07a2cf90` |
| scvi capability | `6a6d11ca1663a0a1b1fc14bd284515498492506f1d51fb7bd47116ba4392112c` |
| scvi request | `82fbd44723826be1749d837ff29a7c6f9e15b3d4d878357c9c5e960460865934` |
| scvi matrix input descriptor | `4b287bcd40b986eaf56b140b0e9c5d99c95f0082969f6a68ab7f9aae0e2b8af8` |
| scvi space grant | `262af4e44f835b3688312ca60eea8c6325a3911b018b81fba770a56f2f4c6162` |
| scvi model grant | `ed00d69110cb798ec4d2b5ee60c4edc3b10c54c9d11c6fdadd63d68d6f984e0c` |
| scvi fit-summary grant | `a5a5ce9dd403643219de064302c7a00517d25fb50ab89cf16303085b47648fc2` |
| scvi success receipt | `2c4a2ecfd258de228b3ab63fc0bb6ae865906aaf7224426e08f96be45d91767c` |
| scvi error receipt | `dacd86e9474b05c482a780bbeb2cb4ed48694ea11c73c6be6f9252183b45a82e` |
| chromvar transition | `2a4675dde0fe265edaae65789446147a2d66e22dc142831f722d2fe216ef1489` |
| chromvar capability | `8c696fe80ec094f0d4d24411d37f46a01d55884f7159a3032fc7237a300d4e87` |
| chromvar request | `2b1f597614f59e082af94e4472bc6da2fd432e4da056c6b68a2f7fe7ad90f761` |
| chromvar dynamic resolution | `8f98ac1a30f79bea6e9848ef6c6515a5aab8aa8c233e57478cbad3584f3d82cd` |
| chromvar success receipt | `c9bf84f11ab81e26c5a791c5509ae7e7431b1eeff7e91673ef69b66b43eb62a8` |

## Literal validation record

Pinned validator:
`/home/dirk/Projects/pybench/.venv/bin/python`, Python 3.11.0rc1,
`jsonschema 4.26.0`, native `Draft202012Validator`. No Draft-7 projection,
installation or network access was used.

Python `json` plus `Draft202012Validator.check_schema` and example validation:

```text
PASS manifest: Draft2020 self-check; positive=1; concrete_negative=5; exhaustive_recipes=0
PASS transition_request: Draft2020 self-check; positive=2; concrete_negative=11; exhaustive_recipes=4
PASS transition_receipt: Draft2020 self-check; positive=3; concrete_negative=5; exhaustive_recipes=3
PASS manifest: R selector rejects Python name/probe pairing
PASS transition_request: R selector rejects Python name/probe pairing
PASS transition_receipt: R selector rejects Python name/probe pairing
```

Exhaustive closed-branch probes:

```text
PASS output_descriptor: allowed=15; all_invalid_cross_products_rejected=2865; all_missing_required_bindings_rejected=181; branches=15
PASS input_descriptor: allowed=13; all_invalid_cross_products_rejected=680; all_missing_required_bindings_rejected=119; branches=11
PASS observed_output_descriptor: allowed=14; all_invalid_cross_products_rejected=1372; all_missing_required_bindings_rejected=213; branches=14
```

Dynamic dependency, dependency ownership and cross-field example checks:

```text
PASS dynamic provider cases: available=success; unavailable=OPERATION_PACK_DEPENDENCY_MISSING; missing=OPERATION_PACK_DYNAMIC_PROVIDER_INVALID; empty=OPERATION_PACK_DYNAMIC_PROVIDER_INVALID; malformed=OPERATION_PACK_DYNAMIC_PROVIDER_INVALID; changed=OPERATION_PACK_DYNAMIC_PROVIDER_CHANGED; failure_dispatches=0
PASS dependency ownership conflicting_duplicate: duplicate_or_conflicting_declaration
PASS dependency ownership undeclared_selected: undeclared_or_missing_requirement
PASS dependency ownership missing_selected: undeclared_or_missing_requirement
PASS dependency ownership valid exact operation-level set; pack/ambient augmentation forbidden
PASS cross-field examples: authentication, capability grant closure, exact receipt closure, runtime attestation
PASS error receipt closure: outputs=0; mutation_claims=0
PASS scvi_train closure: requested=3 granted=3 returned=3 extras=0 names=fit_summary,model,space
```

Independent identity and parser checks:

```text
PASS Python canonical self-identities: verified=30
PASS R canonical self-identities: verified=30
PASS R JSON parse: notes/operation_pack_abi_v2_manifest.schema.proposed.json
PASS R JSON parse: notes/operation_pack_abi_v2_transition_request.schema.proposed.json
PASS R JSON parse: notes/operation_pack_abi_v2_transition_receipt.schema.proposed.json
```

Reconciliation and path checks:

```text
PASS conformance ledger: operations=60; conformance_only=1, core_only=4, requires_core_capability=1, requires_v2_atomic_multi_output=11, requires_v2_materialization=1, v1_ready_with_packaging_work=42
PASS conformance ledger: original_Quill_faults=50 field-for-field preserved; amendment_faults=21; total_faults=71; dynamic_provider_cases=6; semantic_rules=14
PASS cited path resolution: unique_local_paths=71; missing=0
```

Actual focused R command:

```r
devtools::load_all('.', quiet=TRUE)
source('tests/test_operation_pack_canonical_identity_contract.R', local=.GlobalEnv)
stopifnot(isTRUE(test_operation_pack_canonical_json_v1_contract()))
source('tests/test_op_catalog_semantic_contract.R', local=.GlobalEnv)
stopifnot(isTRUE(test_op_catalog_semantic_contract()))
```

Result:

```text
PASS tests/test_operation_pack_canonical_identity_contract.R::test_operation_pack_canonical_json_v1_contract
PASS tests/test_op_catalog_semantic_contract.R::test_op_catalog_semantic_contract
```

Accepted live v1 protocol bytes remain unchanged and byte-identical to Quill:

```text
39112be67f3d022725d8dc57a569d7bfd94ea0242f1421be4d2d479be56795bb  inst/protocol/operation-pack-v1.schema.json
7fa992ab7dcb8b07f9d75621b4a5eb27cd29c21edac33ad962e6c1393999361e  inst/protocol/operation-pack-canonical-json-v1.md
d5e80b58e4f18b37d0e906e7dac127fd17fbb88ea56dd83926406691303b655b  inst/protocol/pybench-op-v2.schema.json
PASS v1 protocol bytes: 3/3 unchanged and cross-repository byte-identical
```

Final closure also passed `git diff --check`, the exact eight-file allowlist
from Phase 0, and clean-worktree verification after the containing commit.

## Re-audit boundary

Sable should re-audit only these planning records against findings 1–5.
Implementation, live protocol activation, operation migration, pack creation,
scientific qualification and Meridian-9 review remain later authorized phases.
