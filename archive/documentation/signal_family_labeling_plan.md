# Signal-Family Labeling Plan

Status: planning scaffold

Purpose: define the end-to-end design for signature/program-based cell labeling
in a way that stays generic beyond one 47-signature use case.

This document is intentionally written from the endpoint backward:

1. what the analyst should be able to do
2. what engine contracts are needed
3. what already exists
4. what is missing
5. what to build first

Related infrastructure:

- large-bundle execution needs an engine-owned chunking surface for chunk-safe
  ops
- see `docs/op_chunking_contract_draft.md`
- canonical workflow recipe lives in `docs/signal_family_labeling_recipe.md`
- closure criteria for this track live in
  `docs/signal_family_and_chunking_closure_checklist.md`

## 1. Endpoint We Want

An analyst should be able to:

- register a family of keyed signals
  - example: 47 gene signatures
  - but also motif programs, classifier scores, branch probabilities, topic loadings
- score every cell against that family
- inspect whether the signal family is usable
  - signature coverage
  - score dynamic range
  - redundancy / competition
  - weak or collapsed keys
- calibrate scores across keys when their raw scales differ
- reduce the family into provisional labels with abstention
  - top label
  - confidence
  - ambiguity
  - unassigned / unknown
- preserve the full signal family, not just the reduced label
- generate diagnostics and visualizations that explain why the label was assigned

The key product is not only a categorical label per cell.

The real product is:

- a signal family
- a calibrated decision layer
- a labeled output with explicit uncertainty
- provenance-linked diagnostics

## 2. Core Design Principle

Do not build this as a one-off "cell type from 47 signatures" feature.

Build it as a generic toolkit for `cell_vector_family`:

- score
- QC
- calibrate
- reduce
- diagnose

Then layer signature-specific recipes on top.

This follows existing `scworkbench` principles:

- primitives stay primitive
- clients stay thin
- provenance stays explicit
- one generic surface should support multiple analytical situations

## 3. Primitive-Level Framing

The central primitive for this work is:

- `cell_vector_family`

Interpretation:

- one score per `(cell_id, key)`
- key can mean signature, motif, topic, branch, state, classifier label, etc.

This makes the design broadly reusable.

Examples of keyed signal families:

- UCell signature scores
- chromVAR motif deviation z-scores
- Palantir fate probabilities
- topic model loadings
- classifier posterior scores

## 4. Concrete Analyst Workflow

Example endpoint workflow for the current use case:

1. store 47 feature sets
2. run `ucell` on one matrix for all 47 sets
3. inspect per-signature summary and QC
4. calibrate scores across signatures
5. reduce calibrated scores into:
   - top label
   - top score
   - second-best score
   - margin
   - ambiguity / abstention
6. visualize:
   - embedding by top label
   - embedding by winning score
   - embedding by score margin
   - embedding of one signature at a time
   - cluster-by-signature heatmap
   - cluster-by-label composition
7. iterate thresholds or signature panel
8. promote final outputs and emit report / replay

## 5. What Already Exists

Current engine support is already strong enough for a first pass.

### 5.1 Signal Production

- `wb_op_ucell()`
  - outputs `signature_scores` as `cell_vector_family`
  - outputs `signature_summary` as `obs_table`

### 5.2 Feature-Set Registry

- `wb_feature_set_replace()`
- `wb_feature_sets()`
- `wb_feature_set_get()`
- metadata fields on feature sets already exist

### 5.3 Reduction

- `cell_vector_family_reduce`
  - already reduces one family into a categorical label
  - already supports:
    - `min_score`
    - `min_margin`
    - `unknown_label`
  - already emits:
    - label
    - top score
    - score margin
    - label summary

### 5.4 Visualization Substrate

- `cell_vector`
- `cell_vector_family`
- plot and table surfaces already exist
- Shiny already knows how to browse these primitives

## 6. What Is Missing

The missing pieces are not special to signatures. They are generic signal-family
needs.

### 6.1 Signal-Family QC

Need a generic QC surface for `cell_vector_family`.

Questions it should answer:

- which keys have near-flat score distributions?
- which keys have weak dynamic range?
- which keys are rare but still structured?
- which keys are highly correlated / redundant?
- which keys fail coverage or feature-match expectations?

For signature-derived families specifically:

- how many features were requested?
- how many matched the matrix?
- how many are missing?
- how much overlap exists between signatures?

### 6.2 Signal-Family Calibration

Current reduction mostly assumes raw scores are comparable.

That is often false.

Examples:

- some signatures are intrinsically weak
- TF-like signatures may have lower raw activity
- different producers can emit different score scales

Need generic cross-key calibration methods such as:

- percentile within key
- z-score within key
- robust z-score within key
- rank normalization

### 6.3 Better Competition Diagnostics

Current reduction is useful but incomplete.

Need explicit decision diagnostics:

- winner
- runner-up
- winner score
- runner-up score
- margin
- confidence tier
- abstention reason
- maybe entropy / competition concentration

### 6.4 Signature-Panel Sufficiency Assessment

Need a way to answer:

- are these signatures sufficient for labeling?

This cannot be answered from count alone.

We need diagnostics for:

- matrix coverage
- signature redundancy
- coherence of high-scoring cells
- whether signatures represent identity vs state

### 6.5 Recipe / Endpoint Documentation

Even with generic ops, analysts need one recommended path.

This document is the first scaffold for that recipe.

### 6.6 Chunked Execution For Large Bundles

Signal-family workflows are one of the clearest cases where engine-owned
chunking is required.

Reason:

- realistic bundles may exceed workstation memory for full-matrix pulls
- some scoring and summary ops are analytically separable across cells or
  features
- clients and scripts should not invent their own batching semantics

This means chunking should be treated as a generic hardening surface rather
than as a `ucell`-specific workaround.

See:

- `docs/op_chunking_contract_draft.md`

This is an infrastructure dependency for robust bundle-scale use of the
signal-family toolkit.

## 7. Proposed Generic Surfaces

### 7.1 `cell_vector_family_qc`

Kind: op

Input:

- `signal` as `cell_vector_family`
- optional grouping vector as `cell_vector`
- optional key metadata / membership metadata

Outputs:

- `key_summary` as `obs_table`
- `pairwise_summary` as `obs_table`
- `group_summary` as `obs_table` when grouping is supplied

Responsibilities:

- per-key distribution summaries
- key sparsity / dynamic range
- pairwise score correlation
- winner-frequency / top-k frequency summaries
- optional grouped summaries by cluster / condition

Optional signature-aware fields when metadata exists:

- n_features_input
- n_features_matched
- n_features_missing
- overlap counts

Why generic:

- applies to any keyed signal family, not just gene signatures

### 7.2 `cell_vector_family_calibrate`

Kind: op

Input:

- `signal` as `cell_vector_family`
- `method`

Methods:

- `percentile`
- `zscore`
- `robust_zscore`
- `rank`

Outputs:

- `calibrated_signal` as `cell_vector_family`
- `calibration_summary` as `obs_table`

Responsibilities:

- normalize score scales across keys
- keep original signal intact
- make calibration provenance explicit

Why generic:

- any competing keyed signals may need cross-key comparability

### 7.3 Extend `cell_vector_family_reduce`

Kind: existing op to extend

New desired behavior:

- keep current simple path
- add richer diagnostics
- support calibrated input naturally
- eventually allow per-key thresholds

Desired outputs:

- `label` as `cell_vector`
- `top_score` as `cell_vector`
- `runner_up_score` as `cell_vector`
- `score_margin` as `cell_vector`
- `decision_table` as `obs_table`
- `label_summary` as `obs_table`

Potential extra params:

- `min_score`
- `min_margin`
- `min_percentile`
- `unknown_label`
- `ties = c("abstain", "first", "multi")`

Why generic:

- this is a general "competing keyed signals -> decision" pattern

### 7.4 Optional Signature-Metadata Helpers

These should be optional, not required by the base generic ops.

Possible future helpers:

- feature-set overlap summary
- feature-set redundancy clustering
- namespace-aware grouping / ontology-aware reduction

Why optional:

- not every `cell_vector_family` comes from feature sets

## 8. Recommended End-State Workflow

### Phase A: Signal Production

- import feature sets
- run `ucell`
- promote signal family and summary

### Phase B: QC

- run `cell_vector_family_qc`
- inspect weak / flat / redundant keys
- revise panel if necessary

### Phase C: Calibration

- run `cell_vector_family_calibrate`
- compare raw vs calibrated behavior

### Phase D: Reduction

- reduce calibrated family to labels
- emit abstention / ambiguity

### Phase E: Diagnostics

- inspect decision table
- inspect cluster-by-label composition
- inspect key score distributions
- inspect embedding localization

### Phase F: Reporting

- promote final signal family
- promote calibrated family
- promote final labels and diagnostics
- emit replay and report

## 9. Visualization Targets

These are endpoint requirements, whether served by current plots or future
wranglers.

### Must-Have

- embedding colored by top label
- embedding colored by top score
- embedding colored by score margin
- embedding colored by one selected key score
- cluster-by-key heatmap
- cluster-by-label composition plot

### Strongly Desirable

- pairwise key correlation heatmap
- key overlap / redundancy heatmap
- winner vs runner-up scatter
- per-key score distributions
- ambiguity map

## 10. Current Use Case: 47 Gene Sets x 20 Genes

This use case is sufficient to motivate the design, but should not define it too
narrowly.

What this use case stresses:

- small signatures with variable detectability
- possible signature redundancy
- possible weak-but-specific programs
- need for abstention
- need for per-signature calibration

The key lesson:

Do not rely only on a global raw-score threshold.

Needed logic:

- within-cell competition
- within-key calibration
- explicit ambiguity handling

## 11. Are the 47 Signatures Sufficient?

Not knowable a priori.

The right answer must come from QC.

Minimum sufficiency checks:

- enough genes matched in the matrix
- enough detectable expression
- enough score dynamic range
- not too redundant with neighboring signatures
- labels localize coherently on the embedding
- high-scoring cells show expected marker support

If many signatures fail these checks, the panel is not yet sufficient for
robust labeling.

## 12. Phased Implementation Proposal

### Phase 1: Use What Exists

Goal:

- run first-pass signature labeling immediately

Use:

- feature-set registry
- `ucell`
- current `cell_vector_family_reduce`
- current visualization surfaces

Deliver:

- first-pass labels
- first-pass ambiguity
- practical pressure from real usage

### Phase 2: Add Generic Calibration

Build:

- `cell_vector_family_calibrate`

Reason:

- highest leverage missing generic primitive op

### Phase 3: Extend Reduction Diagnostics

Build:

- richer outputs from `cell_vector_family_reduce`

Reason:

- necessary to justify labeling decisions

### Phase 4: Add Generic QC

Build:

- `cell_vector_family_qc`

Reason:

- answers "are the signals usable?" across many workflows

### Phase 4.5: Add Engine-Owned Chunking

Build:

- generic chunking contract for chunk-safe ops
- initial executor and merge helpers
- first migrated target: `ucell`

Reason:

- signal-family workflows need a bundle-scale execution path
- chunking should be engine-owned for provenance and consistency
- this hardening is reusable beyond signature scoring

### Phase 5: Add Signature-Specific Convenience Recipe

Build:

- a documented recipe or thin wrapper for signature labeling

Reason:

- analysts need a canonical path
- engine should still stay generic underneath

## 13. Contract Placement

These changes should map cleanly to existing engine surfaces.

- new compute -> op
- new summaries -> `obs_table`
- new categorical labels -> `cell_vector`
- new score families -> `cell_vector_family`
- new human-facing summaries -> identity-card issuer only if promoted artifacts need it
- client work should remain rendering and orchestration only

Do not:

- implement score calibration only in Shiny
- implement label logic only in notebooks
- create a second special-case label storage path

## 14. Open Questions

- Should per-key thresholds live in reduction, or in a separate calibration /
  decision object?
- Do we want a `decision_table` primitive to stay as `obs_table`, or is a more
  explicit tabular contract needed?
- How much signature metadata should be attached to the signal family itself vs
  queried from the feature-set registry?
- Should signature-overlap analysis be a separate helper/op or part of QC?
- When do we want hierarchical labeling support?

## 15. Immediate Scaffold Use

Use this document as the scaffold for implementation tracking.

Suggested next working checklist:

- [ ] Run first-pass 47-signature analysis with existing `ucell` + reduction
- [ ] Record pain points from that first pass
- [ ] Draft contract for `cell_vector_family_calibrate`
- [ ] Draft extension contract for `cell_vector_family_reduce`
- [ ] Draft contract for `cell_vector_family_qc`
- [ ] Decide whether signature-overlap analysis is part of QC or a separate helper
- [ ] Add tests and smoke workflows incrementally
