# Trajectory Handoff: 2026-04-11

This note is a working handoff for the current trajectory-analysis thread on the `signal` bundle. It is not collaborator-facing documentation. It is meant to let the next session pick up quickly without reverse-engineering the recent reports.

## Context

We used the Track 3 winner-labeling outputs in `reports/track3_signal_full_20260402_103300` as the basis for lineage-specific trajectory work.

The winner labels come from the pruned winner analysis on the `signal` bundle. Those winners are not treated as final ontology truth; they are being used operationally to define inclusion and exclusion sets for trajectory inference.

Two important design decisions emerged:

1. B-lineage trajectory should be fit on a dedicated winner-filtered cell set rather than the old exploratory `b_candidates1` set.
2. T-lineage trajectory should be split into two parts:
   - part 1: DN to progenitor-like states
   - part 2: DN to mature T populations

The reason for the T split is that a single Slingshot run might avoid the DN compartment or treat it as a terminal side branch rather than the required bridge.

## Important bundle cell sets

### `set:trajectory_bcell`

Created explicitly from winner exclusions for the B trajectory.

Excluded winner labels:

- `MPP2`
- `Mastcell`
- `B_mem`
- `B_PC`
- `B1b`
- `Basophil`
- `Eosinophil`
- `DN4`
- `DP`
- `ISP`
- `NKT`
- `T_CD4`
- `T_CD8`
- `TCD8_TE`
- `TCD8_mem` interpreted as `TCD8_Tem`
- `T_MAIT`
- `Tgd`
- `Treg`
- `DN2a`
- `DN2b`
- `DN3`
- `ILC2`
- `ILC3`
- `NK`

Count at creation time:

- `44,907` cells

This replaced use of the earlier exploratory set `set:b_candidates1`, which should be considered a review scaffold rather than canonical trajectory input.

### `set:trajectory_tcell`

Created explicitly from winner exclusions for T part 1.

Excluded winner labels:

- `MPP2`
- `Mastcell`
- `B_mem`
- `B_PC`
- `B1b`
- `Basophil`
- `Eosinophil`
- `DN4`
- `DP`
- `ISP`
- `NKT`
- `T_CD4`
- `T_CD8`
- `TCD8_TE`
- `TCD8_mem` interpreted as `TCD8_Tem`
- `T_MAIT`
- `Tgd`
- `Treg`
- `ILC2`
- `ILC3`
- `NK`
- `FrBC`
- `FrD`
- `FrE`

Count at creation time:

- `28,892` cells

This is a first-pass part-1 T trajectory set, not a final T-specific ontology gate.

## B-lineage trajectory outputs

Directory:

- `reports/track3_signal_full_20260402_103300/b_slingshot`

Main report:

- `track3_b_slingshot_report.html`

Important artifacts:

- `b_slingshot_payload.rds`
- `tables/overview_plot_df.csv`
- `tables/plot_df.csv`
- `tables/curve_df.csv`
- `tables/pseudotime_df.csv`
- `tables/pseudotime_summary.csv`

Current B setup:

- cell set: `set:trajectory_bcell`
- start cluster: `FrE`
- lineage label: `B-lineage`

Run summary from the clean rerun:

- `fit_cells_n = 12745`
- lineages:
  - `L1 = 12114`
  - `L2 = 10227`
  - `L3 = 8859`

Note:

- The pseudotime counts sum above `fit_cells_n` because cells can lie on multiple Slingshot lineages near shared regions.
- This was previously misread because stale outputs contaminated the directory. The directory was later deleted and rebuilt cleanly.

### B-lineage lineage-1 dynamics

Directory:

- `reports/track3_signal_full_20260402_103300/b_lineage1_dynamics`

Main report:

- `track3_b_lineage1_dynamics_report.html`

Main contents:

- recap of the current `trajectory_bcell` Slingshot geometry
- focus on lineage `L1`
- anchor-gene dynamics
- winner-signature dynamics:
  - `FrE`, `FrD`, `FrBC`, `FrA`, `CLP`
- cycling dynamics:
  - `S_phase`, `G2M_phase`, `cycle_max`
- canonical B-cell program dynamics
- `demo_bcell_panel` trend

Important tables:

- `tables/gene_trends.csv`
- `tables/winner_signature_trends.csv`
- `tables/cycle_trends.csv`
- `tables/canonical_signature_trends.csv`
- `tables/demo_bcell_panel_trend.csv`

Interpretation assumption:

- inverted trajectory
- low pseudotime is near the `FrE / CD19` side
- higher pseudotime moves toward earlier states

Important biology note:

- the most mature B population here is `CD19`, not plasma-cell or memory endpoints

## T-lineage trajectory outputs

### T part 1 Slingshot

Directory:

- `reports/track3_signal_full_20260402_103300/t_slingshot`

Main report:

- `track3_t_slingshot_report.html`

Important artifacts:

- `b_slingshot_payload.rds`
- `tables/overview_plot_df.csv`
- `tables/plot_df.csv`
- `tables/curve_df.csv`
- `tables/pseudotime_df.csv`
- `tables/pseudotime_summary.csv`

Current T part-1 setup:

- cell set: `set:trajectory_tcell`
- start cluster: `DN3`
- lineage label: `T-lineage`

Run summary:

- `fit_cells_n = 9468`
- lineages:
  - `L1 = 8815`
  - `L2 = 6874`
  - `L3 = 5470`

Retained included winner clusters in the current T run:

- `STHSC`
- `CLP`
- `MPP3`
- `FrA`
- `MPP4`
- `DN3`
- `Mo_Ly6Cpos`
- `DN2b`
- `pDC`

Auto-dropped as too small:

- `D_CD8`
- `LTHSC`
- `MF_small`
- `DN1`
- `DN2a`

Important interpretation:

- This is a valid first-pass T part-1 trajectory scaffold, but the retained manifold is still broader than a clean DN-only or T-only manifold.
- It is useful for validation, not yet a final part-1 T gate.

### T part-1 lineage-1 dynamics

Directory:

- `reports/track3_signal_full_20260402_103300/t_lineage1_dynamics`

Main report:

- `track3_t_lineage1_dynamics_report.html`

Main contents:

- recap of the current `trajectory_tcell` Slingshot geometry
- focus on lineage `L1`
- anchor-gene dynamics for early T biology
- winner-signature dynamics:
  - `DN3`, `DN2b`, `DN2a`, `DN1`, `CLP`
- cycling dynamics:
  - `S_phase`, `G2M_phase`, `cycle_max`
- canonical T-cell program dynamics

Anchor-gene panel currently used:

- `Flt3`
- `Il7r`
- `Cd34`
- `Ly6d`
- `Lef1`
- `Rag1`
- `Rag2`
- `Dntt`
- `Ptcra`
- `Notch1`
- `Bcl11b`
- `Tcf7`
- `Cd3d`
- `Cd3e`
- `Trac`
- `Mki67`
- `Top2a`
- `Pcna`

Canonical T program sets currently defined in script:

- `Early_lymphoid`
- `T_commitment`
- `Recombination`
- `TCR_complex`

Interpretation assumption:

- inverted trajectory
- low pseudotime near the `DN3` side
- higher pseudotime moves toward progenitor-like states

Important tables:

- `tables/gene_trends.csv`
- `tables/winner_signature_trends.csv`
- `tables/cycle_trends.csv`
- `tables/canonical_signature_trends.csv`

## Scripts added or updated in this thread

### Generic / reusable trajectory reporting

- `scripts/track3_b_slingshot_run.R`
- `scripts/track3_b_slingshot_report.Rmd`

Although named `b_*`, these were generalized to accept:

- `--cell_set`
- `--start_cluster`
- `--lineage_label`
- `--exclude_clusters`

They now support both B and T lineage runs.

### B lineage

- `scripts/track3_b_lineage1_dynamics_run.R`
- `scripts/track3_b_lineage1_dynamics_report.Rmd`

### T lineage

- `scripts/track3_t_lineage1_dynamics_run.R`
- `scripts/track3_t_lineage1_dynamics_report.Rmd`

## Known issues / caveats

1. Getter warning still appears on selected-gene expression slices:

- `Warning: Converting to a dense matrix may use excessive memory`

This has been acceptable for the current selected-gene dynamics reports, but the backend sparse path is still not fully hardened.

2. The T part-1 set is still semantically broad.

The current `trajectory_tcell` exclusion-only rule leaves several progenitor and non-ideal winners in the retained set. This is acceptable for a first validation pass, but likely needs tightening before final interpretation.

3. The B and T trajectory reports are only first-pass structure validation.

Neither should be treated as finished biological trajectory products yet.

## Where to pick up next

### B lineage

Likely next options:

- interpret lineage-1 dynamics in detail
- choose whether to analyze `L2` or `L3` similarly
- add feature-set or pathway dynamics beyond the current panels if needed

### T lineage

The main next decision is probably:

1. decide whether `trajectory_tcell` needs tightening before further use
2. if kept, interpret the current part-1 lineage-1 dynamics
3. define T part 2:
   - DN to mature T populations
   - this should be a separate trajectory set and separate Slingshot run
4. later concatenate part 1 and part 2 through the DN overlap

### General practical note

If resuming the T work, do not assume the current `trajectory_tcell` set is final. It should be re-evaluated from the report before building the part-2 trajectory.
