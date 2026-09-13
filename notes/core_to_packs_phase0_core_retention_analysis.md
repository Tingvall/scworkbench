# Phase 0 core-retention analysis

Status: evidence-locked planning input; no extraction authorized.
scworkbench source: `4f7420899db650d895505202e7e9827ea5814b62`.

## Adjudication

| Operation | Engine-owned law | Separable calculation | Decision |
| --- | --- | --- | --- |
| `feature_set_import` | Only core may validate a feature universe, allocate/replace durable feature-set identity and membership, and publish that registry mutation with provenance. | GMT/RDS/table/list parsing, column mapping, collection inference and gene-name cleanup can become an internal parser capability supplied to core. | Retain the public state-transition operation in core. A future parser plug-in may return an inert candidate table; it must not write `feature_sets` or `feature_set_membership`. |
| `feature_set_namespace_transfer` | Cross-matrix transfer changes the durable feature-set registry and must enforce source/target matrix identities, feature alignment, thresholds and overwrite policy under core authority. | Computing a proposed source-to-target membership mapping is separable. | Retain admission and publication in core; a future mapper may propose rows and diagnostics only. |
| `cell_set_derive` | Cell-set naming, membership validation, overwrite/history behavior and durable registry publication are bundle-state laws. | Selector/recipe evaluation can produce a candidate ordered cell-ID vector. | Retain in core; future methods may request admission of candidate membership but cannot publish it directly. |
| `metadata_cell_vector` | This is the method-neutral canonical adapter from retained metadata and its cell universe to a provenance-backed typed `cell_vector`. It keeps clients from establishing competing metadata-to-primitive identity rules. | Value coercion and missing-value policy are small pure helpers, but no independent scientific method remains after removing the state adapter. | Retain in core. |

Implementation anchors are [`R/op_feature_set_import_qc.R`](../R/op_feature_set_import_qc.R), [`R/feature_sets.R`](../R/feature_sets.R), [`R/cell_set_recipes.R`](../R/cell_set_recipes.R), [`R/cell_sets_membership.R`](../R/cell_sets_membership.R), [`R/op_metadata_cell_vector.R`](../R/op_metadata_cell_vector.R), and the registered adapters in [`R/op_catalog.R`](../R/op_catalog.R). The exact live contracts and component digests are in `core_to_packs_phase0_operation_baseline.json`.

`winner_cell_sets` is not reassigned here. Its method belongs to `scwbGenePrograms`, but its current runner calls the core cell-set registry writer. The ABI matrix therefore marks it `requires_core_capability`: ABI v2 needs a sanctioned request/response boundary so the pack can propose winner memberships and core can validate and publish them atomically.

## Negative core-necessity check

The repository traces bundle opening, validation, public getters, recipient inspection, provenance storage, session staging, promotion/finalization, target-reproduction planning/execution, and operation-pack activation to engine APIs outside the scientific operation catalog. Those facilities do not require any of the other 55 scientific methods. `py_protocol_hello` is a protocol fixture, not a state dependency. Tests that use PCA, UMAP, scVI or another method to manufacture state do not make that method part of the authority kernel.

Accordingly, no controller assignment is challenged. The four retained operations are sufficient as public operation-catalog state transitions; lower-level engine APIs remain core but are not counted as registered scientific operations.

## Boundaries

- Core ownership is mutation and identity authority, not scientific correctness.
- A parser or mapper extension would be trusted installed code, not a sandbox.
- Registry conformance does not establish biological validity or superiority of a selected feature/cell set.
- This analysis does not authorize changes to the 60-operation catalog.
