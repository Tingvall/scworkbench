# Signal-Family And Chunking Closure Checklist

Status: tracks 1 and 2 closed

Purpose: define the explicit finish line for the two linked hardening tracks:

1. signal-family toolkit
2. generic chunking strategy

This document exists to prevent drift.

`scworkbench` is strongest when:

- semantics are explicit
- engine truth is canonical
- one path exists for each capability
- docs and contracts match reality

So these tracks should not be left in a half-finished state while the real
labeling analysis moves ahead.

## Core Rule

Do not start the full real-bundle cell-labeling workflow as a primary track
until tracks 1 and 2 below are closed to an engine-quality standard.

"Closed" means:

- the canonical docs describe the real engine behavior
- contract tests exist
- the surface is available through the engine, not just scripts
- there are no known major gaps that force clients or agents to improvise

## Track 1: Signal-Family Toolkit

Goal:

- make signal-family scoring, QC, calibration, reduction, and diagnostics a
  coherent generic engine workflow based on `cell_vector_family`

### 1.1 Scope Freeze

- [x] endpoint workflow documented
- [x] generic design framed around `cell_vector_family`
- [x] signal-family work explicitly linked to large-bundle chunking

### 1.2 Core Ops

- [x] `cell_vector_family_calibrate` exists
- [x] `cell_vector_family_qc` exists
- [x] `cell_vector_family_reduce` emits richer decision diagnostics
- [x] grouped QC exists
- [x] calibrated reduction policy is documented clearly enough that analysts
  have one recommended path

### 1.3 Diagnostics And Sufficiency

- [x] key-level QC summaries exist
- [x] pairwise redundancy summaries exist
- [x] decision table exists
- [x] abstention reason exists
- [x] signature-panel sufficiency checklist is codified into a practical recipe
- [x] expected visualization set is documented against actual current engine
  surfaces

### 1.4 Recipe Closure

- [x] one canonical signature-labeling workflow is documented end to end
- [x] recommended defaults are explicit
- [x] threshold iteration guidance is explicit
- [x] promotion/report expectations are explicit

### 1.5 Testing Closure

- [x] contract tests for calibrate
- [x] contract tests for QC
- [x] contract tests for richer reduce outputs
- [x] at least one bundle-scale smoke workflow test or repeatable benchmark path
  is documented for the toolkit

### 1.6 Done Criteria

Track 1 is done when:

- an analyst can follow one documented engine-native path from signal family to
  labeled output with diagnostics
- no major part of that path depends on Shiny-only logic or one-off scripts
- the docs no longer describe "missing pieces" that are actually required for
  the endorsed workflow

## Track 2: Generic Chunking Strategy

Goal:

- make chunk-safe ops executable on large bundles through an engine-owned
  contract rather than script-level batching

### 2.1 Contract

- [x] chunking contract draft exists
- [x] chunking metadata exists in the op catalog
- [x] chunking metadata is visible through `wb_op_interface()`
- [x] contract doc reflects final implemented behavior rather than draft-only
  intent

### 2.2 Generic Infrastructure

- [x] generic chunk partition helper exists
- [x] conservative merge helpers exist
- [x] generic internal chunk executor exists
- [x] chunk helper semantics are documented in roxygen or engine docs, not only
  in tests

### 2.3 First Real Migration

- [x] `ucell` declares chunkability
- [x] `ucell` chunking is wired through the generic helper
- [x] chunked-vs-unchunked equivalence test exists for `ucell`
- [x] explicit serial backend control exists for `ucell`
- [x] at least one additional op using a different chunk axis or merge shape is
  migrated through the generic helper

### 2.4 Provenance And Replay

- [x] chunk metadata is recorded in run params
- [x] replay/provenance expectations for chunked runs are tested explicitly
- [x] it is documented which chunk metadata is execution-only versus semantic
  contract

### 2.5 Backend Honesty

- [x] sparse coercion limitations are either improved or documented honestly as
  a known constraint
- [x] benchmark notes exist for large-bundle `ucell` behavior
- [x] engine guidance is explicit for constrained environments
  - example: use `parallel_backend = "serial"` when socket-based backends fail

### 2.6 Done Criteria

Track 2 is done when:

- chunk-safe ops have one canonical engine path
- chunked execution is visible and auditable in engine outputs/provenance
- at least two materially different ops have validated use of the generic
  helper, or the docs explicitly constrain the surface to the currently
  supported set
- clients and scripts no longer need to invent their own batching semantics for
  the endorsed workflows

## Track Dependencies

Track 1 depends on track 2 for bundle-scale operability.

Track 2 is justified in part by track 1, but should remain generic beyond
signal-family workflows.

The real labeling analysis is a separate downstream track.

That downstream track should not become the place where unfinished work from
tracks 1 and 2 gets silently patched.

## Closure Result

Track 1 is now closed.

Reason:

- the signal-family toolkit has a canonical engine-native recipe
- the supporting generic ops exist and are tested
- grouped QC, reduction defaults, sufficiency guidance, and bundle-scale
  smoke/benchmark guidance are documented

Track 2 is now closed.

Reason:

- the chunking contract is implemented and documented to first-pass closure
- chunk metadata is engine-visible
- generic helper infrastructure exists
- two materially different ops are migrated through the generic helper:
  - `ucell`
  - `feature_trend_spearman`
- chunked provenance and replay behavior is tested explicitly
- backend limitations and benchmark behavior are documented honestly

## Next Primary Track

The next primary track is the real-bundle cell-labeling analysis.

That analysis should now proceed using the closed engine surfaces from tracks 1
and 2 rather than inventing new workflow semantics during analysis time.
- [ ] decide whether to close track 2 by broader migration or by explicitly
  constraining the supported chunked-op surface for now
