# AnnData / Pybench / BPCells Findings And Plan

This document records the current state of the AnnData ingest work, the
technical findings from reading and testing, and the recommended next steps.

It exists so the work can pause cleanly and resume later without rediscovery.

Related docs:

- [anndata_ingest_contract_draft.md](/home/dirk/Projects/lymphocyte_trajectory/scworkbench/docs/anndata_ingest_contract_draft.md)
- [staged_bundle_assembly_draft.md](/home/dirk/Projects/lymphocyte_trajectory/scworkbench/docs/staged_bundle_assembly_draft.md)
- [pybench_integration_contract.md](/home/dirk/Projects/lymphocyte_trajectory/scworkbench/docs/pybench_integration_contract.md)
- [pybench_api_inventory_draft.md](/home/dirk/Projects/lymphocyte_trajectory/scworkbench/docs/pybench_api_inventory_draft.md)
- [pybench_op_protocol_v1.md](/home/dirk/Projects/lymphocyte_trajectory/scworkbench/docs/pybench_op_protocol_v1.md)

## Executive Summary

The right architecture is now clear.

`AnnData` import should:

- go through `pybench`
- use staged bundle assembly semantics
- write BPCells matrix fragments natively from Python
- register those fragments in the existing bundle contract

The key technical uncertainty was:

- can Python-written BPCells directories be opened by R `BPCells` without
  special handling?

That answer is now:

- yes

This means the remaining work is not conceptual.

It is implementation work:

- matrix fragment registration in `pybench`
- feature registry writing
- integration tests

## Architectural Decision

### What AnnData import is

AnnData import is a source adapter.

It is not:

- a new bundle semantic model
- a Seurat conversion workflow
- an R-side reticulate bridge
- primarily an op-protocol feature

### Ownership boundary

`scworkbench` owns:

- staged assembly semantics
- canonical meanings of cells, matrices, spaces, metadata, sets
- bundle schema/manifest authority

`pybench` owns:

- reading `.h5ad` / `AnnData`
- extracting source-native contents
- writing those contents into the bundle under the staged assembly contract

This follows:

- centralize the contract, decentralize the compute

## Why Pybench Is The Right Place

After reviewing the current system, `pybench` is clearly the correct runtime
for AnnData ingestion because:

- `AnnData` is Python-native
- `pybench` already reads bundles directly
- `pybench` already writes bundle-native payloads directly
- `pybench` is already the intended Python-side runtime boundary

Relevant existing `pybench` surfaces:

- [bundle.py](/home/dirk/Projects/pybench/src/pybench/bundle.py)
- [getters.py](/home/dirk/Projects/pybench/src/pybench/getters.py)
- [spaces_write.py](/home/dirk/Projects/pybench/src/pybench/spaces_write.py)
- [artifacts_payload.py](/home/dirk/Projects/pybench/src/pybench/artifacts_payload.py)

This is much better than:

- forcing AnnData through Seurat
- using `reticulate`
- inventing a second ingest pathway centered in R

## Current Engine State

The R engine already has the right staged assembly shape:

- `wb_init_bundle()`
- `wb_define_cells()`
- `wb_attach_matrix()`
- `wb_attach_space()`
- `wb_attach_metadata()`

Relevant files:

- [bundle_init.R](/home/dirk/Projects/lymphocyte_trajectory/scworkbench/R/bundle_init.R)
- [ingest_cells.R](/home/dirk/Projects/lymphocyte_trajectory/scworkbench/R/ingest_cells.R)
- [attach_to_cells.R](/home/dirk/Projects/lymphocyte_trajectory/scworkbench/R/attach_to_cells.R)

The data layer already supports staged import well:

- cells are canonical
- matrices are fragment-based
- spaces are registry-backed
- getters reconstruct one logical view

This means AnnData ingest does not require a new storage concept.

It requires a new source adapter and Python-side matrix writer.

## Current Pybench State

The current `pybench` package already had:

- bundle open/close
- getters for cells/meta/features/spaces/sets
- space writing
- artifact payload writing
- Python op protocol support

What it did not have:

- staged bundle writers for cells
- staged metadata attach
- feature registry writing
- matrix fragment writing
- AnnData extraction helpers

## First Implementation Slice Already Added

A first partial slice was added in `pybench`:

- [ingest_bundle.py](/home/dirk/Projects/pybench/src/pybench/ingest_bundle.py)
- [ingest/anndata.py](/home/dirk/Projects/pybench/src/pybench/ingest/anndata.py)
- [ingest/__init__.py](/home/dirk/Projects/pybench/src/pybench/ingest/__init__.py)
- [test_anndata_ingest.py](/home/dirk/Projects/pybench/tests/test_anndata_ingest.py)

Current capabilities of that slice:

- define cells from `obs`
- attach metadata from `obs`
- attach spaces from `obsm`

Current explicit limitation:

- matrix writing is still marked as pending

This is intentional. It avoids pretending the matrix backend problem is solved
before BPCells parity is proven.

## BPCells Python Findings

### Package availability

The `bpcells` Python package exists and can be installed into the `pybench`
virtual environment.

In this environment, it was installed into:

- `../../pybench/.venv`

### Actual installed API

The installed package layout differs slightly from the docs shorthand.

Useful objects are under:

- `bpcells.experimental`
- especially `bpcells.experimental.DirMatrix`

The tested writer API is:

```python
from bpcells.experimental import DirMatrix
DirMatrix.from_scipy_sparse(scipy_mat, out_dir)
```

### Important caveat

The documented `from_h5ad(...)` path is not the right generic default for all
matrices, because BPCells Python is explicitly integer-oriented and documented
H5AD conversion truncates floating point values.

So the safe V1 path should target:

- counts-like integer matrices

not arbitrary normalized/log-transformed matrices.

## BPCells Python -> R Parity Test

This was the most important direct test.

### Question

If Python writes a BPCells directory, can R `BPCells::open_matrix_dir()` read it
unchanged?

### Test performed

Python:

- created a small `3 x 4` sparse integer matrix
- wrote it to:
  - `/tmp/bpcells_py_dir`

using:

```python
from scipy import sparse
from bpcells.experimental import DirMatrix
m = sparse.csc_matrix([[1,0,2,0],[0,3,0,4],[5,0,0,6]], dtype='int32')
DirMatrix.from_scipy_sparse(m, '/tmp/bpcells_py_dir')
```

R:

- opened the same directory with:

```r
BPCells::open_matrix_dir("/tmp/bpcells_py_dir")
```

### Result

R saw:

- dimensions `3 x 4`
- exact matrix contents:

```text
     [,1] [,2] [,3] [,4]
[1,]    1    0    2    0
[2,]    0    3    0    4
[3,]    5    0    0    6
```

### Conclusion

Python-written BPCells directories are readable by R BPCells in the current
environment.

This removes the largest architectural uncertainty.

## Name / Identity Findings

The Python-written BPCells directory contained:

- `row_names`
- `col_names`
- `shape`
- `storage_order`
- compressed index/value files

But in the test:

- `row_names` and `col_names` were empty

The currently installed Python API did not obviously expose row/column name
setters during quick inspection.

This is acceptable for the bundle contract because canonical identity is not
required to live inside the BPCells directory alone.

The bundle already stores canonical identity in:

- `matrix_fragments.feature_ids_json`
- `matrix_fragments.cell_ids_json`

So the bundle registry remains the real authority on identity/order, even if
the BPCells directory names are empty.

## What This Means For The Matrix Contract

The correct Python-side bundle matrix write path is:

1. extract a counts-like sparse matrix from AnnData
2. write BPCells directory from Python
3. register matrix row in `matrices`
4. register feature rows in `features`
5. register fragment row in `matrix_fragments`
6. rely on existing R getters to read it normally

This should mirror the current R-side attach path in:

- [attach_to_cells.R](/home/dirk/Projects/lymphocyte_trajectory/scworkbench/R/attach_to_cells.R)

The key registry row fields that matter:

- `matrices.matrix_id`
- `matrices.layer`
- `matrices.feature_type`
- `matrices.n_features`
- `matrices.n_cells`
- `matrices.storage`
- `matrices.path`

and in `matrix_fragments`:

- `fragment_id`
- `matrix_id`
- `storage`
- `path`
- `n_features`
- `n_cells`
- `feature_ids_json`
- `cell_ids_json`
- `source`
- `created_at`

## Remaining Gap

The remaining hard work is not BPCells directory compatibility anymore.

It is bundle registration parity.

Specifically, `pybench` still needs:

- feature registry writer
- matrix registry writer
- matrix fragment registry writer
- integration test that writes a full fragment and then reads it through R
  `wb_slice()`

## Recommended V1 Scope

The correct narrow first production scope is:

- AnnData cells from `obs`
- AnnData metadata from `obs`
- AnnData spaces from `obsm`
- AnnData integer/count matrices from `X` or explicit layers

Do not try in V1:

- arbitrary float layers
- graphs
- full `uns` import
- magical import of every AnnData structure

## Recommended Implementation Order

### 1. Finish Python-side staged matrix writing

Add `pybench` functions for:

- feature registration
- matrix registry creation/update
- matrix fragment registration
- BPCells directory write from scipy sparse matrix

Suggested module:

- `pybench.ingest_bundle`

### 2. Extend the AnnData adapter

In:

- [anndata.py](/home/dirk/Projects/pybench/src/pybench/ingest/anndata.py)

add:

- extraction of a chosen matrix/layer
- validation that it is counts-like / integer-safe
- call into the BPCells fragment writer

### 3. Add one real integration test

The critical test is:

1. initialize a minimal bundle
2. ingest AnnData cells + matrix + spaces from Python
3. open the resulting bundle in R
4. confirm:
   - `wb_cells()`
   - `wb_matrices()`
   - `wb_spaces()`
   - `wb_slice()`
   all work normally

### 4. Only then add convenience wrappers

After matrix parity is real, consider:

- a small bench-facing convenience wrapper
- or a documented staged workflow

But not before.

## Concrete Next Tasks

1. Add `pybench` feature writer for `features`.
2. Add `pybench` matrix registry writer for `matrices`.
3. Add `pybench` fragment registry writer for `matrix_fragments`.
4. Add BPCells sparse-matrix writer wrapper around
   `DirMatrix.from_scipy_sparse(...)`.
5. Extend AnnData adapter to import one integer matrix.
6. Add cross-runtime parity test against R getters.

## Current Status Label

The AnnData ingest effort should currently be considered:

- architecturally decided
- partially implemented
- technically de-risked on BPCells directory compatibility
- still incomplete on full matrix fragment registration

## Short Bottom Line

The hardest conceptual question is answered:

- Python-native BPCells output is readable by R BPCells

So the path is now clear:

- keep AnnData in `pybench`
- keep bundle semantics in the engine
- finish matrix fragment registration parity
- then the AnnData ingester becomes real
