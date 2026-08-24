# scworkbench

For externally executed, dataset-specific terminal figures and reports, use
provenance-bound analysis capsules only after applying the installed op-first
decision law in `inst/onboarding/ANALYSIS_CAPSULES.md`. Ad hoc analysis is
permitted; unrecorded durable evidence is not.

`scworkbench` is an R engine for reproducible, disk-backed single-cell analysis.

The package is designed around portable analysis bundles, typed primitives,
explicit operations, promoted artifacts, and provenance. User interfaces,
scripts, notebooks, and agents should call exported engine APIs rather than
reimplementing storage, plotting, or analysis semantics.

## Status

This repository is under active development. Its public contracts are versioned
with the package; this statement does not imply CRAN or Bioconductor acceptance.

License: MIT. See [LICENSE.md](LICENSE.md).

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
inst/onboarding/           installed operator documentation
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
wb_op_interface("metadata_cell_vector", bundle = b)

s <- wb_session_new()
rr <- wb_session_run_op(
  session = s,
  bundle = b,
  op_name = "metadata_cell_vector",
  inputs = list(
    source_column = "dataset_id",
    vector_name = "dataset_id",
    value_type = "categorical",
    missing_policy = "error",
    cell_set = "all",
    min_cells = 1L
  )
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
- `wb_entity_certificate()`
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

## Documentation

The public documentation index and ownership policy are in
[docs/getting_started.md](docs/getting_started.md) and
[docs/source_ownership.md](docs/source_ownership.md). The short user path is:
open and validate a bundle, inspect an operation interface, run it in a
session, promote the terminal result, reopen, inspect lineage, then finalize
and audit a read-only recipient bundle.

The shipped, platform-agnostic onboarding library is available in a checkout
at [inst/onboarding](inst/onboarding), or after installation through
`system.file("onboarding", package = "scworkbench")`.

Independently distributed scientific operations can be explicitly activated
through the operation-pack v1 ABI. Installation is inert; see
[docs/operation_packs.md](docs/operation_packs.md) for trust, authoring,
provenance, recipient, and conformance semantics.
Protocol v1 structurally admits R packages and Python distributions. The
current runtime activates R packs; Python activation remains a typed
runtime-unavailable boundary until the audited PyBench integration is present.

Contribution, support, and composite-release policies are documented in
[docs/CONTRIBUTING.md](docs/CONTRIBUTING.md),
[docs/SUPPORT.md](docs/SUPPORT.md), and
[docs/release_process.md](docs/release_process.md).

## Testing

Run the canonical package contract suite. It generates a disposable golden
bundle unless `--bundle=/path/to/bundle` is supplied, sources every top-level
`tests/test_*.R` contract definition, discovers every top-level `test_*`
function, and executes each exactly once. Tests with a first `bundle_dir`
argument receive an isolated copy of the baseline bundle. The runner rejects
duplicate names, unsupported required arguments, empty test files, and stale
intentional exclusions, then prints discovered/executed/passed/skipped/failed/
excluded accounting:

```sh
Rscript inst/tests/run_contract_tests.R
```

Run a specific contract test:

```sh
Rscript -e 'devtools::load_all(".", quiet = TRUE); source("tests/test_public_api_boundary_contract.R"); stopifnot(test_public_api_boundary_contract())'
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
inst/fullstack/check_fullstack_contracts.sh
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

See [docs/extension_engineering.md](docs/extension_engineering.md) for the detailed rules.

## Known Caveats

- Some optional capabilities depend on suggested packages such as `BPCells`,
  `RANN`, and `UCell`.
- Large matrices must be accessed through getters/chunk-aware ops; avoid
  materializing whole matrices in new code.
- Generated semantic docs and graph SVG/DOT files can change substantially
  after catalog refreshes.
