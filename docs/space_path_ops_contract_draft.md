# Space Path Ops Contract Draft

Status: v1 implemented, draft retained for contract and extension planning

Purpose: define a generic engine-owned op family for checkpoint-anchored path
construction and path-relative scoring in any latent space.

This is intended to be:

- reusable across methods
- reusable across lineages
- reusable across reference/query projection workflows

It should not be a one-off trajectory helper for a single method.

The core v1 op family described here now exists in the engine. This draft now
serves two purposes:

- document what the implemented surface means
- document how later extensions should preserve that same abstraction

## Core Design Position

The core abstraction is:

- an ordered path through a named `space`

not:

- a Slingshot convenience wrapper
- a Monocle3-specific branch artifact
- a hard-coded B/T/innate lineage helper

Trajectory-method-specific helpers may exist later, but only as adapter ops
that feed the generic path primitive and scoring surface.

## Problem This Solves

Users may approximately know the intended trajectory structure:

- a start state
- intermediate checkpoints
- an end state

But the actual manifold between checkpoints may curve.

So the engine needs a contract for:

1. defining checkpoint-anchored paths
2. optionally letting cells between checkpoints bend the path
3. scoring cells relative to that path
4. projecting the path into `space_2d` for visualization

This is especially valuable in shared latent spaces such as PeakVI, where:

- reference paths should be reusable
- projected query cells should be scoreable against the same path

## Op Family

### 1. `space_path_define`

Intent:

- construct a reusable path in a named `space`

Required inputs:

- `space`

Required path-definition inputs:

- ordered checkpoints

Checkpoint sources could include:

- ordered `cell_set` refs
- ordered explicit `cell_id` groups
- ordered user coordinates in the same space

V1 implementation:

- support ordered checkpoint cell sets first

Recommended checkpoint input contract for v1:

- one ordered character vector parameter such as `checkpoint_sets`
- each element names a `cell_set`
- order is analytically meaningful and required

Example:

- `checkpoint_sets = c("set:STHSC", "set:CLP", "set:FrA", "set:DN2b", "set:DN3")`

Current main parameters:

- `fit_mode`
  - `linear`
  - later `manifold_smooth`
- later `dims` / `exclude_dims`
  - for subspace-constrained path definition
- `path_id_out`
- `n_path_points`
  - sampling density along fitted path
- `checkpoint_summary`
  - default `centroid`

Outputs:

- `path`
  - kind `space_path_family`

Implemented v1 semantics:

- compute centroid per checkpoint
- connect checkpoints in order
- sample a piecewise-linear path

Recommended additional v1 outputs in params:

- resolved checkpoint order
- checkpoint sizes
- number of fitted path points
- fit mode

Later extension semantics:

- same anchors
- fit a manifold-aware curved path between them
- first recommended smoothing rule:
  - begin from the linear checkpoint path
  - let nearby cells deform sampled path points locally
  - keep checkpoint anchors fixed

### 2. `space_path_score`

Intent:

- score cells against a defined `space_path_family`

Required inputs:

- `space`
- `path`

Current main parameters:

- `score_mode`
  - default `orthogonal_projection`
- `distance_metric`
  - default Euclidean in the space
- `anchor_window`
  - optional local neighborhood tuning for smoothed paths later
- `score_prefix`

Implemented outputs:

- `path_scores`
  - kind `cell_vector_family`

Recommended keys inside `path_scores`:

- `progress`
  - normalized progress along path
- `distance`
  - distance to fitted path
- `nearest_segment`
  - segment index
- `nearest_anchor`
  - anchor/checkpoint index

Recommended v1 `value_type` policy:

- `progress` and `distance`
  - continuous
- `nearest_segment` and `nearest_anchor`
  - discrete but still encoded in `cell_vector_family`

Recommended key naming convention:

- `progress`
- `distance`
- `nearest_segment`
- `nearest_anchor`

Avoid embedding the path id into the key name itself if the primitive already
carries path identity in metadata or provenance.

Current companion summary output:

- `obs_table`
  - compact path scoring summary

Current workflow guidance:

- `space_path_score` is intentionally geometric and broad
- every scored cell can receive a `progress` and `distance`
- but downstream biological trajectory summaries should not blindly use all
  scored cells

Current recommended workflow rule:

- use `distance` as the primary path-membership gate
- include cells in downstream trajectory dynamics only if
  `distance <= median(distance) + 1.5 * MAD(distance)`

This is currently a workflow-level convention rather than a separate dedicated
membership op.

### 3. `space_path_project_2d`

Intent:

- create a drawable 2D rendering of an analytical path

Required inputs:

- `path`
  - `space_path_family`
- `space_2d`
  - target rendering space

Implemented outputs:

- `curves`
  - `path_2d_family`

Important semantics:

- this is a display/helper op
- it must not redefine the analytical path
- the 2D path is explicitly a projection/approximation for rendering

Important v1 limitation:

- many `space_2d` objects are cell embeddings, not globally parameterized
  transforms
- therefore arbitrary high-dimensional path points cannot always be projected
  exactly

So v1 should be explicit that projection may be approximate, for example via:

- nearest-neighbor interpolation from cells shared between the analytical space
  and the `space_2d`
- local weighted interpolation in the paired cell coordinates

## Adapter Ops (Later, Not Core)

Possible later adapters:

- `slingshot_to_space_path`
- `palantir_to_space_path`
- `monocle3_to_space_path`

These should:

- consume trajectory-method-specific outputs
- emit the same generic `space_path_family`

That keeps the core abstraction stable.

## Primitive In / Primitive Out

### `space_path_define`

In:

- `space`
- checkpoint refs (likely `cell_set` refs in params or inputs)

Out:

- `space_path_family`

### `space_path_score`

In:

- `space`
- `space_path_family`

Out:

- `cell_vector_family`
- `obs_table`

### `space_path_project_2d`

In:

- `space_path_family`
- `space_2d`

Out:

- `path_2d_family`

## Concrete Interface Sketch

The intended `op_catalog`-style interface shape is approximately:

### `space_path_define`

- `requires = list(space = "space")`
- `produces = list(path = "space_path_family")`
- `promotable = c("path")`

Suggested params:

- `checkpoint_sets`
  - `string_vec`
- `fit_mode`
  - `choice`
  - default `linear`
- `n_path_points`
  - `int`
- `checkpoint_summary`
  - `choice`
  - default `centroid`
- `path_id_out`
  - `string`

Future `manifold_smooth` params:

- `smooth_k`
  - neighbor count per provisional path point
- `smooth_n_iter`
  - number of refinement passes
- `smooth_weight`
  - distance-weighting rule label

### `space_path_score`

- `requires = list(space = "space", path = "space_path_family")`
- `produces = list(path_scores = "cell_vector_family", fit_summary = "obs_table")`
- `promotable = c("path_scores", "fit_summary")`

Suggested params:

- `score_mode`
  - `choice`
  - default `orthogonal_projection`
- `distance_metric`
  - `choice`
  - default `euclidean`
- `score_prefix`
  - `string`

### `space_path_project_2d`

- `requires = list(path = "space_path_family", plot_space = "space_2d")`
- `produces = list(curves = "path_2d_family")`
- `promotable = c("curves")`

Suggested params:

- `project_mode`
  - `choice`
  - default `local_interpolation`
- `approx_points`
  - `int`
  - for display compaction

## Why `cell_vector_family` For Scoring?

Scoring naturally produces multiple per-cell values:

- progress
- distance
- nearest segment
- nearest anchor

Bundling them as `cell_vector_family` keeps the surface generic and compact
while preserving downstream reuse.

## Path Construction Modes

### V1: `linear`

Meaning:

- ordered checkpoint summaries
- straight segments between checkpoints

Pros:

- simple
- stable
- easy to validate
- good first contract target

Cons:

- curved manifolds may be shortcut between checkpoints

### V2: `manifold_smooth`

Meaning:

- checkpoints anchor the order
- intervening cells pull the path onto the manifold

Pros:

- better for curved biological manifolds
- closer to how users think about checkpoint-guided trajectories

Cons:

- more assumptions
- more parameters
- more provenance needs

Important design principle:

- define the primitive so both modes fit inside the same contract
- do not create separate primitive kinds for linear vs smoothed paths

## Progress Semantics

Progress should be explicit and method-independent.

Recommended v1 rule:

- normalized arclength from `0` to `1`

Where:

- `0` = beginning of path
- `1` = end of path

This is more reusable than raw pseudotime-like units.

## Distance Semantics

Recommended v1 rule:

- Euclidean distance from each cell to its nearest point or segment on the
  fitted path in the original `space`

This gives an explicit measure of:

- how well the cell conforms to the intended path

That is one of the key advantages over pure nearest-neighbor pseudotime
transfer.

## Relationship To PeakVI

This op family is especially valuable for:

- `peakvi_fit`
- `peakvi_project`

because it enables:

- define reference paths once in PeakVI space
- project new cells into the same space
- score them against the same paths

This is a major reason to keep the abstraction generic and not tied to one
trajectory method.

## Provenance Requirements

At minimum record:

- source `space_id`
- checkpoint definitions and order
- checkpoint summary rule
- fit mode
- number of fitted path points
- scoring mode
- distance metric

For smoothed paths later also record:

- smoothing parameters
- neighborhood rules
- any manifold-pull settings

## V1 Recommendation

Implement in this order:

1. docs + primitive contract
2. `space_path_define` with `fit_mode = "linear"`
3. `space_path_score`
4. `space_path_project_2d`
5. only then manifold-aware fitting

## What Not To Do

Do not:

- make the path primitive itself 2D-first
- encode trajectory-method semantics into the core path primitive
- skip anchor provenance because the path points seem self-explanatory
- force projected paths to pretend they are exact when they are interpolated for
  display

## V1 Decisions To Treat As Frozen For Now

These should be treated as the current intended v1 contract unless we discover a
substantial problem.

1. Core op family
- `space_path_define`
- `space_path_score`
- `space_path_project_2d`

2. Checkpoint definition input
- ordered `checkpoint_sets`
- not method-specific lineage objects

3. First path-construction mode
- `fit_mode = "linear"`

4. Main scoring output
- one `cell_vector_family`
- keys:
  - `progress`
  - `distance`
  - `nearest_segment`
  - `nearest_anchor`

5. Progress semantics
- normalized arclength from `0` to `1`

6. 2D projection semantics
- explicit derived approximation for display
- not the analytical truth

7. Method adapters are later.
- do not block the generic path subsystem on Slingshot/Monocle3/Palantir
  adapter work

## Remaining Open Questions Before Implementation Expands

These are the main remaining contract questions after the current v1 decisions
are treated as settled.

1. Should `space_path_define` accept only checkpoint cell sets in v1, or also
ordered explicit coordinates?
Decision:

- v1 accepts checkpoint cell sets / checkpoint cells only
- no free coordinate checkpoints yet

2. Should `space_path_score` emit only `cell_vector_family`, or also a compact
summary `obs_table` in the same run?
Decision:

- also emit a compact `obs_table`
- this should summarize path-level scoring diagnostics rather than replace the
  per-cell score family

3. Should `space_path_project_2d` support more than one interpolation strategy
in v1, or just one explicit default?
Decision:

- one explicit v1 default only
- recommended default: `local_interpolation`
- keep the op semantics honest by describing the 2D curve as an approximation

4. Should path-definition ops be promotable by default, or should path
promotion be opt-in until the storage contract settles?
Decision:

- path outputs should be promotable
- both analytical `space_path_family` and projected `path_2d_family`

5. How strongly should the engine validate that checkpoint sets overlap the
declared `space` cell universe before fitting begins?
Decision:

- strict-fail if any checkpoint resolves to zero cells in the declared `space`
- strict-fail if fewer than two non-empty checkpoints remain
- warning-only for:
  - very small checkpoints
  - overlapping checkpoints
  - large checkpoint-size imbalance

## Updated V1 Interface Direction

Given the decisions above, the intended v1 surface is now:

### `space_path_define`

- `requires = list(space = "space")`
- `produces = list(path = "space_path_family")`
- `promotable = c("path")`

Suggested params:

- `checkpoint_sets`
  - ordered `string_vec`
- `fit_mode`
  - `choice`
  - default `linear`
- `checkpoint_summary`
  - `choice`
  - default `centroid`
- `n_path_points`
  - `int`
- `path_id_out`
  - `string`

Suggested default behavior:

- compute one path per run
- use checkpoint centroids as anchors
- sample `25` fitted points per segment unless overridden

### `space_path_score`

- `requires = list(space = "space", path = "space_path_family")`
- `produces = list(path_scores = "cell_vector_family", fit_summary = "obs_table")`
- `promotable = c("path_scores", "fit_summary")`

Suggested summary purpose:

- path-level scoring diagnostics
- checkpoint/path coverage summaries
- distance / progress distribution summaries

Recommended v1 summary columns:

- `path_id`
- `space_id`
- `fit_mode`
- `n_checkpoints`
- `n_path_points`
- `cells_scored`
- `mean_distance`
- `median_distance`
- `p90_distance`

### `space_path_project_2d`

- `requires = list(path = "space_path_family", plot_space = "space_2d")`
- `produces = list(curves = "path_2d_family")`
- `promotable = c("curves")`

Suggested params:

- `project_mode`
  - `choice`
  - default `local_interpolation`
- `approx_points`
  - `int`

This keeps the first implementation simple while preserving a clean upgrade path.

## Decision Summary

These are the decisions that should now be treated as the intended v1 contract
direction unless we later discover a concrete implementation problem.

1. Checkpoints are cell-defined in v1.
- ordered checkpoint cell sets are the canonical input form
- free coordinate checkpoints are deferred

2. Scoring returns both vector and table surfaces.
- `cell_vector_family` remains the analytical per-cell score output
- `obs_table` is the compact summary companion

3. 2D projection is approximate and standardized.
- `space_path_project_2d` should use one explicit default projection mode in v1
- current default is `local_interpolation`

4. Path outputs are promotable.
- analytical `space_path_family`
- projected `path_2d_family`
- scoring outputs including summary tables

5. Validation is strict on missing checkpoint support and warning-level on
weaker quality issues.
- fail on empty checkpoint resolution
- fail if fewer than two non-empty checkpoints remain
- warn on small checkpoints, overlap, and major checkpoint-size imbalance

6. V1 define runs should produce one path at a time.
- schema can remain capable of multiple `path_id` values later
- but the intended first operational contract is one path per op run

7. Resolved anchor centroids belong in metadata, not in the primitive body.
- checkpoint cells define anchors
- centroid coordinates should be retained for auditability
- fitted path coordinates remain the analytical path payload

8. The summary table should stay compact and path-level in v1.
- one summary row per path
- use the recommended columns listed above unless a strong reason emerges to
  expand it

9. V1 path density should be deterministic and modest by default.
- recommended default is `25` fitted points per segment
- total fitted points should therefore be:
  - `1 + (n_checkpoints - 1) * 25`

10. V1 scoring semantics should remain intentionally simple.
- `progress` = normalized arclength
- `distance` = Euclidean distance to nearest segment
- `nearest_anchor` = nearest checkpoint anchor by path order
- `nearest_segment` = segment index

11. The first smoothed mode should be conservative and checkpoint-fixed.
- `fit_mode = "manifold_smooth"` should not change the primitive or scoring
  contracts
- nearby cells should bend the path locally
- checkpoint anchors should remain fixed exactly in the first smoothed mode
- the analytical interpretation should be cell-supported curvature between
  checkpoints, not shortest Euclidean interpolation

## Non-Goals For V1

- not a replacement for Slingshot/Palantir/Monocle3
- not full graph inference
- not arbitrary manifold learning inside the path op
- not client-owned path editing semantics

## Working Principle

- generic engine path first
- trajectory-method adapters later
- analytical path first, 2D path second
- checkpoints define intent; cells shape the manifold
