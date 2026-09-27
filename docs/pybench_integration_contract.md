# Pybench Integration Contract (R Bench + Python Runtime)

This document records how `scworkbench` (R engine / bench) and `pybench` (Python runtime) are intended to work together.

It exists for future maintainers (human and agent) so we do not accidentally drift into ad hoc cross-language coupling.

## Core Principle

`scworkbench` and `pybench` are **peer compute runtimes** sharing one bundle contract.

- `scworkbench` is the canonical engine and contract authority
- `pybench` is a Python-native runtime for methods best implemented in Python
- the **bundle** (SQLite + payload files) is the integration boundary

No large in-memory R<->Python object transfer should be required.

## Separation Of Responsibilities

### Bench (R engine) owns

- op registry / `wb_op_interface()` contract definitions
- param capture and provenance (birth certificates)
- run/session registry and status
- artifact registry rows (`artifacts`) and IDs
- promotion semantics / DAG semantics

### Pybench (Python runtime) owns

- reading bundle inputs (getters) via the shared bundle contract
- running Python-native compute (for example `scvi-tools`, `palantir`)
- writing primitive payloads directly into bundle payload tables/files
- returning a compact success/error receipt to bench

## Handoff Contract

Bench should hand Python:

- bundle path
- symbolic refs (sets, artifact refs, space IDs, matrix IDs)
- small params payload
- pre-registered artifact IDs (with expected artifact `type`)

Pybench should return:

- `status` (`ok` / `error`)
- output artifact IDs + payload write stats
- warnings
- optional timings

Bench records provenance/run outcome centrally.

## Symbolic References Over Literal Payloads (Required)

Before handing off to Python:

- literal `cell_ids` should be materialized as a `cell_set` (ephemeral or named)
- literal `feature_ids` should be materialized as a `feature_set`

Why:

- params remain small
- provenance remains readable/replayable
- avoids giant JSON payloads and brittle handoffs

This is the default policy unless there is a compelling reason not to.

## Storage Contract Rule (Non-Negotiable)

Python must write primitive payloads **exactly** as R expects to read them.

Validity criterion:

- a Python-written artifact is valid iff current R `wb_art_load()` can read it without special-case hacks

Implications:

- write by primitive kind contract, not by op-specific storage
- preserve ordering/type semantics (for example `cell_vector` numeric fidelity via `value_type/value_num`)
- add parity tests when payload schemas change

## Native Python Matrix Getters

Current `pybench` has bundle-native Python matrix getters.

Meaning:

- Python can resolve `matrix_id` through the bundle registry
- Python can open canonical bundle matrix payloads directly
- Python getters remain the right path for Python-native consumers that can
  safely read matrices in-process

Historical core PeakVI bridge (retained-run context, not a live no-pack op):

- the removed core `peakvi_fit` used an R-staged sparse chunk bridge:
  - R reads the matrix through the mature R BPCells path
  - R stages sparse chunk files plus manifest metadata
  - Python assembles from those staged chunks before training PeakVI
- the historical PyBench `peakvi_fit` still supports native bundle matrix reads when
  `matrix_chunks_dir` is absent; that path is local/development capable, not the
  current cluster production default.
- the historical PyBench `peakvi_project` requires staged chunks.

Current CPU PeakVI fit/project execution is owned by the explicitly activated
`scwbLatent` pack. Its private Python process receives only bounded
stage-relative typed matrix chunks; it does not receive bundle registry or
publication authority. See [peakvi_fit.md](peakvi_fit.md).

Historical reason:

- native Python BPCells reads were pursued because upstream Python BPCells could
  not handle double matrices
- a fork fixed double-matrix reads and worked locally
- the native/forked BPCells path hit segmentation faults on Tetralith
- re-promoting native BPCells reads to production requires a cluster smoke that
  exercises the forked/double-matrix path without segmentation faults

Implications:

- keep Python getter behavior deterministic in feature/cell ordering
- do not assume every Python-native op must read matrices directly from BPCells
- do not treat historical native PeakVI bundle reads as a current pack grant

Historical core scVI training bridge (retained for reading old runs only):

- The retired core `scvi_train` used R-staged sparse-chunk transport.
- R validated count-like input and metadata covariates, staged the selected
  matrix and cell metadata, preregisters `model_ref` and `obs_table` outputs,
  and invoked `pybench.ops.scvi_train`.
- Python wrote the latent space, a bundle-relative scVI model directory, and
  the requested fit-summary payload. R remained the authority for the op
  interface, artifact rows, run/session provenance, and promotion.
- New training uses `scwblatent::scvi_train` and the generic ABI-v3
  authenticated metadata/count-slice boundary; it has no normalized-matrix
  override. See [scvi_train.md](scvi_train.md).

## Parity Discipline

When an R function has a Python counterpart:

1. add/maintain inline `pybench-parity` comment on the R function
2. update `docs/pybench_parity_map.md`
3. if storage semantics changed, add/update a parity test

The parity map is the central index. Inline comments are local tripwires.

## SQLite / Concurrency Policy

Direct Python writes are allowed, but assume:

- **single writer at a time per bundle**

Do not rely on concurrent R+Python writes to the same bundle without explicit locking/orchestration.

## Schema / Migration Policy (Current)

Current policy:

- bench (R) is migration authority
- pybench checks for required tables/columns and fails fast if missing

Python should not silently create/alter schemas unless explicitly designed to do so.

## Versioning Guidance

`pybench` should be versioned as a package, but compatibility is primarily with the **bundle/storage contract**.

Changes to payload table semantics or getter semantics should be treated as contract changes and documented.

## Architectural Slogans (Relevant)

- Separation of compute and display.
- Primitives stay primitive; civilization lives in birth certificates.
- Contracts determine the best friendships.
