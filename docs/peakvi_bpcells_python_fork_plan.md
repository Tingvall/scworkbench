# PeakVI BPCells Python Fork Plan

Date: 2026-04-22

Audience: engine work on `scworkbench` + sibling `pybench`

Goal: replace the current `peakvi_fit` Matrix Market staging path with direct
Python reads from bundle-native BPCells matrix payloads.

## Current Status

This route is now working in practice.

Verified outcomes:

- Python `bpcells` fork can read `packed-double-matrix-v2` bundle matrices
- `pybench` now exposes a native bundle matrix getter and `peakvi_fit` uses it
- R-side `peakvi_fit` Matrix Market staging was removed
- full `signal` bundle ATAC matrix read succeeds inside the rebuilt full-stack image
- one-epoch full-matrix `peakvi_fit` smoke on `signal` succeeds inside the rebuilt full-stack image

Persistent local fork started:

- repo: `/home/dirk/Projects/BPCells_python_fork`
- branch: `python-noninteger-read`
- first fork commit: `2e7b83c`

Observed full `signal` matrix read:

- shape `(105642, 66191)`
- `nnz = 505072181`
- peak RSS about `11.98 GB`

Observed full `signal` one-epoch `peakvi_fit` smoke:

- `space = peakvi_space_signal_full_sif_smoke`
- `model_engine = peakvi`
- `total_sec = 372.4023`

## Decision

We will continue down the BPCells route.

The current best path is:

1. fork or patch the Python `bpcells` package
2. add non-integer matrix read support in the Python bindings
3. use that from `pybench` to read bundle matrices directly
4. remove the R-side Matrix Market export from `peakvi_fit`

This preserves the bundle as the canonical storage contract.

## What We Verified

### Core BPCells support exists already

Upstream C++ core supports sparse matrix storage and reading for:

- `uint32_t`
- `uint64_t`
- `float`
- `double`

Relevant upstream file:

- `BPCells/r/src/bpcells-cpp/matrixIterators/StoredMatrix.h`

`StoredMatrix<T>` has explicit version strings for:

- `packed-uint-matrix-v*`
- `packed-float-matrix-v*`
- `packed-double-matrix-v*`

For non-uint packed matrices it reads `val` directly as `T`.

### Python bindings are the actual bottleneck

Upstream Python files:

- `BPCells/python/src/matrix.hpp`
- `BPCells/python/src/matrix.cpp`
- `BPCells/python/src/bindings.cpp`
- `BPCells/python/src/bpcells/experimental/matrix.py`

Current Python binding layer hardcodes matrix I/O to `uint32_t`:

- `write_matrix_dir_from_memory(const Eigen::SparseMatrix<uint32_t> ...)`
- `load_matrix_dir_subset(...) -> vector<SparseMatrix<uint32_t>>`
- `load_matrix_dir_to_memory(...)` builds `StoredMatrix<uint32_t>`
- `load_matrix_memory_subset(...) -> vector<SparseMatrix<uint32_t>>`

Current Python wrapper hardcodes:

- `DirMatrix.dtype = np.uint32`
- `MemMatrix.dtype = np.uint32`

### Our bundles currently need non-integer read support

Real bundle matrices in `../demo/mat/*` are:

- `packed-double-matrix-v2`

and fail under current Python `bpcells` with a version mismatch against
`packed-uint-matrix-v2`.

## Minimal Fork Shape

### Stage 1: read support only

The smallest useful change is read support for float/double matrices.

Recommended binding shape:

- keep Python `DirMatrix` / `MemMatrix` public API stable
- add typed C++ helper functions under distinct names
- let Python dispatch based on the matrix `version` file

Concrete C++ binding additions:

- `load_matrix_dir_subset_uint32`
- `load_matrix_dir_subset_float`
- `load_matrix_dir_subset_double`
- `load_matrix_dir_to_memory_uint32`
- `load_matrix_dir_to_memory_float`
- `load_matrix_dir_to_memory_double`
- `load_matrix_memory_subset_uint32`
- `load_matrix_memory_subset_float`
- `load_matrix_memory_subset_double`

`dims_matrix_dir(...)` should become dtype-aware internally by inspecting the
matrix version and instantiating `StoredMatrix<T>` accordingly.

### Stage 2: Python wrapper dispatch

In `python/src/bpcells/experimental/matrix.py`:

- detect dtype from `<matrix_dir>/version`
- map:
  - `packed-uint-*` / `unpacked-uint-*` -> `np.uint32`
  - `packed-float-*` / `unpacked-float-*` -> `np.float32`
  - `packed-double-*` / `unpacked-double-*` -> `np.float64`
- dispatch `__getitem__` to the matching low-level binding
- dispatch `MemMatrix` materialization to the matching low-level binding

### Stage 3: tests

Add Python tests for:

- integer matrix roundtrip still works
- float matrix slice works
- double matrix slice works
- real on-disk `packed-double-matrix-v2` directory can be opened and sliced

## Patch Prototype Status

A proof-of-concept patch was prepared in:

- `/tmp/BPCells_upstream/python/src/matrix.hpp`
- `/tmp/BPCells_upstream/python/src/matrix.cpp`
- `/tmp/BPCells_upstream/python/src/bindings.cpp`
- `/tmp/BPCells_upstream/python/src/bpcells/experimental/matrix.py`

That patch is the right architectural shape:

- it keeps the public Python surface stable
- it adds typed C++ binding entry points
- it makes Python dispatch from the on-disk matrix version

It has not yet been compiled successfully in the current host environment
because the local source-build prerequisites are incomplete.

The patch is captured in this repo at:

- `third_party/patches/bpcells-python-noninteger-read.patch`

Helper script to prepare a forked clone:

- `scripts/prepare_bpcells_python_fork.sh`

Container-side build/test harness after the full-stack image is rebuilt:

- `scripts/build_test_bpcells_python_fork_in_container.sh`

## Build Requirements For The Fork

To build Python `bpcells` from source we need at minimum:

- `python3-dev`
- `libhdf5-dev`
- `libeigen3-dev`
- `libhwy-dev`
- `pybind11`
- `setuptools-scm`
- compiler with C++17 support

Notes from local checks:

- host machine lacked `Python.h`, Highway headers, and HDF5 headers in the
  expected build paths
- the full-stack container has `Python.h` and HDF5 headers
- the full-stack container does not currently have Highway dev headers

So the container definition will need one more system dependency if we want to
build a forked `bpcells` package inside that environment:

- add `libhwy-dev`

## `pybench` Integration Plan

Once the forked `bpcells` package can read float/double BPCells dirs:

### New getter

Add a bundle-native matrix getter in `../../pybench/src/pybench/getters.py`.

Suggested API:

- `matrix_csr(bundle, matrix_id, cell_ids=None, feature_ids=None)`

Responsibilities:

1. resolve matrix registry row from `matrices`
2. resolve matrix payload path from bundle root + `matrices.path`
3. open the BPCells dir via Python `bpcells.experimental.DirMatrix`
4. map requested `cell_ids` to canonical bundle column positions
5. map requested `feature_ids` to canonical bundle row positions
6. return sparse matrix in deterministic order plus resolved ids

Recommended return:

- sparse matrix
- resolved feature ids
- resolved cell ids

### `peakvi_fit` change

Then replace the current `_build_anndata(...)` path in:

- `../../pybench/src/pybench/ops/peakvi_fit.py`

Target path:

1. open bundle
2. use `matrix_id` + `cell_ids` from request
3. read sparse matrix directly from BPCells bundle payload
4. build `AnnData`
5. train PeakVI
6. persist outputs exactly as today

The R request now sends only symbolic metadata for this path.

## `scworkbench` Change

After `pybench` can consume bundle matrices directly, update:

- `R/op_peakvi.R`

Removed:

- `wb_matrix_read_features(...)` staging for `peakvi_fit`
- temporary Matrix Market write
- temporary feature/cell id files

Keep:

- stable `peakvi_fit` user-facing contract
- preregistered outputs
- receipt / provenance / model artifact behavior

## Container Change

Current full-stack container installs:

- `pybench` from sibling repo
- `scvi-tools`

To support the fork route cleanly, the container should eventually install a
forked `bpcells` package as part of the Python runtime layer.

Preferred packaging options:

1. install from a forked git ref during image build
2. vendor the fork into a sibling repo and install from local path

Avoid:

- manual cluster-side `pip install` after image build
- one-off patching inside a running container

## Recommended Execution Order

1. Make the BPCells Python fork compile in a proper build environment.
Preferred first target is the rebuilt full-stack container.
The container-side BPCells build harness should export:
- `CPATH=/usr/include/eigen3:/usr/include/hdf5/serial:/usr/include`
- `LIBRARY_PATH=/usr/lib/x86_64-linux-gnu/hdf5/serial:/usr/lib/x86_64-linux-gnu`
2. Validate slicing on:
   - tiny uint matrix
   - tiny double matrix
   - real `../demo/mat/ATAC_counts`
3. Add `pybench` bundle-native matrix getter using the forked package.
4. Update `pybench.ops.peakvi_fit` to use the getter.
5. Remove Matrix Market staging from `R/op_peakvi.R`.
6. Rebuild the full-stack container with the forked `bpcells`.
7. Run in-container `peakvi_fit` smoke on demo bundle.
8. Run production-style test on `signal` / B-cell trajectory target.

## Non-Goals For This First Pass

- changing the external `peakvi_fit` contract
- redesigning all matrix ops around Python BPCells immediately
- fixing integer-write semantics in Python `bpcells` at the same time

The first win is direct non-integer bundle reads for PeakVI.
