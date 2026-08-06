# Collaborator Dependency Chart

This is a practical dependency inventory for sharing `scworkbench` + `scworkbenchShiny` + `pybench`.

## 1) Engine (`scworkbench`) R packages

### Core (declared in `DESCRIPTION`)

- `DBI`
- `RSQLite`
- `jsonlite`
- `Seurat`
- `Matrix`

### Suggested (declared in `DESCRIPTION`)

- `BPCells`

### Runtime optional by feature/op (from engine code)

- `BPCells`
  - matrix read/write backends, bundle matrix operations, publish matrix export
- `uwot`
  - `umap_fit`, `umap_transform`
- `igraph`
  - kNN graph + Leiden helpers, monocle lineage derivation helpers
- `RANN`
  - fast kNN in geometry ops
- `SingleCellExperiment`
  - Slingshot + Monocle3 containers
- `S4Vectors`
  - Slingshot reducedDims plumbing
- `slingshot`
  - slingshot fit/project
- `monocle3`
  - monocle3 fit/project
- `ggplot2`
  - trajectory/space wrangler plotting helpers
- `viridisLite`
  - optional color palette path

## 2) Shiny client (`scworkbenchShiny`) R packages

### Directly loaded in app/modules

- `shiny`
- `ggplot2`
- `scworkbench`
- `shinyFiles`
- `magrittr`

### Optional (feature-gated via `requireNamespace`)

- `DT`
  - table interactions
- `plotly`
  - interactive plots
- `visNetwork`
  - report DAG/network widgets
- `zip`
  - report export packaging
- `colourpicker`
  - Scene UI color controls

## 3) Python runtime (`pybench`) packages

### Core (`pyproject.toml`)

- `numpy>=1.26`
- `pandas>=2.1`

### Optional extras (`pyproject.toml`)

- `scanpy>=1.10` (`[project.optional-dependencies].scanpy`)
- `palantir>=1.3` (`[project.optional-dependencies].palantir`)
- `scvi-tools>=1.1` (`[project.optional-dependencies].scvi`)
  - required for `peakvi_fit` and other scvi-backed ops

### Dev extras

- `pytest>=8.0`
- `ruff>=0.6`

## 4) Minimal install profile recommendation

For collaborator onboarding, a stable baseline is:

1. `scworkbench` core + `BPCells`
2. `scworkbenchShiny` + optional `DT`, `plotly`
3. `pybench` core + `palantir` extra only if Palantir ops are needed

Then add heavy method stacks (`scanpy`, `scvi-tools`, `monocle3`) only when required.
If the workflow needs `peakvi_fit`, `scvi-tools` is no longer optional for that runtime.
The current full-stack Apptainer image includes it intentionally together with a CUDA-capable
PyTorch build for GPU-backed PeakVI/scvi workloads.

