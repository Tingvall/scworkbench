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

Run this before considering the change complete:

```r
wb_refresh_semantic_catalogs()
```

The command regenerates semantic docs/JSON, validates generated JSON, and fails
if the coverage audit detects a missing op, plot mapper, primitive constructor,
known table type, required parameter/recipe, or invalid graph edge.

## Done Criteria

- Primitive contracts are coherent.
- Extension-point contracts are coherent.
- Promotion works for produced primitives.
- Provenance/DAG remain valid.
- Semantic catalog audit passes via `wb_refresh_semantic_catalogs()`.
- No thin-client violations introduced.
