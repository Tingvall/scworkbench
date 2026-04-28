# Space Path Intent Note

Status: active intent note for implemented v1

Purpose: explain why checkpoint-anchored latent paths belong in the engine and
what analytical role they should play.

This is an intent note, not a storage or implementation contract. The first
engine-owned version of this subsystem is now implemented; this note captures
the intent that shaped it.

## Short Version

We want a generic engine surface for:

- defining ordered paths in a latent space
- using biological checkpoints as anchors
- letting the manifold between checkpoints shape the fitted path
- scoring cells and projected query cells against that path

This is intended to be an engine abstraction, not a client convention and not a
trajectory-method-specific convenience wrapper.

## Why This Belongs In `scworkbench`

This subsystem is aligned with the project slogans:

- primitives stay primitive; civilization comes from birth certificates
- separation of compute and display
- contracts determine the best friendships
- centralize the contract, decentralize the compute

In practical terms:

- the path should be a primitive, not a UI trick
- analytical path definition should be separate from 2D rendering
- reusable relationships between spaces, paths, and scores should be explicit
  engine contracts
- method adapters can remain decentralized later, but the path contract should
  be centralized now

## The Analytical Gap

Current trajectory methods can infer paths or branches, but they do not fully
cover the use case we care about here:

- users often already know the approximate biological route
- they may want to anchor that route with known checkpoints
- they may want to reuse the same route in a shared latent space later
- they may want to score projected query cells against that route without
  refitting the whole trajectory method

That is not the same problem as generic trajectory inference.

It is closer to:

- define a biologically anchored path in a reusable latent space
- then use it as a stable analytical reference object

## Why This Is Especially Important After PeakVI

The engine now has:

- `peakvi_fit`
- `peakvi_project`

So we can create a shared latent space and then project new cells into that same
representation.

That immediately creates demand for path reuse:

- define a reference path once
- project query cells later
- score them against the same path

This is much stronger than:

- refitting a trajectory independently in every dataset
- or copying nearest-neighbor pseudotime heuristics between datasets

## Checkpoints Are Intent, Not The Final Geometry

The user may know checkpoints such as:

- `STHSC -> CLP -> FrA -> DN2b -> DN3`

But the manifold between checkpoints is not usually straight.

So the right conceptual split is:

1. checkpoints define intended order
2. cells between checkpoints shape the actual path

This is why the path subsystem should support both:

- simple piecewise-linear v1
- manifold-aware fitted v2

The important thing is to get the abstraction right before optimizing the
geometry.

The first smoothing mode should therefore be conservative:

- start from the linear checkpoint path
- let nearby cells bend it locally
- keep checkpoint anchors fixed

That gives the manifold some gravity without letting it erase the intended
biological route.

## Cell-Supported Curvature

The path should not be understood as:

- the shortest straight route between checkpoints

It should be understood as:

- the checkpoint-anchored route that is most strongly supported by the cell
  manifold between those checkpoints

That means the analytical trajectory is allowed to curve when cell support
curves.

The important scientific distinction is:

- checkpoints define intent
- cells define curvature

In practice this means:

- dense, coherent cell support between checkpoints should bend the path more
  strongly
- sparse or weakly supported regions should exert less pull
- unrelated dense off-route structure should not automatically dominate simply
  because it is populous

So the smoothing direction is not “connect checkpoints with the shortest line.”
It is closer to:

- follow the cell-supported pseudospatial curvature between checkpoints while
  preserving checkpoint order and identity

## Generic, Not Lineage-Specific

This should not be framed as:

- a T-cell helper
- a B-lineage helper
- a Slingshot extension

It should be framed as:

- a path-in-space subsystem

That makes it reusable for:

- developmental trajectories
- activation gradients
- tumor-to-reference progressions
- method-derived branches
- manually anchored progressions

## Analytical Path First, Display Path Second

The analytical truth should live in the original `space`.

The drawable curve in UMAP should be derived later.

So the design should enforce:

- high-dimensional analytical path first
- 2D projection helper second

That prevents the plotting view from becoming the accidental scientific truth.

## Relationship To Existing Trajectory Methods

This subsystem does not replace:

- Slingshot
- Palantir
- Monocle3

Instead it adds a reusable path layer that can:

- be defined manually from checkpoints
- later be derived from existing trajectory outputs through adapter ops

That is the right balance:

- generic core primitive
- method-specific adapters later

## V1 Intention And Outcome

The first version should prove the abstraction, not the most ambitious fitting
algorithm.

V1 aimed for:

- checkpoint-anchored path definition
- path-relative scoring
- 2D projection for visualization
- a first conservative smoothing mode

That abstraction proved sound enough that a first conservative
`manifold_smooth` mode was added without changing the conceptual surface.

## Working Principle

- build a stable path abstraction first
- keep compute semantics engine-owned
- let projected cells reuse the same path later
- treat checkpoints as intent and cells as manifold shape
