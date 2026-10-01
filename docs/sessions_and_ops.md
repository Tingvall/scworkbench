# Sessions and operations

Inspect an operation first, then place every operation argument inside the
single `inputs` list. Session results are staged computation until promotion.

Install and explicitly activate the required pack before inspecting or running
a packed operation. Use its qualified catalog name, not a guessed legacy alias.
This example uses a core operation and an opened bundle with `dataset_id`:

```r
wb_op_interface("metadata_cell_vector", bundle = b)
s <- wb_session_new()
result <- wb_session_run_op(
  session = s,
  bundle = b,
  op_name = "metadata_cell_vector",
  inputs = list(source_column = "dataset_id", vector_name = "dataset_id",
                value_type = "categorical", missing_policy = "error",
                cell_set = "all", min_cells = 1L)
)
s <- result$session
wb_session_dag(s, bundle = b, include_active = TRUE)
```

Use `wb_session_new()` only when the chain is bounded and cheaply repeatable.
For scVI, PeakVI, large embeddings, and other expensive or long-running work,
create a durable session with `wb_session_create()` in a machine-persistent
workspace and resume it with `wb_session_resume()`. Every successful operation
is checkpointed before the next operation. Durable state validates its source
and staged payload identities before continuing. A detached service protects a
process from terminal closure, but is not a durable scworkbench checkpoint.

Use `wb_op_interface()` to inspect typed inputs, effective defaults, terminal
names, and chunking metadata. Registry changes and linked model/output closures
must use the declared publication group. Never bypass registered dispatch with
a direct mutating `wb_op_*` call or pack runner. For authoring, see the
[SDK tutorial](operation_pack_sdk.md); callbacks are issued by the engine.

`wb_prov_run_details()` is the exact stored JSON-shaped inspection view.
`wb_prov_run_replay_inputs()` is the operation-aware typed view for executing a
recorded run or constructing a sibling. It preserves symbolic references and
reports historical ambiguity or installed-contract incompatibility explicitly.

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
