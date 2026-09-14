# Operation-pack ABI v2 Forge handoff

READY FOR SABLE AUDIT

Status: **PROPOSED, NON-RUNTIME PLANNING ARTIFACT**.

## Checkpoints

- Branch: `feat/operation-pack-abi-v2-spec-forge-20260914`
- Worktree: `/home/dirk/Projects/.scworkbench-worktrees/operation-pack-abi-v2-spec-forge-20260914`
- Exact scworkbench base: `368c864126b2e60880a81fab8dc0abbd34cf27a9`
- Exact PyBench base: `d2e0587950973cf7eeacfc46b2829397cf84f079`
- Quill specification commit: `eb5334a7bec73490ccfbf106f83ba91b1ab39fb8`
- Quill handoff commit: `8f73acebe833606e5d733988cb3d253720fcd333`
- Forge specification commit: `e71c3108d66be0caf79613aae0abecf1a094a019`
- Forge handoff closure: the commit containing this record; its SHA is reported
  in the external completion message because a commit cannot contain its own
  identity.
- Remote action: none; the work order prohibits push, merge, and tag actions.

Only the eight authorized `notes/` records are changed. No R, Python, live
protocol, test, metadata, generated-document, bundle, evidence, manuscript,
container, SIF, or operation implementation changed.

## Delivered records

1. `notes/operation_pack_abi_v2_specification.md`
2. `notes/operation_pack_abi_v2_manifest.schema.proposed.json`
3. `notes/operation_pack_abi_v2_transition_request.schema.proposed.json`
4. `notes/operation_pack_abi_v2_transition_receipt.schema.proposed.json`
5. `notes/operation_pack_abi_v2_state_machine.md`
6. `notes/operation_pack_abi_v2_v1_compatibility.md`
7. `notes/operation_pack_abi_v2_conformance_matrix.csv`
8. `notes/operation_pack_abi_v2_handoff.md`

Every record identifies Quill specification
`eb5334a7bec73490ccfbf106f83ba91b1ab39fb8` and handoff
`8f73acebe833606e5d733988cb3d253720fcd333`.

## Resolved decisions

- Manifest is `scworkbench.operation_pack.v2` with string
  `pack_abi_version="2"`; v2 negotiation is the exact closed ABI interval 2..2.
  Python uses exact process transport `pybench-op-v3`. Scientific-state version
  remains an independent core-owned scheme/digest.
- Definition and pack identities reuse the byte-exact language-neutral
  `scworkbench.operation_pack.canonical_json.v1` algorithm. Original installed
  Python manifest bytes and normalized content are independently authenticated.
- Output categories are `materialization`, `terminal_artifact`, and
  `core_registry_request`. Core preallocates all IDs and publishes all members
  of a promotion group atomically.
- Typed read/write grants and profiles are frozen for ordinary/backed matrices,
  dense/file-backed spaces, 2D spaces, contained models, existing terminal
  primitives, both path families, and cell-set admission.
- Path families have explicit `write_path_2d_family` and
  `write_space_path_family` writers. No primitive kind is pack-extensible.
- Request/receipt schemas bind content, row order/alignment, dimensions,
  ancestry, model linkage, payload containment, semantic metadata, mutation,
  preflight, runtime, request, capability, and receipt identities.
- The state machine specifies prepare, preflight, stage, dispatch, receipt,
  independent audit, publication, fresh reopen, rollback, interrupted recovery,
  and later promotion. Every failure has a zero-committed-residue law.
- R/Python runners use the same logical request/receipt fields and semantics;
  only genuine backend/software attestation values differ.
- Dependencies are operation-scoped. R, PEP 440, and system version schemes are
  explicit; optional selectors are explicit; probes are core-allowlisted,
  read-only and no-network.
- Finalized output inspection is pack-free. Replay requires the exact compatible
  recorded pack. V1 packs coexist on a separate activation path and all retained
  v1/core identities and history remain immutable.
- `cell_vector_assoc` and `cell_vector_association` remain distinct definitions,
  not aliases.

No accepted ABI design decision remains unresolved. Per-operation dependency
minimums and executable migration evidence are Phase 2 shipping gates, not
holes in this language-neutral contract.

## Catalog reconciliation

`operation_pack_abi_v2_conformance_matrix.csv` contains one metadata row, every
accepted operation exactly once (60 unique rows), and all 50 Quill adversarial
faults exactly once.

| Classification | Count | Disposition |
|---|---:|---|
| `v1_ready_with_packaging_work` | 42 | v1 shape is adequate; packaging, preflight and equivalence remain required |
| `requires_v2_atomic_multi_output` | 11 | closed atomic transition capability specified |
| `requires_v2_materialization` | 1 | `umap_transform`; sanctioned 2D-space writer/publication specified |
| `requires_core_capability` | 1 | `winner_cell_sets`; cell-set admission request specified |
| `core_only` | 4 | retained core identity; no migration |
| `conformance_only` | 1 | `py_protocol_hello`; protocol fixture only |

All output kinds and all three output categories occur in the matrix. The sole
Phase 0 `fixture_gap`, `knn_pseudobulk`, is explicitly migration-blocked until
its old-core/new-pack fixture is added; it does not leave an ABI decision open.

## Exact source evidence inspected

Scworkbench at `368c864126b2e60880a81fab8dc0abbd34cf27a9`:

- `inst/protocol/operation-pack-v1.schema.json`
- `inst/protocol/operation-pack-canonical-json-v1.md`
- `inst/protocol/pybench-op-v2.schema.json`
- `R/operation_packs.R`
- `R/operation_pack_python.R`
- `R/op_python_bridge.R`
- `R/pybench_transition.R`
- `R/session_staging.R`
- `R/session_promote.R`
- `R/op_catalog.R`
- `R/op_scvi.R`
- `R/op_peakvi.R`
- `R/op_model_bound_latent_union.R`
- `R/op_palantir.R`
- `R/ops_slingshot.R`
- `R/op_monocle3.R`
- `R/op_space_path.R`
- `R/promote_primitives.R`
- `notes/core_to_packs_phase0_abi_v2_requirements.md`
- `notes/core_to_packs_phase0_abi_gap_matrix.csv`
- `notes/core_to_packs_phase0_operation_baseline.json`
- `notes/core_to_packs_phase0_pack_dependencies.csv`
- `notes/core_to_packs_phase0_migration_fixture_matrix.csv`
- `notes/core_to_packs_phase0_compatibility_policy.md`
- `notes/core_to_packs_phase0_historical_compatibility.csv`

PyBench at the Quill worktree (base
`d2e0587950973cf7eeacfc46b2829397cf84f079`, planning commits above):

- `protocol/operation-pack-v1.schema.json`
- `protocol/operation-pack-canonical-json-v1.md`
- `protocol/pybench-op-v2.schema.json`
- `src/pybench/protocol.py`
- `src/pybench/capability.py`
- `src/pybench/bundle.py`
- `src/pybench/operation_packs.py`
- `src/pybench/artifacts_payload.py`
- `src/pybench/spaces_write.py`
- `tests/test_operation_packs.py`
- `tests/test_capability_v2.py`
- `tests/test_spaces_write_hdf5.py`
- `notes/operation_pack_abi_v2_python_parity_spec.md`
- `notes/operation_pack_abi_v2_python_request_receipt_model.json`
- `notes/operation_pack_abi_v2_python_fault_matrix.csv`
- `notes/operation_pack_abi_v2_python_handoff.md`

Controller records inspected:

- `/home/dirk/Projects/lymphocyte_trajectory/coordination/controller_notes/2026-09-14_core_to_packs_phase1_authorization.md`
- `/home/dirk/Projects/lymphocyte_trajectory/coordination/plans/scworkbench_core_to_packs_roadmap_20260912.md`
- `/home/dirk/Projects/lymphocyte_trajectory/coordination/requests/2026-09-14_forge_operation_pack_abi_v2_canonical_specification.md`

## Validation results

### JSON parsing and schemas

Python `json` parsed all three schemas. Installed `jsonschema 3.2.0` does not
provide a Draft 2020-12 validator, so the validation command made an in-memory
Draft-7-compatible projection (`$defs` to `definitions`) without changing the
files, checked every schema, validated one request and two receipt examples,
and proved an unknown root field is rejected:

```text
PASS notes/operation_pack_abi_v2_manifest.schema.proposed.json schema+examples+closed-root
PASS notes/operation_pack_abi_v2_transition_receipt.schema.proposed.json schema+examples+closed-root
PASS notes/operation_pack_abi_v2_transition_request.schema.proposed.json schema+examples+closed-root
```

Synthetic schema instances also passed R/Python manifest negotiation and
dependency-scheme enforcement, path-free typed cell-set admission, and
success/error receipt exclusivity. Negative variants were rejected as expected.

R `jsonlite` provided the independent parser path:

```text
PASS R jsonlite parse notes/operation_pack_abi_v2_manifest.schema.proposed.json
PASS R jsonlite parse notes/operation_pack_abi_v2_transition_receipt.schema.proposed.json
PASS R jsonlite parse notes/operation_pack_abi_v2_transition_request.schema.proposed.json
```

The installed R `jsonvalidate` front end could not be used because its installed
V8 shared object requires unavailable `libnode.so.72`; no package installation
or network access was attempted.

### Cross-language deterministic identity

The pinned R canonicalizer and pinned PyBench canonicalizer independently
canonicalized two differently ordered/spelled objects to identical bytes and
SHA-256:

```text
{"a":{"x":"µ","y":true},"n":1e0,"z":[3e0,2e0,1e0]}
1719c4112ba264823be791e969e3ff55f8c0da8b39195d88b2689d508727d2a5
```

### Reconciliation and receipt parity

```text
PASS matrix reconciliation metadata=1 operations=60 faults=50 unique
PASS classification counts: 42 / 11 / 1 / 1 / 4 / 1
PASS output coverage: 12 kinds including cell_set_admission; 3 categories
PASS pinned source/fixture path existence matrix_paths=113
PASS worked R/Python receipt field parity leaf_fields=40
```

The two worked receipts have identical leaf-field sets. Only transition/run and
allocated-output IDs plus backend/entry-point attestation values differ.

### Focused accepted v1 checks

```text
PASS test_operation_pack_canonical_json_v1_contract
PASS test_op_catalog_semantic_contract
```

Accepted live-protocol digests remained:

```text
39112be67f3d022725d8dc57a569d7bfd94ea0242f1421be4d2d479be56795bb  inst/protocol/operation-pack-v1.schema.json
7fa992ab7dcb8b07f9d75621b4a5eb27cd29c21edac33ad962e6c1393999361e  inst/protocol/operation-pack-canonical-json-v1.md
d5e80b58e4f18b37d0e906e7dac127fd17fbb88ea56dd83926406691303b655b  inst/protocol/pybench-op-v2.schema.json
```

Each is byte-identical to its pinned PyBench counterpart. The staged closure
tree passed the exact eight-file allowlist and `git diff --cached --check`.
Final commit containment and clean-worktree results are reported with the
containing commit identity.

## Sable audit focus

Audit the proposed names and closed schemas, the three independent version
domains, output-category/profile pairing, recovery completeness, v1 historical
non-substitution, the `umap_transform` classification, and the 60+50 ledger.
Implementation, migration, pack repositories, SIF work, and scientific evidence
remain out of scope.
