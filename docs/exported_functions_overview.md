# Exported Functions Overview

Generated from `NAMESPACE` on 2026-03-10.

Note:

- this is a broad surface map, not a contract document
- canonical extension and architecture rules live in:
  - `inst/foundation_contracts.md`
  - `docs/engine_extension_patterns.md`
  - `docs/navigation_contract_draft.md`

## Bundle Lifecycle

- `wb_bundle_schema`: Bundle schema snapshot (debug helper)
- `wb_close_bundle`: Close an scworkbench bundle
- `wb_list`: List registry tables in the bundle
- `wb_manifest`: Get the manifest from an scworkbench bundle
- `wb_open_bundle`: Open an scworkbench bundle
- `wb_status`: Bundle status summary (developer helper)
- `wb_validate_bundle`: Validate an scworkbench bundle on disk

## Cell Set & Selection

- `wb_cell_set_add`: Add existing cells to a set (membership-based)
- `wb_cell_set_define`: Define a cell set (persist membership + optionally persist recipe)
- `wb_cell_set_remove`: Remove cells from a set
- `wb_cell_set_replace`: Replace membership of a set (set becomes exactly these cells)
- `wb_cell_set_set`: Overwrite membership for a set (replace with exactly cell_ids)
- `wb_cell_sets`: List available cell sets in a bundle.
- `wb_get_cell_set_recipe`: Get the stored recipe for a cell set (if any)
- `wb_get_cell_set_style`: Get visual style for a cell set
- `wb_resolve_cell_set`: Resolve a cell_set selector to cell_ids
- `wb_sel_all`: Select all cells from a cell_set (optionally within a dataset)
- `wb_sel_and`: Intersect (AND) one or more cell_id vectors
- `wb_sel_expr`: Select by expression of a single feature (scalar getter)
- `wb_sel_meta`: Select by cell metadata column (categorical values or numeric range)
- `wb_sel_not`: Negation (NOT): universe minus x
- `wb_sel_or`: Union (OR) one or more cell_id vectors
- `wb_sel_recipe`: Get the recipe from a selector result
- `wb_sel_recipe_print`: Print a compact recipe summary
- `wb_sel_set`: Select union of one or more named sets
- `wb_sel_space_box`: Select cells inside an axis-aligned box in a 2D space
- `wb_sel_vector`: Select by a registered scalar cell vector (numeric range)
- `wb_sel_vector_family`: Select by a cell_vector_family member (numeric range)
- `wb_sel_vector_values`: Select by a scalar cell vector (categorical values)
- `wb_set_cell_set_style`: Set visual style for a cell set
- `wb_set_create`: Create a membership-based cell set

## Core Data Getters

- `wb_cells`: List cell IDs in canonical bundle order
- `wb_feature_ids`: Get feature IDs in canonical order for a matrix
- `wb_features`: Get features registry
- `wb_matrices`: List matrices available in the bundle
- `wb_matrix`: Get a matrix handle (BPCells)
- `wb_matrix_fragments`: List matrix fragments for a matrix
- `wb_matrix_info`: Get matrix registry info
- `wb_matrix_set_genome`: Set canonical organism/build/provider metadata for a matrix
- `wb_matrix_read_feature`: Read one feature vector across cells from virtual matrix fragments
- `wb_matrix_read_features`: Read multiple features across cells
- `wb_matrix_resolve`: Resolve matrix fragments to absolute paths
- `wb_meta`: Get cell metadata
- `wb_motif_libraries`: List motif-library definitions
- `wb_motif_library_import_jaspar`: Import a JASPAR motif set into the motif registry
- `wb_motif_library_register`: Register one motif library definition
- `wb_motif_match_get`: Load motif-to-feature membership rows for a motif match set
- `wb_motif_match_replace`: Replace one motif match set and its motif-to-feature membership
- `wb_motif_match_sets`: List motif-match materializations
- `wb_motif_register`: Register one motif definition
- `wb_motifs`: List motif definitions
- `wb_slice`: Slice a matrix into memory (sparse)
- `wb_space`: Get space coordinates
- `wb_space_info`: Get space registry info
- `wb_space_model`: Get model metadata for a space
- `wb_space_model_path`: Get absolute path to the model file for a space
- `wb_spaces`: List spaces in the bundle
- `wb_spaces_with_model`: List space_ids that have a stored model
- `wb_vector`: Get a single feature vector across cells

## Feature Set & Feature Selection

- `wb_exec_feature_selection_plan`: Execute a feature selection plan
- `wb_feature_set_delete`: Delete a feature set
- `wb_feature_set_get`: Get feature IDs from a feature set
- `wb_feature_set_import_list`: Import feature sets from a named list
- `wb_feature_set_import_table`: Import feature sets from a table
- `wb_feature_set_info`: Read feature set metadata
- `wb_feature_set_namespace_transfer`: Transfer feature-set namespaces between comparable matrix feature universes
- `wb_feature_set_replace`: Replace a feature set
- `wb_feature_sets`: List feature sets
- `wb_search_features`: Search features by matrix_id

## Ingest & Attachment

- `wb_attach_apply`: Apply attach using validated/normalized payload
- `wb_attach_normalize`: Normalize attach payload to canonical forms
- `wb_attach_to_cells`: Attach primitives to existing cells (matrices/spaces/metadata)
- `wb_attach_validate`: Validate attach payload (dry-run)
- `wb_ingest_apply`: Apply ingest using validated/normalized payload
- `wb_ingest_cells`: Ingest new cells into an existing bundle as a named membership-based cell set
- `wb_ingest_normalize`: Normalize ingest payload to canonical forms
- `wb_ingest_report`: Load one ingest report artifact
- `wb_ingest_reports`: List ingest report artifacts
- `wb_ingest_validate`: Validate ingest payload (dry-run)

## Operations (Ops)

- `wb_op_addmodulescore`: Compute Seurat-style module scores
- `wb_op_cells_all`: All cells (canonical order)
- `wb_op_cells_counts_by`: Count cells by a metadata column
- `wb_op_cells_filter`: Filter cells by a predicate on metadata
- `wb_op_cells_in_dataset`: Cells in a dataset (canonical order)
- `wb_op_cells_intersect`: Intersect cell sets (preserve canonical order)
- `wb_op_cells_order_like`: Reorder a cell vector to match canonical bundle order
- `wb_op_cells_sample`: Sample cells (stable/reproducible)
- `wb_op_cells_setdiff`: Set difference of cell sets (A \\ B), preserving canonical order
- `wb_op_cells_split_by`: Split cells by a metadata column
- `wb_op_cells_top_n_by`: Top-N groups by cell count for a metadata column
- `wb_op_cells_union`: Union cell sets (preserve canonical order)
- `wb_op_chromvar`: Compute chromVAR deviations on a peak matrix using matrix genome metadata plus motif library / motif match contracts
- `wb_op_de_wilcox`: Differential expression by Wilcoxon rank-sum (A vs B)
- `wb_op_expr_avg_by`: Average expression by group
- `wb_op_expr_frac_nonzero_by`: Fraction of non-zero expression by group
- `wb_op_expr_pseudobulk_by`: Pseudobulk by group (sum of counts per feature)
- `wb_op_expr_slice`: Slice an expression matrix (thin wrapper over wb_slice)
- `wb_op_expr_vector`: Get one feature vector across cells (thin wrapper over wb_vector)
- `wb_op_expr_zscore_by_feature`: Z-score normalize features (row-wise) on a slice
- `wb_op_feature_set_import`: Import GMT/RDS/table feature-set libraries into bundle namespaces with import manifest artifacts
- `wb_op_feature_set_overlap_qc`: Compute matrix-overlap QC for feature-set namespaces before enrichment or trajectory screening
- `wb_op_interface`: High-level op interface spec (for UIs and agents)
- `wb_op_knn_graph`: Build a kNN graph from a space
- `wb_op_knn_neighbors`: Find kNN neighbors in a space
- `wb_op_knn_pseudobulk`: Compute kNN pseudobulk around query cells
- `wb_op_leiden`: Leiden clustering on a space
- `wb_op_markers_topn`: Marker genes per cluster via one-vs-rest Wilcoxon DE
- `wb_op_meanexpr`: Mean expression per cell over a set of features
- `wb_op_monocle3_fit`: Fit a Monocle3 trajectory model
- `wb_op_monocle3_project`: Project a Monocle3 trajectory into 2D
- `wb_op_slingshot`: Slingshot trajectory inference (2D space like UMAP)
- `wb_op_trajectory_de`: Run per-lineage trajectory DE
- `wb_op_trajectory_geneset_dynamics`: Screen feature-set dynamics along trajectory pseudotime
- `wb_op_trajectory_signature_smooth`: Compute feature-set trajectory signatures
- `wb_op_trajectory_signal_dynamics`: Screen cell-level signal dynamics along trajectory pseudotime
- `wb_op_trajectory_smooth`: Compute per-feature trajectory smoothing
- `wb_op_trajectory_vector_smooth`: Compute trajectory smoothing for cell-level signal families
- `wb_op_umap_fit`: Fit UMAP from a high-D space and persist model for later transform
- `wb_op_umap_transform`: Project cells into an existing fitted UMAP space

## Other

- `wb_cell_coverage`: Report coverage of required inputs for a cell set
- `wb_cell_vector_load`: Load a cell vector primitive by vector_id (artifact:* or session:\emph{:}).
- `wb_cells_with_matrix`: Cells available for a given matrix
- `wb_cells_with_space`: Cells with available coordinates for a space
- `wb_exec_selection_plan`: Execute a selection plan into ordered cell IDs
- `wb_load_space_model`: Load a fitted space model
- `wb_primitive_to_table`: Convert a `wb_primitive` into a normalized data.frame

## Primitives, Artifacts, Provenance & Reporting

- `wb_art_get_labels`: Read label rows for a label-like artifact
- `wb_art_identity_card`: Artifact identity card (compact provenance view)
- `wb_art_list`: List promoted artifacts
- `wb_art_load`: Load a promoted artifact as a primitive
- `wb_art_table_distinct`: List distinct values from a table artifact column
- `wb_art_table_info`: Read table artifact metadata
- `wb_art_table_slice`: Slice rows from a table artifact without full load
- `wb_art_trajectory_de_overview`: Summarize a promoted `trajectory_de` artifact
- `wb_art_trajectory_de_plot_slice`: Build a ranked plotting slice for `trajectory_de`
- `wb_art_trajectory_de_ranked`: Rank `trajectory_de` rows within one lineage
- `wb_art_trajectory_de_slice_primitive`: Slice a `trajectory_de` artifact into a `feature_table` primitive
- `wb_art_trajectory_de_top`: Get top-ranked `trajectory_de` rows for one lineage
- `wb_art_trajectory_related`: Find related trajectory artifacts
- `wb_art_trajectory_smooth_overview`: Summarize a promoted `trajectory_smooth` artifact
- `wb_artifact_type_catalog_semantic`: Export artifact type catalog as semantic metadata
- `wb_freeze_packet`: Freeze a provenance packet
- `wb_freeze_snapshot`: Freeze a provenance snapshot
- `wb_getter_catalog_semantic`: Export getter catalog as semantic metadata
- `wb_migrate_artifacts`: Migrate artifact registry tables
- `wb_parameter_semantics_catalog`: Export parameter semantics catalog
- `wb_plot_contract`: Get a plot contract schema
- `wb_plot_catalog_semantic`: Export plot/wrangler catalog as semantic metadata
- `wb_plot_mapper_list`: List registered plot mappers
- `wb_plot_mapper_register`: Register a plot mapper
- `wb_plot_compatible_types`: Discover compatible plot types
- `wb_plot_compatibility_report`: Build a plot compatibility report
- `wb_plot_min_inputs`: Build minimal plot inputs for compatibility probing
- `wb_plot_space_2d`: Plot a 2D space with overlay sets and per-set glyph styles
- `wb_plot_spec`: Build a renderer-agnostic plot spec
- `wb_plot_validate_dataset`: Validate a wrangled plot dataset
- `wb_prim_cell_vector`: Create a cell_vector primitive
- `wb_prim_cell_vector_family`: Create a cell_vector_family primitive
- `wb_prim_feature_table`: Create a `feature_table` primitive
- `wb_prim_matrix`: Create a matrix primitive
- `wb_prim_model_ref`: Create a model_ref primitive
- `wb_prim_obs_table`: Create an `obs_table` primitive
- `wb_prim_path_2d_family`: Create a path_2d_family primitive
- `wb_prim_space`: Create a space primitive
- `wb_prim_space_2d`: Create a space_2d primitive
- `wb_primitive_catalog_semantic`: Export primitive catalog as semantic metadata
- `wb_promote_analysis`: Promote a session analysis DAG to persisted artifacts
- `wb_prov_artifact_lineage`: Get composed provenance lineage around one artifact
- `wb_prov_bundle_dag`: Build a bundle-level composed provenance DAG
- `wb_prov_dag`: Reconstruct a persisted provenance DAG
- `wb_prov_emit_r_script`: Emit an R replay script from persisted provenance
- `wb_prov_list_heads`: List persisted provenance snapshots
- `wb_prov_run_details`: Inspect one persisted run from provenance
- `wb_prov_validate_replay`: Validate replay of a persisted snapshot
- `wb_recipe`: Get selector recipe metadata
- `wb_recipe_semantics_catalog`: Export recipe semantics catalog
- `wb_report_draft`: Build a structured analysis report draft
- `wb_report_methods`: Draft methods text from session runs
- `wb_report_render_md`: Render a report draft as Markdown
- `wb_refresh_semantic_catalogs`: Refresh and validate all semantic catalog reference files
- `wb_semantic_catalog`: Export unified semantic catalog
- `wb_semantic_catalog_audit`: Audit semantic catalog coverage
- `wb_semantic_compatibility_graph`: Build semantic compatibility graph
- `wb_semantic_graph_dot`: Export semantic compatibility graph as Graphviz DOT
- `wb_semantic_graph_tables`: Export semantic compatibility graph tables
- `wb_semantic_plan_artifact_next_steps`: Plan next actions for a promoted artifact
- `wb_wrangle_plot_dataset`: Wrangle inputs into a validated plot dataset
- `wb_wrangler_catalog_semantic`: Export wrangler catalog as semantic metadata
- `wb_write_artifact_type_catalog_reference`: Write artifact type catalog reference files
- `wb_write_getter_catalog_reference`: Write getter catalog reference files
- `wb_write_parameter_semantics_reference`: Write parameter semantics catalog reference files
- `wb_write_plot_catalog_reference`: Write plot/wrangler catalog reference files
- `wb_write_primitive_catalog_reference`: Write primitive catalog reference files
- `wb_write_recipe_semantics_reference`: Write recipe semantics catalog reference files
- `wb_write_semantic_catalog_reference`: Write unified semantic catalog reference files
- `wb_write_semantic_graph_views`: Write semantic compatibility graph views
- `wb_write_wrangler_catalog_reference`: Write wrangler catalog reference files

## Session, Refs & Client API

- `wb_as_primitive`: Coerce input into a wb_primitive
- `wb_client_discover`: Client facade: discover bundle and runtime capabilities
- `wb_client_inspect`: Client facade: inspect session and bundle runtime state
- `wb_client_load`: Client facade: load primitive by reference
- `wb_client_load_table`: Client facade: load and wrangle reference into normalized table
- `wb_client_promote`: Client facade: promote current session analysis
- `wb_client_run`: Client facade: run an operation
- `wb_client_select`: Client facade: execute a selection plan
- `wb_is_run`: Check whether an object is a wb_run
- `wb_is_session`: Check whether an object is a wb_session
- `wb_new_run`: Create a new in-session run object
- `wb_nav_entities`: List navigable entities for a source
- `wb_nav_handoff`: Build a client-agnostic navigation handoff
- `wb_nav_targets`: List compatible navigation targets
- `wb_ref_artifact`: Create a reference to an artifact output
- `wb_ref_run`: Create a reference to a run output
- `wb_resolve_primitive`: Resolve a "spec" into a wb_primitive
- `wb_session_add_run`: Add a run to a session
- `wb_session_dag`: Build a session DAG view
- `wb_session_dag_run_details`: Inspect one session DAG run node
- `wb_session_new`: Create a new wb_session
- `wb_session_promote_current`: Promote the current analysis in a session
- `wb_session_run_op`: Run an operation in a session
- `wb_session_set_active`: Set an active output reference in a session

## Utilities & Integration

- `wb_add_space`: Add a space (embedding) to an existing bundle
- `wb_compute_profile`: Apply a runtime compute profile
- `wb_geom_trajectory_2d`: Add trajectory curves (2D) as a ggplot layer
- `wb_list_cell_vectors`: List available cell vectors (artifacts + optional session outputs)
- `wb_list_ops`: List available ops (UI/agent interface)
- `wb_list_vector_sources`: List available vector-like things for UIs
- `wb_ops`: List ops with titles/intents
- `wb_publish_app_bundle`: Publish a scworkbench app bundle from a Seurat object
- `wb_read_cell_vector`: Read a cell_vector (scalar per cell) for a set of cells
- `wb_read_cell_vector_family`: Read one member of a cell_vector_family (e.g. pseudotime for a given lineage)
- `wb_register_matrix_fragment`: Register a matrix fragment in the bundle registry
- `wb_resolve_cell_vector`: Resolve a vector reference to a named vector (names = cell_id)
- `wb_vector_ref_to_spec`: Parse a wb_list_vector_sources() ref into a spec list

Total exports: 171
