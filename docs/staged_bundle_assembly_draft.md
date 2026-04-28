# Staged Bundle Assembly Draft

This draft defines the intended canonical workflow for building a bundle from
multiple transient sources.

It is source-agnostic by design.

Seurat is only an adapter example, not the semantic center.

For the practical Seurat-backed one-object-at-a-time workflow, see:

- [multisource_seurat_bundle_workflow.md](/home/dirk/Projects/lymphocyte_trajectory/scworkbench/docs/multisource_seurat_bundle_workflow.md)

## Why This Exists

`scworkbench` already treats the bundle as the durable analysis unit and source
objects as temporary import inputs.

That matters for real workflows where:

- modalities live in separate source objects
- one source object cannot fit in memory at the same time as another
- data should be written into the bundle incrementally
- the final bundle should still expose one logical multimodal view

The architecture already supports this in spirit:

- cells can be ingested into a bundle
- matrices, spaces, and metadata can be attached later
- matrix storage is fragment-based and getter-mediated

The missing piece is a canonical staged assembly API and workflow.

## Core Rule

Build the bundle in stages.

Do not require all source objects to coexist in memory.

The bundle is canonical.
Source objects are temporary loaders.

## Canonical Workflow

The intended workflow is:

1. initialize the bundle
2. define the canonical cell universe
3. attach metadata, matrices, spaces, and sets in stages
4. close and reopen the bundle as needed
5. continue attaching from additional sources

Example shape:

1. load source object A
2. initialize bundle and define cells
3. attach RNA matrices and RNA spaces
4. remove source object A from memory
5. load source object B
6. attach ATAC matrices and ATAC spaces to the same cells
7. remove source object B from memory
8. continue with feature sets, cell sets, or additional modalities

## What Is Canonical

The canonical concepts are:

- bundle
- cell universe
- matrix
- space
- metadata
- cell set
- feature set

The canonical concepts are not:

- Seurat assay
- Seurat reduction
- one-shot publish
- one source object containing everything

## Cell Universe

The bundle must establish one canonical cell universe.

That universe should normally correspond to `core`.

Interpretation:

- `core` means the main bundle cell universe
- it does not mean every cell has every modality
- modality availability is a separate concern

If needed, additional sets may describe modality presence, for example:

- `set:has_rna`
- `set:has_atac`
- `set:has_multiome`

But `core` should remain the main intended analysis universe.

## Storage Model Implication

The current data layer already fits staged assembly:

- `wb_ingest_cells()` creates new cells and memberships
- `wb_attach_to_cells()` attaches matrices, spaces, and metadata to existing
  cells
- attached matrices are written as BPCells fragments
- getters unify registered fragments into one logical matrix view

That means staged assembly is not a new storage concept.

It is a canonical workflow over the existing storage model.

## Engine Boundary

Staged assembly is an engine concern.

Clients may orchestrate it, but must not redefine the semantics.

This implies:

- cell identity matching is engine-owned
- attach validation is engine-owned
- matrix/space registration is engine-owned
- multimodal logical unification is engine-owned

## Proposed API Shape

The exact exported names may change, but the conceptual API should look like
this.

This section now proposes a concrete first-pass public API to build toward.

### 1. Bundle Initialization

Create an empty or minimally seeded bundle.

Proposed export:

```r
wb_init_bundle(
  out_dir,
  bundle_id = NULL,
  bundle_name = NULL,
  overwrite = FALSE
)
```

Behavior:

- create bundle directory structure
- create SQLite database
- bootstrap canonical schema
- write initial `manifest.json`
- return an open bundle handle

Implementation target:

- extract schema/bootstrap logic from `wb_publish_app_bundle()`
- reuse `wb_open_bundle()` as the canonical open path after initialization

This must not imply any source format.

### 2. Define Cells

Declare the canonical cell universe.

Proposed export:

```r
wb_define_cells(
  bundle,
  cell_ids,
  metadata = NULL,
  dataset_id = "dataset_1",
  set_name = "core",
  overwrite = FALSE,
  source = "assembly"
)
```

Behavior:

- establish the canonical bundle cell universe
- write rows into `cells`
- create membership rows for `set_name`
- treat `set_name = "core"` as the default main bundle universe
- optionally attach metadata during definition

Implementation target:

- thin wrapper over `wb_ingest_cells()`
- but with naming and docs that make “define the bundle cell universe” explicit

This layer should stay thin over `wb_ingest_cells()` where possible.

### 3. Attach Modalities

Attach matrices and spaces to existing cells.

Proposed exports:

```r
wb_attach_matrix(
  bundle,
  matrix_id,
  mat,
  layer = "counts",
  feature_type = "feature",
  description = NULL,
  source = "assembly"
)

wb_attach_space(
  bundle,
  space_id,
  coords,
  description = NULL,
  source = "assembly"
)

wb_attach_metadata(
  bundle,
  metadata,
  source = "assembly"
)
```

Behavior:

- attach one modality contribution at a time to existing cells
- validate by bundle `cell_id`
- write matrices as fragments
- register spaces and metadata in canonical stores

Implementation target:

- thin wrappers over `wb_attach_apply()` / `wb_attach_to_cells()`
- prefer one canonical attach surface internally
- do not re-encode attach validation in a new layer

### 4. Attach Sets

Attach cell sets and feature sets independently of source format.

Proposed exports:

```r
wb_add_cell_set(bundle, set_name, cell_ids, source = "assembly", ...)
wb_add_feature_set(bundle, matrix_id, feature_set, feature_ids, ...)
```

Behavior:

- register analysis-relevant sets after cells/modalities already exist
- keep these independent from source import

Implementation target:

- reuse existing set storage helpers where available
- avoid making set creation a side effect of a specific source adapter

### 5. Source Adapters

Proposed Seurat-facing exports:

```r
wb_define_cells_from_seurat(bundle, seurat, dataset_col = NULL, set_name = "core", ...)
wb_attach_matrix_from_seurat(bundle, seurat, matrix_id, assay, layer = "counts", ...)
wb_attach_spaces_from_seurat(bundle, seurat, reductions = NULL, ...)
```

Behavior:

- load one source object
- map source concepts to canonical engine concepts
- call the canonical staged assembly API
- allow source object to be dropped from memory immediately afterward

These functions are adapters, not canonical semantics.

## Source Adapters

Source-specific helpers should sit on top of the canonical assembly API.

Examples:

- `wb_from_seurat_cells()`
- `wb_from_seurat_matrix()`
- `wb_from_seurat_spaces()`
- future adapters for AnnData, Arrow, text files, or custom loaders

AnnData should be the first non-Seurat adapter, implemented through `pybench`
rather than through Seurat conversion or `reticulate`.

The source adapter contract is:

- resolve source object contents
- map them onto canonical engine concepts
- call the canonical assembly API

The source adapter must not define bundle semantics.

## Seurat As The First Adapter

Seurat remains useful as a first adapter because it is a common starting point.

But the intended workflow is not:

- make one giant Seurat object
- publish once

The intended workflow is:

- load one Seurat object
- attach what it owns
- garbage collect it
- load the next Seurat object
- attach what it owns

That is the main reason staged assembly exists.

## Relationship To `wb_publish_app_bundle()`

`wb_publish_app_bundle()` should be treated as a convenience wrapper, not the
canonical center of bundle construction.

Long-term options:

- keep it as a one-shot convenience wrapper over staged assembly
- or gradually refactor it internally to call the staged assembly surfaces

But the architecture should no longer imply that one-shot Seurat publish is the
core model.

## First Working Example

The first end-to-end implementation target should be a real staged assembly
workflow, not just API scaffolding.

Target script shape:

```r
b <- wb_init_bundle("bcell_multisource", bundle_name = "B cell multisource")

rna <- readRDS("rna_object.rds")
b <- wb_define_cells_from_seurat(b, rna, dataset_col = "orig.ident", set_name = "core")
b <- wb_attach_matrix_from_seurat(b, rna, matrix_id = "RNA_counts", assay = "RNA")
b <- wb_attach_spaces_from_seurat(b, rna, reductions = c("pca", "umap.rna"))
rm(rna); gc()

atac <- readRDS("atac_object.rds")
b <- wb_attach_matrix_from_seurat(b, atac, matrix_id = "ATAC_counts", assay = "peaks")
b <- wb_attach_spaces_from_seurat(b, atac, reductions = c("lsi", "umap.atac"))
rm(atac); gc()

wb_close_bundle(b)
```

Success criteria:

- one bundle
- one canonical cell universe
- RNA and ATAC matrices both readable through getters
- spaces from both stages available
- no requirement that both source objects coexist in memory

## Internal Refactor Needed First

Before the staged public API can be implemented cleanly, one internal change is
needed:

- extract bundle/schema/bootstrap logic out of `wb_publish_app_bundle()`

That should become an internal helper first, then a public initialization API.

Without that extraction, staged assembly would risk becoming a wrapper around
publisher internals instead of a clean engine surface.

## Validation Requirements

Staged assembly must validate:

- canonical cell identity matching
- matrix column cell IDs against bundle cells
- space cell IDs against bundle cells
- feature identity within each matrix
- duplicate and missing cell handling
- modality-specific partial coverage

The engine should provide dry-run validation and normalized apply behavior.

Existing attach/ingest adapter patterns are the reference here.

## Performance and Memory

The staged design exists partly for memory discipline.

The intended behavior is:

- source object loaded only for the duration of its contribution
- bundle write happens incrementally
- matrix payloads are persisted as BPCells fragments
- no requirement to materialize all modalities together in RAM

This is a primary design goal, not an accidental side effect.

## First Concrete Use Case

The first target workflow should be:

- source A contains RNA assay and RNA spaces
- source B contains ATAC peak assay and ATAC spaces
- both refer to the same cells
- final bundle contains:
  - one canonical cell universe
  - `RNA_counts`
  - `ATAC_counts`
  - relevant spaces
  - `core` as the main cell set

This use case should become a contract test and a documented example.

## What This Does Not Require Yet

This draft does not require:

- a fragment storage redesign
- a new primitive kind
- a new getter model
- Seurat-specific semantics in the engine core

It only requires making the staged workflow explicit and canonical.

## Implementation Priorities

1. extract bundle initialization/schema bootstrap from `wb_publish_app_bundle()`
2. implement `wb_init_bundle()`
3. implement `wb_define_cells()` as the canonical cell-universe entry point
4. implement thin attach wrappers over existing attach paths
5. add Seurat adapter helpers
6. build the real multisource working example and test
7. update publish/attach docs to point to staged assembly as canonical

## Design Constraints

- preserve getter boundary
- preserve fragment-based logical matrix view
- preserve source-agnostic bundle semantics
- keep clients thin
- do not make Seurat the canonical model

## Open Questions

- whether cell-universe establishment should be a new explicit API or a thin
  specialization of `wb_ingest_cells()`
- whether modality presence sets should be created automatically or only by
  explicit option
- how much convenience should live in Seurat adapters versus canonical assembly
  helpers
- whether `wb_publish_app_bundle()` should be deprecated eventually or retained
  indefinitely as a wrapper
