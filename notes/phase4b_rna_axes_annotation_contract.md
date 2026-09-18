# Phase 4B RNA axes and annotation contract

Status: frozen implementation ledger for the provisional three-method
`scwbRNA` extraction. This is a typed ABI-v3 contract, not an RNA-name dispatch
exception.

| Capability | Request declaration | Core attestation | Failure boundary | Atomicity and parity |
|---|---|---|---|---|
| Session-cell axis | `session_cell_axis`, `read_session_cell_axis`, `effective_session_cells_v1`, `exact_complete_order_v1`, single use | session/run/checkpoint/source identities, ordered non-empty unique cells, content/source/ancestry/payload/descriptor identities | malformed, stale, missing, foreign, duplicate, or reordered cells fail with `PYBENCH_INPUT_IDENTITY_MISMATCH` before dispatch/publication | snapshot and descriptor are staged with the transition; output is published only with the complete receipt; R/Python canonical bytes are identical |
| Conditional output keys | `bounded_grouped_cell_key_cartesian`, required keys plus whole optional groups in manifest order | min/max rows, required keys, optional groups, exact cell axis and row order | partial, reversed, unknown, duplicate, missing, foreign, or reordered key/cell evidence fails before publication | the whole family and one observed-cardinality receipt publish together; the pack alone selects optional groups |
| Matrix feature annotation | `matrix_feature_annotations`, `read_matrix_feature_annotations`, matrix input, `feature_type`, matrix-feature order, preserve null, single use | matrix/input descriptor/content identities, exact ordered feature rows, content/source/ancestry/payload/descriptor identities | mutation, misalignment, stale evidence, cross-matrix substitution, malformed null policy, or reader collision fails before dispatch/publication | snapshot is immutable transition evidence and must match again at dispatch; R/Python validate the same preimages |

Reader names are disjoint from input, provenance-reader, and typed-slice names.
A `one_per_cell` result using the session axis must declare
`session_cell_axis_order_v1`. A bounded grouped shape must use
`declared_bounded_key_groups_v1`, and that resolver is invalid with any other
shape. No core branch names `cell_suffix_label`, `rna_qc_metrics`, or
`hvg_select`.

The authoritative adversarial corpus covers empty/duplicate session axes,
foreign/missing/reordered output cells, incomplete/reversed/unknown optional
groups, mutated/reordered/cross-matrix annotations, name collisions, stale
source evidence, and incomplete receipts. Publication is fail-closed and retry
safe.

The extraction is deliberately provisional: only `cell_suffix_label`,
`rna_qc_metrics`, and `hvg_select` moved. Core normalization, PCA, UMAP, and
all Phase 4C methods remain outside `scwbRNA`.
