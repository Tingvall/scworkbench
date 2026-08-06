# `scworkbench` <-> `pybench` Parity Map (Draft)

Purpose:

- track which R engine functions have Python counterparts
- make contract-touching edits visible
- reduce silent drift between `scworkbench` and `pybench`

Conventions:

- `Status`
  - `implemented`: Python counterpart exists and was smoke-tested
  - `partial`: Python counterpart exists but not fully parity-tested
  - `planned`: intended counterpart not implemented yet
- `Contract Notes` highlight invariants that must stay aligned

## Bundle / Handle

| R (`scworkbench`) | Python (`pybench`) | Area | Status | Contract Notes |
|---|---|---|---|---|
| `wb_open_bundle()` | `pybench.bundle.open_bundle()` | bundle handle | implemented | `manifest.json` + `manifest.storage.sqlite.path` |
| `wb_close_bundle()` | `pybench.bundle.close_bundle()` | bundle handle | implemented | close SQLite connection only |

## Core Getters

| R (`scworkbench`) | Python (`pybench`) | Area | Status | Contract Notes |
|---|---|---|---|---|
| `wb_cells()` | `pybench.getters.cells()` | getter | implemented | canonical order by `cells.rowid`; set membership join semantics |
| `wb_cell_sets()` | `pybench.getters.cell_sets()` | getter | implemented | `core` sorted first |
| `wb_resolve_cell_set()` | `pybench.getters.resolve_cell_set()` | getter | implemented | `"all"` support + stable ordering |
| `wb_spaces()` | `pybench.getters.spaces()` | getter | implemented | hide phantom/empty `space_id` rows |
| `wb_space_info()` | `pybench.getters.space_info()` | getter | implemented | registry rows from `spaces` |
| `wb_space()` | `pybench.getters.space()` | getter | implemented | unified `space_2d`/`space_coords`; requested order is exact; omitted order is canonical all-bundle order restricted to cells present in the space |
| `wb_matrices()` | `pybench.getters.matrices()` | getter | implemented | ordered by `matrix_id` |
| `wb_matrix_info()` | `pybench.getters.matrix_info()` | getter | implemented | registry rows from `matrices` |
| `wb_features()` | `pybench.getters.features()` | getter | implemented | canonical feature order uses `features.rowid` |
| `wb_feature_ids()` | `pybench.getters.feature_ids()` | getter | implemented | canonical order by `rowid` within `matrix_id` |
| `wb_meta()` | `pybench.getters.meta()` | getter | implemented | preserve default `rowid` order + explicit `cells` alignment |

## Feature Set Getters

| R (`scworkbench`) | Python (`pybench`) | Area | Status | Contract Notes |
|---|---|---|---|---|
| `wb_feature_sets()` | `pybench.getters.feature_sets()` | getter | implemented | group/count semantics + filters |
| `wb_feature_set_get()` | `pybench.getters.feature_set_get()` | getter | implemented | preserve saved order (`rank ASC`) |
| `wb_feature_set_info()` | *(not yet)* | getter | planned | thin wrapper over `feature_sets()` |

## Artifact Registry Reads

| R (`scworkbench`) | Python (`pybench`) | Area | Status | Contract Notes |
|---|---|---|---|---|
| `wb_art_list()` | `pybench.getters.art_list()` | registry read | implemented | filter by `type`, order by `created_at DESC` |
| *(internal row query)* | `pybench.getters.art_get_row()` | registry read | implemented | one-artifact lookup for payload writers |

## Python Op Bridges

| R (`scworkbench`) | Python (`pybench`) | Area | Status | Contract Notes |
|---|---|---|---|---|
| `wb_op_peakvi_fit()` | `pybench.ops.peakvi_fit` | op bridge | implemented | keep training params aligned: `n_latent`, `n_layers`, `n_hidden`, `dropout`, `max_epochs`, `lr`, `early_stopping`; production/cluster path is R-staged sparse chunks -> Python PeakVI; native pybench BPCells reads are local/dev capable when `matrix_chunks_dir` is absent but are not cluster production default until forked/double-matrix BPCells reads pass a cluster smoke; writeback remains `space` + `model_ref` |
| `wb_op_peakvi_project()` | `pybench.ops.peakvi_project` | op bridge | implemented | consumes `model_ref(engine=\"peakvi\")`; currently requires the staged sparse chunk bridge; writes `space` only |
| `wb_op_scvi_train()` | `pybench.ops.scvi_train` | op bridge | implemented | R validates count-like RNA input and covariates, stages `scworkbench_sparse_matrix_chunks_v1` chunks plus cell metadata, and preregisters `model_ref` + `obs_table`; Python writes `space` + bundle-relative `model_ref` + `scvi_fit_summary` table; requires pybench `scvi` extra |

## Non-Artifact Bundle Writes

| R (`scworkbench`) | Python (`pybench`) | Area | Status | Contract Notes |
|---|---|---|---|---|
| `wb_add_space()` | `pybench.add_space()` / `pybench.spaces_write.add_space()` | bundle write | implemented | writes `spaces` + `space_2d`/`space_coords`, validates cells, refreshes manifest |

## Primitive Payload Contracts (Write Side)

Note:

- Python currently writes **payload tables only**
- R bench remains owner of `artifacts` registry row + provenance/run registry

| R Contract Touchpoint | Python (`pybench`) | Primitive Kind | Status | Contract Notes |
|---|---|---|---|---|
| `.wb_promote_cell_vector()` | `write_artifact_cell_vector_payload()` | `cell_vector` | implemented | `artifact_labels` + `value_type`/`value_num` fidelity |
| `.wb_promote_relation_family()` | `write_artifact_relation_family_payload()` | `relation_family` | implemented | `artifact_relation_rows`; nullable `weight/value/distance` |
| `.wb_promote_path_2d_family()` | `write_artifact_path_2d_family_payload()` | `path_2d_family` | implemented | `artifact_curves_2d` |
| `.wb_promote_model_ref()` | `write_artifact_model_ref_payload()` | `model_ref` | implemented | `artifact_model_ref`; file path written separately |
| `.wb_promote_cell_vector_family()` | *(not yet)* | `cell_vector_family` | planned | `artifact_pseudotime` |
| `.wb_promote_tabular_common()` | *(not yet)* | `feature_table` / `obs_table` | planned | `artifact_tables` + `artifact_table_rows` JSON row encoding |

## Loader Compatibility Targets (R Reads Python Writes)

These are the immediate parity tests to add:

- `wb_art_load(..., expected_kind = "cell_vector")` reads Python-written `artifact_labels`
- `wb_art_load(..., expected_kind = "relation_family")` reads Python-written `artifact_relation_rows`
- `wb_art_load(..., expected_kind = "path_2d_family")` reads Python-written `artifact_curves_2d`
- `wb_art_load(..., expected_kind = "model_ref")` reads Python-written `artifact_model_ref`

## Change Discipline

When editing any R function listed here:

1. Update inline `pybench-parity` comment if semantics changed
2. Update this parity map
3. If storage contract changed, add/adjust a parity test (Python write -> R read)
