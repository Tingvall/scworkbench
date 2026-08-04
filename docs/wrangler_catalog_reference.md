# scworkbench Wrangler Catalog

<!-- Generated from wb_wrangler_catalog_semantic(); do not edit entries by hand. -->

Wrangler count: 14

## plot_mapper

### `plot_mapper:space2d_overlay_v1`

Function: `wb_wrangle_plot_dataset`

Title: Space + Vector Embedding Overlay Wrangler

Description: Combines a 2D space with optional cell-vector overlays into an embedding_overlay dataset.

Consumes: space_2d, cell_vector, cell_vector_family

Produces: embedding_overlay dataset

Use when:
- color UMAP by expression or scores
- overlay sets or labels on a 2D space

### `plot_mapper:feature_table_volcano_v1`

Function: `wb_wrangle_plot_dataset`

Title: Feature Table Volcano Wrangler

Description: Maps differential or trend-like feature tables to volcano plot columns.

Consumes: feature_table

Produces: ranked_features dataset

Use when:
- plot DE effect versus significance
- inspect feature-level statistics

### `plot_mapper:feature_table_trend_scatter_v1`

Function: `wb_wrangle_plot_dataset`

Title: Feature Trend Scatter Wrangler

Description: Maps feature trend statistics to a feature_scatter plot dataset.

Consumes: feature_table

Produces: feature_scatter dataset

Use when:
- plot pseudotime trend statistics
- inspect feature association effects

### `plot_mapper:cell_vector_violin_v1`

Function: `wb_wrangle_plot_dataset`

Title: Cell Vector Violin Wrangler

Description: Combines a numeric cell vector with a grouping vector to form distribution data.

Consumes: cell_vector, cell_vector_family

Produces: distribution dataset

Use when:
- compare scores across groups
- display UCell/module score distributions

### `plot_mapper:cell_vector_category_count_bar_v1`

Function: `wb_wrangle_plot_dataset`

Title: Categorical Cell Vector Count Wrangler

Description: Counts categorical cell-vector labels for category bar plots.

Consumes: cell_vector

Produces: category_summary dataset

Use when:
- summarize winner labels
- count categorical annotations

### `plot_mapper:feature_table_dotplot_v1`

Function: `wb_wrangle_plot_dataset`

Title: Feature Group Dotplot Wrangler

Description: Maps marker-style feature group summaries to dotplot columns.

Consumes: feature_table

Produces: feature_group_summary dataset

Use when:
- plot markers by cluster
- show percent expression and average expression

### `plot_mapper:feature_table_pathway_bar_v1`

Function: `wb_wrangle_plot_dataset`

Title: Pathway Summary Wrangler

Description: Maps pathway enrichment observation tables to ranked pathway bars.

Consumes: obs_table

Produces: pathway_summary dataset

Use when:
- plot pathway enrichment
- rank GSEA or feature-set terms

### `plot_mapper:feature_table_ranked_lollipop_v1`

Function: `wb_wrangle_plot_dataset`

Title: Ranked Table Lollipop Wrangler

Description: Maps feature or observation tables with score-like columns to ranked entity data.

Consumes: feature_table, obs_table

Produces: ranked_entities dataset

Use when:
- show top genes
- show top dynamic signals
- show top pathways

### `plot_mapper:feature_table_heatmap_ranked_v1`

Function: `wb_wrangle_plot_dataset`

Title: Ranked Feature Heatmap Wrangler

Description: Maps feature-by-group values to a matrix-like ranked heatmap dataset.

Consumes: feature_table

Produces: matrix_like dataset

Use when:
- compare ranked features across groups

### `plot_mapper:feature_table_feature_rank_bar_v1`

Function: `wb_wrangle_plot_dataset`

Title: Feature Rank Bar Wrangler

Description: Maps feature tables with score-like values to ranked bar data.

Consumes: feature_table

Produces: ranked_features dataset

Use when:
- show compact ranked feature summaries

### `plot_mapper:trajectory_pseudotime_smooth_panel_v1`

Function: `wb_wrangle_plot_dataset`

Title: Pseudotime Smooth Wrangler

Description: Maps trajectory_smooth tables to per-gene pseudotime curve panels.

Consumes: obs_table:trajectory_smooth

Produces: trajectory_smooth dataset

Use when:
- plot gene dynamics along pseudotime

### `plot_mapper:trajectory_pseudotime_signature_line_v1`

Function: `wb_wrangle_plot_dataset`

Title: Pseudotime Signature Wrangler

Description: Maps signature, gene-set, signal, or driver curves to pseudotime line datasets.

Consumes: obs_table:trajectory_signature_smooth, obs_table:trajectory_geneset_dynamics_curve, obs_table:trajectory_signal_dynamics_curve

Produces: trajectory_signature_smooth dataset

Use when:
- plot gene-set dynamics
- plot signal dynamics
- plot driver-gene curves

## table

### `table:primitive_to_table`

Function: `wb_primitive_to_table`

Title: Primitive To Table Wrangler

Description: Projects primitive-native payloads to normalized data.frames for display, export, or light client use.

Consumes: feature_table, obs_table, cell_vector, cell_vector_family, relation_family, space_path_family, space_2d

Produces: data.frame

Use when:
- inspect a primitive as rows
- export primitive payload
- normalize promoted artifacts for clients

### `table:client_load_table`

Function: `wb_client_load_table`

Title: Client Reference To Table Wrangler

Description: Loads a session/artifact/reference through the client facade and converts the resolved primitive to a normalized table.

Consumes: artifact ref, session ref, primitive ref

Produces: data.frame

Use when:
- load and inspect artifact tables
- agent-friendly reference inspection
