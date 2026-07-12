# `scvi_train`

`scvi_train` is the scworkbench-side contract for training an RNA scVI model
through pybench and returning normal bundle state.

Target workflow:

```text
RNA_counts -> scvi_train -> rna.scvi -> umap_fit
```

## Purpose

The op trains a count-aware RNA latent model from a raw/count-like matrix and
emits:

- a reusable latent `space`, for example `rna.scvi`;
- a reusable `model_ref` with `engine = "scvi"`;
- a promoted `fit_summary` observation table with training parameters, runtime,
  input dimensions, covariates, and metrics.

The latent space is written into the normal bundle spaces registry, so existing
downstream ops and Shiny should consume it like any other space.

## Inputs

Required:

- `matrix`
  - matrix primitive, expected to be raw RNA counts or count-like integer values.

Standard cell selection:

- `cell_set`
- `cell_ids`

Optional metadata/covariate fields:

- `batch_key`
- `categorical_covariates`
- `continuous_covariates`

All covariates must exist in bundle cell metadata.

## Parameters

Defaults:

- `n_latent = 30`
- `n_hidden = 128`
- `n_layers = 2`
- `dropout = 0.1`
- `max_epochs = NULL`
- `early_stopping = TRUE`
- `seed = 1`
- `use_gpu = FALSE`
- `output_space_id = "rna.scvi"`
- `overwrite = FALSE`
- `allow_non_counts = FALSE`

`allow_non_counts=FALSE` makes the op fail early for matrix ids/layers that look
normalized and for sampled non-integer or negative values. Set it to `TRUE` only
for an intentional expert override.

## Staging Contract

The production-safe bridge uses R-staged sparse chunks, matching the PeakVI
cluster pattern.

Staged directory contents:

- `manifest.json`
- `feature_ids.txt`
- `cell_metadata.tsv`
- one or more Matrix Market chunk files, `chunk_00001.mtx`, ...
- one cell-id file per chunk, `chunk_00001_cells.txt`, ...

`manifest.json` fields:

- `protocol = "scworkbench_sparse_matrix_chunks_v1"`
- `matrix_id`
- `value_type = "counts"`
- `orientation = "features_by_cells"`
- `feature_ids_file`
- `cell_metadata_file`
- `n_features`
- `n_cells`
- `batch_key`
- `categorical_covariates`
- `continuous_covariates`
- `chunk_cells`
- `chunks`, each with `index`, `mtx`, `cells`, `n_features`, `n_cells`

The Python side transposes feature-by-cell chunks into AnnData cell-by-feature
`X`, uses `cell_metadata.tsv` for `obs`, uses `feature_ids.txt` for `var`,
trains `scvi.model.SCVI`, and writes outputs back to the bundle.

## Expected pybench Module

Module:

```text
pybench.ops.scvi_train
```

Request protocol:

```text
pybench-op-v1
```

Required request fields:

- `inputs$matrix`
- `inputs$cell_ids`
- `inputs$matrix_chunks_dir`
- `inputs$cell_metadata_path`
- `params$output_space_id` or `params$space_id_out`
- `outputs$model`
- `outputs$fit_summary`

Expected pybench outputs:

- add bundle space `output_space_id`;
- write model payload for preregistered `outputs$model`:
  - `engine = "scvi"`
  - `model_space_id = output_space_id`
  - `in_space_id = output_space_id`
  - `model_type = "scvi_train"`
  - bundle-relative model directory under `artifact_models/`;
- write `outputs$fit_summary` as an `obs_table`.

## Runtime Status

`pybench.ops.scvi_train` is implemented. It consumes the staged sparse-chunk
protocol, writes the latent space through the shared bundle space contract,
writes a bundle-relative scVI model directory for the preregistered
`model_ref`, and writes the preregistered `fit_summary` `obs_table`.

The bridge requires a pybench environment with the `scvi` extra, including
`anndata`, `scvi-tools`, and the staged-matrix dependencies. The R contract
test validates the interface, count/covariate checks, staging manifest, and
R-side model-reference loading without requiring a real scVI training runtime.
