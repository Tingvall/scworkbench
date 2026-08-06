# Navigation Contract Draft

This document defines the draft engine contract for cross-artifact and cross-plot
navigation.

The goal is to let clients ask:

- what entities are present here
- what context is attached to them
- what other engine objects are compatible targets
- what handoff payload should be sent to another client surface

Without this contract, clients will invent ad hoc friendships. That violates the
engine-first architecture.

## Why

The system already has:

- typed primitives
- plot contracts
- artifact identity cards
- related-artifact discovery

But it does not yet have a general contract for navigation between those objects.

Examples that need this:

- `trajectory_de` gene -> matching `trajectory_smooth` plot
- `trajectory_smooth` lineage -> matching `trajectory_signature_smooth` plot
- same gene -> other lineage in compare mode
- pathway row -> pathway-focused plot/report
- selected cells -> scene panel or selector recipe

These are all navigation problems, not rendering problems.

## Core Principle

Contracts determine the best friendships.

Clients must not guess:

- that a `feature_id` should open a smooth plot
- that a `lineage_id` should map to another artifact
- that a row in one dataset is compatible with another panel

The engine should declare:

- what entities a source contains
- what target workflows are valid
- what payload is needed for the handoff

## Scope

This contract is for navigation and handoff only.

It is not:

- a rendering contract
- a selector replacement
- a provenance replacement
- a client-specific routing system

## Design Goals

- Engine-owned and client-independent
- Extensible by primitive kind / table type / plot dataset type
- Explicit about entity semantics
- Safe to use across Shiny, notebooks, scripts, and agents
- Composable with existing artifact and plot contracts

## Core Concepts

## Source

A source is something navigable:

- an artifact ref
- a primitive
- a wrangled plot dataset
- optionally, a selected row from a dataset

## Entity

An entity is the navigable object carried across the handoff.

Examples:

- `feature`
- `cell`
- `lineage`
- `feature_set`
- `pathway`
- `cluster`

Minimum fields:

- `entity_kind`
- `entity_id`

Optional fields:

- `label`
- `score`
- `direction`
- `rank`

## Context

Context is the attached navigation state needed to interpret the entity.

Examples:

- `artifact_id`
- `plot_type`
- `matrix_id`
- `cell_set`
- `lineage_id`
- `feature_set`
- `model_signature`

## Target

A target is an engine-declared compatible destination.

Examples:

- related artifact
- compatible plot workflow
- same artifact with alternate lineage context
- selector or report workflow

## Handoff Payload

A handoff payload is the minimal engine-declared bundle of information needed by
another client surface.

Examples:

- `ref = artifact:obs_table_...`
- `plot_type = pseudotime_smooth_panel`
- `params = list(lineage = ..., feature = ...)`

## Proposed API Shape

Names are draft only.

## `wb_nav_entities(source, ...)`

Returns the entities exposed by a source.

Example output columns:

- `entity_kind`
- `entity_id`
- `label`
- `group_kind`
- `group_id`
- `score`
- `rank`

Current built-in entity kinds:

- `lineage`
- `feature`
- `feature_set`

## `wb_nav_targets(source, entity = NULL, bundle, runs = NULL, ...)`

Returns compatible target workflows for a source or selected entity.

Example output columns:

- `target_kind`
- `target_id`
- `action`
- `label`
- `reason`
- `priority`

## `wb_nav_handoff(source, target, entity = NULL, bundle, runs = NULL, ...)`

Returns a client-agnostic handoff payload.

Example output:

- `ref`
- `plot_type`
- `params`
- `selection`
- `notes`

Current built-in actions:

- `open_smooth_plot`
- `open_de_plot`
- `open_signature_plot`
- `compare_other_lineage`

Clients apply the payload. They do not invent it.

## Relationship to Existing Contracts

## Primitives

Navigation is downstream of primitive semantics.

Primitive kind alone is not enough. Navigation may also depend on:

- `table_type`
- primitive `meta`
- provenance

## Plot Contracts

Plot contracts define display compatibility.

Navigation contracts define handoff compatibility.

They are related, but different.

Example:

- a `trajectory_de` table can be plotted as `ranked_lollipop`
- a selected `feature` from that same table can navigate to `trajectory_smooth`
- a selected `lineage` from `trajectory_smooth` can navigate to a paired
  `trajectory_signature_smooth` plot

Those are two different contracts.

## Identity Cards

Identity cards summarize an artifact for humans.

Navigation contracts expose structured, machine-usable target relationships.

An identity card may mention a related artifact. The navigation contract should
make that relationship explicit and queryable.

## Related Artifact Discovery

`wb_art_trajectory_related()` is an example of early navigation infrastructure.

It should eventually become a special case of the general navigation layer, not
remain a one-off forever.

## First Implementation Targets

The first implementation should be intentionally narrow.

## `trajectory_de`

Entities:

- `feature`
- `lineage`

Context:

- `matrix_id`
- `cell_set`
- `model_signature`
- `lineage_id`

Targets:

- matching `trajectory_smooth`
- same `trajectory_de` with alternate lineage context

## `trajectory_smooth`

Entities:

- `feature`
- `lineage`

Targets:

- matching `trajectory_de`
- same smooth artifact with alternate lineage context

This is enough to support:

- DE -> smooth handoff
- smooth -> DE handoff
- compare same gene across lineages

## Extensibility Model

Navigation must be open for new source/target families without changing core
client code.

Recommended pattern:

- registry of navigation resolvers
- source matcher by primitive kind / table type / source op / dataset type
- target resolver returning declared compatible handoffs

This should mirror the extensibility style used for:

- op catalog
- plot mapper registry
- identity-card issuers

## Non-Goals

The first version should not try to solve:

- arbitrary click-anywhere plot introspection
- free-form semantic guessing from column names alone
- universal navigation across every artifact type

Start with explicit typed entities and explicit target declarations.

## Client Responsibilities

Clients should:

- render available navigation actions
- pass selected entity/context to the engine
- apply returned handoff payloads

Clients should not:

- infer targets from random columns
- reimplement matching logic
- hardcode pairings that the engine does not declare

## Open Questions

- Should navigation be defined on raw artifacts, wrangled datasets, or both?
- Should selected plot rows carry standardized navigation columns?
- Should target compatibility include confidence / preference ranking?
- Should handoff payloads be fully generic, or partly target-specific?
- How should cross-panel compare mode consume handoff payloads?

## Current Recommendation

Implement the first engine-backed navigation contract for:

- `trajectory_de`
- `trajectory_smooth`
- `trajectory_signature_smooth`
- `trajectory_geneset_dynamics`
- `trajectory_signal_dynamics`

Then make Shiny consume it for:

- DE -> smooth
- smooth -> DE
- compare-in-other-panel actions
- gene-set dynamics table -> gene-set curve
- gene-set curve -> driver genes / driver-gene curves
- driver-gene table -> driver-gene curve
- signal dynamics table -> signal curve

For `trajectory_geneset_dynamics`, the current source/target intent is:

- `trajectory_geneset_dynamics` / `trajectory_geneset_dynamics_top`:
  ranked `feature_set` entities can navigate to the matching
  `trajectory_geneset_dynamics_curve` plot and to the matching driver-gene
  table.
- `trajectory_geneset_dynamics_curve`:
  selected `feature_set` entities can navigate to driver genes and
  driver-gene curves.
- `trajectory_geneset_dynamics_drivers` /
  `trajectory_geneset_dynamics_driver_curve`:
  selected driver `feature` entities can navigate to the matching
  driver-gene curve and parent gene-set curve.

For `trajectory_signal_dynamics`, the current source/target intent is:

- `trajectory_signal_dynamics` / `trajectory_signal_dynamics_top`:
  ranked signal entities can navigate to the matching
  `trajectory_signal_dynamics_curve` plot.
- `trajectory_signal_dynamics_curve`:
  selected signal entities can use the same-artifact compare target.

If that contract stays clean, extend it to other plot families later.
