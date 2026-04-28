# `space_path_family` Primitive (Design Note)

Status: proposed

Purpose: represent ordered paths through a named latent space as a reusable
engine primitive.

This is motivated by checkpoint-anchored trajectory scoring in spaces such as
`lsi`, `pca`, and especially `peakvi_space`, but it is intentionally broader
than any one method or lineage.

## Why We Need It

Current trajectory-like primitives are split:

- `cell_vector` and `cell_vector_family`
  - good for per-cell scalar outputs like pseudotime or progress
- `relation_family`
  - good for soft memberships or route/branch weights
- `path_2d_family`
  - good for drawable 2D curves after projection into a plotting space

What we do not have is a primitive for:

- an ordered path in the original analytical space
- defined by biological checkpoints or other anchors
- optionally bent by the intervening cell manifold
- reusable for scoring projected/query cells later

That gap becomes especially important once we have:

- `peakvi_fit`
- `peakvi_project`

because those ops create a shared latent space where paths should be portable
across datasets, including projected query cells.

## Core Idea

Treat the analytical path as a first-class geometric object in a named space.

The path should not be:

- just a list of cells
- just a 2D display curve
- just a method-specific trajectory artifact

Instead, it should be:

- an ordered sequence of coordinates in a named `space`
- plus anchor metadata
- plus fitting metadata

Cells and checkpoints inform the path.
The path itself is the geometric object.

## Why Not Use Cells Directly?

If the path is forced to be a sequence of observed cells:

- it becomes noisy
- it becomes sensitive to sampling density
- it is harder to reuse across projected datasets
- it becomes harder to define stable checkpoint semantics

So the primitive should store coordinates in the latent space, even if some
path points are not occupied by exact observed cells.

This is correct analytically:

- checkpoints define intended order
- intervening cells can pull the fitted path onto the manifold
- the resulting geometric path may pass through latent coordinates not occupied
  by a literal cell

## Path Classes

The primitive should support at least two construction classes:

1. `linear`
- piecewise-linear segments between ordered anchors
- simplest, most robust v1

2. `manifold_smooth`
- anchors define order
- intermediate cells bend the path
- intended v2 path-fitting mode

Other future path classes could include:

- `trajectory_adapter`
  - path sampled or derived from Slingshot / Monocle3 / Palantir outputs
- `manual_coords`
  - explicit user-supplied waypoints in the space

## Proposed Primitive Shape

Candidate name: `space_path_family`

Proposed required fields:

- `kind = "space_path_family"`
- `space_id`
  - named analytical space the path lives in
- `path_id`
  - path key / family member key
- `point`
  - ordered point index along the fitted path
- `dim`
  - integer dimension index
- `value`
  - numeric coordinate value for that dimension

Recommended row shape is long form per `(path_id, point, dim)`.

This keeps the primitive aligned with the existing family-style primitives,
which prefer parallel atomic vectors over nested list-columns.

## Recommended V1 Row Schema

Recommended in-memory v1 fields:

- `kind = "space_path_family"`
- `space_id`
- `path_id`
- `point`
- `dim`
- `value`
- `meta`

Where:

- `space_id`
  - repeated scalar string, one per row
- `path_id`
  - allows multiple paths in one primitive later without changing schema
- `point`
  - integer path point index, ordered within `path_id`
- `dim`
  - integer coordinate dimension, `1..n_dims`
- `value`
  - numeric coordinate value
- `meta`
  - primitive-level metadata list, not row-level payload

Recommended invariants:

- all core vectors have equal length
- `point >= 1`
- `dim >= 1`
- no duplicate `(space_id, path_id, point, dim)` rows
- all path points for a given `path_id` either share the same set of dimensions
  or fail validation

## Why Long Form Is Preferred

Compared with storing one matrix per path:

- long form is easier to validate in the same style as other family primitives
- long form is easier to promote into bundle storage later
- long form makes sparse or partial future representations possible if needed

This is more engine-native than a nested matrix/list-column payload.

## Candidate Constructor Shape

Recommended constructor shape:

- `wb_prim_space_path_family(space_id, path_id, point, dim, value, meta = list())`

This mirrors the style of:

- `wb_prim_cell_vector_family(...)`
- `wb_prim_relation_family(...)`
- `wb_prim_path_2d_family(...)`

## Anchors Versus Fitted Path

V1 recommendation:

- store fitted path rows in the primitive body
- store anchor definitions in `meta`

Recommended anchor metadata fields:

- `meta$anchor_mode`
- `meta$anchor_id`
- `meta$anchor_label`
- `meta$anchor_order`
- `meta$anchor_cell_set`
- `meta$anchor_summary`

This keeps the main primitive body focused on the actual path used for scoring,
while preserving the coarse biological intent that generated it.

Proposed required metadata:

- `meta$space_id`
- `meta$fit_mode`
  - `linear`, `manifold_smooth`, ...
- `meta$n_dims`

Proposed optional metadata:

- `meta$anchor_mode`
  - `checkpoint_centroid`, `trajectory_adapter`, `manual_coords`, ...
- `meta$anchor_labels`
- `meta$anchor_cell_sets`
- `meta$smoothing`
- `meta$nn_k`
- `meta$notes`

Recommended future smoothing metadata:

- `meta$smooth_k`
- `meta$smooth_n_iter`
- `meta$smooth_weight`
- `meta$smooth_neighbor_mode`

Recommended additional metadata:

- `meta$path_class`
  - `linear`, `manifold_smooth`, `trajectory_adapter`
- `meta$n_points`
- `meta$checkpoint_n`
- `meta$coordinate_space_kind`
  - usually `"space"`
- `meta$score_default`
  - optional future default for path scoring semantics

## Recommended Two-Layer Representation

The primitive should distinguish:

1. anchors
- coarse intended checkpoints / waypoints

2. fitted path
- sampled points actually used for scoring

This distinction matters because:

- user intent lives in the anchors
- analytical scoring should usually use the fitted path

So the primitive metadata should preserve anchor provenance even if the main row
payload stores only the fitted path points.

## Semantics

Primitive shape is generic.
Meaning comes from:

- producing op contract
- birth certificate / provenance
- metadata describing path construction mode

Examples:

- B-lineage path through `peakvi_space`
  - anchors: `STHSC -> CLP -> FrA -> FrE`
- T-lineage part-1 path
  - anchors: `STHSC -> CLP -> FrA -> DN2b -> DN3`
- tumor projection path
  - anchors defined on a reference, then reused for projected query cells

This follows the project rule:

- primitives stay primitive; civilization lives in birth certificates

## Relationship To Existing Primitives

Recommended coexistence pattern:

- `space_path_family`
  - analytical high-dimensional path
- `path_2d_family`
  - explicit projected/rendered 2D view of that path
- `cell_vector_family`
  - per-cell path-relative scores such as progress or distance

This keeps analytical geometry separate from display geometry.

## Why `path_2d_family` Is Not Enough

`path_2d_family` is a rendering primitive.

It answers:

- what curve should be drawn in a 2D view?

It does not answer:

- what analytical path exists in the original latent space?
- how should cells be scored against that path?
- how should the same path be reused across projected query cells?

So `space_path_family` should be a new primitive, not an overloaded
reinterpretation of `path_2d_family`.

## Projection To 2D

The engine will need a helper op that turns:

- `space_path_family`

into:

- `path_2d_family`

for display in a chosen `space_2d`.

Important:

- the analytical truth remains in `space_path_family`
- the `path_2d_family` is an explicit derived rendering view

This fits the thin-client / compute-vs-display separation.

## Future Promotion / Storage Direction

Storage is intentionally not designed in full yet, but the likely direction is
a dedicated long-form payload table analogous to `artifact_curves_2d`.

Candidate future shape:

- one row per `(artifact_id, path_id, point, dim, value)`

with primitive-level metadata stored in artifact metadata / provenance JSON.

That should be designed only after the primitive and op contracts settle.

## Scoring Against The Path

This primitive is intended to support downstream scoring ops that emit:

- progress along path
- distance to path
- nearest segment
- nearest anchor / nearest checkpoint

Those should likely be returned as:

- `cell_vector_family`
- optionally paired with a compact `obs_table` for diagnostics/summaries

## Provenance Requirements

Birth certificate metadata should record at minimum:

- source `space_id`
- anchor derivation mode
- anchor definitions or references
- fitting mode
- sampling density / number of fitted points
- smoothing parameters if used
- whether the path was linear or manifold-shaped

If the path is derived from an existing trajectory object, provenance should
also record:

- source op
- source model ref or path source
- lineage/branch/route selection rules

## Working Principle

- Separation of compute and display.
- Paths should be analytical objects before they are plot overlays.
- Checkpoints express intent; cells shape the manifold.

## V1 Decisions To Treat As Frozen For Now

These are the current recommended v1 decisions unless a strong counterargument
emerges:

1. The core analytical primitive is new.
- use `space_path_family`
- do not overload `path_2d_family`

2. The primitive body stores fitted path coordinates, not checkpoint cells.
- checkpoints live in metadata/provenance
- fitted path points are the analytical object

3. The primitive uses long-form coordinate rows.
- `(space_id, path_id, point, dim, value)`
- avoid nested list-column or matrix payloads in v1

4. `path_2d_family` remains a derived rendering primitive.
- analytical path first
- 2D path second

5. V1 path class is `linear`.
- manifold-shaped fitting is a later extension, not a reason to delay the core
  primitive

6. The primitive must remain generic.
- not Slingshot-specific
- not PeakVI-specific
- not lineage-specific

## Remaining Open Questions Before Full Implementation

These do not block design agreement, but they should be answered before
promotion/storage and full op implementation are finalized.

1. Multi-path support in one primitive
- allow multiple `path_id` values in one primitive from day one
- or keep v1 practice to one path per primitive even if schema allows many

2. Anchor metadata granularity
- store only checkpoint labels and cell-set refs
- or also store resolved anchor centroids explicitly in metadata

3. Scoring metadata location
- should default scoring semantics live only in provenance
- or also in `meta$score_default`

4. Promotion/storage table shape
- one dedicated long-form payload table is likely
- exact schema is still open

5. Path sampling density policy
- op-chosen default only
- or user-tunable with contract-level hard caps/guidance

## Current Decision Updates

The following choices are now the current intended contract direction:

1. Checkpoints come from cells, not free coordinates, in v1.
- use checkpoint cell sets / resolved cells
- derive checkpoint summaries such as centroids from those cells
- do not support arbitrary user-supplied coordinate checkpoints in v1

2. Path primitives are promotable.
- `space_path_family` should be treated as a promotable analytical output
- projected `path_2d_family` outputs should also remain promotable as rendering
  views

3. Validation should be strict on empty checkpoints and permissive on weaker
quality issues.
- fail if any checkpoint resolves to zero cells in the declared `space`
- fail if fewer than two non-empty checkpoints remain
- warn, but do not fail, for:
  - very small checkpoints
  - overlapping checkpoints
  - large checkpoint-size imbalance

4. The scoring family should have a compact tabular companion.
- analytical per-cell outputs still live in `cell_vector_family`
- scoring runs should also be allowed to emit a compact `obs_table`
- that table should summarize path diagnostics rather than replace the
  per-cell scores

5. V1 2D projection should standardize on one explicit approximation mode.
- use a single declared default rather than several loosely specified
  alternatives
- current recommended default is `local_interpolation`
- this keeps the display contract honest while avoiding premature mode
  proliferation

6. V1 practice should be one path per primitive, even if the schema allows
multiple `path_id` values.
- keep the schema future-proof for multi-path payloads
- but have each define op produce one analytical path per run in v1
- this keeps provenance, promotion, and debugging simpler

7. Resolved anchor centroids should be preserved in metadata.
- checkpoint cells define anchors
- resolved centroid coordinates should be stored in `meta`
- fitted path rows remain the primitive body

8. Anchor metadata should be required and explicit.
- minimum expected anchor metadata:
  - `anchor_label`
  - `anchor_order`
  - `anchor_cell_set`
  - `anchor_n_cells`
  - `anchor_summary`
- v1 default anchor summary is `centroid`

9. Smoothed paths should still preserve checkpoint provenance in the same
primitive shape.
- smoothing changes fitted path geometry, not primitive ontology
- anchor centroids and anchor identities must remain recoverable from metadata
- smoothing-specific parameters should be stored in metadata/provenance, not in
  a separate primitive kind
