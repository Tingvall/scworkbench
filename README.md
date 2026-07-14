# scworkbench

`scworkbench` is an R engine for reproducible, disk-backed single-cell analysis.

The package is designed around portable analysis bundles, typed primitives,
explicit operations, promoted artifacts, and provenance. User interfaces,
scripts, notebooks, and agents should call exported engine APIs rather than
reimplementing storage, plotting, or analysis semantics.

## Status

This repository is under active development. Contracts are increasingly stable,
but the package is not yet a polished public release.

License: MIT. See `LICENSE.md`.

## Core Ideas

- **Bundle**: portable analysis unit containing SQLite metadata, matrix/space
  payloads, cell sets, artifacts, reports, models, and provenance.
- **Getters**: the storage boundary. Ops, wranglers, clients, and agents should
  use getters instead of direct SQL/storage access.
- **Selectors**: composable cell-selection recipes over bundle state.
- **Primitives**: typed internal currency, including `matrix`, `space`,
  `space_2d`, `cell_vector`, `cell_vector_family`, `feature_table`,
  `obs_table`, `model_ref`, and `path_2d_family`.
- **Ops**: explicit analysis operations with declared inputs, parameters,
  outputs, promotable artifacts, and provenance.
- **Wranglers and plot contracts**: renderer-independent display datasets.
- **Promotion and provenance**: exploratory session outputs can be selectively
  promoted into durable artifacts with inspectable lineage.
- **Semantic catalogs and KG export**: machine-readable records for ops,
  getters, wranglers, artifacts, primitives, recipes, and compatibility edges.

## Repository Layout

```text
R/                         R package source
tests/                     focused contract and smoke tests
docs/                      contract docs, semantic catalogs, graph exports
inst/foundation_contracts.md
                           stable foundation contracts
inst/golden_bundle/        generated tiny cross-repo fixture
inst/fullstack/            cross-repo contract check script
containers/                container build recipes
man/                       generated R documentation
AGENTS.md                  standing instructions for coding agents
```

Generated local analysis outputs and scratch scripts are intentionally ignored
by git (`reports/`, `scripts/`, container `.sif` files).

## Quick Start For Developers

Work from the repository root:

```r
devtools::load_all(".", quiet = TRUE)
```

Open a bundle:

```r
b <- wb_open_bundle("/path/to/bundle")
on.exit(wb_close_bundle(b), add = TRUE)
```

Inspect core state:

```r
wb_status(b)
wb_matrices(b)
wb_spaces(b)
wb_cell_sets(b)
wb_art_list(b)
```

Inspect and run an operation:

```r
wb_list_ops()
wb_op_interface("trajectory_geneset_dynamics", bundle = b)

s <- wb_session_new()
rr <- wb_session_run_op(
  session = s,
  bundle = b,
  op_name = "cells_counts_by",
  inputs = list(cell_set = "all", column = "dataset_id")
)
```

Promote selected session output:

```r
wb_session_promote_current(
  bundle = b,
  session = rr$session,
  name_prefix = "example",
  created_by = "developer",
  fail_fast = TRUE
)
```

## Important Public Surfaces

Bundle lifecycle:

- `wb_open_bundle()`
- `wb_close_bundle()`
- `wb_validate_bundle()`
- `wb_manifest()`

Core getters:

- `wb_cells()`
- `wb_meta()`
- `wb_matrices()`
- `wb_matrix()`
- `wb_spaces()`
- `wb_space()`
- `wb_feature_sets()`

Selectors:

- `wb_sel_all()`
- `wb_sel_set()`
- `wb_sel_meta()`
- `wb_sel_expr()`
- `wb_sel_vector()`
- `wb_sel_vector_family()`

Ops and sessions:

- `wb_list_ops()`
- `wb_op_interface()`
- `wb_session_new()`
- `wb_session_run_op()`
- `wb_session_promote_current()`

Artifacts and provenance:

- `wb_art_list()`
- `wb_art_load()`
- `wb_art_identity_card()`
- `wb_art_birth_certificate()`
- `wb_prov_bundle_dag()`
- `wb_prov_artifact_lineage()`

Semantic/KG:

- `wb_refresh_semantic_catalogs()`
- `wb_semantic_catalog()`
- `wb_semantic_catalog_audit()`
- `wb_kg_export_jsonl()`
- `wb_kg_export_neo4j_csv()`
- `wb_kg_catalog_audit()`

See `docs/exported_functions_overview.md` for a broader function map.

## Contract References

Start here:

- `inst/onboarding/README.md`: shipped onboarding library for any agent or
  computational operator. After installation, obtain it with
  `system.file("onboarding", package = "scworkbench")`.
- `AGENTS.md`: engine guardrails and coding-agent brief.
- `docs/contracts.md`: cross-repo contract index.
- `inst/foundation_contracts.md`: bundle/getter/selector foundation contracts.
- `docs/engine_extension_patterns.md`: how to add ops, wranglers, getters,
  navigation, and semantic records.
- `docs/primitive_catalog_reference.md`: primitive contracts.
- `docs/artifact_type_catalog_reference.md`: artifact type contracts.
- `docs/op_catalog_reference.md`: operation catalog reference.
- `docs/getter_catalog_reference.md`: getter catalog reference.
- `docs/wrangler_catalog_reference.md` and `docs/plot_catalog_reference.md`:
  plot/wrangler contracts.
- `docs/semantic_catalog_reference.md`: unified semantic search/planning
  catalog.

## Testing

Run the canonical package contract suite. It generates a disposable golden
bundle unless `--bundle=/path/to/bundle` is supplied, sources every top-level
`tests/test_*.R` contract definition, and then runs the canonical suite:

```sh
Rscript inst/tests/run_contract_tests.R
```

Run a specific contract test:

```sh
Rscript -e 'devtools::load_all(".", quiet = TRUE); source("tests/test_knowledge_graph_contract.R"); stopifnot(test_knowledge_graph_contract())'
```

Refresh semantic catalogs after changing ops, getters, wranglers, primitive
types, artifact types, recipes, or parameter semantics:

```sh
Rscript -e 'devtools::load_all(".", quiet = TRUE); wb_refresh_semantic_catalogs(docs_dir = "docs")'
```

Check package diff hygiene:

```sh
git diff --check
```

Cross-repo fullstack tripwire:

```sh
/home/dirk/Projects/lymphocyte_trajectory/coordination/scripts/check_fullstack_contracts.sh
```

The fullstack script is a contract tripwire, not a replacement for focused
package tests.

## Golden Bundle

Generate the small cross-repo fixture:

```sh
Rscript inst/golden_bundle/create_golden_bundle.R /tmp/scwb_golden
```

The golden bundle is generated, not source-controlled as a mutable working
bundle. It is used to verify core assumptions across `scworkbench`, `pybench`,
`scworkbenchShiny`, and `scwb-agent`.

## Cross-Repo Boundaries

`scworkbench` owns:

- bundle schema and migrations
- primitive and artifact semantics
- getter, selector, op, wrangler, and plot contracts
- provenance and promotion semantics
- semantic catalog and KG export semantics

Sibling repositories consume those contracts:

- `scworkbenchShiny`: thin UI/client.
- `pybench`: Python peer runtime for bundle-compatible Python-native methods.
- `scwb-agent`: typed agent harness and KG/runtime consumer.

Consumers should not redefine engine semantics locally.

## Adding A New Engine Capability

Use the existing extension pattern:

1. Add or update the `wb_op_*()` / getter / wrangler implementation.
2. Register the public contract in the canonical catalog, usually
   `R/op_catalog.R` for ops.
3. Add focused contract tests.
4. Update relevant docs.
5. Refresh semantic catalogs with `wb_refresh_semantic_catalogs()`.
6. Run focused tests and `git diff --check`.
7. Create a coordination handoff for contract-adjacent changes.

See `docs/engine_extension_patterns.md` for the detailed rules.

## Known Caveats

- License is not finalized.
- The package is research infrastructure, not a CRAN-ready release.
- Some optional capabilities depend on suggested packages such as `BPCells`,
  `RANN`, and `UCell`.
- Large matrices must be accessed through getters/chunk-aware ops; avoid
  materializing whole matrices in new code.
- Generated semantic docs and graph SVG/DOT files can change substantially
  after catalog refreshes.
