# Operation-pack ABI v2 Forge handoff — Sable Amendment 02

READY FOR SABLE RE-AUDIT

Status: **PROPOSED, NON-RUNTIME PLANNING ARTIFACT**.

## Checkpoints and scope

- Branch: `feat/operation-pack-abi-v2-spec-forge-20260914`
- Amendment 02 parent: `a1e989b5fb155315918882f559b196b3358c9597`
- Amendment 02 specification commit: `02a620a11f5bcdd2c80b48aa1054698b544ba95e`
- Exact Phase 0 base: `368c864126b2e60880a81fab8dc0abbd34cf27a9`
- Quill specification: `eb5334a7bec73490ccfbf106f83ba91b1ab39fb8`
- Quill handoff: `8f73acebe833606e5d733988cb3d253720fcd333`
- First Sable audit: `f05ce0923d2b9bfbd7cfd8447208a674fb21319a`
- Focused Sable re-audit: `be23f800428dda93dbc0e4d6d963f8ee5f786e99`
- The closure commit containing this handoff is reported externally because a
  commit cannot contain its own identity.
- Remote action: none. Push, merge and tag are prohibited by the work order.

Amendment 02 changes the manifest schema, specification, state-machine note,
conformance ledger and this handoff. The complete Phase 0-to-descendant diff
remains inside the original eight-file planning allowlist. No implementation,
live protocol, test, package metadata, operation, bundle, evidence, manuscript,
container, SIF or release artifact changed.

## Blocking correction closed

Manifest inputs are now 11 closed discriminated branches. Primitive kind fixes
its declaration alignment. Manifest outputs are now 15 closed discriminated
branches. Category, primitive kind and storage profile jointly fix one legal
shape; the three categories are disjoint, and branch-local
`additionalProperties: false` rejects unknown fields before registration.

The mechanical equivalence projection is explicit:

- Request input profile, reader and observed identity/value fields are
  request-only and are projected out. Manifest and request then expose the same
  11 `(kind, alignment)` tuples.
- Request output writer, relative staging root, allocated ID, expected
  dimensions/order, ancestry/linkage, semantic constraints and grant identity
  are request-only and are projected out. Manifest and request then expose the
  same 15 `(category, kind, storage_profile)` tuples. Each tuple maps to exactly
  one sanctioned request writer.
- Manifest names, requiredness, allocated-ID key, promotion group and applicable
  declaration semantics remain identity-bearing definition fields rather than
  tuple dimensions. They are admitted only on their applicable closed branch.

Consequently, the three exact Sable probes now fail native Draft 2020-12
validation before handler or catalog registration:

1. `matrix` input with `alignment="none"`;
2. `materialization + model_ref + terminal_primitive_v1`;
3. `terminal_artifact + matrix + matrix_ordinary_v1`.

Manifest negative recipes now include those probes, exhaustive invalid input
and output tuple enumeration, and required-field removal for every branch.
Fault rows F072–F078 bind the same seven cases to stable pre-registration,
zero-residue outcomes.

## Counts and reconciliation

- Manifest inputs: 11 legal tuples, 66 invalid closed-enum combinations.
- Manifest outputs: 15 legal tuples, 345 invalid closed-enum combinations.
- Required-field removals rejected: 44 input and 105 output cases.
- Unknown-property probes rejected: all 11 input and all 15 output branches.
- Positive schema examples: manifest 1, request 2, receipt 3 (6 total).
- Negative schema recipes: manifest 12, request 15, receipt 8 (35 total;
  24 concrete mutations and 11 exhaustive recipes).
- Ledger: 60 unique operations, 78 unique faults, 6 dynamic-provider cases and
  C01–C14. F001–F071 are field-for-field identical to Amendment 01; F072–F078
  are the seven Amendment 02 additions. Classifications remain
  42 / 11 / 1 / 1 / 4 / 1.

The complete path count uses only semicolon-delimited non-empty values from the
ledger's `positive_fixture`, `adversarial_fixture`, and `source_anchor` fields;
every value beginning `future:` is excluded. The amended ledger contains 120
unique counted paths, and all 120 resolve against the pinned scworkbench or
Quill worktree.

## Identity disposition

The manifest example data is byte-semantically unchanged; only its registration
schema and negative recipes changed. The request and receipt schema files are
byte-identical to Amendment 01. Therefore no worked manifest definition or
dependent identity changed. Both pinned canonicalizers independently
recomputed all 30 request/receipt self-identities without mismatch, including:

| Identity | SHA-256 |
|---|---|
| scvi transition | `7d6e84475b85cf91e7a4dee48fd458e685ae6ce3cf0a767e4bd5b36c07a2cf90` |
| scvi capability | `6a6d11ca1663a0a1b1fc14bd284515498492506f1d51fb7bd47116ba4392112c` |
| scvi request | `82fbd44723826be1749d837ff29a7c6f9e15b3d4d878357c9c5e960460865934` |
| scvi success receipt | `2c4a2ecfd258de228b3ab63fc0bb6ae865906aaf7224426e08f96be45d91767c` |
| scvi error receipt | `dacd86e9474b05c482a780bbeb2cb4ed48694ea11c73c6be6f9252183b45a82e` |
| chromvar transition | `2a4675dde0fe265edaae65789446147a2d66e22dc142831f722d2fe216ef1489` |
| chromvar capability | `8c696fe80ec094f0d4d24411d37f46a01d55884f7159a3032fc7237a300d4e87` |
| chromvar request | `2b1f597614f59e082af94e4472bc6da2fd432e4da056c6b68a2f7fe7ad90f761` |
| chromvar success receipt | `c9bf84f11ab81e26c5a791c5509ae7e7431b1eeff7e91673ef69b66b43eb62a8` |

Proposed schema file digests are:

```text
e214e356c029ac42aab3be18af03078280267301a6cd5fec2336d9e96c9886f7  notes/operation_pack_abi_v2_manifest.schema.proposed.json
0a14ad57ed8c48c16e9300355c31f7f1dd8cd2e82cf3c1998975a1c12ac2b61d  notes/operation_pack_abi_v2_transition_request.schema.proposed.json
8baba38a83eb3e5cc3ed0eb3628288a18deff7fc0f1b27e0c67fcb2686d228ad  notes/operation_pack_abi_v2_transition_receipt.schema.proposed.json
```

## Validation record

Native validation used read-only
`/home/dirk/Projects/pybench/.venv/bin/python` with Python 3.11.0rc1 and
`jsonschema 4.26.0` `Draft202012Validator`; no Draft-7 projection, installation
or network access was used.

```text
PASS manifest: Draft2020 self-check positive=1 concrete_negative=8 exhaustive_recipes=4 total_negative=12
PASS transition_request: Draft2020 self-check positive=2 concrete_negative=11 exhaustive_recipes=4 total_negative=15
PASS transition_receipt: Draft2020 self-check positive=3 concrete_negative=5 exhaustive_recipes=3 total_negative=8
PASS tuple equivalence: manifest_input(kind,alignment)=request_projection count=11
PASS tuple equivalence: manifest_output(category,kind,profile)=request_projection(writer removed) count=15 unique_writer_per_tuple=1
PASS manifest input: legal=11 invalid_exhaustive=66 required_field_removals=44 unknown_property_branches=11
PASS manifest output: legal=15 invalid_exhaustive=345 required_field_removals=105 unknown_property_branches=15
PASS exact Sable rejection: MAN-MATRIX-ALIGNMENT-NONE
PASS exact Sable rejection: MAN-MATERIALIZATION-MODEL-TERMINAL-PROFILE
PASS exact Sable rejection: MAN-TERMINAL-MATRIX-ORDINARY
PASS ledger: operations=60 faults=78 prior_faults_F001-F071_exact=71 new_faults_F072-F078=7 dynamic_provider=6 semantic_rules_C01-C14=14
PASS complete ledger path accounting: fields=positive_fixture,adversarial_fixture,source_anchor exclusion=empty_or_future unique=120 resolved=120 missing=0
PASS worked manifest example content unchanged; no definition/identity chain change
PASS pinned-PyBench canonical self-identities: verified=30
PASS R canonical self-identities: verified=30
PASS scvi_train closure: requested=3 granted=3 returned=3 extras=0
PASS all six chromvar dynamic-provider cases; failure_dispatches=0
```

The exact focused R invocation was:

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

Accepted live v1 protocol files remain byte-identical to Quill:

```text
39112be67f3d022725d8dc57a569d7bfd94ea0242f1421be4d2d479be56795bb  inst/protocol/operation-pack-v1.schema.json
7fa992ab7dcb8b07f9d75621b4a5eb27cd29c21edac33ad962e6c1393999361e  inst/protocol/operation-pack-canonical-json-v1.md
d5e80b58e4f18b37d0e906e7dac127fd17fbb88ea56dd83926406691303b655b  inst/protocol/pybench-op-v2.schema.json
PASS v1 protocol bytes: 3/3 unchanged and cross-repository byte-identical
```

Final `git diff --check`, eight-file maximum allowlist and clean-worktree checks
passed on the closure commit.

## Routing

Return this narrow planning descendant to Sable only. Meridian-9 review,
implementation, live activation, operation migration, pack repositories and
runtime qualification remain unauthorized until Sable accepts.
