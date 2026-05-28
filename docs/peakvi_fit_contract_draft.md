# `peakvi_fit` Contract Draft (v1)

Contracts determine the best friendships.

This draft defines a first `scworkbench` engine op contract for PeakVI integration via `pybench`.

## Design Position (Important)

`peakvi_fit` is a **model-producing latent-space op**.

It should follow the same broad bench pattern as other model-producing surfaces:

- `umap_fit` produces a reusable result (`space_2d`) and a reusable model (`model_ref`)
- `palantir_fit` produces analysis outputs plus a reusable model (`model_ref`)
- `monocle3_fit` produces analysis outputs plus a reusable model (`model_ref`)

For PeakVI, the reusable analysis product is the latent embedding itself.

Therefore:

- `peakvi_fit` v1 should produce:
  - `space`
  - `model` (`model_ref`)
- it should **not** try to absorb downstream UMAP or trajectory semantics
- it should **not** invent a PeakVI-specific artifact family when generic `model_ref` already exists

## Op Intent

Train a PeakVI model on a chosen ATAC/count matrix inside the bench/pybench contract boundary and emit:

- a reusable latent space for downstream analysis
- a reusable serialized model reference for continuation / projection / auditability

Primary downstream uses include:

- `umap_fit` on `peakvi_space`
- trajectory fitting on `peakvi_space`
- comparison of `lsi` vs `peakvi_space`
- stable provenance for latent-space-sensitive analyses

## Scope (v1)

`peakvi_fit` runs model training and latent extraction only.

v1 does **not** include:

- denoised accessibility outputs
- imputed matrices
- differential accessibility
- out-of-sample transform
- continued training

Those can be added later as distinct ops if they become real needs.

## Required Inputs (v1)

### 1) `matrix` (`matrix`)

The feature-by-cell matrix used to train PeakVI.

Expected semantics:

- ATAC-like counts / accessibility matrix
- rows = features / peaks
- columns = cells
- effective cell universe is determined by standard bench `cell_set` / `cell_ids` resolution

Important:

- `peakvi_fit` should be **matrix-first**, not `space`-first
- PeakVI is not a consumer of an existing latent space

### 2) Cell universe

Use standard engine semantics:

- `cell_set` (preferred symbolic reference)
- and/or `cell_ids`

Bench should continue preferring symbolic refs over large literal vectors.

## Optional Inputs / Parameters (v1)

### Latent shape

- `n_latent` (integer; default candidate `30`)
  - target latent dimensionality for the emitted `space`

### Batch / covariate handling

- `batch_key` (string; nullable)
  - observation field used as the PeakVI batch covariate
  - if `NULL`, run without batch correction

Recommendation:

- keep v1 to a single explicit batch field if one is needed
- do not expose arbitrary covariate formula machinery yet

### Training control

- `max_epochs` (integer; nullable)
  - if `NULL`, allow scvi-tools to choose or use bench default

- `seed` (integer; nullable)
  - random seed for reproducibility

- `use_gpu` (bool; default `FALSE` or runtime-default)
  - explicit, provenance-visible runtime choice

### Feature filtering

PeakVI generally expects the input matrix to already reflect the intended feature universe.

Recommendation for v1:

- do **not** add internal feature-selection policy to `peakvi_fit`
- if feature filtering is needed, it should happen upstream and be provenance-visible there

### Naming

- `space_id_out` (string; default `"peakvi_space"`)
  - emitted latent space id

This matches the existing codebase expectation that a `peakvi_space` may exist.

## Outputs (v1)

### 1) `space` (`space`)

PeakVI latent embedding.

- kind: `space`
- `space_id = space_id_out` (default `peakvi_space`)
- one row per effective cell
- dimensions = `n_latent`

Semantics:

- this is the primary reusable analytical result of the op
- downstream ops should consume it exactly as they consume `lsi`, `pca`, or other latent spaces

### 2) `model` (`model_ref`)

Serialized PeakVI model reference.

- kind: `model_ref`
- `engine = "peakvi"`
- `model_space_id = space_id_out`
- `in_space_id` should point to the training input identity used for model fitting

Recommended `in_space_id` rule for v1:

- if a matrix-trained model has no true input `space`, set `in_space_id` to `space_id_out` for compatibility
- but record the training matrix id explicitly in provenance / model payload

Reason:

- current `model_ref` contract is space-oriented
- we should not block PeakVI on a broader `model_ref` redesign
- but we should record the matrix truth honestly in the birth certificate

## Outputs Summary (recommended v1 set)

- `space` (`space`)
- `model` (`model_ref`)

That is enough for a first-class reusable latent-space op.

## Why This Contract

PeakVI is closer to `umap_fit` than to a downstream trajectory op:

- it learns a reusable representation
- that representation is itself a first-class engine primitive
- the trained model may be reused later

So the right contract is:

- result primitive: `space`
- model primitive: `model_ref`

not:

- ad hoc script output
- bespoke `peakvi_model` storage type
- implicit notebook-side state

## Provenance / Birth Certificate Requirements

Bench remains provenance authority.

Record at minimum:

- matrix id used for training
- effective cell universe (`cell_set` and/or resolved cell count)
- feature count
- cell count
- `n_latent`
- `batch_key` (or explicit `NULL`)
- `max_epochs` (resolved)
- `seed`
- `use_gpu`
- scvi-tools version
- PeakVI / scvi model class
- emitted `space_id_out`

Recommended additional provenance:

- training wall time
- early stopping / convergence summary if cheaply available
- device actually used (`cpu`, `cuda`, etc.)

For `model_ref`, the serialized payload should also carry:

- `engine = "peakvi"`
- training matrix id
- latent space id
- resolved params
- package versions

## Validation Rules (op-level)

Before Python handoff:

- matrix resolves successfully
- effective cell universe is non-empty
- effective feature universe is non-empty
- matrix values are numeric and finite
- `n_latent >= 2`
- `batch_key`, if provided, exists in the observation metadata available to the Python side

After Python receipt:

- declared outputs match preregistered artifact IDs/types
- latent `space` rows align exactly to effective cell order
- latent dimensionality matches resolved `n_latent`
- `wb_art_load()` succeeds for `model`

## Mapping to `pybench` (v1)

Expected Python-side implementation: `pybench.ops.peakvi_fit`

Responsibilities:

1. load request via protocol
2. resolve matrix and effective cells from the bundle
3. resolve batch metadata if requested
4. train PeakVI using scvi-tools
5. extract latent embedding for the effective cells
6. serialize the trained Python model to bundle model storage
7. write:
   - `space` payload
   - `model_ref` payload
8. return compact receipt to the R bench

Important note:

- `pybench` already has generic `model_ref` payload writing
- `peakvi_fit` should reuse that path, not create a special-case schema

## Proposed `wb_op_interface()` Shape (Draft)

### Requires

- `matrix`

### Produces

- `space`
- `model_ref`

### Promotable

- `space`
- `model`

### Candidate parameters

- `n_latent`
- `batch_key`
- `max_epochs`
- `seed`
- `use_gpu`
- `space_id_out`

## Session / Catalog Sketch

Recommended catalog concept:

- `op_name = "peakvi_fit"`
- `title = "PeakVI fit (pybench)"`
- `description = "Train a PeakVI model on a matrix via the pybench Python runtime and emit a latent space plus model reference."`
- `intent = c("latent", "model", "python")`

## Coexistence With Existing Ops

Recommended downstream usage:

1. `peakvi_fit` -> emits `peakvi_space`
2. `umap_fit(space = peakvi_space)` -> emits `umap.peakvi_space`
3. trajectory ops consume `peakvi_space`
4. trajectory project ops consume `umap.peakvi_space`

This matches the existing tests/docs pattern that already refers to:

- `peakvi_space`
- `umap.peakvi_space`

## Deferred (v2+)

Possible later ops:

- `peakvi_transform`
  - project new cells into an existing fitted PeakVI model
  - likely consumes `model_ref` + `matrix`
  - likely produces `space`

- `peakvi_denoise`
  - if denoised accessibility becomes a real engine need

- `peakvi_feature_scores` or similar
  - only if a stable, generally useful contract emerges

These should remain separate ops.

## Open Questions

1. Should `model_ref$in_space_id` remain `space_id_out` for compatibility, or should we extend `model_ref` later to carry matrix-native training identity more explicitly?
2. Do we want `batch_key` in v1, or do we begin with a no-batch contract and add it immediately after?
3. Should the op emit an optional training summary `obs_table` in v1, or keep the first contract strictly minimal?
4. Do we want a paired `peakvi_transform` contract immediately, or only after `peakvi_fit` is proven useful?
