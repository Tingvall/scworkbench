# Typed named-cell-set consumption

A durable named cell set is a scientific input, not only a convenient selector.
For every successful operation using a named analysis universe, group,
membership, query, candidate, or endpoint set, the engine records a typed
`cell_set -> run` `CONSUMES` binding. This applies to core operations and to
explicitly activated operation-pack operations because both contribute to the
same merged operation catalog and executor.

The binding preserves the catalog parameter role and canonical durable set ID.
Its versioned resolution record authenticates two related facts without
embedding a large cell-ID vector:

- source membership: sorted-cell-ID SHA-256 and count for the declared durable
  set;
- effective membership: sorted-cell-ID SHA-256 and count after intersection
  with the operation's effective cell universe when that parameter type has
  intersection semantics.

`cell_ids_or_set` scalar named-set values and named `cell_set` controls are
typed dependencies. Explicit ad hoc cell-ID vectors remain literal inputs and
do not create a durable set edge. A `list_or_cell_set` endpoint descriptor
records its nested `cell_set` while an explicit `cells`, `cell_ids`, or `x`/`y`
descriptor does not.

Inspect persisted evidence with `wb_prov_run_details()`,
`wb_prov_bundle_dag()`, `wb_prov_artifact_lineage()`, and
`wb_entity_certificate()` for either the run or the `cell_set`. Binding roles
remain visible on graph edges and certificate relationships.

Strict replay and target reproduction verify the recorded source-membership
identity against the destination before execution or publication. A missing
set fails with `CELL_SET_RESOLUTION_REQUIRED`; a same-name set with different
membership fails with `CELL_SET_RESOLUTION_MISMATCH`. Deep/content validation
also reports stable `RUN_NAMED_CELL_SET_*` diagnostics for missing, mis-roled,
wrong-set, mismatched, stale, dangling, or fabricated bindings.

Historical snapshots written before provenance schema 1.10 are not rewritten.
They remain inspectable at their original assurance boundary, but absence of
typed cell-set edges in those snapshots is not upgraded into proof of exact
selection ancestry.
