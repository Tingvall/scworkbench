# RNA Map Ops

scworkbench supports a first-pass RNA map workflow for matrix-only bundles:

```r
RNA_counts -> matrix_log_normalize -> hvg_select -> pca_fit -> umap_fit
```

This is platform infrastructure. It creates inspectable PCA/UMAP spaces from a
typed bundle; it does not perform cell-type annotation or biological
interpretation.

## hvg_select

`hvg_select` selects highly variable features from a matrix and returns a
promotable `feature_table`.

```r
rr <- wb_session_run_op(
  session,
  bundle,
  "hvg_select",
  inputs = list(
    matrix = "RNA_log_norm",
    n_features = 2000,
    method = "vst"
  )
)
```

The output `selected_features` table has `feature_id`, `rank`, `mean`,
`variance`, `dispersion`, `score`, `detected_cells`, `detected_fraction`,
`selected`, `method`, and `matrix_id`.

The current `method = "vst"` is a lightweight stabilized dispersion score:

```text
score = log1p(variance / mean)
```

This is intentionally chunk-compatible and suitable for BPCells-backed
matrices. It is not a full Seurat VST clone. `method = "dispersion"` and
`method = "variance"` are also available. Batch-aware HVG selection is reserved
but not implemented; passing `batch_key` fails explicitly.

## pca_fit

`pca_fit` computes PCA from a matrix and selected features, then persists the
coordinates as a normal scworkbench `space`.

```r
rr_pca <- wb_session_run_op(
  rr$session,
  bundle,
  "pca_fit",
  inputs = list(
    matrix = "RNA_log_norm",
    features = wb_ref_run(rr$run$run_id, "selected_features"),
    n_components = 50,
    backend = "irlba",
    space_id_out = "rna.pca",
    center = TRUE,
    scale = TRUE,
    seed = 1
  )
)
```

If the HVG table is promoted, use:

```r
features = wb_ref_artifact("<hvg_feature_table_artifact>", "selected_features")
```

For explicit feature vectors, use:

```r
feature_ids = c("geneA", "geneB", "geneC")
```

The op outputs:

- `space`: symbolic reference to the persisted PCA space.
- `loadings`: `feature_table` with feature loadings per PC.
- `variance`: `obs_table` with per-PC variance explained.
- `fit_summary`: `obs_table` with matrix, feature, backend, and output-space parameters.

The PCA space can be consumed by UMAP:

```r
wb_session_run_op(
  rr_pca$session,
  bundle,
  "umap_fit",
  inputs = list(
    space = "rna.pca",
    dims = 1:30,
    space_id_out = "rna.umap",
    seed = 1
  )
)
```

## Scale Behavior

`hvg_select` reads the input matrix in feature chunks and avoids full matrix
materialization.

`matrix_log_normalize` supports both single-fragment and multi-fragment BPCells
matrices. Multi-fragment logical matrices are normalized fragment-by-fragment
and registered as multi-fragment output matrices with the same cell partitions.

`pca_fit` reads only the selected feature block. The default backend is
`irlba::prcomp_irlba()`, which is the intended path for large sparse/backed
matrices. The selected block size is recorded in `fit_summary` as
`approx_dense_gb`; dense backends are guarded by `max_dense_gb`.

The implementation removes non-constant features before PCA so scaling does not
fail on zero-variance columns.

## Claim Boundary

Allowed claim:

```text
scworkbench can ingest a multi-library 10x Matrix Market dataset and derive
inspectable RNA PCA/UMAP spaces from the resulting typed bundle.
```

Not claimed:

- cell-type annotation;
- developmental trajectory;
- species-specific biology;
- batch-corrected integration.
