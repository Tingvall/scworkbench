# AnnData Ingest Contract Draft

This draft defines the first contract for importing `AnnData` / `.h5ad`
datasets into a `scworkbench` bundle through `pybench`.

It is intentionally aligned with:

- [staged_bundle_assembly_draft.md](/home/dirk/Projects/lymphocyte_trajectory/scworkbench/docs/staged_bundle_assembly_draft.md)
- [pybench_integration_contract.md](/home/dirk/Projects/lymphocyte_trajectory/scworkbench/docs/pybench_integration_contract.md)
- [pybench_op_protocol_v1.md](/home/dirk/Projects/lymphocyte_trajectory/scworkbench/docs/pybench_op_protocol_v1.md)

## Core Rule

`AnnData` is a source adapter.

It is not the semantic center of the bundle.

The canonical concepts remain:

- bundle
- cell universe
- matrix
- space
- metadata
- cell set
- feature set

## Ownership Boundary

### `scworkbench` engine owns

- staged assembly semantics
- validation of bundle concepts
- canonical meanings of cells, matrices, spaces, sets
- manifest/schema authority

### `pybench` owns

- reading `.h5ad` / `AnnData`
- extracting cells, layers, metadata, spaces
- writing those contributions into the bundle under the staged assembly contract

This follows:

- centralize the contract, decentralize the compute

## Why `pybench`

This should go through `pybench`, not through `reticulate` or Seurat
conversion, because:

- `AnnData` is Python-native
- `pybench` already reads bundles directly
- `pybench` already writes some bundle payloads directly
- avoiding R<->Python object transfer is a core integration goal

## Scope Of V1

V1 is bundle assembly, not analysis provenance.

That means:

- import cells from `obs`
- import metadata from `obs`
- import one or more matrices from `X` / `layers`
- import one or more spaces from `obsm`
- optionally import feature annotations from `var`

V1 does not need:

- trajectory/model import
- arbitrary `uns` import
- full Scanpy object reconstruction in R
- conversion through Seurat

## Canonical Source Mapping

The first mapping should be:

- `adata.obs_names` -> `cell_id`
- `adata.obs` -> cell metadata
- `adata.var_names` -> `feature_id`
- `adata.var` -> feature annotations where possible
- `adata.X` or `adata.layers[name]` -> matrix payload
- `adata.obsm[name]` -> space payload

Optional later:

- `adata.varm`
- `adata.obsp`
- `adata.uns`
- feature sets / cell sets encoded in source metadata

## Cell Identity Contract

The adapter must establish one canonical bundle cell universe.

Rules:

- `cell_id` comes from `obs_names` unless explicitly overridden
- cell IDs must be unique after normalization
- the adapter must not silently reorder cells relative to `obs_names`
- the first source that defines cells normally defines `core`

If multiple staged imports are used:

- later imports attach to existing `cell_id`
- mismatched cell IDs fail clearly
- partial overlap behavior must be explicit, not implicit

## Matrix Contract

AnnData matrix import must target the staged assembly matrix contract, not a
special AnnData-only storage path.

V1 writer contract:

- input:
  - dense/sparse matrix-like payload from `adata.X` or `adata.layers[name]`
  - ordered `cell_id`
  - ordered `feature_id`
- output:
  - canonical bundle matrix registration row
  - feature registry rows
  - BPCells-backed fragment or bundle-native matrix payload equivalent

Required semantics:

- preserve source cell order and feature order at write time
- register feature IDs before or during matrix attach
- matrix ID is explicit and engine-owned
- layer naming does not define bundle semantics by itself

Recommended first mapping:

- `X` -> explicit chosen matrix ID
- `layers["counts"]` -> `RNA_counts` or user-specified matrix ID
- other layers imported only when explicitly requested

## Space Contract

AnnData `obsm` entries map to bundle spaces.

Rules:

- one `obsm` key -> one `space_id`
- 2D spaces should use the canonical 2D path
- higher-dimensional embeddings should use `space_coords`
- row order must align exactly to canonical `cell_id`

This should reuse the existing Python writer shape already present in
`pybench.spaces_write.add_space()`.

## Metadata Contract

`obs` columns map to bundle cell metadata.

Rules:

- metadata is attached by `cell_id`
- scalar columns only in V1
- categorical/string/numeric/bool columns supported
- nested/object columns are skipped unless explicitly normalized

V1 should fail or warn on unsupported object columns rather than writing opaque
Python objects into SQLite.

## Feature Annotation Contract

`var` may contribute feature annotation rows when fields map cleanly to bundle
feature columns.

V1 minimum:

- `feature_id` from `var_names`
- `feature_type` explicit or defaulted

Optional mapping when present:

- `chr`
- `start`
- `end`

The adapter must not invent genome semantics from arbitrary `var` columns.

## Source Adapter API Shape

The canonical engine-side staged assembly surface should remain:

- `wb_init_bundle()`
- `wb_define_cells()`
- `wb_attach_matrix()`
- `wb_attach_space()`
- `wb_attach_metadata()`

The Python-side adapter should mirror that shape, not replace it.

Recommended `pybench` modules:

- `pybench.ingest.anndata`
- `pybench.ingest.bundle_write`

Recommended functions:

```python
open_anndata(source) -> AnnData | backed-like handle
anndata_cell_frame(ad) -> pd.DataFrame
anndata_feature_frame(ad) -> pd.DataFrame
anndata_matrix_payload(ad, layer=None) -> MatrixPayload
anndata_space_payload(ad, obsm_key) -> SpacePayload
write_cells(...)
write_metadata(...)
write_matrix(...)
write_space(...)
```

Or a higher-level staged wrapper:

```python
ingest_anndata_stage(
    bundle_dir,
    source,
    *,
    define_cells=False,
    matrix_map=None,
    space_map=None,
    metadata_cols=None,
    feature_type="feature",
)
```

## Handoff Style

This is not naturally an op in the same sense as `palantir_fit`.

It is better modeled as staged assembly orchestration.

So the first implementation should prefer:

- a direct Python API
- or a small Python CLI for staged assembly

over forcing AnnData import through the op protocol.

If later we want a bench-visible import action, that can wrap this staged
assembly adapter.

## Validation Rules

The adapter must validate:

- bundle exists and is writable
- required bundle tables exist
- cell IDs are unique
- feature IDs are unique within matrix
- imported spaces align to imported/defined cells
- later-stage imports do not silently create new cells unless explicitly asked

## Failure Semantics

Fail clearly on:

- duplicate cell IDs
- duplicate feature IDs after normalization
- unknown target cells on attach
- shape mismatch between matrix and cells/features
- `obsm` row count mismatch
- unsupported column/object types in V1

Prefer:

- explicit warnings for skipped metadata columns
- explicit errors for broken alignment

## Transaction / Atomicity Guidance

AnnData import can be large.

So writes should be atomic per stage:

- define cells transaction
- matrix attach transaction
- space attach transaction
- metadata attach transaction

Do not leave a half-written matrix or space advertised as complete.

This is especially important because staged import is meant to survive loading
source objects one at a time.

## Memory Discipline

This adapter exists partly because source objects can be large.

V1 should support a one-object-at-a-time workflow:

1. load AnnData
2. define cells and attach selected matrices/spaces
3. close source object
4. continue with another source if needed

If backed mode is available, use it where practical.

But the contract should not depend on backed mode being present.

## Compatibility With Existing `pybench`

What already exists and should be reused:

- bundle open/close
- direct bundle getters
- direct artifact payload writers
- direct space writer

What is missing:

- staged assembly writers for cells/metadata/matrices
- feature registry writer
- AnnData extraction/normalization helpers

## Recommended First Implementation Slice

1. Add Python-side staged write helpers:
- write/define cells
- write metadata
- write feature registry rows
- write matrix registration + payload

2. Add `pybench.ingest.anndata`:
- open `.h5ad`
- normalize `obs`, `var`, `X/layers`, `obsm`

3. Support one concrete workflow:
- initialize bundle in R
- Python AnnData stage defines cells and attaches one matrix
- Python AnnData stage attaches one or more spaces

4. Add one real parity/integration test:
- small `.h5ad`
- resulting bundle opens in R
- `wb_cells()`, `wb_matrices()`, `wb_spaces()`, `wb_slice()` work as expected

## Non-Goals For V1

- full parity with every AnnData convention
- import of arbitrary graph objects
- import of Python analysis provenance into bench provenance
- automatic magical mapping of all layers and reductions

## Short Plan

1. Extend staged assembly docs to name `AnnData` as the first non-Seurat
   adapter.
2. Add Python staged assembly writers in `pybench`.
3. Add `pybench.ingest.anndata`.
4. Validate on one real `.h5ad`.
5. Only then consider a bench-facing convenience wrapper.
