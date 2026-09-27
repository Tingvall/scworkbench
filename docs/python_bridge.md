# Python bridge

Python-backed operations use protocol v2 and stage declared outputs before the
R engine validates and publishes them. The authoritative machine-readable
protocol resource is shipped with the package:

```r
system.file("protocol/pybench-op-v2.schema.json", package = "scworkbench")
```

Use registered operations such as `scwblatent::scvi_train` through
`wb_session_run_op()`; that operation uses the ABI-v3 pack boundary, not the
historical core bridge. For all operations, do not write protocol payloads or
artifact registry rows directly.
