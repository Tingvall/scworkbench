# scworkbench Operation Catalog

<!-- Generated from wb_op_catalog_semantic(); do not edit op entries by hand. -->

Generated at: source-controlled

Operation count: 14

This document summarizes registered scworkbench ops for humans, agents, and semantic indexing.
The machine-readable companion is `docs/op_catalog_semantic.json`.

## `chromvar`

Title: chromVAR deviations

Intent: atac, motif, signature, score

Description: Bias-corrected chromVAR deviations on a peak matrix using genome-backed GC bias and motif matching against a JASPAR PWM catalog.

Consumes:
- `matrix`: matrix
- `cell_set`: select

Produces:
- `deviation_z`: cell_vector_family [terminal artifact] - Per-cell chromVAR z-scores keyed by motif.
- `deviation_raw`: cell_vector_family [terminal artifact] - Per-cell raw chromVAR deviations keyed by motif.
- `motif_summary`: obs_table [terminal artifact] - Per-motif chromVAR summary statistics.

Promotable outputs: deviation_z, deviation_raw, motif_summary

Replay equivalence:
- `deviation_z`: `exact_canonical_value`
- `deviation_raw`: `exact_canonical_value`
- `motif_summary`: `exact_canonical_value`

Key parameters:
- `motif_library` (string, default=NULL): Canonical motif-library key from the motif registry.
- `motifs` (string_vec, default=NULL): Optional motif-key subset within motif_library.
- `motif_match_set` (string, default=NULL): Optional canonical motif-match-set key to reuse cached motif-to-peak matches.
- `min_motif_peaks` (int, default=10): Minimum number of matched peaks per retained motif.
- `max_motif_peaks` (int, default=NULL): Optional maximum number of matched peaks per retained motif.
- `motif_p_cutoff` (dbl, default=5e-05): Motifmatchr p-value cutoff.
- `motif_w` (int, default=7): Motifmatchr background window width.
- `seqlevels_mode` (choice, default=standard): Seqlevel policy; standard chromosomes are the default.
- `seqlevels_include` (string_vec, default=NULL): Optional explicit seqlevels to keep after applying seqlevels_mode.
- `seqlevels_exclude` (string_vec, default=NULL): Optional explicit seqlevels to drop after applying seqlevels_mode.
- `background_iterations` (int, default=50): Number of chromVAR background iterations.
- `background_w` (dbl, default=0.1): Background peak matching window width.
- `background_bs` (int, default=50): Background peak matching bin count.

## `feature_set_import`

Title: Feature-Set Library Import

Intent: feature_set, import, gene_set, provenance, library

Description: Import GMT/RDS/table feature-set libraries into the bundle feature-set registry and emit import provenance tables.

Consumes:
- `matrix`: matrix
- `cell_set`: select

Produces:
- `import_summary`: obs_table [terminal artifact] - One-row summary of parsed/imported/skipped/rejected set counts.
- `import_manifest`: obs_table [terminal artifact] - One row per parsed feature set with target namespace, overlap counts, and import status.
- `rejected_sets`: obs_table [terminal artifact] - Feature sets rejected during import, typically because no genes mapped to the matrix.

Promotable outputs: import_summary, import_manifest, rejected_sets

Replay equivalence:
- `import_summary`: `exact_canonical_value`
- `import_manifest`: `exact_canonical_value`
- `rejected_sets`: `exact_canonical_value`

Key parameters:
- `source_path` (path, default=NULL): Path to GMT, RDS list/data.frame, or CSV-like table source.
- `source_format` (choice, default=auto): Input parser. auto infers from file extension.
- `namespace` (string, default=NULL): Target feature-set namespace base label.
- `collection` (string, default=NULL): Optional collection label recorded in import manifests.
- `subcollection` (string, default=NULL): Optional subcollection label; used for namespace splitting when requested.
- `species` (string, default=NULL): Species/organism label recorded in feature-set metadata.
- `organism` (string, default=NULL): Optional organism label; when omitted, species is used.
- `gene_id_type` (string, default=NULL): Identifier type expected in source genes, for example gene_symbol.
- `set_id_col` (string, default=feature_set): For table sources, column containing set identifiers.
- `set_name_col` (string, default=NULL): For table sources, optional human-readable set-name column.
- `gene_col` (string, default=feature_id): For table sources, column containing gene/feature identifiers.
- `description_col` (string, default=description): For table sources, optional set description column.
- `split_by_collection` (bool, default=FALSE): If TRUE, append detected/declared subcollection to the namespace base.
- `overwrite` (bool, default=TRUE): If FALSE, existing feature sets are skipped instead of replaced.
- `strict` (bool, default=FALSE): If TRUE, error on genes absent from the matrix; otherwise drop absent genes.
- `created_by` (string, default=NULL): Optional creator label stored in feature-set provenance.
- `source_id` (string, default=NULL): Optional source/library identifier stored in feature-set metadata.
- `source_version` (string, default=NULL): Optional source/library version stored in feature-set metadata.
- `origin` (string, default=imported): Origin label stored in feature-set metadata.
- `is_readonly` (bool, default=TRUE): Whether imported feature sets are registered read-only.

## `feature_set_namespace_transfer`

Title: Feature-Set Namespace Transfer

Intent: feature_set, transfer, namespace, matrix, provenance

Description: Transfer matrix-scoped feature-set namespaces between comparable matrices using mirror or intersect semantics.

Consumes:
- `source_matrix`: matrix
- `target_matrix`: matrix
- `cell_set`: select

Produces:
- `transfer_summary`: obs_table [terminal artifact] - Namespace-level summary of transfer mode, matrix compatibility, and transferred/skipped/rejected set counts.
- `transfer_manifest`: obs_table [terminal artifact] - One row per source feature set with source/target matrices, namespaces, retained members, status, and set IDs.
- `transfer_rejected`: obs_table [terminal artifact] - Feature sets rejected during intersect transfer because retained members failed thresholds.

Promotable outputs: transfer_summary, transfer_manifest, transfer_rejected

Replay equivalence:
- `transfer_summary`: `exact_canonical_value`
- `transfer_manifest`: `exact_canonical_value`
- `transfer_rejected`: `exact_canonical_value`

Key parameters:
- `namespace` (string, default=NULL): Single source namespace to transfer.
- `namespaces` (string_vec, default=NULL): Optional multiple source namespaces to transfer.
- `feature_sets` (string_vec, default=NULL): Optional feature-set subset within selected source namespaces.
- `mode` (choice, default=mirror): mirror requires identical feature universes; intersect retains only target-valid members and records loss.
- `target_namespace` (string, default=NULL): Optional target namespace override. Defaults to the source namespace.
- `overwrite` (bool, default=FALSE): If FALSE, existing target feature sets are skipped instead of replaced.
- `strict` (bool, default=TRUE): If TRUE, fail when intersect mode rejects any selected set by retention thresholds.
- `min_retained_features` (int, default=1): Minimum target-retained members required to transfer a set.
- `min_retained_fraction` (dbl, default=0): Minimum fraction of source members retained on the target matrix.
- `created_by` (string, default=NULL): Optional created_by metadata for transferred registry rows.
- `notes` (string, default=NULL): Optional provenance note. This op is not for gene-to-peak, peak-to-gene, motif-to-TF, ortholog, or synonym mapping.

## `cell_set_derive`

Title: Derived Cell Set

Intent: selection, provenance, registry

Description: Materialize a selector-derived or explicitly declared cell universe as a named cell set with lifecycle role/status and manifest tables.

Consumes:
- `cell_set`: select

Produces:
- `manifest`: obs_table [terminal artifact] - One-row lifecycle manifest for the named derived cell set, including counts, role, status, recipe availability, and source summary.
- `rule_table`: obs_table [terminal artifact] - Ordered per-rule derivation audit table with input/output/removal counts and source fields.

Promotable outputs: manifest, rule_table

Replay equivalence:
- `manifest`: `exact_canonical_value`
- `rule_table`: `exact_canonical_value`

Key parameters:
- `target_cell_set` (string, default=NULL): Name of the derived cell set to create, for example set:universe_b_l1_weight090.
- `role` (choice, default=analysis_universe): Lifecycle role of the derived set.
- `status` (choice, default=candidate): Lifecycle status controlling interpretation and default visibility.
- `source` (string, default=selector_recipe): Source/provenance label stored on membership rows.
- `created_by` (string, default=NULL): Optional creator label.
- `description` (string, default=NULL): Human-readable derivation rationale.
- `recipe` (list, default=NULL): Optional selector recipe stored with the derived cell set.
- `overwrite` (bool, default=TRUE): If TRUE, replace existing membership for the target set; if FALSE, add cells to it.

## `metadata_cell_vector`

Title: Metadata Cell Vector

Intent: metadata, cell_vector, provenance, technical_diagnostics

Description: Materialize an imported cell metadata column as a typed, provenance-backed cell vector.

Consumes:
- `cell_set`: select

Produces:
- `vector`: cell_vector [terminal artifact] - Typed per-cell vector materialized from imported bundle metadata.

Promotable outputs: vector

Replay equivalence:
- `vector`: `exact_canonical_value`

Key parameters:
- `source_column` (metadata_field, default=NULL): Imported metadata name or explicit wb_ref_metadata_field() reference to materialize.
- `cell_set` (cell_set, default=all): Named bundle cell set defining the vector universe.
- `value_type` (choice, default=auto): Explicit vector value type; auto records a conservative native-type decision.
- `missing_policy` (choice, default=error): How missing values are handled before vector materialization.
- `missing_label` (string, default=__MISSING__): Replacement label when missing_policy='as_category'.
- `vector_name` (string, default=NULL): Stable promoted vector name; collision protection is controlled by overwrite.
- `overwrite` (bool, default=FALSE): Allow a new immutable artifact to supersede an existing vector with the same name.

## `slingshot_adopt`

Title: Adopt an existing Slingshot fit

Intent: trajectory, adoption, provenance, source_derived

Description: Adopt a checksummed source-derived Slingshot fit as a complete trajectory family without refitting it.

Consumes:
- `model`: model_ref
- `cell_set`: select

Produces:
- `pseudotime`: cell_vector_family [terminal artifact] - Source-derived lineage-specific pseudotime values; no refit is performed.
- `lineage_weights`: cell_vector_family [terminal artifact] - Source-derived Slingshot lineage membership weights; no refit is performed.
- `curves`: path_2d_family [terminal artifact] - Source-derived two-dimensional Slingshot lineage curves.
- `model`: model_ref [terminal artifact] - Contained source-derived Slingshot model bound to the adopted trajectory fit family.
- `adoption_summary`: obs_table [terminal artifact] - Source checksum, subobject identity, coordinate-alignment result, fit identity, dimensions, and explicit external-execution boundary.

Promotable outputs: pseudotime, lineage_weights, curves, model, adoption_summary

Replay equivalence:
- `pseudotime`: `exact_canonical_value`
- `lineage_weights`: `exact_canonical_value`
- `curves`: `exact_canonical_value`
- `model`: `loadable_reference`
- `adoption_summary`: `exact_canonical_value`

Key parameters:
- `source` (entity_ref, default=NULL): Registered external_source reference for the object from which the selected Slingshot fit was extracted.

## `monocle3_fit`

Title: Monocle3 fit (hybrid space)

Intent: trajectory

Description: Fit monocle3 graph/pseudotime using a scworkbench latent space injected into monocle3's UMAP slot.

Consumes:
- `fit_space`: space
- `cell_set`: select

Produces:
- `pseudotime`: cell_vector [terminal artifact] - Rooted global pseudotime per cell from monocle3.
- `branch_membership`: relation_family [terminal artifact] - Derived cell-to-lineage membership relations (tree root-to-leaf paths; binary weights in the current implementation).
- `model`: model_ref [terminal artifact] - Session-chainable monocle3 CDS model (engine='monocle3').

Promotable outputs: pseudotime, branch_membership, model

Replay equivalence:
- `pseudotime`: `exact_canonical_value`
- `branch_membership`: `exact_canonical_value`
- `model`: `loadable_reference`

Key parameters:
- `dims` (string_vec, default=NULL): Optional fit-space dimensions to use (e.g. 1:20 as explicit integer vector).
- `root_cells` (cell_ids, default=NULL): Root cell IDs (exactly one of root_cells or root_pr_nodes).
- `root_pr_nodes` (string_vec, default=NULL): Principal graph root node IDs (advanced; exactly one of root_cells or root_pr_nodes).
- `k` (int, default=20): kNN size for monocle3 clustering.
- `cluster_method` (choice, default=leiden): Monocle3 clustering backend.
- `num_iter` (int, default=2): Monocle3 clustering iterations.
- `partition_qval` (dbl, default=0.05): Partition significance threshold.
- `weight` (bool, default=FALSE): Use weighted nearest-neighbor graph for monocle3 clustering.
- `resolution` (dbl, default=NULL): Optional clustering resolution (NULL lets monocle3 choose).
- `random_seed` (int, default=42): Random seed for clustering.
- `use_partition` (bool, default=FALSE): Learn graph per partition. FALSE is recommended for current tree semantics.
- `close_loop` (bool, default=FALSE): Allow loop closure in graph learning. FALSE is required for tree-derived lineages.
- `verbose` (bool, default=FALSE): Verbose monocle3 output.

## `monocle3_project`

Title: Monocle3 project curves

Intent: trajectory

Description: Project a fitted monocle3 trajectory graph into a 2D display space.

Consumes:
- `model`: model_ref
- `plot_space`: space_2d
- `cell_set`: select

Produces:
- `curves`: path_2d_family [terminal artifact] - Projected monocle3 root-qualified lineage curves in the chosen 2D display space.

Promotable outputs: curves

Replay equivalence:
- `curves`: `exact_canonical_value`

Key parameters:
- `approx_points` (int, default=200): Target max curve points per lineage for display (0/NULL = no compaction).

## `peakvi_fit`

Title: PeakVI fit (pybench)

Intent: latent, model, python

Description: Train a PeakVI model on a matrix via the pybench Python runtime and emit a latent space plus model reference.

Consumes:
- `matrix`: matrix
- `cell_set`: select

Produces:
- `space`: space [materialization; committed by: model] - PeakVI latent space written into the bundle spaces registry.
- `model`: model_ref [terminal artifact] - Serialized PeakVI Python model payload (engine='peakvi').

Promotable outputs: model

Replay equivalence:
- `space`: `exact_canonical_value`
- `model`: `loadable_reference`

Key parameters:
- `n_latent` (int, default=20): Target latent dimensionality for the emitted PeakVI space.
- `n_layers` (int, default=2): Number of hidden layers passed to the PeakVI model constructor.
- `n_hidden` (int, default=256): Hidden width passed to the PeakVI model constructor.
- `dropout` (number, default=0.2): Dropout rate passed to the PeakVI model constructor.
- `batch_key` (metadata_field, default=NULL): Optional observation field used as the PeakVI batch covariate.
- `max_epochs` (int, default=500): Maximum training epochs passed through to scvi-tools.
- `lr` (number, default=0.001): Optional learning rate passed through in train plan_kwargs.
- `early_stopping` (bool, default=TRUE): If TRUE, enable scvi-tools early stopping during PeakVI training.
- `seed` (int, default=1): Random seed for PeakVI training.
- `use_gpu` (bool, default=FALSE): If TRUE, request GPU-backed training in scvi-tools.
- `space_id_out` (string, default=peakvi_space): Space id to write for the learned PeakVI latent embedding.

## `scvi_train`

Title: scVI train (pybench)

Intent: latent, model, python, rna, counts

Description: Train an RNA scVI model on a raw/count-like matrix via the pybench Python runtime and emit a latent space, model reference, and fit summary.

Consumes:
- `matrix`: matrix
- `cell_set`: select

Produces:
- `space`: space [materialization; committed by: model, fit_summary] - scVI latent space written into the bundle spaces registry.
- `model`: model_ref [terminal artifact] - Serialized scVI Python model payload (engine='scvi').
- `fit_summary`: obs_table [terminal artifact] - Training summary, parameter, runtime, and metric table emitted by pybench.

Promotable outputs: model, fit_summary

Replay equivalence:
- `space`: `exact_canonical_value`
- `model`: `loadable_reference`
- `fit_summary`: `exact_canonical_value`

Key parameters:
- `n_latent` (int, default=30): Target latent dimensionality for the emitted scVI space.
- `n_hidden` (int, default=128): Hidden width passed to the scVI model constructor.
- `n_layers` (int, default=2): Number of hidden layers passed to the scVI model constructor.
- `dropout` (number, default=0.1): Dropout rate passed to the scVI model constructor.
- `batch_key` (string, default=NULL): Optional cell metadata field used as the scVI batch covariate.
- `categorical_covariates` (metadata_field_array, default=NULL): Optional categorical cell metadata covariates passed to scVI setup_anndata.
- `continuous_covariates` (metadata_field_array, default=NULL): Optional continuous cell metadata covariates passed to scVI setup_anndata.
- `max_epochs` (int, default=NULL): Optional maximum training epochs passed through to scvi-tools.
- `early_stopping` (bool, default=TRUE): If TRUE, enable scvi-tools early stopping during scVI training.
- `seed` (int, default=1): Random seed for scVI training.
- `use_gpu` (bool, default=FALSE): If TRUE, request GPU-backed training in scvi-tools.
- `output_space_id` (string, default=rna.scvi): Space id to write for the learned scVI latent embedding.
- `space_id_out` (string, default=NULL): Deprecated compatibility alias for output_space_id.
- `model_artifact_id` (string, default=NULL): Optional preregistered model artifact id. NULL lets scworkbench assign one.
- `overwrite` (bool, default=FALSE): If TRUE, allow replacing an existing output_space_id.
- `allow_non_counts` (bool, default=FALSE): If TRUE, bypass raw/count-like matrix checks. Use only for intentional expert overrides.

## `peakvi_project`

Title: PeakVI project (pybench)

Intent: projection, latent, python

Description: Project cells from an ATAC matrix through a saved PeakVI model and emit a latent space.

Consumes:
- `matrix`: matrix
- `model`: model_ref
- `cell_set`: select

Produces:
- `space`: space [materialization; committed by: fit_summary] - Projected PeakVI latent space written into the bundle spaces registry.
- `fit_summary`: obs_table [terminal artifact] - Projection receipt and output-space summary.

Promotable outputs: fit_summary

Replay equivalence:
- `space`: `exact_canonical_value`
- `fit_summary`: `exact_canonical_value`

Key parameters:
- `batch_key` (string, default=NULL): Optional observation field used as the PeakVI batch covariate during projection.
- `use_gpu` (bool, default=FALSE): If TRUE, request GPU-backed model loading/projection in scvi-tools.
- `space_id_out` (string, default=peakvi_project_space): Space id to write for the projected PeakVI latent embedding.

## `model_bound_latent_union`

Title: Model-Bound Latent-Space Union

Intent: latent, integration, projection, provenance

Description: Combine disjoint fitted-reference and projected-query latent coordinates only when both are bound to the same retained PeakVI or scVI model identity.

Consumes:
- `reference_space`: space
- `query_space`: space
- `model`: model_ref
- `projection_summary`: obs_table
- `cell_set`: select

Produces:
- `space`: space [materialization; committed by: union_summary] - Durable high-dimensional space containing fitted reference and projected query coordinates in canonical cell order.
- `union_summary`: obs_table [terminal artifact] - Model, source-space, output-space, cell-count, dimension, disjointness, and no-transformation record.

Promotable outputs: union_summary

Replay equivalence:
- `space`: `exact_canonical_value`
- `union_summary`: `exact_canonical_value`

Key parameters:
- `space_id_out` (string, default=model_bound_latent_union): New durable space identity for the unchanged row-wise coordinate union.

## `palantir_fit`

Title: Palantir fit (pybench)

Intent: trajectory

Description: Run Palantir pseudotime/branch probabilities on a scworkbench latent space via the pybench Python runtime.

Consumes:
- `fit_space`: space
- `cell_set`: select

Produces:
- `pseudotime`: cell_vector [terminal artifact] - Palantir pseudotime (single-root, global).
- `branch_membership`: relation_family [terminal artifact] - Palantir branch probabilities as cell-to-branch relations (`branch:*` keys; weights are probabilities).
- `branch_summary`: obs_table [terminal artifact] - Palantir branch probability summary table.
- `entropy`: cell_vector [terminal artifact] - Palantir entropy per cell.
- `model`: model_ref [terminal artifact] - Palantir Python model payload (engine='palantir').

Promotable outputs: pseudotime, branch_membership, branch_summary, entropy, model

Replay equivalence:
- `pseudotime`: `exact_canonical_value`
- `branch_membership`: `exact_canonical_value`
- `branch_summary`: `exact_canonical_value`
- `entropy`: `exact_canonical_value`
- `model`: `loadable_reference`

Key parameters:
- `root_cell` (string, default=NULL): Single Palantir early/root cell ID (Palantir-native single-root semantics).
- `terminal_cells` (cell_ids, default=NULL): Optional explicit terminal cell IDs passed to Palantir as terminal states (recommended for branch probabilities).
- `dims` (string_vec, default=NULL): Optional fit-space dimensions to use (for example 1:20 as explicit integer vector).
- `knn` (int, default=30): kNN size for Palantir diffusion graph and pseudotime.
- `n_diffusion_components` (int, default=10): Number of diffusion components for Palantir.
- `n_waypoints` (int, default=300): Number of Palantir waypoints.
- `use_early_cell_as_start` (bool, default=TRUE): Pass through to Palantir; if TRUE, force the provided early/root cell to be used as trajectory start.
- `seed` (int, default=20): Random seed for Palantir stochastic steps.

## `palantir_project`

Title: Palantir project trajectories

Intent: trajectory

Description: Project Palantir branch trajectories into a 2D display space using Palantir-style mellon interpolation from the fitted Palantir model.

Consumes:
- `model`: model_ref
- `plot_space`: space_2d
- `cell_set`: select

Produces:
- `curves`: path_2d_family [terminal artifact] - Palantir-style smoothed branch trajectories projected into the chosen 2D display space.

Promotable outputs: curves

Replay equivalence:
- `curves`: `exact_canonical_value`

Key parameters:
- `prob_min` (dbl, default=0.05): Minimum branch probability mask threshold for branch trajectory interpolation.
- `smoothness` (dbl, default=1): Palantir-style mellon trajectory smoothing multiplier (higher = smoother).
- `min_cells_per_branch` (int, default=50): Minimum eligible cells required to derive a branch trajectory.
- `approx_points` (int, default=200): Number of trajectory sample points per branch (curve resolution).
