# scworkbench Parameter Semantics Catalog

<!-- Generated from wb_parameter_semantics_catalog(); do not edit entries by hand. -->

Parameter count: 53

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

### `output_matrix_id`

Title: Output Matrix Identifier

Description: Matrix id assigned to a newly created bundle matrix.

Applies to: matrix-producing op params

Affects: downstream matrix selection, replay, artifact interpretation

Guidance:
- Use a name that records the transform and scale, for example RNA_log1p_cp10k.
- Do not reuse an existing matrix id unless overwrite behavior is intentional.

Aliases: new_matrix_id, target_matrix_id

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

### `min_mean_score`

Title: Minimum Mean Score Filter

Description: Minimum mean smoothed curve score required before a gene set or signal passes report filters.

Applies to: op params

Affects: low-abundance filtering, reported dynamics

Guidance:
- Use this to avoid over-interpreting tiny but smooth low-expression changes.
- Thresholds are score-scale dependent; keep disabled for broad discovery if unsure.

Aliases: mean_score_threshold

### `min_max_score`

Title: Minimum Maximum Score Filter

Description: Minimum maximum smoothed curve score required before a gene set or signal passes report filters.

Applies to: op params

Affects: low-abundance filtering, reported dynamics

Guidance:
- For log1p CP10K mean scores, a small threshold such as 0.1 can separate robust programs from near-zero wiggles.
- Do not reuse the same number for UCell, chromVAR, or other score scales without checking distributions.

Aliases: max_score_threshold

### `min_signal_to_noise`

Title: Minimum Signal-To-Noise Filter

Description: Minimum amplitude divided by mean bootstrap standard error required before a curve passes filters.

Applies to: op params

Affects: uncertainty-aware filtering, reported dynamics

Guidance:
- Requires bootstrap-derived standard errors to be meaningful.
- Use as a support filter, not as a formal p-value.

Aliases: snr_threshold, min_snr

### `low_abundance_max_score`

Title: Low-Abundance Flag Threshold

Description: Maximum score threshold below which dynamic-looking curves are flagged as low abundance.

Applies to: op params

Affects: interpretation, report triage

Guidance:
- This flag warns about low-expression dynamics without removing them by default.
- Set relative to the selected matrix or score method.

Aliases: low_expression_threshold, low_signal_threshold

## import

### `source_path`

Title: Feature-Set Source Path

Description: File-backed source for feature-set imports, such as GMT, RDS list/data.frame, or CSV-style table.

Applies to: feature-set import params

Affects: imported library, provenance, replay

Guidance:
- Use file-backed imports for agent/session execution so provenance can point to the source.
- Record source_id and source_version when the path alone is not a durable library identity.

Aliases: gene_set_file, gmt_path

### `source_format`

Title: Feature-Set Source Format

Description: Parser choice for a feature-set import source.

Applies to: feature-set import params

Affects: column interpretation, wide versus long parsing, library import validity

Guidance:
- Use auto for ordinary .gmt and .rds files.
- Set explicitly when a file extension is ambiguous.

Aliases: format, input_format

### `split_by_collection`

Title: Split Feature-Set Namespace By Collection

Description: Controls whether broad gene-set libraries are split into collection/subcollection namespaces during import.

Applies to: feature-set import params

Affects: namespace granularity, screening universe, multiple testing universe

Guidance:
- Use TRUE for broad mixed libraries such as MSigDB when collection/subcollection labels are meaningful.
- Keep WikiPathways or focused custom libraries in their own namespace unless splitting adds biological clarity.

Aliases: split_namespace, collection_split

### `gene_id_type`

Title: Gene Identifier Type

Description: Records the identifier convention used by imported feature-set genes.

Applies to: feature-set import params

Affects: mapping interpretation, cross-species reliability, QC interpretation

Guidance:
- Use explicit labels such as gene_symbol or ensembl_id when known.
- The current import path matches against bundle feature IDs; it does not perform synonym or ortholog mapping.

Aliases: feature_id_type, id_type

## matrix_transfer

### `source_matrix_id`

Title: Source Matrix Identifier

Description: Matrix id that owns the source matrix-scoped feature-set namespace or other transferable registry state.

Applies to: matrix transfer params

Affects: source feature universe, registry provenance, transfer validity

Guidance:
- Use a matrix whose feature IDs define the existing feature-set memberships.
- Do not use this for cross-feature-type conversion; that requires an explicit mapping artifact.

Aliases: from_matrix, source_matrix

### `target_matrix_id`

Title: Target Matrix Identifier

Description: Matrix id that will receive transferred feature-set memberships after mirror or intersect validation.

Applies to: matrix transfer params

Affects: target feature universe, retained features, downstream namespace availability

Guidance:
- Use mirror only when source and target feature universes are identical.
- Use intersect when feature universes overlap and loss should be recorded.

Aliases: to_matrix, target_matrix

### `target_namespace`

Title: Target Feature-Set Namespace

Description: Optional namespace assigned to transferred feature sets on the target matrix.

Applies to: feature-set transfer params

Affects: downstream namespace selection, provenance readability

Guidance:
- Leave NULL to preserve source namespace.
- Set explicitly when keeping raw-count and normalized-matrix namespaces separate is useful.

Aliases: destination_namespace

### `min_retained_features`

Title: Minimum Retained Features

Description: Minimum number of source feature-set members that must remain valid on a target matrix during transfer.

Applies to: feature-set transfer params

Affects: intersect transfer rejection, screening universe quality

Guidance:
- Use with mode='intersect' to avoid transferring nearly empty sets.
- For mode='mirror' this should normally be trivially satisfied.

Aliases: min_transfer_features

### `min_retained_fraction`

Title: Minimum Retained Fraction

Description: Minimum fraction of source feature-set members that must remain valid on a target matrix during transfer.

Applies to: feature-set transfer params

Affects: lossy transfer rejection, QC stringency

Guidance:
- Use to prevent broad lossy transfers from silently changing gene-set meaning.
- This is not a biological mapping confidence score; it only measures retained feature IDs.

Aliases: transfer_fraction

## mutation

### `overwrite`

Title: Overwrite Existing Output

Description: Controls whether an op may replace an existing persisted bundle object with the same identifier.

Applies to: mutating op params

Affects: bundle state, reproducibility, rerun safety

Guidance:
- Keep FALSE for safety when creating named outputs.
- Set TRUE only for deliberate deterministic reruns or temporary development outputs.

Aliases: replace, force

## normalization

### `scale_factor`

Title: Library-Size Normalization Scale

Description: Target per-cell total used when converting raw counts to scaled expression before log transformation.

Applies to: matrix normalization params

Affects: expression scale, dynamic curves, feature-set scores

Guidance:
- 10000 is the common log1p(CP10K) convention for scRNA-seq.
- Changing this value changes numeric scale but usually preserves rank-like patterns after log1p.

Aliases: target_sum, counts_per_cell, cp_scale

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

### `permutation_seed`

Title: Permutation Random Seed

Description: Seed used for empirical score-pseudotime permutation tests.

Applies to: trajectory dynamics op params

Affects: p_dynamic reproducibility, q_dynamic reproducibility

Guidance:
- Set explicitly for replayable reports.
- Changing the seed can slightly change empirical p-values when n_permutations is modest.

Aliases: perm_seed

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

### `target_cell_set`

Title: Target Derived Cell Set

Description: Stable bundle name assigned to a newly materialized derived cell universe.

Applies to: cell-set derivation params

Affects: bundle registry, downstream op inputs, claim auditability

Guidance:
- Use meaningful names for claim-supporting universes.
- Downstream promoted runs should consume this named set rather than a raw cell_id vector.

Aliases: output_cell_set, derived_cell_set

## selection_lifecycle

### `role`

Title: Cell-Set Lifecycle Role

Description: Declared purpose of a cell set, such as analysis_universe, exclusion_set, endpoint_set, annotation, diagnostic, or temporary.

Applies to: cell-set derivation params

Affects: visibility, interpretation, agent planning

Guidance:
- Use analysis_universe for claim-supporting restriction sets.
- Use temporary for exploratory sets that should not be interpreted as accepted state.

Aliases: cell_set_role

### `status`

Title: Cell-Set Lifecycle Status

Description: Declared maturity of a cell set, such as candidate, accepted, superseded, rejected, active, or temporary.

Applies to: cell-set derivation params

Affects: visibility, interpretation, audit state

Guidance:
- Use candidate while evaluating a restriction.
- Use accepted only after biological and diagnostic review.

Aliases: cell_set_status, lifecycle_status

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

## statistics

### `n_permutations`

Title: Empirical Permutation Count

Description: Number of score-pseudotime permutations used to estimate empirical dynamic-score p-values.

Applies to: trajectory dynamics op params

Affects: p_dynamic, q_dynamic, runtime

Guidance:
- Use 0 for fast exploratory discovery.
- Use hundreds to thousands for final reports when runtime is acceptable.
- Permutation p-values support dynamic-score ranking but do not replace effect-size and abundance filters.

Aliases: n_perm, permutations

### `p_adjust_method`

Title: P-Value Adjustment Method

Description: Multiple-testing correction method used to convert empirical p_dynamic values into q_dynamic values.

Applies to: statistical op params

Affects: FDR calls, reported statistical support

Guidance:
- BH is the usual default for discovery-style FDR control.
- Correction is across the screened feature-set universe, so namespace/subset choice matters.

Aliases: fdr_method, multiple_testing_method

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

### `trajectory_fit_id`

Title: Trajectory Fit Identity

Description: Stable identity binding trajectory-derived artifacts emitted from one fit, including model_ref, pseudotime, lineage weights, and projected paths.

Applies to: trajectory artifacts and params

Affects: lineage label meaning, artifact compatibility, provenance validation

Guidance:
- Lineage labels such as L1 are only meaningful within one trajectory_fit_id.
- Do not combine pseudotime, weights, model, or paths across fit families without an explicit mapping operation.

Aliases: trajectory_family_id, fit_family_id

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

