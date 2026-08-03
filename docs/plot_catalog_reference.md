# scworkbench Plot/Wrangler Catalog

<!-- Generated from wb_plot_catalog_semantic(); do not edit plot entries by hand. -->

Generated at: 2026-08-03T11:22:51+0200

Plot count: 12

This document summarizes registered plot contracts and mapper wranglers for humans, agents, and semantic indexing.
The machine-readable companion is `docs/plot_catalog_semantic.json`.

## `embedding_overlay`

Title: Embedding Overlay

Dataset type: embedding_overlay

Description: Display cells in a 2D embedding with optional color, shape, size, alpha, or set overlays.

Use when:
- show marker expression on UMAP
- show cell set membership in space
- inspect per-cell scores spatially

Compatible refs / data:
- space_2d
- cell_vector
- cell_vector_family
- artifact-backed cell vectors

Required fields:
- `cell_id`: character
- `x`: numeric
- `y`: numeric

Optional fields:
- `color_value`: any
- `color_type`: character
- `shape_value`: any
- `size_value`: numeric
- `alpha_value`: numeric
- `set_name`: character
- `label`: character

Mappers:
- `space2d_overlay_v1` (priority=10)

## `volcano`

Title: Volcano Plot

Dataset type: ranked_features

Description: Plot feature-level effect size against adjusted p-value for differential or trend-like feature tables.

Use when:
- inspect DE results
- find significant feature effects

Compatible refs / data:
- feature_table with feature_id, effect/rho/logFC, p_adj

Required fields:
- `feature_id`: character
- `effect`: numeric
- `p_adj`: numeric

Optional fields:
- `p_raw`: numeric
- `label`: character
- `significant`: logical
- `direction`: character
- `rank`: numeric

Mappers:
- `feature_table_volcano_v1` (priority=10)

## `trend_scatter`

Title: Trend Scatter

Dataset type: feature_scatter

Description: Plot feature-level trend or association statistics as a scatter plot.

Use when:
- inspect pseudotime trend statistics
- compare feature trend effect and significance

Compatible refs / data:
- feature_table with feature_id and numeric trend columns

Required fields:
- `feature_id`: character
- `x`: numeric
- `y`: numeric

Optional fields:
- `p_adj`: numeric
- `p_raw`: numeric
- `direction`: character
- `significant`: logical
- `rank`: numeric
- `label`: character
- `color_value`: any
- `size_value`: numeric

Mappers:
- `feature_table_trend_scatter_v1` (priority=10)

## `violin`

Title: Violin Plot

Dataset type: distribution

Description: Show distributions of per-cell vector values across groups.

Use when:
- compare scores across labels
- show UCell/module/chromVAR distributions

Compatible refs / data:
- cell_vector
- cell_vector_family

Required fields:
- `entity_id`: character
- `group`: character
- `value`: numeric

Optional fields:
- `color_value`: any
- `facet`: character
- `label`: character

Mappers:
- `cell_vector_violin_v1` (priority=10)

## `category_count_bar`

Title: Category Count Bar

Dataset type: category_summary

Description: Show counts and percentages for categorical cell-vector labels.

Use when:
- summarize label counts
- inspect winner label composition

Compatible refs / data:
- categorical cell_vector

Required fields:
- `category`: character
- `count`: numeric

Optional fields:
- `pct`: numeric
- `rank`: numeric
- `label`: character

Mappers:
- `cell_vector_category_count_bar_v1` (priority=10)

## `dotplot`

Title: Dotplot

Dataset type: feature_group_summary

Description: Show feature expression summaries across groups with percent-expressed and average-expression encodings.

Use when:
- marker expression by cluster
- feature set marker summaries

Compatible refs / data:
- feature_table with group summaries

Required fields:
- `feature_id`: character
- `group`: character
- `pct_expr`: numeric
- `avg_expr`: numeric

Optional fields:
- `rank`: numeric
- `significant`: logical
- `direction`: character
- `label`: character

Mappers:
- `feature_table_dotplot_v1` (priority=10)

## `pathway_bar`

Title: Pathway Bar

Dataset type: pathway_summary

Description: Show ranked pathway or feature-set enrichment terms.

Use when:
- inspect enrichment results
- rank pathways by adjusted p-value or score

Compatible refs / data:
- feature_table pathway enrichment output

Required fields:
- `pathway`: character
- `p_adj`: numeric

Optional fields:
- `score`: numeric
- `overlap`: numeric
- `set_size`: numeric
- `query_size`: numeric
- `namespace`: character
- `significant`: logical
- `label`: character

Mappers:
- `feature_table_pathway_bar_v1` (priority=10)

## `ranked_lollipop`

Title: Ranked Lollipop

Dataset type: ranked_entities

Description: Show ranked entities from feature tables or obs_table summaries.

Use when:
- show top genes
- show top pathways
- show dynamic gene sets
- show driver genes

Compatible refs / data:
- feature_table
- obs_table with entity and score columns

Required fields:
- `feature_id`: character
- `score`: numeric

Optional fields:
- `p_adj`: numeric
- `p_raw`: numeric
- `direction`: character
- `significant`: logical
- `rank`: numeric
- `label`: character

Mappers:
- `feature_table_ranked_lollipop_v1` (priority=10)

## `heatmap_ranked`

Title: Ranked Heatmap

Dataset type: matrix_like

Description: Show matrix-like feature-by-group values from ranked feature tables.

Use when:
- compare top feature values across groups

Compatible refs / data:
- feature_table with feature_id, group, value

Required fields:
- `feature_id`: character
- `group`: character
- `value`: numeric

Optional fields:
- `rank`: numeric
- `label`: character
- `direction`: character
- `significant`: logical

Mappers:
- `feature_table_heatmap_ranked_v1` (priority=10)

## `feature_rank_bar`

Title: Feature Rank Bar

Dataset type: ranked_features

Description: Show ranked feature values as bars.

Use when:
- show top ranked features
- compact marker/trend summary

Compatible refs / data:
- feature_table with feature_id and value/score

Required fields:
- `feature_id`: character
- `value`: numeric

Optional fields:
- `rank`: numeric
- `label`: character
- `direction`: character
- `significant`: logical
- `p_adj`: numeric
- `p_raw`: numeric

Mappers:
- `feature_table_feature_rank_bar_v1` (priority=10)

## `pseudotime_smooth_panel`

Title: Pseudotime Smooth Panel

Dataset type: trajectory_smooth

Description: Show per-feature smoothed expression curves along trajectory pseudotime.

Use when:
- plot gene dynamics along trajectory
- inspect trajectory_smooth outputs

Compatible refs / data:
- trajectory_smooth obs_table

Required fields:
- `feature_id`: character
- `pseudotime`: numeric
- `expr`: numeric

Optional fields:
- `lineage_id`: character
- `n_cells`: integer
- `label`: character

Mappers:
- `trajectory_pseudotime_smooth_panel_v1` (priority=10)

## `pseudotime_signature_line`

Title: Pseudotime Signature Line

Dataset type: trajectory_signature_smooth

Description: Show feature-set or signal curves along trajectory pseudotime.

Use when:
- plot gene-set dynamics
- plot UCell/module score dynamics
- plot driver-gene curves

Compatible refs / data:
- trajectory_signature_smooth
- trajectory_geneset_dynamics_curve
- trajectory_signal_dynamics_curve

Required fields:
- `feature_set`: character
- `pseudotime`: numeric
- `value`: numeric

Optional fields:
- `lineage_id`: character
- `n_cells`: integer
- `label`: character
- `feature_id`: character
- `driver_rank`: integer
- `value_raw`: numeric
- `value_smooth`: numeric
- `value_se`: numeric
- `value_ci_low`: numeric
- `value_ci_high`: numeric

Mappers:
- `trajectory_pseudotime_signature_line_v1` (priority=10)

