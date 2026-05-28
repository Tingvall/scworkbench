# Agent Onboarding: scworkbench

This document is for fast, correct orientation of a new coding/analysis agent.

## 1. Mental Model

- Engine-first system.
- Thin clients are replaceable.
- Internal consistency is the product advantage.

Practical rule: if a behavior differs between client and engine, engine contracts win.

## 2. Layered Architecture

### Bundle
- Unit of transport + persistence.
- Contains tables for cells/features/matrices/spaces/sets/artifacts/runs/provenance.

### Data Layer
- May use fragmented payload representation.
- Must expose unified logical access through getters.

### Getters
- Only getters interact with storage details.
- Getters define stable contracts for all downstream compute.

### Selectors
- Build reusable subset logic over cells/features.
- Intended for reproducible intent (recipes), not only transient filtering.

### Primitives
- Typed IO across engine layers.
- Prevents client-specific object leakage into compute layer.

### Ops
- Contracted compute functions that consume/emit primitives.
- Discoverable via `wb_list_ops()` and `wb_op_interface()`.

### Wranglers
- Convert primitives to display-ready datasets/contracts (plots/tables/reports).
- Should be pure-ish mapping layer, not hidden compute core.

## 3. Why This Matters

This structure enables:
- multi-client portability,
- agent-operable workflows,
- selective promotion,
- auditability and replay.

## 4. Session Start Checklist

1. Open bundle, inspect matrices/spaces/cell sets.
2. Discover op contracts before running compute.
3. Run through session API, not ad-hoc internals.
4. Promote only intentional outputs.
5. Emit run context + DAG + replay script for major analyses.

## 5. Common Failure Modes

- Client resolves sets itself instead of engine semantics.
- New op returns shape that violates primitive contract.
- Feature/cell IDs passed as huge literals instead of symbolic references.
- Report claims not tied to run/artifact IDs.

## 6. Canonical References

- Op contracts: `wb_op_interface()`
- Primitive loading: `wb_art_load()`, `wb_resolve_primitive()`
- DAG: `wb_session_dag()`
- Provenance script emission: `wb_prov_emit_r_script()`
