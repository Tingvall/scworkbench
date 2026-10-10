# scworkbench Primitive Catalog

<!-- Generated from wb_primitive_catalog_semantic(); do not edit entries by hand. -->

Primitive count: 12

### `graph`

Constructor: `wb_prim_graph`

Title: Standalone Graph

Description: Ordered domain-neutral nodes, edges, incidences and typed attributes with optional independently authenticated multi-axis associations.

Shape: ordered NEI components, typed attributes, separate bindings

Payload level: payload/bounded SQLite stage

Promotable: TRUE

Use when:
- retain ordinary graphs or hypergraphs
- stream graph components independently of cell axes

### `matrix`

Constructor: `wb_prim_matrix`

Title: Matrix Reference

Description: Symbolic reference to a feature-by-cell matrix stored in the bundle.

Shape: matrix_id

Payload level: reference

Promotable: FALSE

Use when:
- select expression/accessibility matrix
- pass matrix identity to ops

### `space`

Constructor: `wb_prim_space`

Title: Space Reference

Description: Symbolic reference to a cell embedding or latent space stored in the bundle.

Shape: space_id

Payload level: reference

Promotable: FALSE

Use when:
- select latent/embedding space for ops

### `space_2d`

Constructor: `wb_prim_space_2d`

Title: 2D Space Reference

Description: Reference to a two-dimensional cell space, typically UMAP-like coordinates.

Shape: space_id or table with cell_id/x/y

Payload level: reference/table

Promotable: TRUE

Use when:
- plot cells in 2D
- overlay scores or sets

### `cell_vector`

Constructor: `wb_prim_cell_vector`

Title: Cell Vector

Description: One value per cell, continuous or categorical.

Shape: cell_id, value, value_type

Payload level: payload

Promotable: TRUE

Use when:
- store pseudotime
- store labels
- store per-cell scores

### `cell_vector_family`

Constructor: `wb_prim_cell_vector_family`

Title: Cell Vector Family

Description: Long-form collection of keyed per-cell vectors.

Shape: key, cell_id, value, value_type

Payload level: payload

Promotable: TRUE

Use when:
- store UCell signatures
- store chromVAR motif scores
- store per-lineage or per-feature vectors

### `relation_family`

Constructor: `wb_prim_relation_family`

Title: Relation Family

Description: Sparse long-form cell-to-key relations with optional weights, values, or distances.

Shape: key, cell_id, optional weight/value/distance

Payload level: payload

Promotable: TRUE

Use when:
- store branch membership
- store fuzzy assignments
- store edge-like relations

### `feature_table`

Constructor: `wb_prim_feature_table`

Title: Feature Table

Description: Data frame where rows are feature-centric results such as genes, peaks, or markers.

Shape: table with feature_id plus table_type

Payload level: payload

Promotable: TRUE

Use when:
- store DE tables
- store marker tables
- store feature trend results

### `obs_table`

Constructor: `wb_prim_obs_table`

Title: Observation Table

Description: Generic observation-style data frame specialized by table_type and entity_kind.

Shape: table plus table_type/entity_kind

Payload level: payload

Promotable: TRUE

Use when:
- store summaries
- store trajectory curves
- store pathway results
- store dynamics tables

### `model_ref`

Constructor: `wb_prim_model_ref`

Title: Model Reference

Description: Reference to a stored model artifact and the spaces it maps between.

Shape: engine, model_space_id, in_space_id, artifact_id

Payload level: reference

Promotable: TRUE

Use when:
- store projection models
- project new data into fitted space

### `path_2d_family`

Constructor: `wb_prim_path_2d_family`

Title: 2D Path Family

Description: Lineage or curve coordinates in a 2D plotting space.

Shape: key, point, x, y

Payload level: payload

Promotable: TRUE

Use when:
- draw trajectory curves on UMAP
- inspect fitted lineages

### `space_path_family`

Constructor: `wb_prim_space_path_family`

Title: High-Dimensional Space Path Family

Description: Curves in an arbitrary-dimensional bundle space, represented point-by-dimension.

Shape: space_id, path_id, point, dim, value

Payload level: payload

Promotable: TRUE

Use when:
- represent checkpoint paths
- score cells against high-dimensional trajectories
