# scworkbench Parameter Semantics Catalog

<!-- Generated from wb_parameter_semantics_catalog(); do not edit entries by hand. -->

Parameter count: 30

## classification

### `class_min_amplitude`

Title: Minimum Amplitude For Non-Flat Class

Description: Minimum curve range required before assigning a non-flat dynamic class.

Applies to: op params

Affects: flat versus dynamic classes, turns_on/turns_off/transient calls

Guidance:
- Use this to avoid classifying tiny numerical wiggles as biology.
- Keep distinct from min_amplitude if you want permissive reporting but conservative classes.

Aliases: dynamic_class_amplitude

### `on_off_min_delta`

Title: On/Off Delta Threshold

Description: Minimum late-minus-early absolute difference required for turns_on or turns_off classes.

Applies to: op params

Affects: turns_on calls, turns_off calls

Guidance:
- Interpret relative to score scale.
- A stricter threshold reduces weak monotonic calls.

Aliases: delta_threshold

### `monotonic_min_abs_rho`

Title: Monotonicity Threshold

Description: Minimum absolute Spearman correlation with pseudotime required for monotonic on/off classes.

Applies to: op params

Affects: turns_on calls, turns_off calls, transient calls

Guidance:
- Higher values require cleaner monotonic behavior.
- Transient or multi-phase curves should not be forced into monotonic classes.

Aliases: rho_threshold

## data_source

### `matrix`

Title: Matrix Input

Description: Symbolic matrix primitive consumed by an op. The matrix defines the feature universe and measurement scale.

Applies to: op inputs

Affects: feature universe, measurement scale, detected features

Guidance:
- Choose RNA/ATAC/counts/normalized matrix intentionally.
- Matrix semantics are more important than the string id; future matrix metadata should formalize this.

Aliases: matrix_id

### `space`

Title: Embedding / Latent Space Input

Description: Symbolic space primitive used for geometry, clustering, nearest-neighbor, projection, or trajectory operations.

Applies to: op inputs

Affects: geometry, neighborhoods, trajectory shape

Guidance:
- Use a space whose dimensions represent the biology under study.
- Changing space can change distances, branches, and inferred progress.

Aliases: space_id, fit_space, plot_space

### `model`

Title: Model Reference Input

Description: Reference to a fitted model or trajectory object used by downstream projection/smoothing/dynamics ops.

Applies to: op inputs

Affects: pseudotime, lineage keys, projection semantics

Guidance:
- Model provenance defines the biological orientation and branch structure.
- Do not treat models from different methods as interchangeable without checking semantics.

Aliases: model_ref

## filtering

### `min_cells_per_bin`

Title: Minimum Cells Per Bin

Description: Minimum number of cells required for a pseudotime bin to be retained.

Applies to: op params

Affects: curve support, missing bins, confidence

Guidance:
- Higher values make curves more stable but can remove sparse terminal regions.
- Report this when interpreting missing or truncated curves.

Aliases: min_bin_cells

### `min_amplitude`

Title: Minimum Curve Amplitude Filter

Description: Minimum observed/smoothed curve range required for a signal or feature set to pass report filters.

Applies to: op params

Affects: reported dynamics, noise filtering

Guidance:
- This is a reporting/filter threshold, not a p-value.
- Set it relative to score scale; amplitude units differ between mean expression, UCell, chromVAR, and ranks.

Aliases: amplitude_threshold

### `min_bins_observed`

Title: Minimum Observed Bins Filter

Description: Minimum number of retained pseudotime bins required for a curve to pass filters.

Applies to: op params

Affects: curve completeness, terminal-region confidence

Guidance:
- Higher values reduce fragmentary curves.
- Sparse branches may fail this filter even if biologically interesting.

Aliases: min_bins

### `min_features_detected`

Title: Minimum Detected Set Members

Description: Minimum number of feature-set members detected in the matrix before a set passes filters.

Applies to: op params

Affects: feature-set validity, dropout robustness

Guidance:
- Use this to avoid interpreting gene sets represented by too few measured genes.
- Important for targeted panels and cross-species or sparse feature spaces.

Aliases: min_detected_genes

### `min_detected_fraction`

Title: Minimum Detected Set Fraction

Description: Minimum fraction of feature-set members detected in the matrix before a set passes filters.

Applies to: op params

Affects: feature-set validity, dropout robustness

Guidance:
- Complements min_features_detected by scaling with set size.
- Useful when screening gene sets of very different sizes.

Aliases: detected_fraction

## reporting

### `top_n`

Title: Top-N Retention

Description: Number of top-ranked records retained for compact outputs or reports.

Applies to: op params

Affects: report size, visible discoveries

Guidance:
- Does not usually change the full underlying calculation unless explicitly documented.
- Use larger values for exploratory reports.

Aliases: n_top

## reproducibility

### `seed`

Title: Random Seed

Description: Seed used for stochastic algorithms or resampling.

Applies to: op params

Affects: reproducibility, stochastic outputs

Guidance:
- Set explicitly for replayable reports.
- Changing seed can affect stochastic fits, bootstraps, or approximations.

Aliases: random_seed, bootstrap_seed

## selection

### `cell_set`

Title: Cell Set / Analysis Universe

Description: Restricts the cells considered by an op. This is a biological and computational universe choice, not a cosmetic filter.

Applies to: op inputs

Affects: cell inclusion, statistics, plots, runtime

Guidance:
- Use a biologically justified set for focused analysis.
- Use all/core intentionally; changing the set can change effect sizes, trajectory curves, and enrichment.

Aliases: cells, cell_ids

## signal

### `signal_keys`

Title: Signal Key Subset

Description: Optional restriction to selected keys in a cell_vector_family, such as UCell signatures or chromVAR motifs.

Applies to: op params

Affects: screening universe, reported signals

Guidance:
- Use NULL for broad signal-family screening.
- Use explicit keys for targeted follow-up.

Aliases: keys, signature_keys, motif_keys

## signature

### `score_method`

Title: Feature-Set Scoring Method

Description: Defines how member features are collapsed into a per-cell or per-bin feature-set score.

Applies to: op params

Affects: score scale, curve shape, dynamic ranking

Guidance:
- Mean/sum depend on expression scale and set size.
- Rank-based methods reduce scale sensitivity but change interpretation.

Aliases: scoring, signature_score_method

### `namespace`

Title: Feature-Set Namespace

Description: Selects the registered collection of feature sets to screen or score.

Applies to: op params

Affects: tested hypotheses, multiple testing universe, discovery scope

Guidance:
- Treat namespace as the biological hypothesis library.
- Report the namespace because it defines what could have been discovered.

Aliases: gene_set_namespace, collection

### `feature_sets`

Title: Feature-Set Subset

Description: Optional restriction to named feature sets within a namespace.

Applies to: op params

Affects: screening universe, reported terms

Guidance:
- Use NULL for broad discovery.
- Use explicit subsets for targeted validation.

Aliases: gene_sets, signatures

## smoothing

### `smooth_method`

Title: Curve Smoothing Method

Description: Optional smoother applied to binned curves before metrics and class assignment.

Applies to: op params

Affects: curve shape, classification, confidence bands

Guidance:
- Smoothing can reveal broad dynamics but can also erase sharp transitions.
- Report the method because it affects classes.

Aliases: smoother

### `loess_span`

Title: LOESS Span

Description: Controls the locality of LOESS smoothing when smooth_method is loess.

Applies to: op params

Affects: smoothness, local transitions

Guidance:
- Smaller span follows local variation more closely.
- Larger span produces broader, smoother trends.

Aliases: span

## summary

### `summary_fun`

Title: Bin Summary Function

Description: Statistic used to summarize cell-level values within each bin.

Applies to: op params

Affects: curve values, outlier sensitivity

Guidance:
- Mean is sensitive to outliers and abundance shifts.
- Median is more robust but may compress sparse expression.

Aliases: summary_function

## trajectory

### `pseudotime`

Title: Pseudotime Vector Input

Description: Continuous per-cell progress coordinate, usually inferred by a trajectory method or path-scoring op.

Applies to: op inputs

Affects: ordering, trend tests, dynamic classes

Guidance:
- Pseudotime is relative to its root/orientation.
- Compare methods only after aligning orientation and intersecting cells when needed.

Aliases: trajectory_time, progress

### `pseudotime_direction`

Title: Pseudotime Direction

Description: Controls whether pseudotime is used as provided or inverted before binning, curve metrics, and class assignment.

Applies to: op params

Affects: early/late interpretation, turns_on/turns_off labels, report captions

Guidance:
- Set this so early and late correspond to the biological start and endpoint.
- Inversion changes interpretation, not the underlying cell scores.

Aliases: orientation, direction

### `start_label`

Title: Biological Start Label

Description: Human-readable label for the intended biological start of a trajectory or dynamics analysis.

Applies to: op params

Affects: metadata, reports, interpretation

Guidance:
- Use this to make orientation explicit in reports.
- This records intent; it does not root the trajectory by itself.

Aliases: root_label, early_label

### `end_label`

Title: Biological End Label

Description: Human-readable label for the intended biological endpoint of a trajectory or dynamics analysis.

Applies to: op params

Affects: metadata, reports, interpretation

Guidance:
- Use this to make endpoint interpretation explicit.
- This records intent; it does not alter model geometry by itself.

Aliases: terminal_label, late_label

### `lineage`

Title: Lineage Subset

Description: Restricts analysis to one or more lineage/path keys from a trajectory, relation, or path family.

Applies to: op params

Affects: branch selection, curve counts, reported dynamics

Guidance:
- Use lineage keys that are present in the upstream model/artifact.
- Different methods may use different lineage/branch key semantics.

Aliases: branch, path_id, lineage_id

### `n_bins`

Title: Pseudotime Bin Count

Description: Number of bins used to aggregate cells along pseudotime before curve summaries and dynamics metrics.

Applies to: op params

Affects: curve resolution, noise, runtime

Guidance:
- More bins preserve detail but increase sparsity/noise.
- Fewer bins smooth curves but may hide sharp transitions.

Aliases: bins

## trajectory_inclusion

### `mad_multiplier`

Title: MAD Distance Inclusion Multiplier

Description: Threshold multiplier for median absolute deviation distance filters around a trajectory/path.

Applies to: workflow or op params

Affects: included cells, trajectory tightness, terminal contamination

Guidance:
- Lower values create a tighter trajectory tube and exclude more distant cells.
- Interpret relative to the embedding/space; unlike fixed distance thresholds, MAD adapts to scale.
- Not yet universal in op interfaces; include when route inclusion becomes a first-class op parameter.

Aliases: mad_threshold, distance_mad_multiplier

## uncertainty

### `bootstrap_n`

Title: Bootstrap Replicate Count

Description: Number of bootstrap resamples per bin for confidence intervals; zero disables bootstrap intervals.

Applies to: op params

Affects: confidence bands, runtime

Guidance:
- Use for report-quality uncertainty bands.
- Large values increase runtime.

Aliases: n_bootstrap

### `ci_level`

Title: Confidence Interval Level

Description: Nominal confidence level for bootstrap confidence bands.

Applies to: op params

Affects: confidence band width

Guidance:
- Higher levels produce wider intervals.
- Only meaningful when bootstrap_n is greater than zero.

Aliases: confidence_level

