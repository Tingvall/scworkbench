# Trajectory Handoff: 2026-04-16

This note is a working handoff for the current continuation of the trajectory-analysis thread on the `signal` bundle. It is not collaborator-facing documentation. It records what was tried after the earlier handoff, what failed, what now works, and which reports should be treated as current for the reversed T-lineage part-1 analysis.

## Context

Work continued in `reports/track3_signal_full_20260402_103300` on the same winner-based trajectory universes:

- `set:trajectory_bcell`
- `set:trajectory_tcell`

The main completed additions in this session were:

1. a combined B-method comparison report across Slingshot, Palantir, and Monocle3
2. a full rebuild of T part-1 across Slingshot, Palantir, and Monocle3
3. a reversal of the T part-1 direction from `STHSC -> DN3`
4. reversed T dynamics reports for the selected Slingshot, Palantir, and Monocle trajectories
5. a combined T-method comparison report

## Current high-level status

### B lineage

B is in a good state and should be treated as stable enough for ongoing interpretation.

Current collaborator-facing comparison report:

- `reports/track3_signal_full_20260402_103300/b_method_comparison/track3_b_method_comparison_report.html`

This compares:

- Slingshot lineage `L1`
- Palantir route `branch:TACTCAAAGTCATTAG-1`
- Monocle3 UMAP branch `root:Y_77::lineage:Y_112`

The B thread also led to one interpretation note worth retaining:

- `Mo_Ly6Cpos` behaves like an attractor basin in the current manifold
- likely because the upstream `HSC` / progenitor side is comparatively diffuse in the embedding while `Mo_Ly6Cpos` is more geometrically distinct
- global manifold methods are therefore more easily pulled into that basin

This interpretation is geometric, not proof of the biological ground truth, but it matches the behavior seen across Monocle3 and Palantir.

### T lineage part 1

The important outcome is that the original direction (`DN3 -> STHSC`) was not the useful one on this manifold. The reversed direction (`STHSC -> DN3`) is the version that now gives a coherent cross-method story.

So for T part 1, the current working interpretation should be:

- start/root on the `STHSC` side
- move toward `DN3` and early committed T structure

## T part-1 attempts and what happened

### First rebuild on the original direction

We first rebuilt T part 1 on the same `set:trajectory_tcell` universe and same retained winner structure, but still rooted from `DN3`.

Directories:

- `reports/track3_signal_full_20260402_103300/t_slingshot_redo`
- `reports/track3_signal_full_20260402_103300/t_monocle3`
- `reports/track3_signal_full_20260402_103300/t_palantir`

Key result:

- Slingshot was acceptable
- Palantir was only usable as a single-route view
- Monocle3 was poor

Important Monocle failure mode:

- the branch curves looked like tiny terminal fragments only
- inspection showed this was not a plotting bug
- the saved `curve_df` really had only `26` total curve points across two short local branches
- Monocle had not learned a usable long `DN3 -> STHSC` backbone in that configuration

Conclusion:

- the original direction was not a good working setup for this T manifold

### Reversed-direction rebuild

We then reran the same `trajectory_tcell` manifold the other way around:

- `STHSC` as root/start
- `DN3` as distal target

This changed the picture substantially and is now the working T setup.

## T part-1 reversed overview reports

### Reverse Slingshot

Directory:

- `reports/track3_signal_full_20260402_103300/t_slingshot_rev`

Main report:

- `track3_t_slingshot_report.html`

Setup:

- cell set: `set:trajectory_tcell`
- start cluster: `STHSC`
- fit space: `lsi`
- plot space: `umap.atac`

Run summary:

- `fit_cells_n = 9468`
- lineages:
  - `L1 = 7931`
  - `L2 = 7115`
  - `L3 = 6443`
  - `L4 = 4907`

Selected lineage for downstream use:

- `L1`

### Reverse Palantir

Directory:

- `reports/track3_signal_full_20260402_103300/t_palantir_rev`

Main report:

- `track3_t_palantir_report.html`

Setup:

- cell set: `set:trajectory_tcell`
- fit space: `lsi`
- plot space: `umap.atac`
- root winner: `STHSC`
- terminal winner: `DN3`

Representative cells actually used:

- root: `ACTTAGTCACCTGGTG-1`
- terminal: `TGAACAGAGTTGCCTC-10`

Important note:

- this produces only one explicit Palantir branch
- so it is still useful for route/pseudotime geometry and dynamics
- but branch probability is trivial in this setup

Selected route for downstream use:

- `branch:TGAACAGAGTTGCCTC-10`

### Reverse Monocle3

There are two relevant Monocle reversed runs.

#### First reversed Monocle run

Directory:

- `reports/track3_signal_full_20260402_103300/t_monocle3_rev`

Main report:

- `track3_t_monocle3_report.html`

This run was better than the original direction, but still too narrow and unstable:

- only `2` branches
- the branch geometry was still not convincing enough to trust as the final Monocle view

#### Final reversed Monocle run: no downsampling + explicit root

Directory:

- `reports/track3_signal_full_20260402_103300/t_monocle3_rev_nodownsample`

Main report:

- `track3_t_monocle3_report.html`

This is the Monocle run that should now be treated as current.

Setup:

- cell set: `set:trajectory_tcell`
- fit space: `umap.atac`
- plot space: `umap.atac`
- no stratified downsampling
- effective fit cells: `28807`
- explicit root cell: `CTTTCTTGTCGTTATC-1`

Why this mattered:

- the earlier Monocle run produced only tiny local curve fragments
- this rerun produced a real graph with `572` curve points across `15` branches
- all branches now share one root: `Y_163`

Largest branches:

- `root:Y_163::lineage:Y_83 = 9442`
- `root:Y_163::lineage:Y_9 = 9024`
- `root:Y_163::lineage:Y_40 = 8624`
- `root:Y_163::lineage:Y_1 = 7984`

Selected branch for downstream use:

- `root:Y_163::lineage:Y_40`

## T part-1 reversed dynamics reports

These are the current source-of-truth dynamics reports for T part 1.

### Reverse Slingshot dynamics

Directory:

- `reports/track3_signal_full_20260402_103300/t_slingshot_rev_dynamics`

Main report:

- `track3_t_slingshot_rev_dynamics_report.html`

Selected path:

- Slingshot lineage `L1`

Cell count:

- `7931`

Interpretation:

- low pseudotime near `STHSC`
- higher pseudotime moving toward `DN3` / early committed T states

### Reverse Monocle3 dynamics

Directory:

- `reports/track3_signal_full_20260402_103300/t_monocle3_rev_dynamics`

Main report:

- `track3_t_monocle3_rev_dynamics_report.html`

Selected path:

- `root:Y_163::lineage:Y_40`

Cell count:

- `8624`

Interpretation:

- low pseudotime near `STHSC`
- higher pseudotime moving toward `DN3` / early committed T states

### Reverse Palantir dynamics

Directory:

- `reports/track3_signal_full_20260402_103300/t_palantir_rev_dynamics`

Main report:

- `track3_t_palantir_rev_dynamics_report.html`

Selected path:

- `branch:TGAACAGAGTTGCCTC-10`

Cell count:

- `9468`

Interpretation:

- Palantir pseudotime rooted at `STHSC`
- larger values move toward the `DN3` terminal direction

## Combined T comparison report

Current collaborator-facing combined report:

- `reports/track3_signal_full_20260402_103300/t_method_comparison/track3_t_method_comparison_report.html`

This compares:

- Slingshot lineage `L1`
- Palantir reverse route `branch:TGAACAGAGTTGCCTC-10`
- Monocle3 reverse branch `root:Y_163::lineage:Y_40`

Important overlap summary:

- Slingshot vs Palantir Jaccard: `0.838`
- Slingshot vs Monocle Jaccard: `0.288`
- Palantir vs Monocle Jaccard: `0.273`

Interpretation:

- Slingshot and Palantir are close in membership
- Monocle is narrower and more selective

Important Monocle branch breakdown:

Of the selected Monocle branch `Y_40`:

- `43%` are also in Slingshot `L1`
- `45%` are also in the Palantir reverse route
- `55%` are in neither of those two selected paths

That Monocle-only fraction is not random. It is mostly:

- `STHSC` (`1953` cells; `22.6%` of the full Monocle branch)
- `FrA` (`1366`; `15.8%`)
- `CLP` (`998`; `11.6%`)

So Monocle `Y_40` is not mainly adding irrelevant cells. It is holding onto a broader upstream/progenitor segment relative to the chosen Slingshot and Palantir paths.

## Code added in this session

### B comparison

- `scripts/track3_b_method_comparison_run.R`
- `scripts/track3_b_method_comparison_report.Rmd`

### T overview wrappers

- `scripts/track3_t_slingshot_run.R`
- `scripts/track3_t_monocle3_run.R`
- `scripts/track3_t_palantir_run.R`

### T reversed dynamics

- `scripts/track3_t_slingshot_rev_dynamics_run.R`
- `scripts/track3_t_slingshot_rev_dynamics_report.Rmd`
- `scripts/track3_t_monocle3_rev_dynamics_run.R`
- `scripts/track3_t_monocle3_rev_dynamics_worker.R`
- `scripts/track3_t_monocle3_rev_dynamics_report.Rmd`
- `scripts/track3_t_palantir_rev_dynamics_run.R`
- `scripts/track3_t_palantir_rev_dynamics_worker.R`
- `scripts/track3_t_palantir_rev_dynamics_report.Rmd`

### T comparison

- `scripts/track3_t_method_comparison_run.R`
- `scripts/track3_t_method_comparison_report.Rmd`

## Practical next steps

If continuing from here, the most likely useful next moves are:

1. tighten collaborator-facing prose in the T comparison report the same way the B comparison was refined
2. decide whether the T thread also needs an explicit narrative paragraph about manifold geometry / attractor basins analogous to the B `Mo_Ly6Cpos` note
3. decide whether to keep Monocle `Y_40` as the official third T path, or to test one or two nearby Monocle branches now that the no-downsampling rerun is available
4. if needed, build a joint B+T project-level summary note that links the B and T comparison reports together

## Bottom line

The original T part-1 direction (`DN3 -> STHSC`) should not be treated as the working result.

The current working T part-1 interpretation is:

- root on the `STHSC` side
- move toward `DN3`
- use:
  - Slingshot `L1`
  - Palantir `branch:TGAACAGAGTTGCCTC-10`
  - Monocle3 `root:Y_163::lineage:Y_40`

Those are now the trajectories that should be used for any follow-up T comparison or discussion.
