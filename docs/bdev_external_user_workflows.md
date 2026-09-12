# Bdev External-User Workflows

This guide covers the three connected workloads planned for the B-cell
development project. It is development documentation, not preprint evidence.
The examples show intended boundaries and must be adapted after inspecting the
actual inputs.

## Bundle layout

Use three independent working bundles:

1. `bdev_reference`: the published Seurat state and selected published
   Slingshot fit;
2. `parse_cytokines`: Parse RNA preprocessing, differential expression and
   cytokine-gene-set derivation;
3. `bdev_ko_integration`: aligned Bdev and knockout ATAC counts, Bdev-trained
   PeakVI model, projected knockout coordinates and joint display state.

Move only selected, evidence-backed outputs across bundle boundaries. Do not
copy unrelated raw experiments into the Bdev reference bundle.

## 1. Bdev Seurat reference and Slingshot adoption

Import the same Seurat RDS used for the published analysis. Select assays,
layers, metadata and reductions explicitly; importing a reduction preserves its
coordinates and does not refit it.

```r
library(scworkbench)

source_rds <- "/path/to/authoritative_bdev_seurat.rds"
source_sha <- wb_source_sha256(source_rds)

bdev <- wb_bundle_from_seurat(
  input = source_rds,
  bundle_dir = "/path/to/bdev_reference.scwb",
  matrix_specs = list(
    list(matrix_id = "RNA_counts", seurat_assay = "RNA", layer = "counts", feature_type = "gene"),
    list(matrix_id = "ATAC_counts", seurat_assay = "ATAC", layer = "counts", feature_type = "peak")
  ),
  reductions = c("pca", "umap"),
  metadata_cols = c("sample_id", "cell_type", "seurat_clusters"),
  overwrite = FALSE,
  created_by = "collaborator"
)
```

The importer deliberately does not guess which object in `misc` is the
authoritative trajectory. Inspect the RDS, choose the exact published
`SlingshotDataSet`, and name that extraction path in the analysis record.

```r
seurat <- readRDS(source_rds)

# Replace this with the exact, inspected location of the published fit.
published_sds <- seurat@misc$published_slingshot

adoption_model <- wb_slingshot_adoption_model(
  bundle = bdev,
  sds = published_sds,
  fit_space_id = "umap",
  source_sha256 = source_sha
)

adopted <- wb_session_run_op(
  wb_session_new(), bdev, "slingshot_adopt",
  inputs = list(
    model = adoption_model,
    source = wb_ref_entity("external_source", "seurat_rds"),
    cell_set = "all",
    min_cells = 1L
  ),
  notes = "Adopt the explicitly selected published Slingshot fit without refitting"
)

wb_session_promote_current(
  bdev, adopted$session,
  outputs = c("pseudotime", "lineage_weights", "curves", "model", "adoption_summary"),
  name_prefix = "published_bdev_slingshot",
  created_by = "collaborator"
)
```

Before adoption, confirm the importer-assigned external-source ID with public
provenance getters rather than assuming `seurat_rds`. Adoption fails if the
source checksum, fit cells, fit coordinates, lineages or curve dimensions do
not match the retained state.

## 2. Parse RNA and cytokine gene sets

`ReadParseBio()` is a Seurat input adapter, not a scworkbench operation. Run it
outside the bundle, save the resulting Seurat object, checksum it, and import
the raw RNA counts and required sample/replicate metadata. Retain the original
Parse output inventory separately.

```r
# ReadParseBio arguments depend on the delivered Parse output layout.
parse_seurat <- Seurat::ReadParseBio("/path/to/parse-output")
saveRDS(parse_seurat, "/path/to/parse_unfiltered_seurat.rds", version = 3)

parse <- wb_bundle_from_seurat(
  input = "/path/to/parse_unfiltered_seurat.rds",
  bundle_dir = "/path/to/parse_cytokines.scwb",
  matrix_specs = list(
    list(matrix_id = "RNA_counts", seurat_assay = "RNA", layer = "counts", feature_type = "gene")
  ),
  metadata_cols = c("sample_id", "replicate", "condition"),
  reductions = character(0),
  overwrite = FALSE,
  created_by = "collaborator"
)
```

Calculate factual QC metrics first. Species-specific feature matching is
explicit and recorded; adjust these patterns to the actual feature namespace.

```r
qc <- wb_session_run_op(
  wb_session_new(), parse, "rna_qc_metrics",
  inputs = list(
    matrix = "RNA_counts",
    cell_set = "all",
    min_cells = 1L,
    mitochondrial_pattern = "^MT-",
    ribosomal_pattern = "^RP[SL]",
    pattern_ignore_case = FALSE
  )
)

qc_promoted <- wb_session_promote_current(
  parse, qc$session,
  outputs = c("metrics", "qc_features", "summary"),
  name_prefix = "parse_rna_qc",
  created_by = "collaborator"
)
qc_id <- qc_promoted$promoted$artifact_id[qc_promoted$promoted$output == "metrics"]
qc_ref <- paste0("artifact:", qc_id)
```

Inspect distributions before choosing thresholds. The values below are
placeholders, not recommendations.

```r
accepted <- wb_sel_vector_family(parse, qc_ref, "total_counts", min = 1000)
accepted <- wb_sel_vector_family(accepted, qc_ref, "detected_features", min = 500, bundle = parse)
accepted <- wb_sel_vector_family(accepted, qc_ref, "mitochondrial_percent", max = 15, bundle = parse)

wb_cell_set_derive(
  parse,
  cell_set = "set:parse_qc_accepted",
  cells = accepted,
  role = "analysis_universe",
  status = "accepted",
  source = "registered RNA QC metrics",
  created_by = "collaborator",
  description = "Cells passing collaborator-selected Parse RNA QC thresholds"
)
```

`matrix_log_normalize` creates a full bundle matrix because its transform is
per cell. Use `set:parse_qc_accepted` for HVG, PCA, UMAP, Leiden, differential
expression and marker operations. Unselected cells remain retained and
distinguishable from the accepted analysis universe.

The cytokine set itself is a scientific selection, not an automatic QC result.
Select genes from a promoted DE/marker table in a reviewed script or capsule,
save the selected table plus its contrast and threshold metadata, then use
`feature_set_import` in the Bdev integration context. Run
`feature_set_overlap_qc`, `addmodulescore` or `ucell`, followed by
`trajectory_signature_smooth` or `trajectory_geneset_dynamics` against the
adopted Bdev trajectory.

## 3. Cell Ranger ARC and PeakVI mapping

Cell Ranger ARC ingestion currently has a declared external preprocessing
boundary. Use Seurat/Signac to read each ARC output, preserve paired RNA/ATAC
cell identities, calculate fragment-aware QC, and create a common Bdev/KO peak
universe. Record the Cell Ranger output inventory, fragment/index identities,
reference genome, peak coordinates and software parameters.

Do not use `wb_bundle_from_10x_mtx()` for a mixed RNA/ATAC ARC matrix. Import
the staged Seurat assays explicitly with `wb_bundle_from_seurat()` and
`matrix_specs`, or attach already aligned matrices through the governed ingest
interfaces.

The integration bundle must contain:

- one ATAC count matrix with the same ordered peak universe for Bdev and KO;
- disjoint retained cell sets for Bdev reference and KO query cells;
- unambiguous sample/genotype metadata and one recorded genome build.

The governed model sequence is:

```r
fit <- wb_session_run_op(
  wb_session_new(), integration, "peakvi_fit",
  inputs = list(
    matrix = "ATAC_common_peaks",
    cell_set = "set:bdev_reference",
    min_cells = 10L,
    n_latent = 20L,
    use_gpu = TRUE,
    space_id_out = "peakvi.bdev_reference"
  )
)

projected <- wb_session_run_op(
  fit$session, integration, "peakvi_project",
  inputs = list(
    matrix = "ATAC_common_peaks",
    model = wb_ref_run(fit$run$run_id, "model"),
    cell_set = "set:ko_query",
    min_cells = 1L,
    use_gpu = TRUE,
    space_id_out = "peakvi.ko_projected"
  )
)

joint <- wb_session_run_op(
  projected$session, integration, "model_bound_latent_union",
  inputs = list(
    reference_space = "peakvi.bdev_reference",
    query_space = "peakvi.ko_projected",
    model = wb_ref_run(fit$run$run_id, "model"),
    projection_summary = wb_ref_run(projected$run$run_id, "fit_summary"),
    cell_set = "all",
    min_cells = 1L,
    space_id_out = "peakvi.bdev_ko_joint"
  )
)

display <- wb_session_run_op(
  joint$session, integration, "umap_fit",
  inputs = list(
    space = "peakvi.bdev_ko_joint",
    cell_set = "all",
    min_cells = 3L,
    dims = 1:20,
    space_id_out = "umap.peakvi.bdev_ko_joint",
    seed = 1L
  )
)
```

The union operation only row-binds unchanged fitted and projected coordinates
after checking disjoint cells, equal dimensions, complete coverage and shared
model identity. It does not refit or transform either group. The joint UMAP is
a downstream display embedding; it does not itself establish biological
mapping quality.

## Current boundaries

- No automatic search selects a Slingshot fit from Seurat `misc`.
- Parse reading and Cell Ranger ARC/Signac preprocessing occur externally.
- The operation-pack v1 ABI cannot publish matrices or latent spaces, so
  TF-IDF/LSI/common-peak construction is not represented as an operation pack.
- Real-data success is not established by the included synthetic workflow
  contracts.
- Confirm whether the knockout is `FLT2KO` or `FLT3KO` before creating durable
  labels.

## Starter prompt

```text
Work only through scworkbench public interfaces. Inspect inputs before writing.
Do not overwrite inherited state, infer storage paths, or silently select a
trajectory/model. Record external source identities and checksums. Separate
metric calculation from scientific threshold selection. Show the proposed
cell, feature and source boundaries before each irreversible promotion.

For this task, create or continue exactly one of these governed workloads:
[Bdev reference import and explicit Slingshot adoption | Parse RNA cytokine
workflow | Bdev-trained PeakVI projection of KO cells]. Report unsupported
steps as explicit external boundaries rather than emulating them with an
unregistered operation. End with retained outputs, validation results,
unresolved scientific choices and the exact next registered operation.
```
