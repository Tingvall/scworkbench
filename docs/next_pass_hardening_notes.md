# Next Pass: Hardening / Bugfixing (Before New Features)

Status: agreed priority for the next session.

Goal:
- Focus on reliability, ergonomics, and performance hardening before adding new features.

## Scope (Next Session)

1. Scene performance hardening
- Investigate slow Scene tab open/render path.
- Prioritize base render bottlenecks over trajectory overlay (trajectory curves are now compact by default in `slingshot_project`).
- Candidate fixes:
  - cache 2D coordinates by `space_id`
  - cache overlay set memberships
  - reduce unnecessary reactive redraws
  - optional rasterization / performance mode for large point clouds

2. Plots tab robustness (stale state / transition bugs)
- Continue eliminating stale `plot_type` / stale axis selection edge cases.
- Continue removing warning/error loops (especially around `violin`, `cell_vector_family`, plot-type switches).
- Verify both static and interactive (`plotly`) paths.

3. Trajectory UX stabilization (Scene)
- Validate pseudotime/curves lineage selector flow across:
  - fresh slingshot runs
  - promoted artifacts
  - missing/stale trajectory refs
- Keep thin-client behavior: use bench helpers (`wb_family_keys`, `wb_trajectory_keys`) rather than client-side lineage parsing.

4. Identity card polish (after lineage and plotting are stable)
- Clarify slingshot split in UI:
  - `slingshot_fit` artifact = pseudotime/model (not curves)
  - `slingshot_project` artifact = display curves
- Add more upstream lineage highlights where useful.

5. Regression-test every bug fixed
- Add a focused test whenever a reproducible bug is patched.
- Protect human/agent ergonomics as a first-class quality bar.

## Recent Relevant Changes (Context for Resume)

- `slingshot_fit` / `slingshot_project` split is in place and tested.
- `model_ref` promotion/load supports slingshot models.
- `slingshot_project` now emits compact `path_2d_family` by default (`approx_points = 200`).
- `wb_geom_trajectory_2d()` now accepts direct `path_2d_family` primitives (ergonomics fix).
- Engine provenance hardening is in place:
  - birth certificates
  - identity cards
  - lineage status on promoted artifacts
  - minimal artifact replay script emission
- Scene trajectory selector UI exists, but needs more hardening/perf work.
- Plots tab has multiple hardening patches, but still needs bug-hunting on edge transitions.

## Explicit Non-Goal (Next Session)

- Do not add major new features first.
- Hardening/bugfixing comes before feature expansion (scvi-tools, GRN, more adapters, etc.).

