# `space_path` Subspace / Dimension-Filtered Paths

Status: future extension note

Purpose: record the idea that `space_path` should eventually support defining
and scoring trajectories in a selected subspace of a latent space rather than
always using every dimension.

## Motivation

The current `space_path` implementation uses the full chosen analytical space.

That is often reasonable, but it can be suboptimal when some latent dimensions
are dominated by signals that are not desirable trajectory drivers, such as:

- cell cycle
- stress / damage responses
- technical structure
- broad programs that are real but not relevant to the developmental question

For example:

- a PeakVI space may contain dimensions strongly associated with cycling
- a developmental path may be cleaner if those dimensions are excluded
- the path should then follow lineage-relevant structure rather than nuisance
  variation

So the future feature is:

- define the analytical path in a selected subspace
- still render it in the same display space afterwards

## Intended Use Case

This is especially attractive for:

- checkpoint-anchored developmental paths
- branch-specific trajectories outside ambiguous progenitors
- shared latent spaces such as PeakVI where dimensions can be empirically
  associated with known programs

The motivating idea is:

- trajectory geometry should be driven by lineage-relevant axes
- not by dimensions known to reflect cycling or other unwanted programs

## Core Design Idea

The analytical path remains:

- a path in a named `space`

But the geometry of that path would be computed in:

- either all dimensions of the space
- or a chosen subset of dimensions

The display layer remains separate:

- `space_path_project_2d()` still renders the resulting analytical path into a
  `space_2d`

So this feature does not change the primitive ontology.

It changes only:

- which coordinates are used to define and score the analytical path

## Candidate Contract Surface

Likely parameters for future `space_path_define` / `space_path_score`:

- `dims`
  - explicit dimensions to use
- or `exclude_dims`
  - explicit dimensions to ignore

Recommended v1 extension rule:

- support either `dims` or `exclude_dims`
- never both at the same time

Possible examples:

- `dims = c(1, 2, 4, 5, 7, 8, 10)`
- `exclude_dims = c(3, 6, 9)` to remove cycling-like dimensions

Recommended provenance metadata:

- `subspace_mode`
  - `"all_dims"`, `"include_dims"`, or `"exclude_dims"`
- `dims_used`
- `dims_excluded`
- `n_dims_used`

## Why This Fits The Existing `space_path` Design

This extension is aligned with the existing philosophy:

- analytical path first
- display projection second
- checkpoints define intent
- cells define curvature

Subspace selection simply says:

- which analytical coordinates should be allowed to define that curvature

That is a legitimate model choice, not a rendering tweak.

## How Dimensions Might Be Chosen

This note does not lock the selection strategy, but likely approaches include:

1. Prior biological knowledge

- known cycling-associated latent dimensions
- known nuisance-associated latent dimensions

2. Empirical association with signatures

- correlate each latent dimension with:
  - cycling scores
  - stress scores
  - lineage program scores
- then remove dimensions strongly associated with unwanted programs

3. Manual analyst choice

- interactive or scripted exclusion after inspecting dimension behavior

This means the main problem is not implementing subspaces mechanically.

The real problem is:

- deciding and documenting why a given dimension subset is biologically
  justified

## Scope Boundary

This would strengthen `space_path`, but it would not solve de novo progenitor
fate discovery.

It is still most appropriate for:

- branch-conditioned trajectory construction
- known developmental corridors
- cleaner lineage progression outside ambiguous progenitor regions

So this is a refinement of the current method, not a change in its biological
scope.

## Proposed Later Documentation Language

Possible user-facing framing:

- `space_path` can be defined in a selected latent subspace to suppress known
  nuisance dimensions and focus trajectory geometry on lineage-relevant axes.

## Practical Summary

Future `space_path` should support:

1. defining paths in all dimensions of a space
2. defining paths in a selected subset of dimensions
3. excluding known nuisance dimensions such as cycling-associated axes
4. rendering the resulting analytical path into the same 2D display space

This is a natural and potentially powerful extension, especially for PeakVI.
