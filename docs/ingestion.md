# Canonical Container Ingestion

scworkbench can initialize bundles from the dominant single-cell containers:
Seurat, SingleCellExperiment, AnnData/h5ad, and 10x Matrix Market triplets.
Importer v1 packages container state into existing bundle primitives; it does
not reconstruct upstream preprocessing provenance or import every model, graph,
or tool-history slot.

## APIs

```r
wb_bundle_from_seurat(input, bundle_dir, ...)
wb_bundle_from_sce(input, bundle_dir, ...)
wb_bundle_from_h5ad(input, bundle_dir, ...)
wb_bundle_from_10x_mtx(input, bundle_dir, ...)
```

Each `input` may be an in-memory object where applicable, or a path:

- Seurat: Seurat object or `.rds`
- SingleCellExperiment: SingleCellExperiment object or `.rds`
- AnnData: `.h5ad` path, imported through `zellkonverter::readH5AD()`
- 10x Matrix Market: directory containing one or more triplets, or an explicit
  sample table with `sample_id`, `matrix_path`, `barcodes_path`, and
  `features_path`.

Important cell identity rule:

- Imported bundle `cell_id` values must be unique.
- The core `wb_define_cells()` API rejects duplicate `cell_id` values; importer-specific repair must happen before canonical bundle cells are defined.
- `wb_bundle_from_h5ad()` defaults to `duplicate_cell_id_policy = "make_unique"` because published h5ad files can contain duplicated `.obs_names`.
- `wb_bundle_from_sce()` defaults to `duplicate_cell_id_policy = "error"` unless the caller explicitly opts into repair.
- With `"make_unique"`, IDs are repaired deterministically with R `make.unique(..., sep = ".")`.
- Original observation names are preserved in metadata. For h5ad this defaults to `ann_data_obs_name`; for direct SCE ingestion this defaults to `original_cell_id`.
- The ingestion report records the duplicate policy, duplicate row count, duplicate unique-ID count, and original-ID metadata column.
- `wb_bundle_from_10x_mtx()` defaults to `duplicate_cell_id_policy = "prefix"`, which creates final cell IDs as `{sample_id}:{barcode}` and preserves the original barcode in cell metadata.

Important feature identity rule:

- Imported bundle `feature_id` values must be unique within each matrix.
- `wb_bundle_from_h5ad()` defaults to `duplicate_feature_id_policy = "make_unique"` because published h5ad files can contain duplicated `.var_names`.
- `wb_bundle_from_sce()` defaults to `duplicate_feature_id_policy = "error"` unless the caller explicitly opts into repair.
- `wb_bundle_from_10x_mtx()` defaults to `duplicate_feature_id_policy = "error"` because Cell Ranger feature IDs are normally expected to be unique.
- With `"make_unique"`, feature IDs are repaired deterministically with R `make.unique(..., sep = ".")`.
- Original feature/variable names are preserved in feature metadata. For h5ad this defaults to `ann_data_var_name`; for direct SCE ingestion this defaults to `original_feature_id`.
- The ingestion report records the duplicate feature-ID policy, duplicate row count, duplicate unique-ID count, and original-ID feature metadata column.

Important h5ad atomicity rule:

- `wb_bundle_from_h5ad()` builds in a sibling staging directory and promotes the staged bundle to `bundle_dir` only after read, identifier repair, SCE import, matrix attach, reduced dimension import, and report promotion succeed.
- `wb_bundle_from_10x_mtx()` uses the same staging principle and promotes only after all library triplets, matrix fragments, feature metadata, and the ingest report are written.
- On failure, the staged directory is removed. When `overwrite = TRUE` or no final bundle exists, `bundle_dir` is replaced by a non-bundle directory containing `INGEST_FAILED.json`.
- `INGEST_FAILED.json` records the phase reached, source path, selected duplicate-ID policies, and final error text. It is deliberately not a valid bundle.

Op-style aliases are also exported:

```r
bundle_ingest_seurat(input, bundle_dir, ...)
bundle_ingest_sce(input, bundle_dir, ...)
bundle_ingest_h5ad(input, bundle_dir, ...)
bundle_ingest_10x_mtx(input, bundle_dir, ...)
```

## Examples

### Seurat

```r
seurat <- readRDS("my_seurat_object.rds")

b <- wb_bundle_from_seurat(
  seurat,
  bundle_dir = "bundles/my_seurat_bundle",
  assays = c("RNA"),
  layers = "counts",
  categorical_cols = c("seurat_clusters"),
  overwrite = TRUE
)

wb_matrices(b)
wb_spaces(b)
wb_cell_sets(b)
```

### SingleCellExperiment

```r
sce <- readRDS("reprocessed_allen_tophat_counts_sce.rds")

b <- wb_bundle_from_sce(
  sce,
  bundle_dir = "bundles/allen_sce_bundle",
  assays = c("tophat_counts"),
  overwrite = TRUE
)

wb_matrices(b)
wb_meta(b)
wb_art_list(b)
```

### AnnData/h5ad

```r
b <- wb_bundle_from_h5ad(
  "pbmc3k_processed_scanpy.h5ad",
  bundle_dir = "bundles/pbmc3k_h5ad_bundle",
  categorical_cols = c("louvain"),
  duplicate_cell_id_policy = "make_unique",
  duplicate_feature_id_policy = "make_unique",
  overwrite = TRUE
)

wb_matrices(b)
wb_spaces(b)
wb_cell_sets(b)
```

### 10x Matrix Market

```r
samples <- data.frame(
  sample_id = c("sample1", "sample2"),
  matrix_path = c("sample1_matrix.mtx.gz", "sample2_matrix.mtx.gz"),
  barcodes_path = c("sample1_barcodes.tsv.gz", "sample2_barcodes.tsv.gz"),
  features_path = c("sample1_features.tsv.gz", "sample2_features.tsv.gz"),
  stage = c("Pupa", "Nurse")
)

b <- wb_bundle_from_10x_mtx(
  input = "extracted_10x_directory",
  bundle_dir = "bundles/my_10x_bundle",
  sample_table = samples,
  matrix_id = "RNA_counts",
  overwrite = TRUE
)

wb_matrices(b)
wb_meta(b, cells = head(wb_cells(b)))
wb_art_list(b)
```

## Mapping Summary

### Seurat

| Seurat state | scworkbench object | Notes |
| --- | --- | --- |
| `assays[[assay]]` layer/slot | matrix | Imported with `wb_attach_matrix()`; default layer is `counts`. |
| `meta.data` | cell metadata | Stored in the bundle `cells` table and discoverable with `wb_meta()`. |
| categorical metadata | cell sets | Optional; one set per column/value. |
| `reductions` embeddings | spaces | Imported with `wb_add_space()`. |
| identities/clusters | cell metadata/cell sets | Imported when present in metadata, for example `seurat_clusters`. |
| graphs, commands, misc | unsupported in v1 | Presence and limitations are recorded in the ingestion report artifact. |

### SingleCellExperiment

| SCE state | scworkbench object | Notes |
| --- | --- | --- |
| `assays()` | matrices | All assays or selected assays may be imported. |
| `colData()` | cell metadata | Stored in the bundle `cells` table. |
| categorical `colData()` columns | cell sets | Optional; one set per column/value. |
| `rowData()` | feature metadata artifact | Stored as a promoted `feature_table` artifact. |
| `reducedDims()` | spaces | Numeric embeddings with at least two dimensions are imported. |
| `altExpNames()` | ingestion metadata | Presence is recorded; altExp matrices are not imported by default in v1. |
| `metadata()` / `int_metadata()` | unsupported in v1 | Not imported except through report summaries. |

### AnnData/h5ad

| AnnData state | scworkbench object | Notes |
| --- | --- | --- |
| `.X` / converted assays | matrices | Read through `zellkonverter::readH5AD()` and imported through SCE mapping. |
| `.obs` | cell metadata | Imported through converted `colData()`. |
| duplicated `.obs_names` | unique `cell_id` plus original metadata | Default policy makes final IDs unique and stores originals in `ann_data_obs_name`. |
| categorical `.obs` columns | cell sets | Optional; useful for labels such as `louvain`. |
| `.var` | feature metadata artifact | Imported through converted `rowData()`. |
| duplicated `.var_names` | unique `feature_id` plus original feature metadata | Default policy makes final IDs unique and stores originals in `ann_data_var_name`. |
| `.obsm` numeric embeddings | spaces | Imported through converted `reducedDims()`. |
| `.raw`, `.layers`, `.obsp`, `.uns` | ingestion metadata / unsupported in v1 | Top-level presence is recorded when `rhdf5` is available; graph and arbitrary `uns` payloads are not imported. |

### 10x Matrix Market

| 10x state | scworkbench object | Notes |
| --- | --- | --- |
| `matrix.mtx[.gz]` | matrix fragment | Matrix Market orientation is features x cells. Multiple libraries are written as BPCells fragments under one logical `matrix_id`. |
| `barcodes.tsv[.gz]` | cell IDs and metadata | Default final ID is `{sample_id}:{barcode}`. Original barcode is stored in `barcode`. |
| `features.tsv[.gz]` | feature registry and feature metadata artifact | Columns are interpreted as `feature_id`, `feature_name`, `feature_type`. |
| sample table columns | cell metadata | All sample-table columns except file paths are copied to cells. |
| Matrix Market comments | ingestion report | `%metadata_json:` comments are parsed when present and stored in the report details payload. |

## Ingestion Reports

Every constructor writes a promoted `container_ingest_report` artifact. The
report records:

- source container type and path when provided;
- importer version;
- matrices and spaces imported;
- generated categorical cell sets;
- feature metadata artifact id, when produced;
- duplicate cell-ID policy and counts;
- duplicate feature-ID policy and counts;
- ingestion status and phase reached for successful in-bundle reports;
- 10x Matrix Market details such as library count, source paths, total cells,
  total features, total nonzero entries, sample metadata columns, barcode
  prefixing, and Cell Ranger metadata when present;
- unsupported or presence-only fields.

Failed h5ad imports do not promote a partial bundle. They leave a lightweight
`INGEST_FAILED.json` marker in `bundle_dir` when a final marker can be safely
written.

This failure marker covers normal R-level ingestion failures. Process-level
aborts, external kills, filesystem loss, or container termination can still
stop execution before R can write the marker; production wrappers should treat
unexpected process termination as an incomplete ingestion even if no fresh
`INGEST_FAILED.json` was written.

Use `wb_art_list()` and `wb_art_load()` to inspect these artifacts.

## Limitations

Importer v1 is intentionally scoped:

- It initializes bundles from container state; it does not reconstruct complete upstream preprocessing provenance.
- It imports matrices, metadata, reduced dimensions, feature metadata, and categorical labels, but not arbitrary tool histories.
- Seurat graphs/commands/misc, AnnData `.uns`/`.obsp`, and SCE `metadata()`/`int_metadata()` are not fully imported.
- AnnData support depends on `zellkonverter`; optional top-level h5ad field reporting depends on `rhdf5`.
- Matrix attachment uses scworkbench's existing BPCells-backed matrix storage, so `BPCells` must be available to write matrices.
