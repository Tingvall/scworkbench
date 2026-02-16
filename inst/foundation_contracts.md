# scworkbench Foundation Contracts

This document defines the current contract for the foundation layers:

1. Data layer (SQLite + BPCells bundle)
2. Getter layer (`wb_*` read APIs)
3. Selector layer (`wb_sel_*`)

## Scope

These contracts are intended to be stable for all clients:

- notebooks
- Shiny apps
- AI agents

Ops/wranglers may evolve more quickly, but should build on these guarantees.

## Data Layer Contracts

### Canonical Cell Order

- Canonical order is defined by `cells` table row order (`rowid`).
- `wb_cells(bundle, cell_set = "all")` is the canonical order source.

### Required Tables

At minimum, bundles should provide:

- `cells`
- `datasets`
- `features`
- `matrices`

Additional tables are optional based on capabilities (spaces, artifacts, etc.).

### Matrix Alignment

- Matrix columns are expected to align with canonical cell order.
- Getter functions that read matrix slices/vectors must preserve requested cell order.

## Getter Layer Contracts

### Deterministic Ordering

- `wb_cells()` returns ordered `cell_id` vectors.
- `wb_meta(bundle, cells=...)` aligns rows to requested `cells` order.
- `wb_space(bundle, cells=...)` aligns outputs to requested `cells` order.

### Coverage Helpers

- `wb_cells_with_space()` returns cells with available coordinates for a space.
- `wb_cells_with_matrix()` returns available cells for a matrix.
- `wb_cell_coverage()` reports requested/effective coverage for input requirements.
- Effective-cell resolution (`.wb_effective_cells`) treats `inputs$cell_ids` as explicit
  requested universe override and then applies required-input intersections.
- Ops should rely on session-level effective-cell resolution instead of ad-hoc filtering.

### Type/Shape Guarantees

- Getter return classes and key columns are stable and documented in roxygen.
- Errors are raised for unknown IDs or invalid argument shapes.

## Selector Layer Contracts

### Input Model

Selectors accept:

- a bundle (`scworkbench_bundle`) as pipeline root
- selector output vectors with attached bundle metadata

### Output Model

Every selector returns:

- character vector of `cell_id`
- canonical bundle ordering
- attached bundle (`attr(x, "wb_bundle")`)
- attached recipe (`attr(x, "wb_recipe")`)

### Algebra Semantics

- `wb_sel_and`: intersection
- `wb_sel_or`: union
- `wb_sel_not`: universe minus input

All outputs are canonical-order deterministic.

## Reference Model Contracts

The engine supports a single canonical reference model across runtimes:

- `wb_ref_run(run_id, output_name)` for ephemeral session outputs
- `wb_ref_artifact(artifact_id, output_name)` for persisted outputs
- `wb_resolve_primitive()` as canonical resolver for primitive/spec/artifact/session refs
- `wb_vector_ref_to_spec()` and `wb_list_vector_sources()` for stable vector references

This reference model is intended to be shared by all clients (Shiny, Python, Node, agents).

## Validation Strategy

Foundation behavior is verified by:

- `tests/test_foundation_data_getters_selectors.R`
- `tests/test_all.R` integration execution

When contracts change, update:

1. this document
2. roxygen docs for affected functions
3. foundation tests
