# `peakvi_fit`

User-facing reference for the engine-native PeakVI fit op.

## Purpose

`peakvi_fit` trains a PeakVI model on an ATAC/count matrix and emits:

- a reusable latent `space`
- a reusable `model_ref` with `engine = "peakvi"`

This makes PeakVI a first-class model-producing op inside `scworkbench`,
rather than an external script step.

Primary downstream uses:

- run `umap_fit` on the learned latent space
- run trajectory methods on the learned latent space
- compare `lsi` and PeakVI representations
- reuse the saved model with `peakvi_project`

## Inputs

Required:

- `matrix`
  - matrix primitive, typically an ATAC count/accessibility matrix

Standard cell selection:

- `cell_set`
- `cell_ids`

`peakvi_fit` is matrix-first. It does not consume an existing latent space.

## Main Parameters

- `n_latent`
  - latent dimensionality of the emitted space
- `n_layers`
  - hidden-layer count passed to PeakVI
- `n_hidden`
  - hidden width passed to PeakVI
- `dropout`
  - dropout rate passed to PeakVI
- `batch_key`
  - optional observation field used as PeakVI batch covariate
- `max_epochs`
  - optional training cap
- `lr`
  - learning rate
- `early_stopping`
  - whether to enable scvi-tools early stopping
- `seed`
  - optional random seed
- `use_gpu`
  - explicit runtime choice
- `space_id_out`
  - emitted latent space id

Current defaults are aligned with the script-parity path:

- `n_latent = 20`
- `n_layers = 2`
- `n_hidden = 256`
- `dropout = 0.2`
- `max_epochs = 500`
- `lr = 1e-3`
- `early_stopping = TRUE`

## Outputs

- `space`
  - PeakVI latent embedding written into the bundle spaces registry
- `model`
  - serialized `model_ref` with `engine = "peakvi"`

The latent space is the main reusable analytical result.

## Current Execution Path

The current production/cluster path is:

1. R resolves the effective cells and matrix metadata.
2. R reads the selected matrix slice through the mature R BPCells path.
3. R stages sparse chunk files plus a manifest.
4. Python loads those staged chunks, assembles the sparse matrix, builds `AnnData`, and trains PeakVI.
5. Python writes the latent space and model payload back into the bundle.
6. R records run provenance and returns the emitted primitives.

Important:

- `peakvi_fit` in `pybench` still supports native bundle matrix reads when
  `matrix_chunks_dir` is absent
- native Python BPCells reads are local/development capable, but not currently
  the production cluster default
- the R/scworkbench production path supplies staged sparse chunks
- `peakvi_project` currently requires staged sparse chunks

## Why The Staged Chunk Bridge Exists

Upstream Python BPCells did not handle the double-matrix bundle payloads needed
for this use case. A fork added double-matrix read support and worked on the
workstation, but the native/forked path later produced segmentation faults on
the Tetralith/cluster runtime.

Until that forked/double-matrix path passes a real cluster smoke without
segmentation faults, staged sparse chunks are the production-safe PeakVI
transport.

The staged bridge keeps:

- BPCells reading in the mature R path
- PeakVI training in Python
- the cross-runtime handoff small, explicit, and recoverable

## Cluster Usage Notes

- for early smoke tests, pass an explicit low `max_epochs`
- if R-side staging becomes heavy, tune:
  - `SCWORKBENCH_PEAKVI_STAGE_CHUNK_CELLS`
- default staging chunk size is `256`

Recommended smoke pattern:

- start with a small subset or one-epoch run
- then scale to the full bundle once the container/runtime path is confirmed

## Relationship To `peakvi_project`

`peakvi_fit` learns and saves the reference model.

`peakvi_project` reuses a saved PeakVI `model_ref` to place new cells into that
existing latent space without refitting the model.

Current contract:

- `peakvi_fit`: staged sparse chunks for production/cluster; native pybench
  bundle reads remain available only when `matrix_chunks_dir` is absent
- `peakvi_project`: staged-only

That pairing is the intended workflow for:

- reference/query mapping
- tumor-to-reference projection
- reusable latent-space-centered analysis

## Related Docs

- `docs/peakvi_fit_contract_draft.md`
- `docs/peakvi_script_parity_handoff.md`
- `docs/peakvi_tetralith_handoff_2026_04_22.md`
- `docs/apptainer_fullstack.md`
