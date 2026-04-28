# PeakVI Tetralith Handoff

Date: 2026-04-22

Audience: Codex agent working on the development machine

Goal: make `peakvi_fit` viable for real bundle-scale runs on Tetralith GPU nodes.

## Context

We are not doing software development on the cluster environment. The cluster is
for running analysis workloads against the existing container and bundle.

Target runtime here is:

- container: `singularities/scworkbench_fullstack_full.sif`
- bundle: `bundles/signal`
- initial target cell set: `set:trajectory_bcell`
- matrix: `ATAC_counts`
- batch covariate: `dataset_id`

The current container runtime needs environment hygiene:

- use `singularity/apptainer ... --no-home`
- unset `PYTHONPATH`, `PYTHONHOME`, `PYTHONUSERBASE`
- unset `R_LIBS`, `R_LIBS_USER`, `R_LIBS_SITE`
- inside R, force `.libPaths(c("/usr/local/lib/R/site-library", "/usr/local/lib/R/library"))`

Those issues are operational and already understood. They are not the primary
blocker for full PeakVI.

## Cluster Constraint

Tetralith GPU nodes have:

- 1 GPU
- 32 CPU cores
- 96 GiB RAM

The larger 384 GiB nodes do not have GPUs.

Implication:

- we cannot solve current `peakvi_fit` memory pressure by simply requesting a
  larger-memory GPU node on Tetralith
- a full B-cell trajectory PeakVI run must fit within a 96 GiB GPU node, or the
  implementation must become more memory-efficient

## What Fails Today

Current `peakvi_fit` implementation is in:

- `R/op_peakvi.R`
- `repo/pybench/src/pybench/ops/peakvi_fit.py`

Current flow:

1. R resolves the full requested matrix slice from the bundle using
   `wb_matrix_read_features(...)`
2. R materializes the full feature-by-cell slice in memory
3. R writes the entire slice to temporary Matrix Market files
4. Python reads the Matrix Market file with SciPy
5. Python transposes the matrix and builds `AnnData`
6. Python trains PeakVI and writes the latent space + model back to the bundle

This is the wrong shape for bundle-scale ATAC data on 96 GiB GPU nodes.

For `bundles/signal` B-cell trajectory:

- features: 105,642 peaks
- cells: 44,907 cells

The likely memory spike is the staging path, not only the PeakVI model itself:

- large sparse matrix in R
- Matrix Market serialization
- Matrix Market reread in Python
- transpose + `AnnData` construction

## Existing Python Capability

`pybench` already knows how to:

- open the bundle
- read SQLite-backed metadata
- read cells, cell sets, spaces, matrix registry, feature ids

Relevant files:

- `repo/pybench/src/pybench/bundle.py`
- `repo/pybench/src/pybench/getters.py`

However, `pybench` does **not** currently have a matrix payload reader for
bundle matrices stored as `bpcells`.

The signal bundle manifest confirms matrix payloads are stored as BPCells dirs:

- `mat/mat_frag_ATAC_counts_20260310_234935`
- `mat/mat_frag_RNA_counts_20260310_234721`

Python in the current container does not expose a `bpcells`/`BPCells` Python
module, so this is not a matter of flipping an existing import.

## Requested Engineering Change

Keep the external `peakvi_fit` op contract stable, but replace the internal
matrix handoff.

### We should build

A more memory-efficient bundle-to-Python path for `peakvi_fit` that removes the
current Matrix Market staging.

Preferred outcome:

- Python consumes the bundle matrix directly, without R materializing the full
  matrix and without `writeMM()`

Acceptable intermediate outcome:

- Python receives the matrix through a more efficient scratch-backed sparse
  format and/or chunked handoff that avoids the current worst-case duplication

### We should not build

- a cluster-only workaround that depends on special node types we do not have
- a Tetralith-specific branch in engine behavior
- a manual ad hoc Python script outside the bench contract

## Proposed Direction

### Option A: direct Python bundle matrix reader

Best long-term solution if practical.

Build Python-side support in `pybench` for reading bundle matrix payloads from
the registered BPCells directory, aligned to requested `cell_ids` and bundle
feature order.

Then update `pybench.ops.peakvi_fit` to:

1. open bundle
2. resolve `matrix_id`
3. resolve `cell_ids`
4. read sparse matrix directly from bundle storage
5. build `AnnData`
6. train PeakVI
7. persist outputs exactly as today

R-side `wb_op_peakvi_fit()` would then pass only symbolic/request metadata:

- `bundle_dir`
- `matrix_id`
- `cell_set`
- `cell_ids`
- `batch_key`
- training params
- preregistered output ids

and would stop writing:

- `matrix.mtx`
- `feature_ids.txt`
- `cell_ids.txt`

### Option B: smarter staged sparse handoff

If direct BPCells reading in Python is too much work right now, replace Matrix
Market with something less pathological.

Examples:

- scratch-backed H5AD written once
- scratch-backed CSC/CSR `npz`
- chunked sparse export/import path

This is second-best. It still stages data, but should reduce memory duplication
and I/O overhead.

## Required Invariants

Whatever changes internally, preserve these external behaviors:

- op name remains `peakvi_fit`
- inputs remain matrix-first
- latent embedding persists as bundle `space`
- trained model persists as bundle `model_ref`
- provenance / receipt behavior stays compatible with current bridge
- bundle-facing workflows continue to use `wb_session_run_op(...)`

Do not redesign the user-facing contract unless strictly necessary.

## Bench-Level Acceptance Criteria

The dev-machine implementation is good enough when all of the following are
true:

1. `peakvi_fit` no longer uses Matrix Market staging from R to Python.
2. A production-style run on `bundles/signal` B-cell trajectory is materially
   more memory-efficient than the current path.
3. The op still writes:
   - a `space` via `space_id_out`
   - a `model_ref` artifact under `artifact_models/`
4. The existing container runtime can still execute the op with the usual env
   sanitation.
5. The design is general engine work, not a Tetralith-specific hack.

## Nice-To-Have

- add explicit logging/timings for:
  - matrix acquisition
  - sparse object construction
  - `AnnData` build
  - PeakVI training
  - output persistence
- if practical, allow scratch/temp root to be configured cleanly from the op
  bridge

## Operational Notes From Cluster Testing

- `library(scworkbench)` can be polluted by host R libraries unless `.libPaths()`
  is forced inside container
- Python can be polluted by host packages unless `--no-home` and env cleanup are
  used
- these are important runtime notes, but they are not the main blocker
- the main blocker is the current memory-heavy matrix handoff design

## Recommended Next Dev Step

Inspect the current BPCells payload layout and decide quickly whether direct
Python reading is tractable.

If yes:

- implement Python matrix getter support in `pybench`
- switch `peakvi_fit` to direct bundle reads

If no:

- implement a chunked or scratch-backed sparse handoff that replaces Matrix
  Market while keeping the op contract unchanged
