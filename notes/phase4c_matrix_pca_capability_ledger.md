# Phase 4C matrix publication and parameter-bound space ledger

This ledger freezes the language-neutral ABI-v3 amendment agreed by Forge and
Quill before shared protocol bytes changed.  It is additive: documents that do
not use these capabilities retain their prior canonical bytes and identities.

## Manifest grants

- `publication_policies` declares `authenticated_add_or_replace_v1` for a
  matrix or space materialization.  The target identifier and overwrite flag
  are named parameters; publication is core-owned and spans the complete
  promotion group.
- A matrix materialization can declare `staged_matrix_fragments_v1`.  Its
  feature axis must exactly equal the source typed-slice feature axis and its
  cell fragments must form an ordered, gap-free partition of the source cell
  axis without crossing authenticated source-fragment boundaries.
- `parameter_axes` declares an integer parameter-derived axis.  The Phase 4C
  profile derives `PC1` through `PC<n_components>` and bounds the value by
  `min(cell_count - 1, feature_count - 1)` from one typed-slice grant.
- New dimension policies bind a space, feature-by-parameter table,
  one-row-per-parameter table, or singleton parameter echo to that exact axis.

## Request and receipt grants

- `materialization_publication_grant.v1` authenticates target, add/replace
  mode, conflict policy, complete promotion closure, transition source state,
  and either registry absence or the complete existing target preimage.
- `source_fragment_schedule.v1` authenticates logical source-fragment order,
  byte identity, and its contiguous span in the typed-slice cell axis.
- `matrix_fragment_grant.v1` binds the typed-slice grant, exact axes, fragment
  policy, source schedule, and output dimensions.
- `parameter_axis_grant.v1` binds normalized parameter value, computed bounds,
  labels, source axes, and label order.
- `matrix_fragment_manifest.v1` records every core-written part, its parent
  source fragment, exact span and axes, semantic content identity, and payload
  identity.  `observed_materialization_publication.v1` says only
  `validated_not_published`; a pack can never claim durable publication.

## Authority and atomicity

Packs receive typed readers and private typed writers, never a bundle, SQL
connection, registry handle, or arbitrary path.  All parts remain private
until their complete output and receipt closure passes.  Core revalidates the
target preimage and applies matrix/space registries, payloads, terminal
artifacts, provenance, and transition receipts through the existing promotion
transaction/workspace.  Failure preserves the exact old state and remains
retryable.  Python may attest the staged intent but cannot claim bundle
durability.

## Closed failures

Declaration errors use the existing manifest schema/semantic codes; source or
typed-slice identity drift is `PYBENCH_INPUT_IDENTITY_MISMATCH`; invalid axes,
fragments, values, or parameter-bound shapes are `PYBENCH_OUTPUT_INVALID`;
missing closure members are `PYBENCH_RECEIPT_MISMATCH`; undeclared stage files
are `PYBENCH_OUT_OF_SCOPE_MUTATION`; post-audit byte drift is
`PYBENCH_STALE_STAGING_IDENTITY`; and preimage/publication conflicts use
`PYBENCH_PUBLICATION_FAILED`.
