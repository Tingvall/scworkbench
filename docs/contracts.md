# scworkbench Cross-Repo Contract Index

`scworkbench` is the contract authority for the full stack.

Sibling repositories consume these contracts; they should not redefine engine
semantics locally.

## Canonical Boundaries

- `scworkbench`: engine, bundle schema, getters, selectors, primitives, ops,
  artifacts, provenance, promotion, plot contracts, navigation, semantic
  catalogs.
- `scworkbenchShiny`: thin Shiny client for input collection, orchestration, and
  rendering.
- `pybench`: Python-native peer runtime that reads and writes bundle-compatible
  primitive payloads.
- `scwb-agent`: typed LLM orchestration harness over exported engine contracts.

## Core Contract References

- Engine identity and guardrails: `AGENTS.md`
- Shared foundation: `docs/agent_shared_foundation.md`
- Stable foundation contracts: `inst/foundation_contracts.md`
- Extension rules: `docs/engine_extension_patterns.md`
- Exported surface map: `docs/exported_functions_overview.md`
- Bundle ingest and assembly: `docs/staged_bundle_assembly_draft.md`
- Primitive contracts: `docs/primitive_catalog_reference.md`
- Artifact type contracts: `docs/artifact_type_catalog_reference.md`
- Getter contracts: `docs/getter_catalog_reference.md`
- Op contracts: `docs/op_catalog_reference.md`
- Plot and wrangler contracts: `docs/plot_catalog_reference.md`,
  `docs/wrangler_catalog_reference.md`
- Navigation contract: `docs/navigation_contract_draft.md`
- Semantic catalog: `docs/semantic_catalog_reference.md`,
  `docs/semantic_catalog.json`
- Knowledge graph export: `R/knowledge_graph.R`
- R/Python integration: `docs/pybench_integration_contract.md`,
  `docs/pybench_op_protocol_v1.md`, `docs/pybench_parity_map.md`

## Consumer Repo Rules

### Shiny

The Shiny app must remain a thin client. It may collect inputs, call engine APIs,
render primitive/artifact outputs, and present confirmation UI. It must not own
compute semantics, plot compatibility, artifact dependency planning, or
provenance rules.

Primary consumer reference:

- `../scworkbenchShiny/docs/agent_client_brief.md`

### pybench

`pybench` is a peer compute runtime sharing the bundle contract. It may read
bundle inputs and write primitive payloads directly when those payloads load
through current R `wb_art_load()` without special-case handling. R remains the
authority for run registry, provenance, promotion, and schema migration.

Primary consumer references:

- `../pybench/README.md`
- `docs/pybench_integration_contract.md`
- `docs/pybench_op_protocol_v1.md`

### scwb-agent

The agent harness may orchestrate exported engine APIs through typed tools. It
must not expose arbitrary shell, arbitrary R code, untyped tool calls, or local
copies of engine semantics.

The KG boundary is JSONL-first. `scworkbench` exports the canonical KG files and
schema semantics; `scwb-agent` validates the manifest and consumes the graph
through typed read-only tools. Neo4j runtime/import details belong to
`scwb-agent`; KG node/edge semantics remain owned here.

Primary consumer references:

- `../scwb-agent/AGENTS.md`
- `../scwb-agent/DESIGN.md`

### Knowledge Graph

Stable schema version:

```text
scworkbench.kg.v1
```

Canonical JSONL export files:

```text
kg_manifest.json
kg_nodes.jsonl
kg_edges.jsonl
```

Compatibility CSV export files:

```text
kg_manifest.json
kg_nodes.csv
kg_edges.csv
```

Canonical edge directions:

- `REQUIRES`: consumer -> required input
- `PRODUCES`: producer -> output
- `USES`: user -> dependency
- `CAN_WRANGLE`: source primitive/artifact type -> wrangler
- `CAN_PLOT`: wrangler -> plot
- `BELONGS_TO_SESSION`: Run -> Session
- `BELONGS_TO_BUNDLE`: Session -> Bundle

The export location is explicit and caller-chosen through `out_dir`; generated
KG files are not written under `docs/`.

## Change Declaration

Any cross-repo or contract-adjacent change should carry a dated handoff under:

```text
../handoffs/YYYY-MM-DD_short_description.md
```

Use `docs/agent_handoff_template.md` as the source template, then paste the
completed handoff into the controller/accountant thread.

Minimum declaration:

```text
Repo:
Files:
Behavior changed:
Contract changed: yes/no
Bundle schema changed: yes/no
Artifact/primitive shape changed: yes/no
Semantic catalog updated: yes/no
Tests run:
Downstream risks:
```

If `Contract changed` is `yes`, update the relevant reference above and refresh
generated semantic catalogs when applicable.

## Golden Bundle

The shared tiny fixture is generated, not manually edited:

```sh
Rscript inst/golden_bundle/create_golden_bundle.R /path/to/scwb_golden
```

Default output:

```text
fixtures/golden_bundle/scwb_golden
```

The fixture should stay small and cover the common cross-repo assumptions:

- canonical cells and metadata
- one RNA count matrix
- one 2D space
- core and named cell sets
- feature sets
- at least one promoted primitive artifact when the generator supports it

## Fullstack Contract Check

Run from `lymphocyte_trajectory`:

```sh
scworkbench/inst/fullstack/check_fullstack_contracts.sh
```

This script is intentionally a tripwire, not a replacement for full package
test suites. It checks that the sibling repos still agree on the core bundle,
tool, semantic catalog, and KG JSONL contracts.

## PeakVI Matrix Path Contract

Current controller contract:

- `peakvi_fit` uses R-staged sparse chunks as the production-safe cluster path.
- `pybench` native BPCells matrix reads remain supported for local/development
  `peakvi_fit` runs when `matrix_chunks_dir` is absent, but they are not the
  current cluster production default.
- `peakvi_project` remains staged-only.
- Native Python BPCells reads were pursued because upstream Python BPCells could
  not handle double matrices. A fork fixed double-matrix reads locally, but the
  native/forked path hit segmentation faults on Tetralith.
- Re-promoting native BPCells reads to production requires a cluster smoke that
  exercises the forked/double-matrix BPCells path without segmentation faults.
