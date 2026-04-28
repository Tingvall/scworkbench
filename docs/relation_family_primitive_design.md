# `relation_family` Primitive (Design Note)

Status: design direction agreed; engine scaffold implemented (initial constructor/helpers), storage/promotion semantics pending

Purpose: capture sparse long-form relations as a reusable primitive shape.

This is motivated by trajectory and branch membership use cases (for example monocle3), but is intentionally broader than any one method.

## Why We Need It

Some outputs are not well represented by a single scalar per cell.

Examples:
- Branched trajectory membership (a cell can belong to multiple branches with weights)
- Fate probabilities
- Soft clustering / fuzzy memberships
- Topic/program loadings
- Cell-to-state affinity scores

Current primitives are close, but not ideal:
- `cell_vector`: only one value per cell
- `cell_vector_family`: supports multiple keyed values, but does not make weighted membership semantics first-class
- `obs_table`: can store anything, but loses strong engine semantics

## Core Idea

Treat this as a sparse long-form family primitive with one row per `(cell_id, key)` relation.

Conceptually, this is a bipartite edge-table-like relation:
- left nodes: cells
- right nodes: keys (branches, states, topics, etc.)
- optional edge/row attributes: `weight`, `value`, `distance`, ...

This also makes it a useful stepping stone toward future graph/edge primitives.

## Proposed Primitive Shape

Candidate name: `relation_family`

Proposed required fields:
- `kind = "relation_family"`
- `cell_id` (character, length N)
- `key` (character, length N)

Proposed optional fields (same length N when present):
- `weight` (numeric; optional because not all relations are weighted)
- `value` (numeric; e.g. lineage-specific pseudotime)
- `distance` (numeric; e.g. distance to branch/state)
- `rank` (integer/numeric)
- `meta` (list/scalar metadata at primitive level, not row level)

Validation expectations (v1):
- equal-length vectors across row fields
- non-empty `cell_id`, `key`
- finite numeric values for optional numeric columns when present (unless explicitly allowing `NA`)
- duplicate `(cell_id, key)` pairs either forbidden or reduced deterministically

## Semantics

Primitive shape is generic.
Meaning comes from:
- producing op contract
- birth certificate / provenance (`run$params`, inputs, source_op)

Examples:
- trajectory branch membership: `weight = branch probability` (or derived path-membership score)
- topic model: `weight = loading`
- soft clustering: `weight = membership strength`
- cell-gene relation: `value = score`, no `weight` needed

This follows the project principle:
- primitives stay primitive; civilization lives in birth certificates.

## Monocle3 Motivation (Immediate)

Monocle3 may produce branched structures where cells can be:
- on a shared trunk
- near branch points
- ambiguously assigned across branches

A strict single pseudotime vector (`cell_vector`) is often insufficient.

`relation_family` could represent:
- per-cell branch weights
- optional branch-specific pseudotime (`value`)

This would let us preserve ambiguity instead of forcing hard assignment.

## Relationship to Existing Primitives

Possible coexistence pattern:
- `cell_vector_family`: lineage-specific pseudotime values (simple workflows)
- `relation_family`: branch memberships / affinities / generalized pair relations
- both may be emitted by the same op if useful

This avoids breaking existing clients while enabling richer downstream analysis.

## Wrangling / Client Implications

Likely future helpers:
- `wb_family_keys()` support for `relation_family`
- table wrangler to normalized view (`cell_id`, `key`, `weight`, ...)
- top-keys / per-cell summary wranglers
- plotting contracts for:
  - stacked memberships
  - branch confidence
  - ambiguity heatmaps

Clients should not infer semantics from the primitive alone; use source op + provenance.

## Promotion / Storage (Future)

Likely storage shape mirrors primitive shape:
- artifact table with long rows (`artifact_id`, `cell_id`, `key`, `weight`, optional columns)

Birth certificate should carry:
- source op
- weighting semantics
- normalization rules (for example whether weights sum to 1 per cell)
- branch/key generation policy

## Future Direction: Toward Graph-Shaped Primitives

`relation_family` is effectively a constrained long-form relation / edge-table-like primitive.

This can serve as a bridge toward more general graph modeling later:
- edge-table primitives
- typed node/edge families
- adjacency-derived sparse representations

We should not jump to a full graph primitive until multiple concrete use cases require it.

Current recommendation:
- implement `relation_family` first for monocle3 branch membership and related outputs
- generalize only after repeated reuse patterns emerge

## Open Questions (For Future Work)

- Should we eventually support neutral column names (`a`, `b`) alongside `cell_id`, `key`, or keep this cell-key framing?
- Should `weight` be constrained in some method-specific contracts, while remaining optional in the primitive?
- Should per-cell normalization (`sum(weight)=1`) be enforced, optional, or provenance-declared?
- Should `value` be part of v1, or separate `cell_vector_family` output only?
- How should duplicate `(cell_id,key)` rows be handled?
- Do we want a shared `*_family` helper API for weighted and unweighted families?

## Working Principle

- Separation of compute and display.
- Primitives stay primitive; civilization lives in birth certificates.
