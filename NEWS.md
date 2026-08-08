# scworkbench 0.1.0

## Bundle substrate

- Introduces portable, disk-backed single-cell bundles with typed matrices,
  spaces, models, sets, vectors, tabular artifacts, and provenance.
- Adds public getters, registered operations, closure-aware promotion, strict
  replay, recipient finalization, and read-only audit.
- Adds durable resumable sessions and capability-scoped PyBench protocol v2
  transitions for long-running Python methods.

## Analysis capabilities

- Adds container ingestion for 10x Matrix Market, Seurat,
  SingleCellExperiment, and AnnData inputs.
- Adds conventional RNA representation, scVI, PeakVI, Palantir, Monocle3,
  Slingshot, metadata diagnostics, differential testing, enrichment, and
  composite trajectory operations.

## Release engineering

- Adds complete-discovery CI, source-package policy checks, composite release
  metadata, immutable base-image and runtime locks, source artifact builders,
  release evidence assembly, and explicit GPU/large-data gates.
- Seurat is now optional; core installation no longer pulls it transitively.
- UMAP replay now declares cell-aligned embedding validity separately from raw
  coordinate and serialized-model identity, avoiding false exact-replay claims
  across fresh processes.
- Provenance run, contract, structural, and materialization identities now use
  explicit SHA-256 schemes, eliminating large-payload integer overflow while
  retaining bounded validation of already-persisted legacy identities.
