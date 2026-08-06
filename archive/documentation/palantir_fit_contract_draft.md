# `palantir_fit` Contract Draft (v1)

Contracts determine the best friendships.

This draft defines a first `scworkbench` engine op contract for Palantir integration via `pybench`.

## Design Position (Important)

We do **not** extend Palantir semantics.

Palantir (in the tested API path) is a **single-root** method via `early_cell`.

Therefore:

- `palantir_fit` v1 is **single-root**
- input is `root_cell` (one cell), not a root set
- any future multi-root behavior would require explicit, method-honest design and should not be silently invented

This mirrors our monocle3 decision logic:

- monocle3 natively supports multi-root -> we support multi-root
- Palantir appears single-root -> we keep single-root

## Op Intent

Run Palantir on a chosen scworkbench space (typically latent / reduced coordinates) and emit trajectory outputs suitable for downstream:

- pseudotime analyses
- branch/fate probability analyses
- trajectory-linked GSEA
- tumor placement relative to developmental branches

## Inputs (v1)

### Required

- `fit_space` (`space`)
  - the coordinate space Palantir runs on
  - may be >2D (for example `peakvi_space`, `pca`, `lsi`)

- `root_cell` (`character`, length 1)
  - single early cell ID used as Palantir `early_cell`
  - must be present in the effective cell universe

### Strongly recommended for branch outputs (v1.1 hardening)

- `terminal_cells` (`cell_ids`; vector length >= 1, typically 2+)
  - explicit terminal cell IDs passed to Palantir as `terminal_states`
  - must be present in the effective cell universe
  - this is the reliable path for branch/fate probabilities in our tested Palantir (`1.4.4`) integration

Important observed behavior (real full-core run):

- `root_cell` alone can yield valid `pseudotime` + `entropy`
- but Palantir may return `terminal_states = None` and `branch_probs` with zero columns
- therefore `branch_membership` / `branch_summary` are not guaranteed without explicit terminal endpoints

### Cell universe

Use existing engine pattern:

- `cell_set` (default `core`)
- and/or `cell_ids` (optional explicit subset)

Bench should continue preferring symbolic refs (`cell_set`) over large literal `cell_ids`.

### Optional parameters (advanced but disciplined)

- `dims` (integer vector or string vector of ints)
  - optional subset of dimensions from `fit_space`
  - default: use all available dimensions (or a documented default cap if we choose one)

- `knn` (integer; default candidate `30`)
  - nearest-neighbor graph size

- `n_diffusion_components` (integer; default candidate `10`)
  - diffusion map dimensionality

- `n_waypoints` (integer; default candidate `300`)
  - Palantir waypoint count

- `use_early_cell_as_start` (bool; default `TRUE`)
  - forwarded to `palantir.core.run_palantir(...)`
  - `TRUE` preserves the intuitive root-low -> terminal-high pseudotime direction for our workflow
  - leaving this at Palantir's default (`FALSE`) can produce visually "inverted" pseudotime relative to the supplied `root_cell`

- `seed` (optional integer)
  - only if/where the Palantir path supports deterministic behavior for the chosen steps

## Outputs (v1)

### 1) `pseudotime` (`cell_vector`)

Palantir pseudotime, direct from `PResults.pseudotime`.

- kind: `cell_vector`
- `value_type = "continuous"`
- one scalar per cell in the effective universe

Semantics:

- rooted progression coordinate from the provided `root_cell`

### 2) `branch_membership` (`relation_family`)

Branch/fate probabilities from Palantir `PResults.branch_probs`.

- kind: `relation_family`
- rows: one `(cell_id, branch)` pair per non-missing branch probability entry
- fields:
  - `key` = branch identifier (canonicalized from Palantir branch column names)
  - `cell_id`
  - `weight` = Palantir branch probability

Recommended key convention (v1):

- `branch:<palantir_branch_name>`

Examples:

- `branch:Terminal_A`
- `branch:B_cell`

Semantics:

- `weight_semantics = "palantir_branch_probability"` (recorded in provenance)

Precondition for reliable availability:

- explicit `terminal_cells` should be supplied (v1.1 recommendation)

Note:

- primitive-level normalization is not enforced
- Palantir branch probabilities may be normalized by method semantics, but that is method-level meaning, not primitive contract

### 3) `branch_summary` (`obs_table`) [Included in v1]

Human- and client-friendly summary of branches/terminal states.

- kind: `obs_table`
- `entity_kind = "branch"`
- `table_type = "branch_summary"` (recommended)

Candidate columns (v1):

- `branch` (matches `branch_membership$key` without `branch:` prefix or includes exact key; choose one and document)
- `n_cells_prob_gt_0` (count)
- `mean_prob` (numeric)
- `max_prob` (numeric)
- `top_cell_id` (optional, by probability)

This table is primarily for UX/inspection and quick plotting/wrangling.

### 4) `entropy` (`cell_vector`) [Recommended in v1]

Palantir entropy from `PResults.entropy`.

- kind: `cell_vector`
- `value_type = "continuous"`

Why include:

- useful for branch uncertainty / commitment analyses
- cheap to emit once Palantir is run

### 5) `model` (`model_ref`) [Recommended, can be staged]

Palantir result/model artifact for continuation/reuse.

- kind: `model_ref`
- `engine = "palantir"`

Storage notes:

- model path format may be Python-native (`.pkl`, `.joblib`, etc.)
- in v1 this may be Python-consumable first, with R treating it as an opaque `model_ref` unless a loader/bridge path is added

## Outputs Summary (recommended v1 set)

Minimal-but-useful v1:

- `pseudotime` (`cell_vector`)
- `branch_membership` (`relation_family`)
- `branch_summary` (`obs_table`)
- `entropy` (`cell_vector`)
- `model` (`model_ref`) (optional if we want to defer model serialization)

## Practical Runtime Modes (important)

### A) Pseudotime-only Palantir (root only)

Inputs:
- `root_cell` only (no `terminal_cells`)

Expected behavior:
- `pseudotime` and `entropy` usually available
- `branch_probs` may be empty (`0` branch columns)

This mode should be treated as method-valid but **not sufficient** for branch/fate analyses.

### B) Branch-aware Palantir (recommended)

Inputs:
- `root_cell`
- `terminal_cells` (explicit endpoints)

Expected behavior:
- `pseudotime`
- `entropy`
- `branch_membership`
- `branch_summary`

This is the recommended mode for trajectory branch interpretation and downstream branch-linked GSEA.

## Provenance / Birth Certificate Requirements

Bench remains provenance authority.

Record at minimum:

- `fit_space_id`
- `dims` (resolved)
- `root_cell`
- `terminal_cells` (if provided)
- `knn`
- `n_diffusion_components`
- `n_waypoints`
- Palantir version (`palantir.__version__`)
- Scanpy/anndata versions (useful for reproducibility)

For `branch_membership`, record semantic hints:

- `branch_membership_key_prefix = "branch:"`
- `weight_semantics = "palantir_branch_probability"`
- `branch_membership_requires_terminal_states = TRUE` (engine hint)

## Validation Rules (op-level)

Before Python handoff:

- `root_cell` must be length-1 and non-empty
- `root_cell` must be in effective cells
- `fit_space` must resolve to numeric finite coordinates for effective cells
- `dims` (if provided) must be valid positive integers within `fit_space` bounds
- `terminal_cells` (if provided) must all be present in effective cells

After Python receipt:

- outputs match expected artifact IDs/types
- R `wb_art_load()` succeeds for all declared outputs
- if `terminal_cells` were supplied and `branch_probs` is empty, fail with a method-level error (not a loader SQL error)

## Mapping to `pybench` (v1)

Expected Python side implementation (`pybench.ops.palantir_fit`) should:

1. load request via protocol validator
2. read cells + space via `pybench.getters`
3. build Palantir input matrix/DataFrame
4. run Palantir
5. write payloads via:
   - `write_artifact_cell_vector_payload()` (`pseudotime`)
   - `write_artifact_relation_family_payload()` (`branch_membership`)
   - `write_artifact_table_payload()` (`branch_summary`)
   - `write_artifact_cell_vector_payload()` (`entropy`)
   - `write_artifact_model_ref_payload()` (`model`, if included)
6. emit receipt

## Open Questions (after first implementation pass)

1. `dims` default policy:
- use all dims in `fit_space`
- or cap (for example first 30/50) for stability/performance

2. `branch_summary$branch` column:
- exact `relation_family$key` values (`branch:...`) for strict joinability
- or raw Palantir branch names plus a `relation_key` column

3. `model_ref` serialization format:
- pickle/joblib (Python-native)
- include companion metadata JSON?

4. `seed` semantics:
- which Palantir/scanpy substeps are actually seed-controlled and worth exposing in v1

## Implementation Status (current)

Completed:

1. `pybench.ops.palantir_fit` implemented
2. standalone R bridge contract test implemented and passing
3. first-class `scworkbench` op (`palantir_fit`) implemented and passing
4. full-core run validated with explicit `terminal_cells` (root + CD3/CD19 endpoints)

Current recommendation:

- treat explicit `terminal_cells` as required in practice for branch/fate outputs
- optionally formalize this as a stricter contract requirement in a future `v2`
