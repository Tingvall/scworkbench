# Full real Xenopus independent direct workflow

`direct_xenopus.R` independently implements the pinned pack expressions; it
does not load scworkbench, invoke its helpers, create sessions or dispatch ops.
It reads the approved original RDS SHA-256
`7dfefc974d9b38ea3513c1e181f119f2c4cbde5fcf603298f71953bff7b85280`:
31,535 features, 13,199 cells, 29,297,098 nonzeros. Uses the repaired-baseline
library paths/dependencies and original scientific settings. Criteria and
prospective budgets were recorded in BUDGETS.md before comparisons.

## Successful complete run

```
inst/ci/run_logged_gate /tmp/scwb-engine-simplification-forge-20261018/direct_xenopus_v3.log /tmp/scwb-engine-simplification-forge-20261018/direct_xenopus_v3.exit -- /usr/bin/time -v Rscript notes/engine_simplification/baselines/direct_xenopus.R /tmp/scwb-matrix-streaming-forge-20261018/verified-library /tmp/scwb-engine-simplification-forge-20261018/direct-xenopus-v3
```

Numeric exit **0**, marker
`DIRECT_XENOPUS_READ_COMPUTE_WRITE_REOPEN_ALL_VALUES_OK`.
Wall **98.46 s**, user **89.52 s**, system **7.06 s**, peak RSS
**4,372,768 KiB**. Non-overlapping measured phase sum **93.233 s**;
remaining wall includes initialization and stdout. In particular save_uwot's
visible returned fit caused a large retained log dump: this was not removed
from wall timing, nor hidden inside analytical compute time.

| Phase | Seconds |
| --- | ---: |
| Original RDS SHA-256 | 0.388 |
| Read original RDS | 1.877 |
| Write/reopen source BPCells | 0.190 |
| Normalization read + double arithmetic + seven BPCells writes | 13.603 |
| Reopen seven normalized fragments | 0.040 |
| Build seven row-oriented BPCells indexes | 1.161 |
| HVG reads + complete statistics/ranking | 6.123 |
| Write complete HVG table, SQLite JSON rows | 13.800 |
| PCA selected reads + irlba fit + output tables construction | 7.897 |
| Write PCA HDF5 and loadings/variance JSON tables | 21.469 |
| Read PCA HDF5 + UMAP fit | 9.198 |
| Write UMAP HDF5 + save uwot model | 1.306 |
| Persist full-precision independent reference | 0.073 |
| Reopen/verify all stored tables/spaces/model | 0.394 |
| Independently verify every normalized value against original counts | 15.714 |

Exact source settings: normalization CP10k/log1p, chunks 2,000; HVG vst 2,000,
feature chunks 256; PCA 50, irlba, center/scale TRUE, feature chunks 256,
seed 1; UMAP PCA dimensions 1:30, n_neighbors 30, min_dist .3, spread 1,
Euclidean/nndescent, seed 1, n_threads/n_sgd_threads both 1. See
DIRECT_ALGORITHMS.md for exact expressions. No guard was raised. PCA and UMAP
use rhdf5 dense-space.hdf5.v1, float64, uncompressed coordinates, engine-matching
chunk dimensions/attributes and cell/dimension datasets. Normalized values use
uncompressed double BPCells; source uses compressed BPCells. The retained uwot
model is saved/loaded using the same public uwot functions as the pack.

HDF5 spaces and all model embeddings reopened exactly. Every normalized value
matched an independent original-count R calculation within 1e-14, with exact
cell/feature axes. Scientific comparison to the eventual candidate is still
root-owned; this result alone is not engine-candidate acceptance.

## Complete source metadata/reduction IO extension

After the main process exited, `direct_import_extension.R` reread the original
RDS, wrote full colData/rowData plus explicit ordered axes to SQLite, losslessly
retained the S4 metadata/reference attributes in RDS, and wrote original UMAP
to matching HDF5. It reopened and compared all values/axes, plus lossless RDS
metadata. Exit **0**, marker
`DIRECT_SOURCE_METADATA_AXES_REDUCTIONS_REOPEN_EXACT_OK`.
Wall **5.81 s**, peak RSS **1,056,968 KiB**; source reread **1.769 s**,
write **0.512 s**, reopen/compare **0.249 s**. Conservatively count this whole
extra process, including duplicate source read/startup, in the complete direct
reference: **104.27 s**. This is two observed serial processes, not one
uninterrupted wall measurement. Command uses the same logged-gate/time prefix
and arguments as above, replacing the script with direct_import_extension.R.

## Efficient native-table alternative

The matched existing JSON representation spends 35.269 seconds writing tables
and PCA HDF5. Ordinary direct R need not reproduce the engine's JSON row schema.
`direct_native_table_extension.R` additionally wrote the full-precision tables
using native SQLite typed columns and reopened them exactly. SQLite logical
columns are INTEGER; an explicit retained type descriptor restores logical
values after validating 0/1/NA. Exit **0**, marker
`DIRECT_NATIVE_SQLITE_FULL_PRECISION_TABLES_REOPEN_EXACT_OK`.
Full process **0.77 s**, peak RSS **150,924 KiB**. Native tables write/close/
reopen/compare **0.501 s**; matching PCA HDF5 write/reopen **0.070 s**;
full-precision reference read **0.062 s**.
Component substitution yields **69.572 s**:
104.27 - 13.800 - 21.469 + 0.501 + 0.070.
This is a measured-component assembled efficient reference, NOT an observed
single complete native-table workflow wall. Report both references; the slow
JSON comparator must not be used alone to flatter framework overhead. The
native-table storage schema and precision differ explicitly from the engine.

## IO, passes and limitations

Main measured phases: rchar **4,981,098,400**, wchar **1,258,785,066**,
read_bytes **622,592**, write_bytes **1,259,491,328**. These are process syscall
logical and physical IO counters, not a claim that all bytes are scientific
payload or cold-cache disk IO. Retained chamber allocation after extensions:
**957,936 KiB**; peak transient/open-unlinked disk was not measured.

Logical work: one source SHA/RDS read/import, one normalization coverage pass,
one row-index-build phase (may involve fixed sorting passes), 124 HVG feature
chunks, eight PCA selected-feature chunks, one all-normalized verification
coverage pass. Crucially PCA rchar was **2,894,395,789**, consistent with wide
backend reads for noncontiguous rank-ordered selections, not just the nominal
2,000-feature values. Do NOT call this one physical full-source pass or prove
partition independence from logical coverage. Root was alerted to investigate
the getter/backend separately. No repeated authentication is performed here.

Core provenance, registry, atomic publication, durable recovery and recipient
validation are additional engine services, absent from the direct store and
must be separately attributed. SQLite table row schema differs; raw precise
scientific results are retained independently of existing engine four-decimal
table persistence. Historical cluster timing is not a matched comparator.

Pilots are preserved with failure status, never counted as passes: first run
was deliberately stopped to correct UMAP storage from SQLite to HDF5; second
reached PCA then hit uwot's namespace preflight bug. Explicitly loading
rnndescent, as the pack already does, corrected that harness omission without
changing dependency versions, algorithms or scientific parameters. Native-table
pilot rejected SQLite INTEGER versus R logical until explicit retained schema
restoration was added; numeric/ordering criteria were not weakened.

## Retained independent comparison inputs

Root `/tmp/scwb-engine-simplification-forge-20261018/direct-xenopus-v3` contains
norm_1 through norm_7, pca.h5, umap.h5, model/model.uwot, tables.sqlite,
source_metadata.sqlite, source_UMAP.h5, scientific_reference.rds and axes.rds.
The reference RDS contains complete HVG ranking, selected IDs, PCA coordinates,
loadings/variance, and UMAP embedding; source axes are explicit.

- scientific_reference.rds SHA-256:
  `bb8a84d8cd68c494f7735509539d2b5362a2f257f511f05ca3cabdf4874ee5fb`
- axes.rds SHA-256:
  `3eff7c4344afbf4a5f58c7643a167bf454f9160bcad5351945d9aa1d0e398ed5`

No source/runtime/pack changes, profile changes, SIF, merge or push by helper.
