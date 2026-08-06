# Sessions and operations

Inspect an operation first, then place every operation argument inside the
single `inputs` list. Session results are staged computation until promotion.

```r
wb_op_interface("cells_counts_by", bundle = b)
s <- wb_session_new()
result <- wb_session_run_op(
  session = s,
  bundle = b,
  op_name = "cells_counts_by",
  inputs = list(cell_set = "all", column = "dataset_id")
)
s <- result$session
wb_session_dag(s, bundle = b, include_active = TRUE)
```

For interruption-safe work, create a durable session with `wb_session_create()`
and resume it with `wb_session_resume()`. Durable state validates its source
identity before continuing.
