# Agent Engineer Onboarding

Role: extend and stabilize engine + thin clients.

## Responsibilities

- Add/maintain ops, wranglers, selectors, identity-card issuers, navigation
  resolvers, and contracts.
- Keep clients thin and engine-first.
- Prevent stale/duplicate code paths.
- Harden provenance/replay/deletion safety.
- In current phase: prioritize hardening/bugfixing before feature additions (see `docs/next_pass_hardening_notes.md`).

## Development Rules

1. Contract-first changes
- Define primitive IO and op interface before implementation.
- Register ops in one canonical place.

2. One-path policy
- There should be one canonical way to add ops/wranglers.
- Avoid parallel implementations of same behavior.
- New extensibility surfaces should follow registry/contract patterns, not one-off
  special cases.
- Follow `docs/source_ownership.md`: every runtime function and SQLite table
  constructor has one canonical source owner, and generated references never
  contain manual runtime implementations.

3. Thin-client compliance
- Client collects inputs and renders outputs.
- Client must not replicate engine decision logic.
- Plot compatibility, identity-card semantics, and navigation/handoff logic belong
  in the engine.

4. Test discipline
- Add/extend contract tests for each new capability.
- Validate on real bundle smoke runs.

5. Mutation safety
- Provide plan APIs for destructive actions.
- Require explicit recursive/force semantics where relevant.
- Treat an opened bundle as committed state. Mutating `wb_op_*` implementations,
  registry writers, and matrix/space/model payload writers do not accept direct
  committed calls. Run registered analysis with `wb_session_run_op()` (or
  `wb_client_run()`) and commit it with `wb_session_promote_current()` (or
  `wb_client_promote()`).
- Use `wb_attach_apply()`, `wb_ingest_apply()`, or `wb_bundle_from_*()` only for
  declared ingestion. The handle returned by `wb_init_bundle()` is the bounded
  assembly transaction; reopening that path returns a committed handle and does
  not restore low-level writer authority.
- Do not emulate engine authority with options or flags. The writer capability
  is package-private, connection-bound, and dynamically scoped to the registered
  runner, promotion, or ingestion transaction.
- Dense-space code must cross the central payload resolver/writer boundary.
  SQLite stores registry and provenance rows, while contained HDF5 files store
  coordinates. Consumers use `wb_space()` so partial row/dimension requests
  remain bounded; no operation may restore a relational coordinate writer.

## Standard Engineer Loop

1. Inspect existing contract (`wb_op_interface`, relevant wrangler contracts).
2. Implement engine change.
3. Add tests.
4. Smoke-run on bundle.
5. Update client only if needed (thin adapter only).
6. Update semantic catalogs and docs.
7. Run `wb_refresh_semantic_catalogs()` and fix any audit failure.

## Long-running operation safety

`wb_session_run_op()` returns a list containing `session`, `run`, and `result`.
`run` is a structured `wb_run`, not a `data.frame` or `data.table`: do not
coerce or serialize it wholesale while a result is still staged. For expensive
work, retain `session <- result$session` immediately and promote the intended
terminal output(s) before writing reports, JSON, CSV, plots, identity cards,
or diagnostics. Before promotion, extract only stable scalar IDs if needed and
inspect staged entities with documented session interfaces such as
`wb_session_view(session)`.

```r
session <- wb_session_new()
result <- wb_session_run_op(
  session, bundle, "hvg_select",
  inputs = list(matrix = "RNA_counts", n_features = 2000L)
)
session <- result$session

promotion <- wb_session_promote_current(
  bundle, session, outputs = "selected_features",
  created_by = "operator"
)

# Only after promotion: inspect durable artifacts and emit reports/exports.
artifacts <- wb_art_list(bundle)
run_details <- wb_prov_run_details(bundle, result$run$run_id)
```

Use `wb_op_interface()` to select valid terminal `outputs=` values. Promotion
commits the required provenance closure; staged session state is ephemeral if
the R process exits.

Targeted reproduction uses a narrower public executor. Generate a plan with
`wb_target_reproduction_plan()`, emit it with `wb_target_emit_r_script()`, and
run the script against a separate source-only writable clone. Generated code
must contain no private namespace access. `wb_target_execute_plan()` owns
preflight, topological staged execution, pre-promotion semantic/loadability
verification, and one observable-atomic promotion commit containing the
selected outputs and complete durable replay-equivalence receipt set.

Manifest schema 2.3 separates immutable `creation` identity from authoritative
`current_state`. Successful outermost writer scopes publish a flushed,
validated same-filesystem temporary JSON file with one atomic rename before
releasing the writer lock. `wb_manifest(bundle)` is the durable view;
`wb_manifest(bundle, view = "reconstructed")` is explicitly diagnostic.
Feature summaries use `counts$feature_registry_records` and the deterministic
`counts$feature_counts_by_matrix` map. There is no bundle-level biological
`n_features`; `counts$bundle_unique_feature_count` explains why cross-matrix
identities cannot be deduplicated safely.

Before distributing a bundle, call
`wb_bundle_validation_report(path, level = "recipient")`. Content validation
recomputes persisted run and typed content-identity contracts; recipient adds
finalized-transfer and byte-nonmutation invariants. Do not describe
`structural` as content integrity. An untagged legacy digest is explicitly
unverifiable, and an active non-empty SQLite WAL fails closed because opening it
by path can mutate shared-memory lock bytes. See
`docs/bundle_integrity_validation.md` for the proof taxonomy and diagnostic
contract.

When the change is not an op, map it to the right surface first:

- new compute -> op
- new display normalization -> wrangler / plot mapper
- new human summary -> identity-card issuer
- new cross-surface handoff -> navigation contract
- new storage access path -> getter only

## Semantic Catalog Discipline

Semantic catalogs are not optional documentation. Agents and planning helpers use
them to discover engine capabilities.

When adding or changing a surface, update the corresponding semantic contract:

- ops: op interface and generated op catalog
- getters: getter semantic catalog
- plot mappers: plot/wrangler semantic catalogs
- primitives: primitive catalog and promotion coverage
- promoted table outputs: artifact type catalog / known table-type coverage
- recurring parameters: parameter semantics catalog
- reusable workflows: recipe semantics catalog
- scientific mutation ownership: mutation route catalog

Run this before considering the change complete:

```r
wb_refresh_semantic_catalogs()
```

The command regenerates semantic docs/JSON, validates generated JSON, and fails
if the coverage audit detects a missing op, plot mapper, primitive constructor,
known table type, required parameter/recipe, or invalid graph edge.

`wb_mutation_catalog_semantic()` separately inventories every exported
`wb_op_*`, registry writer, matrix/space/model writer, attachment API, and
  primitive payload writer. Its invariant requires exactly one supported
provenance-producing route for each meaningful public transformation.

## Done Criteria

- Primitive contracts are coherent.
- Extension-point contracts are coherent.
- Promotion works for produced primitives.
- Provenance/DAG remain valid.
- Semantic catalog audit passes via `wb_refresh_semantic_catalogs()`.
- No thin-client violations introduced.
# RNG and administrative identifiers

Scientific RNG parameters control numerical methods only. Administrative
identifiers and ownership tokens use operating-system cryptographic entropy,
do not touch `.Random.seed`, and are collision-checked with bounded retries.
Never call `set.seed()` merely to obtain a different run, artifact, snapshot,
commit, payload, or lock identity. Entropy failure, collision exhaustion, and
conflicting explicit identities fail with the typed diagnostics documented in
`docs/sessions_and_ops.md` and leave the operation retryable.
