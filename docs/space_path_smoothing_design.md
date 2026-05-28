# `space_path` Manifold Smoothing (Design Note)

Status: first conservative mode implemented; note retained for semantics

Purpose: define how `fit_mode = "manifold_smooth"` should behave without
changing the already-established `space_path_family` primitive or the scoring
contract.

This is a design note for the first smoothed path mode. The first conservative
`manifold_smooth` implementation now exists; this note records the intended
semantics rather than serving as the literal code contract.

## Short Version

The smoothed path should be:

- anchored by the ordered checkpoints
- bent by cells that lie between those checkpoints in the analytical space
- still emitted as the same `space_path_family` primitive
- still scored by the same `space_path_score` contract

So smoothing is a new path-construction mode, not a new primitive and not a new
scoring subsystem.

## What Problem Smoothing Solves

The linear v1 path is useful, but it has one obvious failure mode:

- if the manifold bends between checkpoints, straight segments can cut across
  low-density space

That can distort:

- progress scores
- distance-to-path scores
- visual interpretation in projected cells

So the first smoothing mode should preserve:

- checkpoint order
- checkpoint identity
- path portability

while improving:

- geometric faithfulness to the cell manifold

## Core Design Position

The smoothing mode should be:

- checkpoint-anchored
- locally manifold-aware
- conservative

It should not:

- behave like free unconstrained spline fitting
- infer a new biology-first route from scratch
- silently change the intended checkpoint order

The checkpoints define the intended route. The cells only shape the geometry
between them.

## Cell-Supported Curvature

The intended smoothed path should be:

- checkpoint-anchored
- cell-supported
- curved by the manifold where the manifold itself curves

So the path is not best described as:

- the shortest path between checkpoints

It is better described as:

- the route through latent space whose geometry is pulled toward regions of
  coherent cell support between the checkpoints

This is the key idea behind the “gravity” metaphor:

- checkpoints define the route intent
- cells create local curvature

Important refinement:

- not raw density alone
- but nearby density that is consistent with the intended route

So a dense unrelated cloud should not hijack the path merely by existing.
The path should be bent by local support near the provisional route, not by all
cells in the space equally.

## Which Cells Are Allowed To Pull The Path?

Implemented first-mode rule:

- only cells in the effective analysis universe are eligible
- the checkpoint cells are always included
- the path should be pulled primarily by cells near the current linear path

This means smoothing should not use all cells in the space equally.

Instead, it should use a constrained support set such as:

- cells within a distance threshold of the current path, or
- the `k` nearest cells around each provisional path point

This avoids the path being dragged by unrelated off-route structure.

That is why the path should be thought of as following cell-supported
pseudospatial curvature, not as optimizing a shortest Euclidean segment chain.

In the current v1 implementation, this refinement is already reflected in the
pull rule:

- nearby cells matter
- but route-consistent nearby cells matter more

Practically, the current path fitter prefers cells that are:

- near the provisional path point
- on the same or adjacent path segment
- close in projected progress along the current route
- not too far from the current path itself

## Recommended V1 Smoothing Strategy

The first `manifold_smooth` mode is implemented as:

1. Build the linear checkpoint path first.
2. Sample provisional path points along it.
3. For each provisional point:
   - find nearby cells in the analytical space
   - compute a weighted local centroid
4. Replace each provisional point with that local weighted centroid.
5. Re-impose the checkpoint endpoints exactly.
6. Optionally do a small number of smoothing iterations.

This is deliberately conservative:

- anchors stay fixed
- local cell clouds bend the path
- the path remains easy to explain

## Why This Strategy Is Better Than A Free Spline

Because we want:

- manifold pull
- checkpoint loyalty
- reproducibility
- simple provenance

A free spline through checkpoint centroids can still cut through empty space.
A fully unconstrained curve fit can overreact to local density quirks.

The local-centroid deformation approach sits in the middle:

- coarse order from checkpoints
- local shape from neighboring cells

## Anchor Constraint Rule

Implemented rule:

- first and last checkpoint anchors are fixed exactly
- intermediate checkpoint anchors are also fixed exactly in the first smoothed
  mode

This keeps the interpretation very clear:

- smoothing bends the segments between checkpoints
- it does not move the checkpoints themselves

If we later want softer checkpoint attraction rather than exact fixing, that
should be a later extension, not part of the first smoothed mode.

## Neighborhood Definition

The first smoothing mode should use one explicit neighborhood definition only.

Implemented default:

- `neighbor_mode = "knn"`

Meaning:

- for each provisional path point, find the `k` nearest eligible cells in the
  analytical space
- compute a distance-weighted centroid from those cells

Why this is a good first choice:

- easy to reason about
- deterministic
- no global radius tuning dependency
- works across spaces with different scale

## Weighting Rule

Implemented weighting surface:

- inverse-distance or Gaussian-like distance weighting

The design requirement is more important than the exact formula:

- closer cells must pull more strongly
- farther cells must have diminishing influence

The exact weight function should be recorded in provenance, but the first
implementation should keep one default only.

## Iteration Policy

Implemented iteration policy:

- default to a small fixed number of refinement iterations
- something like `n_iter = 2` or `3`

Why:

- one pass may be too stiff
- many passes increase instability and provenance complexity

The first mode should prefer stability over maximal flexibility.

## Monotonicity / Order Safety

Smoothing must preserve path order.

That means:

- the point sequence must remain ordered from checkpoint 1 to checkpoint N
- smoothing must not allow points to fold backward or reorder

Practical implication:

- smoothing should only deform point locations
- it should not reassign or permute point order

## Current Supported Parameters

When `fit_mode = "manifold_smooth"`, the first useful parameter set is:

- `smooth_k`
  - number of neighbor cells used per provisional point
- `smooth_n_iter`
  - number of refinement passes
- `smooth_weight`
  - weighting rule label

Avoid a large surface initially.

Do not add all of these at once:

- radius thresholds
- soft anchor penalties
- tangent regularizers
- graph geodesic options

Those can come later if needed.

## Provenance Requirements

If the path is smoothed, provenance should record at minimum:

- `fit_mode = "manifold_smooth"`
- `checkpoint_sets`
- `checkpoint_summary`
- `n_path_points`
- `smooth_k`
- `smooth_n_iter`
- `smooth_weight`
- effective cell universe used for fitting

The primitive metadata should also keep:

- anchor centroids
- anchor labels/order

so the smoothed geometry remains auditable.

## Relationship To Scoring

No new scoring contract is needed.

The whole point of the primitive abstraction is that:

- linear and smoothed paths emit the same `space_path_family`
- `space_path_score` can operate on both

That means:

- the scoring surface stays stable
- only the path geometry changes

## Relationship To 2D Projection

Again, no new primitive is needed.

The projected curve remains:

- `path_2d_family`

The only difference is:

- the smoothed analytical path should usually yield a better-looking and more
  faithful 2D rendering

## Recommended First Implementation Boundary

The first smoothing implementation currently stops here:

- fixed checkpoint anchors
- `k`-nearest local weighted centroid deformation
- small number of iterations
- same scoring and projection contracts as linear mode

Do not make the first smoothing mode:

- graph-geodesic
- branch-inference-aware
- method-adapter-aware
- user-editable in the client

## Working Principle

- checkpoints define intent
- nearby cells bend the path
- anchors stay fixed
- primitive contract stays unchanged
- smoothing is geometry, not a new ontology
