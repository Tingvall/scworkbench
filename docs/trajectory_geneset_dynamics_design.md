# Trajectory Gene-Set Dynamics

## Intent

`trajectory_geneset_dynamics` is the first-class discovery op for the question:

> Given a trajectory, which pathway / GSEA / module gene sets show interesting
> dynamic behavior along pseudotime?

The op is deliberately generic. It does not hard-code MSigDB. Any library
imported into the bundle feature-set registry can be screened by namespace, for
example `msigdb_h`, `go_bp`, `reactome`, `immgen`, or a project-local namespace.

## Inputs

- `matrix`: expression/accessibility-derived feature matrix.
- `model`: trajectory `model_ref` with lineage pseudotime.
- `namespace`: feature-set namespace from `wb_feature_sets()`.
- Optional `feature_sets`: subset within the namespace.
- Optional `lineage`: subset of trajectory lineages.
- Optional `score_method`: `mean`, `sum`, or `rank_mean` across set members per cell.
- Optional `top_driver_genes`: number of member genes retained in `driver_table`.
- Optional orientation fields: `pseudotime_direction`, `start_label`, `end_label`.
- Optional filters: `min_amplitude`, `min_bins_observed`,
  `min_features_detected`, `min_detected_fraction`.
- Optional curve modeling: `smooth_method`, `bootstrap_n`, `ci_level`.

Feature-set import is intentionally outside this op. The bundle owns its
feature-set registry. The op only consumes a namespace that already exists in
the bundle.

## Algorithm

For each lineage and feature set:

1. Intersect feature-set members with the matrix feature universe.
2. Exclude sets outside `min_set_size` / `max_set_size`.
3. Score each cell by the mean, sum, or rank-mean score of the set members.
4. Bin cells along trajectory pseudotime.
5. Summarize feature-set score per bin.
6. Optionally smooth the binned curve.
7. Optionally bootstrap cells within bins for confidence bands.
8. Compute dynamic metrics from the selected curve (`value_smooth` when
   smoothing is enabled; otherwise `value_raw`).

The current default score is the mean expression/accessibility value across
features in the set. This is intentionally simple, transparent, and compatible
with the existing `trajectory_signature_smooth` semantics.

This is not full UCell scoring. `rank_mean` is a dependency-light rank-based
alternative that ranks the union of screened genes within each cell and averages
the ranks for the set members. Full UCell can still be added later as either an
explicit scoring mode or as a chained workflow that first creates a
`cell_vector_family` and then smooths it over pseudotime.

## Curve Classes

`curve_class` is assigned from the binned curve:

- `turns_on`: positive monotonic trend above the configured rho threshold.
- `turns_off`: negative monotonic trend below the configured rho threshold.
- `transient_peak`: maximum is internal rather than at either end.
- `transient_dip`: minimum is internal rather than at either end.
- `weak_on`: positive late-early shift without strong monotonicity.
- `weak_off`: negative late-early shift without strong monotonicity.
- `flat_or_noisy`: no interpretable coarse class.

The class labels are report labels, not hypothesis tests.

Classification uses the curve values selected for metrics: `value_smooth` when
`smooth_method != "none"`, otherwise `value_raw`.

Decision order:

1. If `amplitude < class_min_amplitude`, class is `flat_or_noisy`.
2. If `abs(late_minus_early) >= on_off_min_delta` and
   `spearman_rho >= monotonic_min_abs_rho`, class is `turns_on`.
3. If `abs(late_minus_early) >= on_off_min_delta` and
   `spearman_rho <= -monotonic_min_abs_rho`, class is `turns_off`.
4. If `peak_bin` is internal, class is `transient_peak`.
5. If `trough_bin` is internal, class is `transient_dip`.
6. If `late_minus_early > 0`, class is `weak_on`.
7. If `late_minus_early < 0`, class is `weak_off`.
8. Otherwise class is `flat_or_noisy`.

An internal peak/trough means the selected bin is not the first or last observed
bin: `bin > 1` and `bin < n_bins_observed`.

Orientation matters. `turns_on` and `turns_off` are defined relative to the
current pseudotime direction. If `pseudotime_direction = "invert"`, the
biological interpretation of on/off is reversed relative to the original
trajectory pseudotime.

## Driver Genes

`driver_table` screens genes inside each feature set with the same binned-curve
metric machinery and keeps the top `top_driver_genes` member genes. This helps
readers see whether a set-level curve is supported by several dynamic members or
dominated by a small number of genes.

`driver_curve_table` stores the corresponding binned curves for those selected
driver genes so reports can plot them under each gene-set curve.

## Outputs

All outputs are promotable `obs_table` primitives.

- `signature_table`: binned curves with `feature_set`, `lineage_id`, `bin`,
  `pseudotime`, `value`, `n_cells`, and `n_features`.
- `dynamics_table`: one row per feature set and lineage with ranking metrics.
- `top_sets`: top-ranked subset of `dynamics_table` for report generation.
- `driver_table`: top dynamic member genes within each screened set.
- `driver_curve_table`: binned curves for top driver genes.
- `fit_summary`: per-lineage diagnostics and parameter echo.

## Plotting Contract

The curve outputs are plotting-native through the existing
`pseudotime_signature_line` plot contract:

- `trajectory_signature_smooth`
- `trajectory_geneset_dynamics_curve`
- `trajectory_geneset_dynamics_driver_curve`

The shared contract requires `feature_set`, `pseudotime`, and `value`.
Gene-set dynamics curves can additionally expose `value_raw`, `value_smooth`,
`value_ci_low`, and `value_ci_high`. Driver-gene curves additionally expose
`feature_id` and `driver_rank`; plot specs color/group by `feature_id` and facet
by `feature_set`.

This keeps the new op client-native without introducing a new primitive kind.

## Dynamic Metrics

The first-version ranking is intentionally generous and report-friendly:

- `amplitude`: max minus min binned score.
- `sd_value`: standard deviation of binned scores.
- `late_minus_early`: last 20 percent mean minus first 20 percent mean.
- `spearman_rho`: monotonic association with pseudotime.
- `peak_bin` / `trough_bin`: where the curve reaches maximum/minimum.
- `dynamic_score`: `amplitude + sd_value + abs(late_minus_early) + abs(spearman_rho) * sd_value`.
- `passes_filters`: whether the set passed report/discovery filters.
- `filter_reason`: semicolon-separated reason for failing filters.
- `curve_class`: coarse behavior label:
  - `turns_on`
  - `turns_off`
  - `transient_peak`
  - `transient_dip`
  - `weak_on`
  - `weak_off`
  - `flat_or_noisy`

Interpretation:

- High `abs(spearman_rho)` means monotonic behavior.
- High `amplitude` with low monotonicity can indicate transient or switch-like
  behavior.
- `late_minus_early` gives direction, not significance.

## What This Is Not

This op is not classical preranked GSEA with permutation p-values. It is a
trajectory-signature screen over gene-set scores. That is appropriate for
discovery reports where we want dynamic biological functions, not only endpoint
enrichment.

Classical enrichment still belongs in `pathway_enrich`, typically downstream of
DE tables or trajectory DE tables.

## Report Workflow

A useful report should:

1. Run `trajectory_geneset_dynamics` on broad gene-set namespaces.
2. Show the highest-ranked monotonic and transient sets separately.
3. Plot top curves using `signature_table`.
4. Group results by `curve_class` so readers see programs that turn on, turn off,
   or peak transiently.
5. Use `driver_table` to show which member genes are most responsible for each
   dynamic set.
6. Include `fit_summary` so the reader sees how many cells and sets were used.
7. Treat terms as hypotheses unless validated by gene-level trends or orthogonal
   evidence.
