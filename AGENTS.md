# scworkbench Agent Brief

Read this first at session start.

## Project Identity

`scworkbench` is the analysis engine.
Clients (Shiny, scripts, notebooks, AI agents) are thin interfaces.

Do not treat Shiny behavior as engine truth. Engine contracts are canonical.

## Core Architecture

1. Bundle
- Portable analysis unit (SQLite metadata + payload files + reports/models/artifacts).
- Source of truth for data, sets, artifacts, and provenance.

2. Data Layer
- Storage can be fragmented for scale/ingest.
- Callers must see one logical matrix/space view.

3. Getter Boundary
- Getters are the only layer that touches physical storage details.
- Ops/wranglers/clients should consume getter contracts, not SQL/storage internals.
- Pack runners use core-issued typed readers and writers, not unrestricted
  getters over a bundle handle. Start pack work at the installed SDK guide.

4. Selectors
- Query language over getter universe (set/meta/expr/vector/space rules).
- Supports compositional logic and recipe/provenance persistence.

5. Primitives
- Internal currency: `matrix`, `space`, `space_2d`, `cell_vector`, `cell_vector_family`,
  `relation_family`, `feature_table`, `obs_table`, `model_ref`,
  `path_2d_family`, `space_path_family`.
- Ops consume/produce primitives. Wranglers map primitives to display contracts.

6. Provenance + Promotion
- Users/agents can tinker in-session and selectively promote outputs.
- DAG + run provenance is required for replayable, auditable analysis.

## Guardrails

- Preserve thin-client principle: clients orchestrate and render; engine computes.
- Avoid duplicate pathways for the same capability (one way to add ops/wranglers).
- Prefer symbolic references (`set:<name>`, refs) over huge literal payloads.
- Do not break existing primitive contracts when adding new ops.

## Immediate Orientation Commands

```r
wb_list_ops()
wb_op_interface("metadata_cell_vector", bundle = b)
wb_matrices(b)
wb_spaces(b)
wb_cell_sets(b)
wb_art_list(b)
wb_session_dag(s, bundle = b, include_artifacts = TRUE, include_active = TRUE)
```

## Where To Read Next

- `inst/onboarding/SYSTEM_OVERVIEW.md`
- `inst/sdk/operation-packs/GUIDE.md` for new operation packs
- `inst/onboarding/SHARED_FOUNDATION.md`
- `inst/onboarding/AGENT_ENGINEER_GUIDE.md`
- `inst/onboarding/AGENT_BIOLOGIST_GUIDE.md`
- `inst/onboarding/PLAYBOOK.md`
- `inst/onboarding/RECIPES.md`
- `docs/getting_started.md`
- `docs/tabular_primitives.md`

## Post-Migration Rules

- Core has five operations; the explicitly activated seven-pack profile has 62.
- New scientific methods normally belong in packs, not the core catalog.
- Declare primitive IO, use authenticated callbacks, compute, emit primitives.
- Check backend support and per-grant schedules; schema parity is not execution parity.
- No direct SQL, receipt hashing, durable path access, or operation-name core exceptions.
- Method tests live in packs; generic authority tests remain core-owned.
- Use focused checks for small corrections and complete gates for frozen integration.
