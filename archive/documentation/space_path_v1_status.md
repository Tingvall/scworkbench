# `space_path` V1 Status

Status: implemented

Purpose: record what now exists in the engine for the `space_path` subsystem,
what has been validated, and what still belongs to later work.

## Short Version

`space_path` v1 is real.

The engine now has:

- an analytical path primitive: `space_path_family`
- path definition in any named `space`
- cell-relative path scoring
- 2D rendering into `path_2d_family`
- a first conservative smoothing mode
- promotion/load/delete support for analytical paths

This is no longer only a design exercise.

## What Exists Now

### Primitive

The analytical path primitive is:

- `space_path_family`

It stores:

- the source `space_id`
- one `path_id`
- ordered path points
- dimension coordinates
- metadata about anchors and fit mode

The analytical truth remains in this primitive.

### Ops

The implemented op family is:

- `space_path_define`
- `space_path_score`
- `space_path_project_2d`

### Implemented Fit Modes

`space_path_define` currently supports:

- `fit_mode = "linear"`
- `fit_mode = "manifold_smooth"`

### Implemented Scoring Outputs

`space_path_score` currently emits:

- `path_scores`
  - kind `cell_vector_family`
  - keys:
    - `progress`
    - `distance`
    - `nearest_segment`
    - `nearest_anchor`
- `fit_summary`
  - kind `obs_table`

### Implemented 2D Rendering

`space_path_project_2d` currently emits:

- `curves`
  - kind `path_2d_family`

The 2D curve is explicitly only a rendering of the analytical path.

## What The Smoothing Mode Means

The current smoothed path is:

- checkpoint-anchored
- cell-supported
- route-consistent

More specifically:

- checkpoint anchors remain fixed exactly
- interior path points are deformed by nearby cells in the analytical space
- cell influence is not based on proximity alone
- the current implementation also prefers cells that are route-consistent with
  the local segment and local progress of the path

So the intended interpretation is:

- checkpoints define intent
- cells define curvature

This is the first implemented version of the “cell-supported curvature” idea.

## Promotion / Persistence

Analytical paths are now first-class promotable outputs.

Support exists for:

- promote
- load
- delete

So `space_path_family` is not only transient session data.

## What Was Validated

The v1 implementation has passed focused contract tests for:

- primitive construction
- op interface conformance
- promotion/load roundtrip for `space_path_family`
- bundle-backed define/score/project behavior on `demo`
- smoothed path invariants:
  - anchors remain fixed
  - interior points differ from the linear path

This means the subsystem is validated at the contract and bundle-integration
level, not only at the helper-function level.

## Current Scope Limits

The current v1 is intentionally narrow:

- one path per primitive/run in practice
- checkpoint inputs come from cell-defined checkpoints
- analytical scoring is Euclidean in the source space
- 2D rendering uses local interpolation
- smoothing is conservative and local, not a general trajectory inference
  engine

## What Is Still Future Work

The most obvious next extensions are:

- trajectory-method adapter ops
  - e.g. `slingshot_to_space_path`
  - e.g. `monocle3_to_space_path`
  - e.g. `palantir_to_space_path`
- subspace / dimension-filtered path definition
  - e.g. exclude cycling-associated latent dimensions in PeakVI
- richer smoothing controls
- stronger route-consistency semantics
- multi-path families in one primitive/run
- more elaborate summary outputs from `space_path_score`

None of those are required for the current v1 to be useful.

## Practical Summary

The engine now supports:

1. define a checkpoint-anchored analytical path in a latent space
2. optionally smooth it with cell-supported curvature
3. score cells along that path
4. render the path in 2D for visualization

That is the first complete version of the subsystem.

## Current Workflow Guidance

One important practical distinction is now explicit:

- all scored cells can receive geometric path coordinates such as `progress` and
  `distance`
- but not all scored cells should automatically be treated as on-trajectory for
  downstream biological dynamics

Current recommended workflow rule:

- use `distance` as the primary path-membership gate
- include cells for downstream trajectory dynamics only if
  `distance <= median(distance) + 1.5 * MAD(distance)`

Why:

- raw path projection is always defined geometrically
- but far-off cells can distort gene/signature/cycle trends if treated as
  equivalent trajectory members
- a robust distance rule adapts across spaces such as `lsi` and PeakVI, where
  absolute Euclidean units are not directly comparable

So in current practice:

- `space_path_score` remains broad and diagnostic
- workflow-level trajectory summaries should use a robust on-path inclusion gate
