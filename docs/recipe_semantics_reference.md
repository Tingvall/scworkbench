# scworkbench Recipe Semantics Catalog

<!-- Generated from wb_recipe_semantics_catalog(); do not edit entries by hand. -->

Recipe count: 10

## agent_planning

### `semantic_next_steps_from_artifact`

Title: Find next steps from an artifact

Question: Given an artifact, what can the agent do next?

Description: Use the semantic catalog and compatibility graph to find downstream getters, wranglers, plots, and ops compatible with the artifact primitive type.

Steps:
- Inspect artifact_type and primitive_kind.
- Find graph edges from artifact_type to primitive via loads_as.
- Follow primitive to wranglers via wrangled_by and plots via feeds_plot.
- Follow primitive to ops via consumed_by for downstream analysis.
- Return candidates with provenance caveats.

Uses:
- `getter:wb_art_identity_card`
- `getter:wb_art_load`
- `artifact_type:cell_vector`
- `primitive:cell_vector`
- `wrangler:table:client_load_table`
- `plot:embedding_overlay`

Cautions:
- Compatibility means technically possible, not biologically appropriate.
- Use provenance and parameter semantics before making claims.

## artifact_inspection

### `inspect_promoted_artifact`

Title: Inspect a promoted artifact

Question: What is this artifact and how can I use or plot it?

Description: Use artifact getters to inspect identity, provenance, table shape, dependencies, and compatible downstream actions.

Steps:
- List artifacts with wb_art_list().
- Read identity/provenance using wb_art_identity_card() and wb_art_birth_certificate().
- If table-like, inspect columns with wb_art_table_info() and preview rows with wb_art_table_slice().
- Load as primitive with wb_art_load() only when payload access is needed.
- Use semantic_compatibility_graph to find compatible wranglers/plots.

Uses:
- `getter:wb_art_list`
- `getter:wb_art_identity_card`
- `getter:wb_art_birth_certificate`
- `getter:wb_art_table_info`
- `getter:wb_art_table_slice`
- `getter:wb_art_load`
- `wrangler:table:client_load_table`

Cautions:
- Do not infer biology from artifact type alone; check source op and parameters.
- Prefer bounded table slices before loading large payloads.

## differential_analysis

### `de_to_pathway_report`

Title: Differential expression to pathway report

Question: Which pathways explain differential genes between two cell sets?

Description: Run DE between two sets, convert ranked/significant features to enrichment queries, and plot top pathway terms.

Steps:
- Define or choose group_a and group_b cell sets.
- Run de_wilcox on the selected matrix.
- Promote de_table and inspect top features.
- Run pathway_enrich on selected up/down genes or ranked query policy.
- Plot pathway_bar and volcano summaries.

Uses:
- `op:de_wilcox`
- `op:pathway_enrich`
- `plot:volcano`
- `plot:pathway_bar`
- `artifact_type:feature_table:de_wilcox`
- `artifact_type:obs_table:pathway_enrich`
- `parameter:cell_set`
- `parameter:matrix`
- `parameter:namespace`

Cautions:
- Cell-set definitions control the comparison.
- Pathway output depends on the selected feature universe and query policy.

## discovery

### `cluster_markers_pathways`

Title: Cluster to markers to pathways

Question: What are the marker genes and pathway programs for clusters?

Description: Cluster cells in a chosen space, find top markers per cluster, and optionally enrich each cluster marker list.

Steps:
- Run leiden on a biologically appropriate space and cell_set.
- Run markers_topn using the cluster labels.
- Promote marker table.
- Optionally run pathway_enrich per cluster marker subset.
- Plot dotplot, ranked lollipop, or pathway bars.

Uses:
- `op:leiden`
- `op:markers_topn`
- `op:pathway_enrich`
- `plot:dotplot`
- `plot:ranked_lollipop`
- `plot:pathway_bar`
- `parameter:space`
- `parameter:cell_set`
- `parameter:matrix`

Cautions:
- Cluster resolution changes biological granularity.
- Markers reflect selected matrix and cell universe.

## matrix_transfer

### `feature_set_namespace_transfer_for_normalized_matrix`

Title: Transfer feature-set namespaces to a derived normalized matrix

Question: How can feature-set libraries registered on raw counts be reused on a comparable derived matrix?

Description: Transfer matrix-scoped feature-set namespaces from a source matrix to a target matrix using mirror or intersect semantics before running dynamics on the target matrix.

Steps:
- Confirm the target matrix is comparable to the source matrix and uses the same feature ID type.
- Run feature_set_namespace_transfer with source_matrix_id, target_matrix_id, namespace, and mode='mirror' for lossless derived matrices.
- Promote transfer_summary, transfer_manifest, and transfer_rejected for provenance.
- Run feature_set_overlap_qc on the target matrix/namespace before broad screening.
- Run trajectory_geneset_dynamics on the target matrix with the transferred namespace.

Uses:
- `op:feature_set_namespace_transfer`
- `op:feature_set_overlap_qc`
- `op:trajectory_geneset_dynamics`
- `getter:wb_feature_sets`
- `artifact_type:obs_table:feature_set_transfer_manifest`
- `parameter:source_matrix_id`
- `parameter:target_matrix_id`
- `parameter:namespace`
- `parameter:target_namespace`

Cautions:
- This is not ortholog/synonym/gene-to-peak/motif-to-TF mapping.
- mode='mirror' requires identical feature universes.
- mode='intersect' changes gene-set membership and must be reported with loss metrics.

## trajectory_discovery

### `trajectory_geneset_dynamics_discovery`

Title: Run gene-set dynamics along a trajectory

Question: Which biological processes turn on, turn off, or behave transiently along a trajectory?

Description: Screen a feature-set namespace across trajectory pseudotime and report dynamic terms plus driver genes.

Steps:
- Inspect available feature-set namespaces with wb_feature_sets().
- Choose trajectory model artifact/model_ref and matrix.
- Run trajectory_geneset_dynamics with namespace, lineage/orientation, and filtering thresholds.
- Promote signature_table, dynamics_table, top_sets, driver_table, driver_curve_table, and fit_summary.
- Plot top dynamic terms and driver-gene curves with pseudotime_signature_line.

Uses:
- `getter:wb_feature_sets`
- `getter:wb_art_list`
- `op:trajectory_geneset_dynamics`
- `plot:pseudotime_signature_line`
- `wrangler:plot_mapper:trajectory_pseudotime_signature_line_v1`
- `parameter:namespace`
- `parameter:score_method`
- `parameter:pseudotime_direction`
- `parameter:min_amplitude`

Cautions:
- Gene-set universe and score_method define the biological meaning.
- Pseudotime orientation controls turns_on versus turns_off labels.
- Amplitude thresholds are scale-dependent filters, not p-values.

### `feature_set_import_qc_then_dynamics`

Title: Import and QC a feature-set library before trajectory screening

Question: Can this external gene-set library be used for dynamic program discovery along a trajectory?

Description: Import a GMT/RDS/table feature-set library into a namespace, record import provenance, QC matrix overlap, then use the namespace in trajectory_geneset_dynamics.

Steps:
- Choose the target matrix that defines the feature universe.
- Run feature_set_import with source_path, namespace, species/gene_id_type, and source_version.
- Promote import_summary, import_manifest, and rejected_sets for auditability.
- Run feature_set_overlap_qc on the imported namespace and inspect include/exclude reasons.
- Use the accepted namespace with trajectory_geneset_dynamics and report QC artifacts alongside dynamics.

Uses:
- `op:feature_set_import`
- `op:feature_set_overlap_qc`
- `op:trajectory_geneset_dynamics`
- `getter:wb_feature_sets`
- `artifact_type:obs_table:feature_set_import_manifest`
- `artifact_type:obs_table:feature_set_overlap_qc`
- `parameter:source_path`
- `parameter:namespace`
- `parameter:split_by_collection`
- `parameter:min_detected_fraction`

Cautions:
- Import matching is against bundle feature IDs; synonym/ortholog mapping is not performed here.
- QC include/exclude thresholds define the screened universe and should be reported.
- Broad libraries should be split only when collection/subcollection semantics are meaningful.

### `trajectory_signal_dynamics_discovery`

Title: Run signal dynamics along a trajectory

Question: Which precomputed cell-level signals are dynamic along pseudotime?

Description: Rank UCell, chromVAR, module-score, or other cell_vector_family signals by dynamic behavior along a trajectory.

Steps:
- Load or identify a cell_vector_family artifact containing signals.
- Choose trajectory model artifact/model_ref and lineage/orientation.
- Run trajectory_signal_dynamics with signal_keys or all keys.
- Promote signal_table, dynamics_table, top_signals, and fit_summary.
- Plot top signal curves with pseudotime_signature_line.

Uses:
- `getter:wb_art_list`
- `getter:wb_read_cell_vector_family`
- `op:trajectory_signal_dynamics`
- `plot:pseudotime_signature_line`
- `parameter:signal_keys`
- `parameter:pseudotime_direction`
- `parameter:min_amplitude`

Cautions:
- Signal scale depends on upstream scoring method.
- Only compare signals with compatible score semantics.

## visualization

### `plot_ucell_on_umap`

Title: Plot UCell signatures on UMAP

Question: Where are signature-high cells located in a 2D embedding?

Description: Overlay one or more UCell signature scores from a cell_vector_family onto a 2D space.

Steps:
- Run or locate ucell output signature_scores.
- Choose a 2D space with wb_spaces() or a space_2d artifact.
- Load/select the desired signature key from the cell_vector_family.
- Use wb_wrangle_plot_dataset for embedding_overlay or plot via compatible client.
- Inspect distribution with violin if group comparison is needed.

Uses:
- `op:ucell`
- `getter:wb_spaces`
- `getter:wb_read_cell_vector_family`
- `plot:embedding_overlay`
- `plot:violin`
- `wrangler:plot_mapper:space2d_overlay_v1`
- `wrangler:plot_mapper:cell_vector_violin_v1`
- `parameter:space`

Cautions:
- UCell scores are rank-based within cells; interpret as relative signature activity.
- Embedding overlay is a visualization, not a statistical test.

### `plot_trajectory_on_umap`

Title: Plot selected trajectory curves on UMAP

Question: How does a selected trajectory or lineage sit in the 2D embedding?

Description: Combine a 2D space with path_2d_family curves and pseudotime/cell overlays for trajectory diagnostics.

Steps:
- Locate trajectory curve artifact or project model/path into 2D.
- Choose only the selected lineage/path used for dynamics if multiple are present.
- Plot full candidate cells in muted color and selected curve in foreground.
- Overlay pseudotime or endpoint labels as needed.
- Use diagnostics to avoid showing unused branches in dynamics figures.

Uses:
- `artifact_type:path_2d_family`
- `op:slingshot_project`
- `op:monocle3_project`
- `op:palantir_project`
- `op:space_path_project_2d`
- `plot:embedding_overlay`
- `primitive:path_2d_family`
- `parameter:lineage`

Cautions:
- 2D curves are display projections and may not equal high-dimensional geometry.
- If dynamics use one lineage, do not display unrelated lineages as if they were used.

