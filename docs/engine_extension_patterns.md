# Engine Extension Patterns

This is the practical guide for extending `scworkbench` without breaking the
engine/client boundary.

Use it when adding new capabilities.

## Core Rule

Put each change in the correct engine surface.

Do not start from the client and work backward.

## Decision Table

If you are adding:

- new analysis compute -> add an op
- new normalized display dataset -> add a wrangler / plot mapper
- new artifact summary text -> add an identity-card issuer
- new cross-surface handoff -> add a navigation resolver / handoff contract
- new storage/query access -> add or extend a getter

## 1. Adding an Op

Canonical path:

- `wb_op_*()` implementation
- runner in `R/op_catalog.R`
- entry in `.wb_op_catalog()`
- contract test

Read:

- `inst/add_op.md`

Do:

- return named primitives
- make promotable outputs explicit
- keep params explicit for provenance

Do not:

- add parallel interface/dispatch registries
- hide substantial compute inside a wrangler or client

## 2. Adding a Plot Contract / Mapper

Use when you need:

- a new plot type
- a new normalization path from primitive/artifact to display dataset

Canonical files:

- `R/wrangler_plots_contracts.R`
- possibly a dedicated wrangler helper file

Do:

- define the contract first
- keep mappers thin when possible
- let the engine answer compatibility queries

Do not:

- infer scientific inputs in the client
- let a plot mapper become a hidden analysis op unless that is an intentional
  transitional state

Rule of thumb:

- if it chooses matrices/features/lineages and derives new analysis summaries,
  it probably wants to be an op
- if it reshapes an existing primitive for rendering, it is a mapper

## 3. Adding an Identity-Card Issuer

Use when the default artifact summary is too generic.

Canonical file:

- `R/artifacts.R`

Do:

- keep the birth certificate canonical
- add human explanation in the issuer
- make the card explain the artifact in domain terms

Good use cases:

- trajectory artifacts
- multi-output workflow artifacts
- domain-specific tables where generic chips are not enough

Do not:

- encode client-specific presentation assumptions
- change provenance structure just to improve the card text

## 4. Adding Navigation / Handoff

Use when a source should lead to another source or plot.

Canonical files:

- `R/navigation.R`
- related artifact helpers in `R/artifacts.R`

Current draft contract:

- `wb_nav_entities()`
- `wb_nav_targets()`
- `wb_nav_handoff()`

Do:

- define explicit entity kinds
- define explicit compatible targets
- return handoff payloads from the engine

Do not:

- guess friendships from arbitrary column names in the client
- encode target selection logic only in Shiny

## 5. Adding Getter Behavior

Use when you need new logical access to bundle data.

Canonical area:

- getter functions in `R/getters.R` and related files

Do:

- preserve ordering and logical-view guarantees
- keep storage details behind getters

Do not:

- let ops, wranglers, or clients read storage internals directly

## 6. Client Work

Clients are allowed to:

- collect inputs
- render outputs
- orchestrate existing engine workflows
- manage local UI state

Clients are not allowed to:

- redefine compute semantics
- redefine plot compatibility
- redefine artifact identity semantics
- redefine navigation compatibility

If a client needs more intelligence, add an engine contract first.

## 7. Tests

Every new extension should have contract tests.

Typical targets:

- op contract test
- plot wrangler contract test
- navigation contract test
- real bundle smoke verification

Prefer:

- one focused contract test for the new surface
- one real-bundle smoke check for confidence

## 8. Docs To Update

At minimum, consider:

- roxygen on exported functions
- `inst/foundation_contracts.md`
- onboarding/playbook docs if the extension surface is important
- dedicated draft contract docs for new surfaces
- staged assembly docs if the change touches bundle creation / ingest / attach

## 9. Common Failure Modes

- putting compute in the client because it is faster to prototype
- adding a second registration path
- letting a plot convenience function become the real compute path
- writing artifact-specific UI logic instead of an engine resolver
- skipping docs because “the code is clear enough”

## 10. Current Important Surfaces

Today the main extensibility surfaces are:

- ops via `op_catalog`
- plot contracts / mappers
- identity-card issuers
- navigation contract
- staged bundle assembly / source adapters

If a new feature does not fit one of these cleanly, stop and decide whether the
surface model needs to expand before implementing it ad hoc.
