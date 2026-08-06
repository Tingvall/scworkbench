# `cell_vector_compare` Contract Draft

Status: draft

Purpose: define a small generic op for comparing two cell-aligned scalar
signals on shared cells.

This is intended to cover use cases such as:

- pseudotime A vs pseudotime B
- module score A vs module score B
- pseudotime vs module score
- entropy vs cycling score

It should remain a compact reusable kernel, not a general-purpose comparison
framework.

## Why This Op Exists

The engine already has trajectory-facing ops such as:

- `trajectory_smooth`
- `trajectory_vector_smooth`
- `trajectory_branch_compare`
- `feature_trend_spearman`

But those answer different questions:

- how does one signal behave along a trajectory?
- how do branches differ?
- how do many features relate to one coordinate?

What is still missing is a symmetric two-signal comparison kernel:

- take signal `a`
- take signal `b`
- restrict to shared cells
- compare them directly

That is useful for trajectory-method agreement, but it is broader than
trajectories.

## Core Design Position

The op should compare:

- two `cell_vector` primitives

not:

- two methods by name
- two trajectories only
- two feature tables

Trajectory-method agreement is one important use case, but the primitive
contract should stay at the cell-signal level.

## V1 Scope

V1 should stay intentionally small.

Inputs:

- `a`
  - kind `cell_vector`
- `b`
  - kind `cell_vector`

Optional effective-cell restriction:

- `cells`

Main comparison spaces:

- `raw`
- `rank`

That is enough to answer the most important questions:

- do the signals agree numerically?
- do they order cells similarly?

## Why Rank Space Matters

Rank-space comparison is especially important when comparing:

- different trajectory methods
- differently scaled module scores
- signals with shifted or stretched numeric ranges

Two methods may disagree in absolute scale while still preserving nearly the
same cell ordering.

So the op should be able to compare:

- raw values
- or cell ranks induced by those values

without requiring separate client logic.

## Proposed Op

### `cell_vector_compare`

Intent:

- compare two cell-level signals on their shared cell universe

Required inputs:

- `a`
- `b`

Recommended params:

- `compare_space`
  - `raw`
  - `rank`
- `ties_method`
  - default `average`

Possible future params:

- `quantile` comparison space
- `zscore` comparison space
- optional monotone-fit residual summaries

These should not be part of the minimal first implementation unless needed.

## Shared-Cell Semantics

The op should always work on the intersecting cells of `a` and `b`.

Recommended behavior:

1. recover cell/value pairs from `a`
2. recover cell/value pairs from `b`
3. intersect cells
4. optionally apply external `cells` restriction
5. fail if fewer than a small minimum number of shared cells remain

This should be explicit in provenance and summary output.

## Comparison Spaces

### `compare_space = "raw"`

Meaning:

- compare the original numeric values directly

Useful for:

- module score magnitude agreement
- same-method reruns
- cases where scale itself matters

### `compare_space = "rank"`

Meaning:

- replace values with ranks on the shared-cell universe
- then compare the ranks

Useful for:

- trajectory-method agreement
- score ordering consistency
- cases where axis shift or scale distortion is expected

## Recommended Outputs

### 1. `summary`

Kind:

- `obs_table`

This should be one-row-per-comparison and include at least:

- `signal_a`
- `signal_b`
- `compare_space`
- `n_shared_cells`
- `pearson`
- `spearman`
- `kendall`
- `mean_delta`
- `mean_abs_delta`
- `median_abs_delta`
- `rmse`
- `max_abs_delta`

Recommended table metadata:

- `table_type = "cell_vector_compare_summary"`
- `entity_kind = "signal_pair"`

### 2. `comparison`

Kind:

- `obs_table`

This should be one-row-per-cell and include:

- `cell_id`
- `a`
- `b`
- `a_cmp`
- `b_cmp`
- `delta`
- optionally `abs_delta`

Meaning:

- `a` and `b` are original values on shared cells
- `a_cmp` and `b_cmp` are the values actually compared
  - identical to `a`/`b` in raw space
  - ranks in rank space
- `delta = a_cmp - b_cmp`

Recommended table metadata:

- `table_type = "cell_vector_compare"`
- `entity_kind = "cell"`

## Why `obs_table` Is The Right Output

This is primarily a comparison/reporting kernel, not a new long-lived numeric
family primitive.

Using `obs_table` for both outputs keeps the result:

- easy to inspect
- easy to plot
- easy to join to metadata
- easy to feed into downstream report workflows

This is also the intended v1 boundary:

- do not emit a dedicated residual `cell_vector`
- do not emit a new comparison-family primitive
- keep the first implementation table-first

If repeated downstream use later shows that one derived quantity such as
`delta` or `abs_delta` needs to become a first-class signal, that can come
later as a separate extraction or conversion step.

## V1 Downstream Position

The first version should assume that `cell_vector_compare` is mainly used for:

- method-agreement checks
- module/module comparison
- pseudotime/module comparison
- report and plot generation

So the comparison result should be treated first as:

- an analytical table output

not as:

- a new reusable signal primitive by default

That keeps the op small and avoids overcommitting to downstream semantics
before we know what users actually chain from it.

## What This Op Is Not

It is not:

- a trajectory fit op
- a smoothing op
- a branch membership op
- a many-to-many feature correlation engine

Those remain separate surfaces.

This op should stay focused on:

- two aligned cell-level signals
- one comparison space
- simple reusable concordance outputs

## Relationship To Existing Ops

This op should complement, not replace:

- `feature_trend_spearman`
  - one coordinate vs many features
- `trajectory_vector_smooth`
  - one signal summarized along one trajectory
- `trajectory_branch_compare`
  - explicit branch contrasts
- `cell_vector_assoc`
  - continuous-vs-group association

The simplest distinction is:

- existing ops mostly ask “how does one signal behave relative to another
  structure?”
- `cell_vector_compare` asks “how similar are these two cell-level signals?”

## Concrete Interface Sketch

Suggested `op_catalog`-style shape:

- `op_name = "cell_vector_compare"`
- `requires = list(a = "cell_vector", b = "cell_vector")`
- `produces = list(summary = "obs_table", comparison = "obs_table")`
- `promotable = c("summary", "comparison")`

Suggested params:

- `compare_space`
  - `choice`
  - default `rank`
  - choices `c("raw", "rank")`
- `ties_method`
  - `choice`
  - default `average`
  - choices as supported by base `rank()`

## Immediate High-Value Use Cases

1. Compare Slingshot pseudotime vs Monocle3 pseudotime on intersecting cells.
2. Compare Palantir pseudotime vs Monocle3 pseudotime on intersecting cells.
3. Compare module score A vs module score B in rank space.
4. Compare a module score against pseudotime.

That is enough to justify the op without overextending it.

## Working Principle

- keep the op small
- keep it generic over cell-level signals
- make rank-space comparison first-class
- avoid baking trajectory-specific assumptions into the core contract
