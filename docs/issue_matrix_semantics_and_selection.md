# Issue: Formalize Matrix Semantics and Selection (Transforms, Defaults, Lineage)

## Summary

We already have strong matrix identity handling via explicit `matrix_id` throughout the engine and clients. What is still mostly implicit is matrix semantics (for example `counts` vs `log1p` vs `tfidf`) and transform lineage (`source_matrix_id`).

This issue proposes a backward-compatible extension to make matrix selection explicit, reliable, and client-agnostic.

## Current State (What already works)

- Matrices are registry-backed and keyed by `matrix_id`
- Ops consume resolved matrix primitives and pass `matrix_id` explicitly
- Clients can discover matrices via `wb_matrices()`
- Artifacts capture `input_matrix_id` in provenance

This is good and should remain the foundation.

## Problem

As we add transformed matrices (log1p/normalized/scaled/TF-IDF/etc.), the engine currently relies on:

- `matrix_id` naming conventions
- `layer`
- `feature_type`
- free-text description

This makes semantic matrix selection brittle for:

- thin clients (Shiny, Python, Flutter, Node)
- agents
- script emitters
- future reproducibility defaults

Examples:

- Which matrix is "normalized RNA"?
- Which matrix should DE use by default?
- Which matrix was derived from which source matrix?

## Goal

Add formal matrix semantics + lineage metadata while preserving existing `matrix_id`-based behavior.

## Proposed Design (Backlog / Future)

### 1. Extend `matrices` registry schema (optional columns, backward-compatible)

Add nullable columns such as:

- `modality` (e.g. `rna`, `atac`, `protein`)
- `value_space` (e.g. `counts`, `log1p_counts`, `tfidf`, `scaled`, `latent`)
- `source_matrix_id` (upstream matrix for transforms)
- `created_by_op` (op name, optional)
- `created_by_run_id` (optional)
- `is_default` / or profile-specific default markers (optional, may be separate table)

### 2. Add matrix selector helper API

New helper (name TBD), e.g. `wb_matrix_select()`:

- exact by `matrix_id`
- symbolic by semantics:
  - `modality = "rna"`
  - `value_space = "log1p_counts"`
  - `prefer_latest = TRUE`
- strict failure when ambiguous

### 3. Expose semantics in client discovery

Extend `wb_matrices()` / `wb_client_discover()` output with semantic fields so thin clients can show:

- human-readable labels
- source lineage
- safer defaults

### 4. Op interface hints (not hard requirements at first)

Allow ops to declare preferred/acceptable matrix semantics, e.g.:

- `de_wilcox`: prefers `rna` + `counts|log1p_counts` (depending policy)
- `addmodulescore`: prefers expression-like matrix
- future ops can be stricter

### 5. Script emitter support

Support two modes:

- explicit (`matrix_id`) for exact reproducibility
- symbolic selector for portability (when user chooses)

## Non-Goals (for first pass)

- Rewriting all ops
- Removing explicit `matrix_id`
- Enforcing one global normalization policy
- Changing existing bundles immediately

## Why this matters

- Reproducibility for agentic workflows
- Thin-client consistency
- Safer defaults as matrix transforms proliferate
- Clear provenance when writing methods/reports

## Acceptance Criteria (future)

- Existing bundles continue to work unchanged
- Existing ops continue to work unchanged with explicit `matrix_id`
- New transformed matrices can be registered with formal semantics
- A selector API resolves matrices deterministically or errors if ambiguous
- Clients can display matrix semantics + lineage

## Notes

This is a schema/selector hardening task, not an architecture pivot. The current explicit `matrix_id` flow is correct and should be preserved.
