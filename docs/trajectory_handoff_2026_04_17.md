# Trajectory Analysis Status: 2026-04-17

This note is the current working handoff for the trajectory-analysis thread on the `signal` bundle. It supersedes the narrower session handoff from 2026-04-16 and records the present state of the completed B, T, and innate trajectory work across Slingshot, Palantir, and Monocle3.

It is not collaborator-facing prose. It is meant to let the next session resume without reconstructing the logic from the reports.

## Scope

All work below lives under:

- `reports/track3_signal_full_20260402_103300`

Main trajectory sets used:

- `set:trajectory_bcell`
- `set:trajectory_tcell`
- `set:trajectory_innate`

Main methods compared:

- Slingshot
- Palantir
- Monocle3

## High-level readout

### Overall conclusion

The multi-method trajectory analysis is now broad enough to treat as a completed first major analysis pass.

Main takeaways:

- B is the strongest and most stable lineage.
- T part 1 is good, but only in the reversed `STHSC -> DN3` framing.
- innate is the softest lineage and remains the most geometry-sensitive.
- Slingshot is the most robust general backbone finder in this dataset.
- Palantir is useful once roots/endpoints are biologically right, but is sensitive to global manifold basins.
- Monocle3 is the most sensitive to setup; when rooted and fit correctly it becomes informative, but it is more selective and less stable than Slingshot.

### Current priority level by lineage

- B: high confidence
- T part 1: medium-high confidence
- innate: medium confidence

## B lineage

### Primary forward B interpretation

The original B analysis remains a strong primary result.

Current forward comparison report:

- `reports/track3_signal_full_20260402_103300/b_method_comparison/track3_b_method_comparison_report.html`

Selected forward B paths:

- Slingshot: `L1`
- Palantir: `branch:TACTCAAAGTCATTAG-1`
- Monocle3: `root:Y_77::lineage:Y_112`

Interpretation:

- start on the B side, near `FrE`
- move toward the earlier `STHSC` / progenitor side

Important forward B note:

- `Mo_Ly6Cpos` behaves like an attractor basin in the current manifold
- likely because the upstream `HSC` / progenitor side is comparatively diffuse while `Mo_Ly6Cpos` is more geometrically distinct
- global manifold methods are therefore more easily pulled into that basin

This is a geometric interpretation, not proof of biological truth, but it matches the Monocle3 and Palantir behavior seen during development.

### Reversed B interpretation

We also completed the reverse B thread so the B analysis now exists in both directions.

Current reversed comparison report:

- `reports/track3_signal_full_20260402_103300/b_rev_method_comparison/track3_b_rev_method_comparison_report.html`

Selected reversed B paths:

- Slingshot: `L1`
- Palantir: `branch:GTAAGCTTCATAAGCC-4`
- Monocle3: `root:Y_314::lineage:Y_155`

Interpretation:

- start on the `STHSC` / upstream side
- move toward the mature B-cell side near `FrE`

Reverse B overlap summary:

- Slingshot vs Palantir Jaccard: `0.883`
- Slingshot vs Monocle Jaccard: `0.205`
- Palantir vs Monocle Jaccard: `0.190`

This means:

- Slingshot and Palantir still agree strongly
- Monocle remains substantially narrower / more selective

### B reports to treat as current

Forward B:

- overviews:
  - `b_slingshot/track3_b_slingshot_report.html`
  - `b_monocle3_umap/track3_b_monocle3_report.html`
  - `b_palantir/track3_b_palantir_report.html`
- dynamics:
  - `b_lineage1_dynamics/track3_b_lineage1_dynamics_report.html`
  - `b_monocle3_umap_dynamics/track3_b_monocle3_dynamics_report.html`
  - `b_palantir_sthsc_dynamics/track3_b_palantir_dynamics_report.html`
- comparison:
  - `b_method_comparison/track3_b_method_comparison_report.html`

Reverse B:

- overviews:
  - `b_slingshot_rev/track3_b_rev_slingshot_report.html`
  - `b_monocle3_rev/track3_b_rev_monocle3_report.html`
  - `b_palantir_rev/track3_b_rev_palantir_report.html`
- dynamics:
  - `b_slingshot_rev_dynamics/track3_b_rev_slingshot_dynamics_report.html`
  - `b_monocle3_rev_dynamics/track3_b_rev_monocle3_dynamics_report.html`
  - `b_palantir_rev_dynamics/track3_b_rev_palantir_dynamics_report.html`
- comparison:
  - `b_rev_method_comparison/track3_b_rev_method_comparison_report.html`

## T lineage part 1

### Main result

The original `DN3 -> STHSC` framing should not be treated as the working result.

The useful T part-1 analysis is the reversed direction:

- root/start on the `STHSC` side
- move toward `DN3`

Current T comparison report:

- `reports/track3_signal_full_20260402_103300/t_method_comparison/track3_t_method_comparison_report.html`

Selected reversed T paths:

- Slingshot: `L1`
- Palantir: `branch:TGAACAGAGTTGCCTC-10`
- Monocle3: `root:Y_163::lineage:Y_40`

Reverse T overlap summary:

- Slingshot vs Palantir Jaccard: `0.838`
- Slingshot vs Monocle Jaccard: `0.288`
- Palantir vs Monocle Jaccard: `0.273`

### Important Monocle note

Monocle3 only became usable for T after:

- reversing the direction
- fitting on `umap.atac`
- turning off downsampling
- using an explicit `STHSC` root cell

Current Monocle run to treat as source of truth:

- `t_monocle3_rev_nodownsample/track3_t_monocle3_report.html`

Selected branch:

- `root:Y_163::lineage:Y_40`

Important Monocle branch composition note:

For selected T Monocle branch `Y_40`:

- `43%` of cells are also in Slingshot `L1`
- `45%` are also in the Palantir route
- `55%` are in neither selected Slingshot nor selected Palantir

That Monocle-only fraction is not random. It is mostly:

- `STHSC`
- `FrA`
- `CLP`

So Monocle `Y_40` is narrower and more upstream-heavy, not simply wrong or noisy.

### T reports to treat as current

- overviews:
  - `t_slingshot_rev/track3_t_slingshot_report.html`
  - `t_monocle3_rev_nodownsample/track3_t_monocle3_report.html`
  - `t_palantir_rev/track3_t_palantir_report.html`
- dynamics:
  - `t_slingshot_rev_dynamics/track3_t_slingshot_rev_dynamics_report.html`
  - `t_monocle3_rev_dynamics/track3_t_monocle3_rev_dynamics_report.html`
  - `t_palantir_rev_dynamics/track3_t_palantir_rev_dynamics_report.html`
- comparison:
  - `t_method_comparison/track3_t_method_comparison_report.html`

## Innate lineage

### Main result

Innate was analyzed in both directions, but this thread remains the least settled biologically.

The manifold clearly contains shared structure, but method agreement is weaker than for B and T, especially for Monocle3.

### Forward innate

Current forward comparison report:

- `reports/track3_signal_full_20260402_103300/innate_method_comparison/track3_innate_method_comparison_report.html`

Selected forward innate paths:

- Slingshot: `L1`
- Palantir: `branch:ACTTAGTCACCTGGTG-1`
- Monocle3: `root:Y_58::lineage:Y_171`

Interpretation:

- start on the `ILC2` side
- move toward `STHSC` / upstream progenitor territory

Forward innate overlap summary:

- Slingshot vs Palantir Jaccard: `0.927`
- Slingshot vs Monocle Jaccard: `0.192`
- Palantir vs Monocle Jaccard: `0.192`

### Reversed innate

Current reversed comparison report:

- `reports/track3_signal_full_20260402_103300/innate_rev_method_comparison/track3_innate_rev_method_comparison_report.html`

Selected reversed innate paths:

- Slingshot: `L1`
- Palantir: `branch:ACAACATGTTTACCGT-14`
- Monocle3: `root:Y_74::lineage:Y_122`

Interpretation:

- start on the `STHSC` side
- move toward `ILC2`

Reversed innate overlap summary:

- Slingshot vs Palantir Jaccard: `0.832`
- Slingshot vs Monocle Jaccard: `0.205`
- Palantir vs Monocle Jaccard: `0.199`

### Innate reports to treat as current

Forward innate:

- overviews:
  - `innate_slingshot/track3_innate_slingshot_report.html`
  - `innate_monocle3/track3_innate_monocle3_report.html`
  - `innate_palantir/track3_innate_palantir_report.html`
- dynamics:
  - `innate_slingshot_dynamics/track3_innate_slingshot_dynamics_report.html`
  - `innate_monocle3_dynamics/track3_innate_monocle3_dynamics_report.html`
  - `innate_palantir_dynamics/track3_innate_palantir_dynamics_report.html`
- comparison:
  - `innate_method_comparison/track3_innate_method_comparison_report.html`

Reverse innate:

- overviews:
  - `innate_slingshot_rev/track3_innate_slingshot_report.html`
  - `innate_monocle3_rev/track3_innate_monocle3_report.html`
  - `innate_palantir_rev/track3_innate_palantir_report.html`
- dynamics:
  - `innate_slingshot_rev_dynamics/track3_innate_rev_slingshot_dynamics_report.html`
  - `innate_monocle3_rev_dynamics/track3_innate_rev_monocle3_dynamics_report.html`
  - `innate_palantir_rev_dynamics/track3_innate_rev_palantir_dynamics_report.html`
- comparison:
  - `innate_rev_method_comparison/track3_innate_rev_method_comparison_report.html`

## Recommended “primary” versus “sensitivity” views

If a cleaner project summary has to be assembled, this is the current recommendation.

### Primary analyses

- B forward comparison
- B reverse comparison
- T reversed comparison

### Sensitivity / supporting analyses

- innate forward comparison
- innate reverse comparison

Reason:

- B is strong in both directions
- T only becomes convincing in the reversed framing
- innate is useful and real, but method divergence is larger and the biological story is less settled

## Method-level interpretation

### Slingshot

- most robust backbone finder in this dataset
- broadest and usually most dependable scaffold
- best default reference method for this project

### Palantir

- most useful when explicit root/terminal semantics are biologically right
- best route-level view
- most exposed to global manifold basin structure

### Monocle3

- most sensitive to setup
- can fail badly if rooted poorly or fit in the wrong regime
- becomes genuinely informative when rooted and fit correctly
- remains narrower / more selective than Slingshot in all major threads

## Analysis completion status

The trajectory-construction phase should be treated as largely complete for this project stage.

What is now finished:

- B forward: overviews, dynamics, comparison
- B reverse: overviews, dynamics, comparison
- T part 1 reversed: overviews, dynamics, comparison
- innate forward: overviews, dynamics, comparison
- innate reverse: overviews, dynamics, comparison

## Recommended next steps

The next useful work is no longer “fit more trajectories.” It is synthesis and interpretation.

Recommended order:

1. make a short project-level summary note across B, T, and innate
2. decide which analyses are figure-grade primary outputs versus sensitivity/supporting views
3. extract a compact list of biological claims that are stable across methods
4. only then do targeted downstream follow-up such as focused DE, pathway summaries, or figure assembly

## Code added after the 2026-04-16 handoff

### Innate overview wrappers

- `scripts/track3_innate_slingshot_run.R`
- `scripts/track3_innate_monocle3_run.R`
- `scripts/track3_innate_palantir_run.R`

### Innate forward dynamics and comparison

- `scripts/track3_innate_slingshot_dynamics_run.R`
- `scripts/track3_innate_slingshot_dynamics_report.Rmd`
- `scripts/track3_innate_monocle3_dynamics_worker.R`
- `scripts/track3_innate_monocle3_dynamics_run.R`
- `scripts/track3_innate_monocle3_dynamics_report.Rmd`
- `scripts/track3_innate_palantir_dynamics_worker.R`
- `scripts/track3_innate_palantir_dynamics_run.R`
- `scripts/track3_innate_palantir_dynamics_report.Rmd`
- `scripts/track3_innate_method_comparison_run.R`
- `scripts/track3_innate_method_comparison_report.Rmd`

### Innate reverse overview, dynamics, and comparison

- `scripts/track3_innate_rev_slingshot_run.R`
- `scripts/track3_innate_rev_monocle3_run.R`
- `scripts/track3_innate_rev_palantir_run.R`
- `scripts/track3_innate_rev_slingshot_dynamics_run.R`
- `scripts/track3_innate_rev_monocle3_dynamics_run.R`
- `scripts/track3_innate_rev_palantir_dynamics_run.R`
- `scripts/track3_innate_rev_slingshot_dynamics_report.Rmd`
- `scripts/track3_innate_rev_monocle3_dynamics_report.Rmd`
- `scripts/track3_innate_rev_palantir_dynamics_report.Rmd`
- `scripts/track3_innate_rev_method_comparison_run.R`
- `scripts/track3_innate_rev_method_comparison_report.Rmd`

### B reverse overview, dynamics, and comparison

- `scripts/track3_b_rev_slingshot_run.R`
- `scripts/track3_b_rev_monocle3_run.R`
- `scripts/track3_b_rev_palantir_run.R`
- `scripts/track3_b_rev_slingshot_dynamics_run.R`
- `scripts/track3_b_rev_monocle3_dynamics_run.R`
- `scripts/track3_b_rev_palantir_dynamics_run.R`
- `scripts/track3_b_rev_method_comparison_run.R`
- `scripts/track3_b_rev_method_comparison_report.Rmd`

### Reusable B dynamics plumbing changes

- `scripts/track3_b_lineage1_dynamics_run.R`
- `scripts/track3_b_palantir_dynamics_run.R`

## Bottom line

The trajectory analysis now supports a coherent project-level interpretation:

- B is the strongest lineage and is stable in both directions.
- T part 1 is convincing only in the reversed `STHSC -> DN3` framing.
- innate contains real shared structure but remains the least settled and most geometry-sensitive thread.

The next work should be synthesis, not more trajectory fitting.
