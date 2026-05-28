# Multi-Source Seurat Bundle Workflow

This is the practical recipe for building one bundle from multiple Seurat
sources when they cannot coexist in memory.

Use this when:

- RNA and ATAC live in separate Seurat objects
- objects are stored as `.Rdata` files
- you want one canonical bundle
- you must load one source, write it, garbage collect it, then load the next

This is the canonical workflow for this use case.

Seurat is only the source adapter.

## Core Rule

The bundle is canonical.

Seurat objects are temporary loaders.

Do not try to merge huge Seurat objects just to publish a bundle.

The intended flow is:

1. initialize bundle
2. load source A
3. define cells and attach source A payloads
4. remove source A from memory
5. load source B
6. attach source B payloads to the same cells
7. remove source B from memory

## Preconditions

Before attaching a second source, confirm:

- both objects use the same canonical `cell_id`
- the cell order may differ, but the IDs must match logically
- assay/reduction names are known

For Seurat-backed imports, canonical cell ids are `colnames(seurat)`.

## Canonical API

The staged assembly surface is:

```r
b <- wb_init_bundle(...)
wb_define_cells(...)
wb_attach_matrix(...)
wb_attach_space(...)
wb_attach_metadata(...)
```

The Seurat adapters over that surface are:

```r
wb_define_cells_from_seurat(...)
wb_attach_matrix_from_seurat(...)
wb_attach_spaces_from_seurat(...)
```

## Minimal Pattern

```r
library(scworkbench)
library(SeuratObject)

load_single_object <- function(path) {
  e <- new.env(parent = emptyenv())
  nm <- load(path, envir = e)
  e[[nm[[1L]]]]
}

b <- wb_init_bundle(
  out_dir = "/path/to/my_bundle",
  bundle_id = "my_bundle",
  bundle_name = "My bundle",
  overwrite = TRUE
)

rna <- load_single_object("/path/to/rna.Rdata")

wb_define_cells_from_seurat(
  bundle = b,
  seurat = rna,
  dataset_col = "orig.ident",
  set_name = "core",
  source = "seurat_rna"
)

wb_attach_matrix_from_seurat(
  bundle = b,
  seurat = rna,
  matrix_id = "RNA_counts",
  assay = "RNA",
  layer = "counts",
  feature_type = "gene",
  source = "seurat_rna"
)

wb_attach_spaces_from_seurat(
  bundle = b,
  seurat = rna,
  reductions = c("pca"),
  overwrite = TRUE,
  source = "seurat_rna"
)

rna_ids <- colnames(rna)
rm(rna)
gc()

atac <- load_single_object("/path/to/atac.Rdata")
stopifnot(identical(rna_ids, colnames(atac)))

wb_attach_matrix_from_seurat(
  bundle = b,
  seurat = atac,
  matrix_id = "ATAC_counts",
  assay = "peaks",
  layer = "counts",
  feature_type = "peak",
  source = "seurat_atac"
)

wb_attach_spaces_from_seurat(
  bundle = b,
  seurat = atac,
  reductions = c("lsi", "umap.atac"),
  overwrite = TRUE,
  source = "seurat_atac"
)

rm(atac, rna_ids)
gc()

wb_refresh_manifest(b)
wb_close_bundle(b)
```

## Worked Example

The first real staged multisource import built:

- bundle: `Signal_history_Ref_bundle`
- source A: `Signal_history_Ref_RNA.Rdata`
- source B: `Signal_history_Ref_peaks.Rdata`

Result:

- `66191` cells in `core`
- matrices:
  - `RNA_counts`
  - `ATAC_counts`
- spaces:
  - `pca`
  - `lsi`
  - `umap.atac`

## What `core` Means

`core` is the canonical bundle cell universe.

It does not mean every cell has every modality.

If needed, add separate modality-availability sets later, for example:

- `set:has_rna`
- `set:has_atac`
- `set:has_multiome`

## What To Attach From Which Source

A good default is:

- RNA source:
  - define cells
  - attach `RNA_counts`
  - attach RNA-native reductions like `pca`
- ATAC source:
  - attach `ATAC_counts`
  - attach ATAC-native reductions like `lsi`, `umap.atac`

Do not duplicate the same space from multiple sources unless you mean to
replace it intentionally.

## Validation Checklist

After the build:

```r
b <- wb_open_bundle("/path/to/my_bundle")

wb_cell_sets(b)
wb_matrices(b)
wb_spaces(b)
wb_manifest(b)

wb_slice(b, matrix_id = "RNA_counts", features = some_genes, cells = some_cells)
wb_slice(b, matrix_id = "ATAC_counts", features = some_peaks, cells = some_cells)
```

You should confirm:

- `core` exists
- expected matrices exist
- expected spaces exist
- manifest counts look sane
- both matrices can be sliced through getters

## Failure Modes We Already Hit

These are real issues uncovered during the first live import.

### 1. Do not depend on full `Seurat` if `SeuratObject` is enough

Staged import should read assay layers from `SeuratObject` where possible.

If the full `Seurat` package is ABI-broken on a machine, the importer should
still work.

### 2. Cell definition must be bulk, not append-style

The canonical bundle cell universe should be written directly.

Do not route first-time bundle cell creation through a row-by-row append path if
that path was designed for smaller incremental ingest.

### 3. Metadata ingest must be set-based

Per-cell SQL updates do not scale.

For atlas-sized imports, metadata writes must use temporary tables and set-based
updates.

### 4. Attached matrices must register features

If a matrix is written physically but does not populate the `features` registry,
getter-based feature queries and slicing will be logically incomplete.

Staged assembly depends on attach.

So attach must register features, not just matrix fragments.

## Engine Boundary

This workflow is engine-owned.

Clients may wrap it, but clients must not redefine:

- cell identity matching
- matrix registration
- feature registration
- space registration
- manifest semantics

## Related Docs

- [staged_bundle_assembly_draft.md](/home/dirk/Projects/lymphocyte_trajectory/scworkbench/docs/staged_bundle_assembly_draft.md)
- [engine_extension_patterns.md](/home/dirk/Projects/lymphocyte_trajectory/scworkbench/docs/engine_extension_patterns.md)
