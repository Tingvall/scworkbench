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

## Scientific RNG and administrative identity

Operation parameters such as `seed`, `random_seed`, `bootstrap_seed`, and
`permutation_seed` control numerical methods only. They cannot influence run,
session, snapshot, commit, artifact, fragment, registry-event, replay-result,
payload-path, lock, workspace, savepoint, or pending-publication identifiers.
Identifier allocation uses operating-system cryptographic entropy and neither
reads nor changes `.Random.seed`; operators must never perturb RNG state to
avoid an identifier collision.

Every durable identifier is checked in its authoritative registry and retried
with a strict bound before it becomes observable. A secure-entropy failure
raises `SCWORKBENCH_IDENTIFIER_ENTROPY_UNAVAILABLE`; exhausted collisions raise
`SCWORKBENCH_IDENTIFIER_COLLISION_EXHAUSTED`; a conflicting explicit internal
identifier raises `SCWORKBENCH_IDENTIFIER_CONFLICT`. These failures occur
before scientific execution or are contained by the owning transaction, so
retry does not require bundle repair.
