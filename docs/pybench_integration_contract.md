# Pybench Integration Contract (R Bench + Python Runtime)

This document records the current authority boundary between `scworkbench`
(R engine) and `pybench` (Python runtime). For new pack authors, the
[SDK](operation_pack_sdk.md) and [Python route map](python_bridge.md) are the
entry points. Historical bridge details below are not new-pack instructions.

It exists for future maintainers (human and agent) so we do not accidentally drift into ad hoc cross-language coupling.

## Core Principle

The packages share primitive and identity contracts, but they are not equal
scientific-state authorities.

- `scworkbench` is the canonical engine and contract authority
- `pybench` is a Python-native runtime for methods best implemented in Python
- a core-owned private transition or typed private computation directory is
  the execution boundary; the committed bundle is never Python write authority

No large in-memory R<->Python object transfer should be required.

## Separation Of Responsibilities

### Bench (R engine) owns

- op registry / `wb_op_interface()` contract definitions
- param capture and provenance (birth certificates)
- run/session registry and status
- artifact registry rows (`artifacts`) and IDs
- promotion semantics / DAG semantics

### Pybench (Python runtime) owns

- consuming admitted typed inputs and granted private readers
- running Python-native compute (for example `scvi-tools`, `palantir`)
- writing only declared private outputs through granted writers
- returning a compact success/error receipt to bench

## Handoff Contract

For a Python-backed pack, core supplies an identity-bound request, private
stage, typed descriptors, output grants, and dependency/runtime bindings. The
handler receives `readers`, `writers`, `params`, and `context`, not a committed
bundle path or unrestricted database connection. ABI v3 uses `pybench-op-v4`;
v2 uses `pybench-op-v3`.

An R-backed scientific pack passes only admitted staged data and checked model
inputs to its private Python helper. Core audits what the R pack submits
through its writers. This does not establish Python-pack runtime parity.

The historical engine bridge supplied:

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

## Symbolic References and Explicit Selections

Prefer typed references and named sets for reusable scientific selections.
Explicit cell/feature lists remain valid when the live contract admits them.
Do not manufacture a durable set or mutate a registry just to reduce JSON size.
Core records literals as literals and named sets with authenticated membership.

Why:

- params remain small
- provenance remains readable/replayable
- avoids giant JSON payloads and brittle handoffs

Durable named-set creation uses a registered operation and promotion.

## Storage Contract Rule (Non-Negotiable)

Python must write primitive payloads **exactly** as R expects to read them.

Validity criterion:

- core must validate source, complete grant/receipt closure, payload identities,
  dimensions, order, and mutation scope before publication; loadability alone
  does not establish validity

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
2. update the relevant shared fixtures and SDK backend-support record
3. if storage or authority semantics changed, add executable parity tests

The installed capability catalog and Python support table distinguish
schema/identity parity from runtime authority. Inline comments are local
tripwires, not qualification evidence.

## SQLite / Concurrency Policy

Direct committed-bundle Python writes are prohibited. Granted writes in an
engine-created private stage are constrained and independently audited.

- **single writer at a time per bundle**

Core owns locking, rollback, and publication. A pack must not add a concurrent
database writer or authorize writes by opening its own connection.

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
