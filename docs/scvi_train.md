# scVI CPU training through scwbLatent

`scvi_train` is no longer a core operation. Install and activate the
`scwbLatent` R operation pack, then call its versioned operation identity
`scwblatent::scvi_train` through `wb_session_run_op()`. Historical core
`scvi_train` runs remain inspectable without activating the pack; they are not
reinterpreted as new pack runs.

```r
fit <- wb_session_run_op(wb_session_new(), bundle,
  "scwblatent::scvi_train", inputs = list(
    matrix = "RNA_counts", batch_key = "sample_id",
    categorical_covariates = "condition",
    continuous_covariates = "quality_score",
    n_latent = 30L, max_epochs = 100L,
    cell_set = "all", min_cells = 2L))
```

The pack receives authenticated, ordered matrix chunks and one core-resolved
cell-metadata snapshot. Metadata fields are selected by stable field ID or an
unambiguous name, typed as categorical or continuous, aligned exactly to the
effective matrix cell axis, and recorded with their values, missingness and
source identities. The pack receives no bundle, SQL connection, registry path,
or storage authority. A generic `nonnegative_integer_v1` typed-slice policy
checks every consumed matrix chunk; the registered layer must be `counts`,
and normalized matrix labels fail before dispatch. Missing covariates,
ambiguous fields, reordered or foreign cells,
nonfinite continuous values and duplicate field selections fail closed.

The private Python helper fits `scvi.model.SCVI` on CPU only. The pack stages
input files under its own temporary directory, verifies their checksums after
the helper returns, and submits a latent `space`, contained `model_ref` tree,
and `fit_summary` in one core-owned atomic output closure. The model and
summary are promotable terminals; promoting either also materializes the
space. Output identifiers are newly allocated and immutable. The former core
overwrite option and deprecated output-space alias are not part of this pack
contract. GPU and large-data performance are not qualified here.

The prospective pack output identity is distinct from the historical core
operation. The focused old-core comparison uses exact ordered cells and latent
dimensions plus Spearman correlation of all pairwise latent distances at a
predeclared minimum of 0.9; it does not compare serialized model bytes or
legacy output hashes. See the frozen reference in
`scwbLatent/tests/fixtures/scvi_old_core_reference.json`.
