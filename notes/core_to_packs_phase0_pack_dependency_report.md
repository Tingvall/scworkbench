# Phase 0 pack-dependency report

The normalized inventory is `core_to_packs_phase0_pack_dependencies.csv`; operation-level dependencies and source anchors are retained in `core_to_packs_phase0_operation_baseline.json`. The scan was made at scworkbench `4f7420899db650d895505202e7e9827ea5814b62` and PyBench `d2e0587950973cf7eeacfc46b2829397cf84f079`.

## Dependency boundary

All seven scientific packs require a compatible scworkbench core. No hard pack-to-pack dependency is justified by the current contracts: matrices, spaces, model references, vectors, relations, feature tables and observation tables cross pack boundaries as typed primitives. For example, `scwbTrajectory` may consume a space without depending on `scwbRepresentation`, and `scwbGenePrograms` may consume a feature table or space without depending on its producer.

| Pack | Operations | Principal method/runtime dependencies observed | Typed flow summary | Release assessment |
| --- | ---: | --- | --- | --- |
| `scwbRNA` | 4 | Matrix/BPCells paths; `irlba`; core database and HDF5 access inherited by present implementations | matrix → matrix, QC vectors/tables and feature tables | Moderate cadence; normalization publishes a durable matrix and waits for ABI v2. |
| `scwbRepresentation` | 6 | `irlba`, `uwot`, `RANN`, `igraph`, Matrix/BPCells | matrix/space/model reference → PCA/UMAP spaces, model reference, neighbors and clustering | Moderate cadence; PCA/UMAP writers and mixed publication require ABI v2. |
| `scwbGenePrograms` | 10 | `UCell`, `BiocParallel`, `RANN`, Matrix | matrix/feature table/vector family/space → vector families and terminal tables | Mostly v1-shaped terminal methods; `winner_cell_sets` needs a sanctioned core registry request. |
| `scwbStatistics` | 6 | Matrix/BPCells and base R statistics | matrix/vectors → feature and observation tables | Low dependency weight; suitable for the first production extraction after v2 conformance. |
| `scwbTrajectory` | 24 | `slingshot`, `monocle3`, SingleCellExperiment/S4 stack, `igraph`, `RANN`; Palantir operations use PyBench with `palantir>=1.3` | spaces/matrices/vectors/models/path families → models, trajectories, paths and statistics | Heaviest R pack and mixed optional stacks; engine-specific runtime preflights are required. |
| `scwbLatent` | 4 | PyBench 0.1.0/protocol 2; Python >=3.11; scVI operations require `scvi-tools>=1.1` plus ingest extras | matrix/model/space → latent spaces, model references and summaries | Python/model release cadence; requires ABI v2 writers, receipts, containment and rollback. |
| `scwbATAC` | 1 | `chromVAR`, motifmatchr/JASPAR-compatible inputs, Bioconductor genomic ranges and genome data | peak matrix → deviation families and summary | Small initial pack but a heavy optional genomics stack; likely grows independently. |

PyBench's pinned [`pyproject.toml`](/home/dirk/Projects/pybench/pyproject.toml) declares Python `>=3.11`, core dependencies, and optional `scvi`, `palantir`, `scanpy`, and `ingest` groups. The inventory also records versions found in [`containers/apptainer/fullstack_r_versions.lock.csv`](../containers/apptainer/fullstack_r_versions.lock.csv) and [`containers/apptainer/fullstack_python_requirements.lock`](../containers/apptainer/fullstack_python_requirements.lock). Those are qualified fullstack environment versions, not inferred package minima. Exact per-operation locks and system-library minima remain **unresolved** because `DESCRIPTION` and PyBench metadata do not declare them at operation granularity. Forge/Quill must freeze pack lockfiles and runtime preflights before extraction.

## Installation, replay and licensing

- The standard profile may install all official packs, but installation must remain inert and activation explicit/process-local.
- Clean/offline qualification must install dependencies ahead of execution. An operation must never fetch a package, model or reference resource during replay.
- Heavy optional stacks should be checked only when their operations are selected; missing dependencies must fail before analytical dispatch or retained publication.
- R/Python pack runners are trusted installed code. ABI conformance is not host sandboxing.
- scworkbench and PyBench are MIT-licensed. Every redistributed dependency retains its own license; the Bioconductor, model and genome/motif stacks require a release-time notice and redistribution review. A source citation is not a license.
- Expected installed size is not inferable from package declarations alone. Measure it from the eventual locked pack artifacts; do not quote an estimate as evidence.

The dependency inventory is deliberately conservative: entries marked “observed” reflect namespace/runtime calls in the current implementation source, not a final minimal dependency declaration.
