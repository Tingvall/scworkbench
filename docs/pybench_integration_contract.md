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

Important exception:

- `peakvi_fit` no longer uses direct Python BPCells reads on the production
  path
- `peakvi_fit` now uses an R-staged sparse chunk bridge:
  - R reads the matrix through the mature R BPCells path
  - R stages sparse chunk files plus manifest metadata
  - Python assembles from those staged chunks before training PeakVI

Implications:

- keep Python getter behavior deterministic in feature/cell ordering
- do not assume every Python-native op must read matrices directly from BPCells
- for cluster-critical paths, prefer the more robust bridge over the more elegant one

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
