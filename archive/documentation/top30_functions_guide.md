# Top 30 Functions Guide

A practical short-list of the most important exported functions to use `scworkbench` effectively.

## 1) Open and Validate

- `wb_open_bundle`: Open a bundle for analysis.
- `wb_close_bundle`: Close bundle connections cleanly.
- `wb_validate_bundle`: Validate bundle integrity.

## 2) Inspect Data Inventory

- `wb_manifest`: Read bundle manifest metadata.
- `wb_matrices`: List available matrices.
- `wb_spaces`: List available spaces/embeddings.
- `wb_cell_sets`: List available cell sets.
- `wb_features`: Inspect feature registry.

## 3) Core Data Access

- `wb_cells`: Get cell IDs in canonical order.
- `wb_feature_ids`: Get feature IDs for a matrix.
- `wb_meta`: Fetch cell metadata.
- `wb_slice`: Pull feature x cell slices.
- `wb_vector`: Pull one feature vector across cells.

## 4) Build and Resolve Sets

- `wb_cell_set_replace`: Create/overwrite a cell set from IDs.
- `wb_cell_set_define`: Persist a cell set with optional recipe.
- `wb_feature_set_replace`: Create/overwrite feature sets.
- `wb_feature_set_get`: Retrieve feature IDs from a feature set.
- `wb_resolve_cell_set`: Resolve selectors to concrete cell IDs.

## 5) Run Analysis Ops

- `wb_session_new`: Start a session DAG.
- `wb_session_run_op`: Run an op with typed inputs/params.
- `wb_op_interface`: Discover op contracts for UI/agents.
- `wb_op_de_wilcox`: Differential expression (Wilcoxon).
- `wb_op_addmodulescore`: Module scoring.
- `wb_op_knn_neighbors`: kNN neighborhood lookup.
- `wb_op_knn_pseudobulk`: Neighborhood pseudobulk aggregation.

## 6) Persist Results

- `wb_session_promote_current`: Promote current session head outputs.
- `wb_promote_analysis`: Promote reachable DAG outputs directly.
- `wb_art_list`: List promoted artifacts.
- `wb_art_load`: Load artifact back as primitive.

## 7) Provenance and Reporting

- `wb_session_dag`: Build run/artifact DAG view.
- `wb_prov_dag`: DAG from persisted provenance snapshot.
- `wb_prov_emit_r_script`: Emit replay script from provenance.
- `wb_report_draft`: Draft report payload from session/bundle context.
- `wb_report_render_md`: Render report markdown.

## Suggested Learning Path

1. Open bundle and inspect (`wb_open_bundle`, `wb_matrices`, `wb_cell_sets`).
2. Resolve/select inputs (`wb_cells`, `wb_feature_set_get`, `wb_resolve_cell_set`).
3. Run ops in session (`wb_session_new`, `wb_session_run_op`).
4. Promote outputs (`wb_session_promote_current`, `wb_art_list`).
5. Reconstruct and report (`wb_session_dag`, `wb_prov_emit_r_script`, `wb_report_render_md`).
