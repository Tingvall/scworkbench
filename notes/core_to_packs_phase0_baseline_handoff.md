# Core-to-packs Phase 0 baseline handoff

**BASELINE PREPARED FOR INDEPENDENT AUDIT**

This status means the planning evidence is assembled. It does not activate Phase 0, authorize extraction, or assert that the collaborator SIF gate has passed.

## Locked sources

- scworkbench: `4f7420899db650d895505202e7e9827ea5814b62`
- PyBench (read-only): `d2e0587950973cf7eeacfc46b2829397cf84f079`, protocol 2
- live no-pack operation catalog: 60 operations; `scworkbench-operation-catalog-v1` SHA-256 `e6a4e1713d1e8e4a3b044d285e6e510afdef46c6d56966f72a15725eea550445`
- controller partition and roadmap: `/home/dirk/Projects/lymphocyte_trajectory/coordination/plans/scworkbench_core_operation_pack_partition_20260912.md` and `/home/dirk/Projects/lymphocyte_trajectory/coordination/plans/scworkbench_core_to_packs_roadmap_20260912.md`

The live catalog and every `wb_op_interface()` were serialized directly. Each record carries a per-definition canonical component digest under the explicitly local scheme `scworkbench-core-catalog-definition-component-v1`; these component digests are not represented as historical pack-definition identities.

## Reconciliation

| Owner | Count |
| --- | ---: |
| core | 4 |
| `scwbRNA` | 4 |
| `scwbRepresentation` | 6 |
| `scwbGenePrograms` | 10 |
| `scwbStatistics` | 6 |
| `scwbTrajectory` | 24 |
| `scwbLatent` | 4 |
| `scwbATAC` | 1 |
| conformance fixture | 1 |
| **Total** | **60** |

Every live operation occurs exactly once and every proposed namespaced identity is unique. No controller assignment is changed. `winner_cell_sets` stays assigned to Gene Programs but needs a sanctioned core registry request. `cell_vector_assoc` and `cell_vector_association` remain separate pending focused semantic adjudication.

## ABI and dependencies

- 42 operations are `v1_ready_with_packaging_work`.
- 11 require v2 atomic mixed publication.
- 1 (`umap_transform`) requires v2 2D-space materialization.
- 1 (`winner_cell_sets`) requires a core capability.
- 4 are core-only and 1 is conformance-only.

ABI v2 must provide engine-sanctioned matrix/space/model writers, atomic materialization-plus-terminal publication and rollback, contained model linkage, R/Python receipt parity, operation-level dependency preflight, pack-free inspection and a cell-set publication request. The detailed list is in `core_to_packs_phase0_abi_v2_requirements.md` and the 60-row matrix.

Dependency versions are not declared per operation in the present sources. The handoff therefore preserves unresolved minima rather than inventing them. `scwbTrajectory`, `scwbLatent` and `scwbATAC` carry the largest optional runtime/license surfaces. No hard scientific pack-to-pack dependency is required; typed primitives are the interoperability boundary. Release-time locks, offline tests and third-party license notices remain gates.

## Fixture and history findings

The repository contains operation-named positive anchors for 59/60 operations. No operation-specific positive test containing the literal identity `knn_pseudobulk` was found under `tests/`; its implementation and interface exist, but an execution fixture is a documented pre-migration gap. Existing tests are mapped conservatively by content and may cover several fixture roles; each migration still needs a dedicated old-core/new-pack comparator, negative preflight, promotion/closure, finalized pack-free reopen, strict replay, missing-pack rejection, and rollback fixture as applicable.

All 60 historical names are enumerated. Existing retained records remain unqualified and immutable; future executions use approved namespaced identities. Inspection stays pack-free, while replay/dispatch requires the exact compatible historical implementation or pack. Textual historical-evidence anchors are recorded only when located; absence is not filled by inference.

## Recommended identities

The working namespaces are `scwbrna`, `scwbrepresentation`, `scwbgeneprograms`, `scwbstatistics`, `scwbtrajectory`, `scwblatent`, `scwbatac`, and test-only `scwbconformance`. Use one repository per scientific pack and a separate optional `scworkbenchStandard` profile. Controller collision checks and approval remain required.

## Audit routing and activation gate

Route this commit to Meridian-9 only after the Controller records the collaborator Bdev SIF gate and other roadmap activation conditions. Independent audit should confirm the catalog extraction, classification decisions, dependency scan, fixture gap and immutable-history policy. Do not begin ABI v2 or extract, rename or remove operations on the strength of this planning status.

No source, schema, generated catalog, package metadata, publication file, evidence bundle, runtime or primary worktree was modified.
