# Metadata Cell-Vector Diagnostics

Imported cell metadata stays in the bundle and is accessed through the getter
boundary. Use `metadata_cell_vector` when a metadata field must participate in
the typed vector, plotting, promotion, or association contracts.

```r
s <- wb_session_new()
perturbation <- wb_session_run_op(
  s, b, "metadata_cell_vector",
  inputs = list(
    source_column = "perturbation", vector_name = "perturbation",
    value_type = "categorical", missing_policy = "error", cell_set = "analysis"
  )
)
s <- perturbation$session

wb_operation_pack_load("scwbStatistics")

lane <- wb_session_run_op(
  s, b, "metadata_cell_vector",
  inputs = list(
    source_column = "X10X_lane", vector_name = "lane",
    value_type = "auto", missing_policy = "as_category", cell_set = "analysis"
  )
)
s <- lane$session

balance <- wb_session_run_op(
  s, b, "scwbstatistics::cell_vector_association",
  inputs = list(
    a = wb_ref_run(perturbation$run$run_id, "vector"),
    b = wb_ref_run(lane$run$run_id, "vector"),
    cell_set = "analysis", method = "auto"
  )
)
s <- balance$session

wb_session_promote_current(
  b, s,
  outputs = list(
    wb_ref_run(perturbation$run$run_id, "vector"),
    wb_ref_run(lane$run$run_id, "vector"),
    wb_ref_run(balance$run$run_id, "summary"),
    wb_ref_run(balance$run$run_id, "detail")
  )
)
```

`value_type = "auto"` only treats native numeric metadata as continuous; all
other columns are categorical, and the recorded run parameters retain that
decision. Missing values must be handled explicitly: fail, drop those cells,
or replace categorical missing values with `missing_label`. `vector_name` is
the promoted artifact name; collisions are rejected unless `overwrite = TRUE`,
which creates a new immutable artifact rather than mutating prior provenance.

`scwbstatistics::cell_vector_association` dispatches categorical × categorical inputs to a
contingency diagnostic with chi-square/Fisher selection, Cramér's V, and
expected-count checks. Continuous × categorical retains the established
Kruskal/ANOVA and eta-squared summary. Continuous × continuous emits Pearson
and Spearman correlation summaries. Promoted vectors work with the existing
`embedding_overlay`, `violin`, and categorical count plot contracts; no
metadata-specific plotting path is required.

## Getter values and exact identifiers

| Call | Returned value / identifier |
| --- | --- |
| `wb_cell_sets(b)` | Character vector of set names, not rows with membership columns. |
| `wb_cells(b, cell_set="set:high_score")` | Character vector of member cell IDs; pass an exact name from `wb_cell_sets()`. |
| `wb_metadata_fields(b)` | Data frame of field definitions; these are metadata identities, not vector IDs. |
| `wb_meta(b, cols=c("cell_id", "score"))` | Metadata data frame. |
| `wb_list_cell_vectors(b)` | Data frame; its `vector_id` is an exact `artifact:<id>` reference (session outputs use `session:<run_id>:<output>`). |
| `wb_cell_vector_load(b, vector_id=id)` | Typed primitive; inspect `cell_id`, `value`, and `value_type`. |
| `wb_read_cell_vector(b, id, cell_ids=cells)` | Named numeric/character vector aligned to requested cells. Separate legacy DB vector IDs remain supported here. |
| `wb_vector(b, matrix_id="counts", feature_id="g1")` | Named numeric feature vector from a matrix; this is not the cell-vector artifact loader. |
| `wb_art_load(b, artifact_id, expected_kind="obs_table")$table` | Data frame for a table artifact. Use `expected_kind="feature_table"` for feature tables. |

A metadata field `score`, artifact display name `score_vector`, bare artifact
ID, and `artifact:<id>` vector reference are distinct. Inspect the relevant
registry instead of guessing a conversion. To use metadata as a typed vector,
run `metadata_cell_vector`; to inspect metadata directly, use `wb_meta()`.
Neither `wb_cell_sets()` nor a loaded primitive is a membership data frame.
See the executable [continuation example](../inst/examples/public_getters_and_continuation.R)
for actual signatures, returned types and a fresh session after promotion.
