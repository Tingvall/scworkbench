# Phase 0 operation-pack ABI v2 requirements

This is specification input only. It does not change the v1 schema or authorize migration.

## Evidence from v1

[`inst/protocol/operation-pack-v1.schema.json`](../inst/protocol/operation-pack-v1.schema.json) can name all current primitive kinds, parameters, replay policies and typed inputs. [`R/operation_packs.R`](../R/operation_packs.R) validates canonical manifests, installed R or Python entry points, process-local activation, runner signatures and declared outputs. Existing conformance tests demonstrate terminal-output operation packs, canonical identities, explicit activation, missing-pack failure and pack-free inspection.

Vocabulary is not writer authority. The v1 runner is trusted code returning primitives; it does not provide a complete sanctioned API for publishing backed matrices, high-dimensional/2D spaces or contained models from private staging, nor a general all-or-nothing transaction spanning those objects and terminal artifacts. Direct calls to present core writers would preserve trusted-code execution but violate the target law that packs never become state authorities.

## Per-operation result

The exact 60-row adjudication is `core_to_packs_phase0_abi_gap_matrix.csv`:

- 42 `v1_ready_with_packaging_work`: terminal/path/vector/table methods whose declared result can use the existing ABI shape, subject to source extraction, dependency preflights and equivalence fixtures;
- 11 `requires_v2_atomic_multi_output`: `matrix_log_normalize`, `pca_fit`, `umap_fit`, `slingshot_fit`, `slingshot_adopt`, `monocle3_fit`, `peakvi_fit`, `scvi_train`, `peakvi_project`, `model_bound_latent_union`, and `palantir_fit`;
- 1 `requires_v2_materialization`: `umap_transform`;
- 1 `requires_core_capability`: `winner_cell_sets`;
- 4 `core_only` operations; and
- 1 `conformance_only` operation.

No operation is labelled `v1_ready`: even structurally supported methods still require package extraction, dependency declarations and old-core/new-pack equivalence qualification.

## Minimum v2 contract

1. **Sanctioned private writers.** Core allocates staging destinations and identities for ordinary/backed matrices, high-dimensional spaces, 2D spaces and model references with contained payloads. R and Python runners receive only declared capabilities.
2. **Atomic declared transition.** One operation may stage multiple materializations plus terminals. Core validates the complete declared set and publishes all or none; malformed receipts, undeclared files, process death or failed validation leave no committed residue.
3. **Identity and alignment.** Core checks cell/feature universes, ordering, dimensions, source ancestry, model linkage, payload containment and canonical identity. Packs do not allocate durable identities.
4. **Receipts and parity.** R and Python paths record the same resolved inputs, effective parameters, software/pack identities, outputs, terminal policies and failure status. Canonical JSON remains language-neutral and activation-order independent.
5. **Core registry requests.** A pack may propose a cell-set mutation with memberships and provenance; core validates and publishes it atomically. This closes `winner_cell_sets` without exposing direct registry authority.
6. **Optional dependency preflight.** Operation-specific R/Python/system requirements are inspected before runner dispatch and without network installation.
7. **Promotion and reopen.** Promotion closure includes required materializations and terminals. Finalized results remain inspectable and validate without the originating pack.
8. **Historical execution.** Stored unqualified core identities remain unchanged. Replay of historical definitions either uses the exact retained core compatibility implementation or fails closed; it never silently resolves to a new namespaced method.
9. **v1 coexistence.** Accepted v1 packs retain their identity and activation behavior or receive an explicit, tested migration rule. ABI v2 must not introduce arbitrary pack-defined primitive kinds.

## Required conformance failures

Tests must cover wrong types/alignment, missing pack/dependency, path escape, undeclared output, incomplete receipt, identity mismatch, process death at each publication boundary, partial multi-output writes, invalid model linkage, missing contained payload, promotion failure, reopen without pack, and replay with/without the exact pack. These are technical contracts, not sandboxing, malicious-code containment, biological validation or universal transactional guarantees.

## Unresolved specification inputs

- Exact v2 manifest versioning and v1-to-v2 compatibility syntax.
- The sanctioned writer request/receipt schemas and rollback recovery state machine.
- Operation-level environment lock and system-library representation.
- Whether the current `cell_vector_assoc` and `cell_vector_association` contracts are intentionally distinct or require a compatibility alias. They must not be collapsed during migration.
- Whether path-family terminal serialization needs an explicit v2 writer despite fitting the v1 primitive/terminal vocabulary; the current matrix treats it as v1-shaped pending conformance.
