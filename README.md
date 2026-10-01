# scworkbench

Portable, provenance-bound analysis with a small core engine and independently
installed scientific operation packs. Start with the
[documentation index](docs/getting_started.md) or the installed
[system overview](inst/onboarding/SYSTEM_OVERVIEW.md).

| Goal | Documentation |
| --- | --- |
| Analyse data | [Operator onboarding](inst/onboarding/AGENT_OPERATOR_GUIDE.md) |
| Install and activate the seven-pack profile | [Standard profile](inst/standard_profile/README.md) |
| Build a new operation pack | [SDK tutorial](docs/operation_pack_sdk.md) |
| Change an engine capability | [Extension engineering](docs/extension_engineering.md) |
| Inspect a transferred bundle | [Recipient audit](docs/recipient_audit.md) |

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

Operation-pack authors: start with the [installed Operation Pack SDK](docs/operation_pack_sdk.md).
Declare typed inputs/outputs, request readers, compute and emit primitives;
core owns authentication, alignment and atomic publication.

## Core Ideas

- **Bundle**: portable analysis unit containing SQLite metadata, matrix/space
  payloads, cell sets, artifacts, reports, models, and provenance.
- **Getters**: the storage boundary. Ops, wranglers, clients, and agents should
  use getters instead of direct SQL/storage access.
- **Selectors**: composable cell-selection recipes over bundle state.
- **Primitives**: typed internal currency, including `matrix`, `space`,
  `space_2d`, `cell_vector`, `cell_vector_family`, `relation_family`,
  `feature_table`, `obs_table`, `model_ref`, `path_2d_family`, and `space_path_family`.
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
inst/sdk/operation-packs/  author guide, templates, capabilities, and lifecycle tests
inst/standard_profile/     source lock, installer, and explicit activation
src/                      native scaffold support; source installation needs a C toolchain
inst/golden_bundle/        generated tiny cross-repo fixture
inst/fullstack/            cross-repo contract check script
containers/                container build recipes
man/                       generated R documentation
AGENTS.md                  standing instructions for coding agents
```

Generated local analysis outputs and scratch scripts are intentionally ignored
by git (`reports/`, `scripts/`, container `.sif` files).

## Quick Start For Developers

This section is for engine source development. Pack authors should instead use
an installed scworkbench and the SDK tutorial; analysts should follow the
operator guide and explicitly activate required packs. Source loading is not
profile activation or a production installation.

Work from the repository root:

```r
devtools::load_all(".", quiet = TRUE)
```

Open a bundle:

```r
b <- wb_open_bundle("/path/to/bundle")
# Close with wb_close_bundle(b) when finished. In a function, use on.exit().
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

See `docs/getter_catalog_reference.md` and `docs/mutation_catalog_reference.md`
for the generated public function maps.

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
through the operation-pack ABI. Installation is inert; see
[docs/operation_packs.md](docs/operation_packs.md) for trust, authoring,
provenance, recipient, and conformance semantics.
Protocols v1, v2, and v3 admit R packages and Python distributions. The
no-pack core exposes exactly five operations: `feature_set_import`,
`feature_set_namespace_transfer`, `cell_set_derive`, `metadata_cell_vector`,
and `slingshot_adopt`. The optional, explicitly activated
[standard profile](inst/standard_profile/README.md) installs seven pinned R
packs and exposes 61 normal operations (five core and 56 packed). R packs
activate in-process; Python packs activate explicitly through the configured
PyBench interpreter and then execute through the same catalog, session,
promotion, provenance, replay, and recipient contracts.

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

To run an auditable focused subset, repeat `--test-file=` with repository test
paths (or basenames relative to `tests/`):

```bash
Rscript inst/tests/run_contract_tests.R \
  --test-file=tests/test_documentation_source_package_curation_contract.R \
  --test-file=tests/test_analysis_capsule_documentation_policy_contract.R
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

Scientific method tests belong to their pack; core tests cover generic engine
authority, and explicitly invoked pinned composites cover real-pack integration.
Use focused selections for narrow changes. Run complete qualification on the
frozen integration candidate rather than repeating it after each prose fix.
Report skips and retained parent evidence separately from current-tree passes.

## Golden Bundle

Generate the small cross-repo fixture:

```sh
Rscript inst/golden_bundle/create_golden_bundle.R /tmp/scwb_golden
```

The golden bundle is generated, not source-controlled as a mutable working
bundle. The publication fullstack gate uses it to verify the core
`scworkbench`/`pybench` boundary. Optional clients may consume the same public
contracts in their own explicitly invoked qualification.

## Cross-Repo Boundaries

`scworkbench` owns:

- bundle schema and migrations
- primitive and artifact semantics
- getter, selector, op, wrangler, and plot contracts
- provenance and promotion semantics
- semantic catalog and KG export semantics

External repositories may consume those contracts as optional clients or peer
runtimes:

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
