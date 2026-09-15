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
