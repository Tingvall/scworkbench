# Signal-Family Labeling Recipe

Status: canonical recipe

Purpose: define the recommended engine-native workflow for converting a
`cell_vector_family` signal layer into provisional cell labels with explicit
uncertainty.

This recipe is generic.

It is motivated by gene-signature labeling, but the same pattern applies to any
competing keyed per-cell signal family.

Related docs:

- design scaffold: `docs/signal_family_labeling_plan.md`
- chunking contract: `docs/op_chunking_contract_draft.md`
- smoke/benchmark note: `docs/signal_family_toolkit_smoke_and_benchmark.md`
- closure checklist: `docs/signal_family_and_chunking_closure_checklist.md`

## 1. When To Use This Recipe

Use this workflow when you have:

- a family of keyed per-cell signals
- keys that are intended to compete or be compared
- a need for:
  - QC
  - calibration
  - explicit abstention
  - reproducible labeling decisions

Examples:

- 47 gene signatures scored by `ucell`
- chromVAR motif activity families
- classifier posterior-like score families
- topic/state/program score families

Do not use this recipe when:

- the scientific question is only "show me program activity"
- no reduction to labels is desired
- the score family is not intended to support competition across keys

## 2. Core Principle

The output is not just a label vector.

The output of this workflow is:

- the raw signal family
- QC on that family
- an optional calibrated family
- a reduced label layer with abstention
- explicit decision diagnostics

That preserves engine truthfulness.

## 3. Canonical Workflow

### Step A: Produce The Signal Family

Recommended default for gene signatures:

- run `ucell`

Canonical outputs:

- `signature_scores` as `cell_vector_family`
- `signature_summary` as `obs_table`

Recommended defaults for `ucell`:

- `missing_features_policy = "drop"`
- `ncores = 1`
- `parallel_backend = "serial"` on constrained systems or when socket-based
  backends are unreliable
- `chunk_size`:
  - `NULL` on small bundles
  - positive integer on large bundles

Notes:

- `ucell` chunking is by `cells`
- UCell semantics still require the full feature universe inside each cell chunk

### Step B: Run Signal-Family QC

Run:

- `cell_vector_family_qc`

Canonical outputs:

- `key_summary`
- `pairwise_summary`
- `group_summary` when an optional grouping vector is supplied

What to inspect first:

- keys with near-zero dynamic range
- keys with zero or near-zero winner frequency
- highly correlated key pairs
- apparent dominance by a small number of keys
- group-specific behavior when a known grouping vector is available
  - example: cluster labels, sample labels, coarse cell classes

Interpretation guidance:

- weak keys are not automatically invalid
- but a key with flat scores, no localization, and no meaningful wins is not a
  good labeling basis

### Step C: Calibrate Across Keys

Run:

- `cell_vector_family_calibrate`

Recommended default:

- `method = "percentile"`

Reason:

- percentile calibration is easy to explain
- it rescales intrinsically weak versus strong keys into a comparable
  within-key evidence scale
- it is a practical default for labeling workflows

Alternative methods:

- `zscore`
- `robust_zscore`

Use alternatives only when you have a clear reason.

### Step D: Reduce To Provisional Labels

Run:

- `cell_vector_family_reduce`

Recommended default policy:

- reduce the calibrated family, not the raw family
- use abstention rather than forced labeling
- start conservative

Recommended starting defaults:

- `rule = "argmax"`
- `unknown_label = "unassigned"`
- `ties = "unknown"`
- `min_score = 0.8` when using percentile-calibrated input
- `min_margin = 0.1` as the initial conservative default

Interpretation:

- `min_score` asks whether the winning key is strong for that key
- `min_margin` asks whether the winner clearly beats the runner-up

What to expect:

- many cells may be `unassigned` on the first pass
- that is a feature, not a failure

Only relax thresholds after diagnostics.

### Step E: Inspect Decision Diagnostics

Inspect:

- `decision_table`
- `label_summary`
- `top_score`
- `runner_up_score`
- `score_margin`
- `abstain_reason`

Questions to answer:

- are abstentions mostly `min_margin`, `min_score`, or `tie`?
- do a few keys dominate because of true biology or poor panel design?
- are rare labels coherent or random?

Default interpretation:

- many `min_margin` abstentions usually mean overlapping or redundant keys
- many `min_score` abstentions usually mean weak signal
- many `tie` abstentions suggest poorly separated label definitions
- if grouped QC shows that a key is coherent within known groups but weak
  globally, do not discard it prematurely

### Step F: Visualize Before Trusting Labels

Minimum visualization set:

- embedding colored by top label
- embedding colored by top score
- embedding colored by score margin
- embedding colored by one selected key score
- cluster-by-key heatmap
- cluster-by-label composition summary

Current engine-facing route:

- embeddings and vector views operate over `cell_vector` / `cell_vector_family`
  surfaces
- grouped summaries are surfaced as `obs_table`
- diagnostic tables should remain promotable alongside the labels they justify

Strongly recommended:

- pairwise key redundancy heatmap
- winner-vs-runner-up view
- per-key score distributions

### Step G: Iterate

Only three things should be tuned in normal use:

- the signal family itself
- the calibration method
- the reduction thresholds

Do not invent client-only postprocessing rules.

If the workflow still fails after reasonable threshold iteration, the likely
problem is:

- poor signal family design
- overlapping label ontology
- insufficiently informative data

## 4. Recommended Threshold Policy

This is the current endorsed default policy for signature labeling.

### Default Policy

1. score with `ucell`
2. QC the raw family
3. calibrate with `percentile`
4. reduce calibrated scores with:
   - `min_score = 0.8`
   - `min_margin = 0.1`
   - `unknown_label = "unassigned"`
   - `ties = "unknown"`

### Relaxation Order

If labeling is too sparse, relax in this order:

1. lower `min_margin`
2. then lower `min_score`
3. only then revisit signal-family composition

Reason:

- `min_margin` is usually the first bottleneck when keys overlap
- lowering `min_score` too early risks turning weak signals into false labels

Suggested exploration sequence:

- `min_margin = 0.10`
- `min_margin = 0.05`
- `min_margin = 0.02`

Hold `min_score` fixed while doing that first pass.

## 5. Signature Sufficiency Checklist

Do not declare the panel sufficient just because it contains many signatures.

Minimum checks:

- every signature has enough matched genes
- score distributions are not flat
- labels or high-score cells localize coherently
- highly redundant signatures are recognized
- canonical markers or expected biology support the assigned labels
- abstention behavior is understandable rather than arbitrary

This checklist is part of the endorsed workflow, not an optional afterthought.

If these checks fail, revise the panel before forcing labels.

## 6. Promotion Guidance

Recommended promoted outputs:

- raw signal family
- raw signal summary
- QC outputs
- calibrated signal family
- reduced label output
- decision table
- label summary

This keeps the reduced label attached to its evidence trail.

## 7. Large-Bundle Guidance

For large bundles:

- prefer chunked execution when supported
- for `ucell`, pass `chunk_size`
- on constrained systems prefer:
  - `ncores = 1`
  - `parallel_backend = "serial"`

Current practical note:

- chunking solves operability before it solves speed
- benchmark large-bundle behavior before treating it as a production-default path

## 8. Minimal Example Pattern

```r
s <- wb_session_new()

r1 <- wb_session_run_op(
  session = s,
  bundle = b,
  op_name = "ucell",
  inputs = list(
    matrix = "RNA_counts",
    cell_set = "all",
    features = sigs,
    chunk_size = 250L,
    ncores = 1L,
    parallel_backend = "serial",
    max_rank = 1500L,
    missing_features_policy = "drop"
  )
)
s <- r1$session

r2 <- wb_session_run_op(
  session = s,
  bundle = b,
  op_name = "cell_vector_family_qc",
  inputs = list(signal = wb_ref_run(r1$run$run_id, "signature_scores"))
)
s <- r2$session

r3 <- wb_session_run_op(
  session = s,
  bundle = b,
  op_name = "cell_vector_family_calibrate",
  inputs = list(
    signal = wb_ref_run(r1$run$run_id, "signature_scores"),
    method = "percentile"
  )
)
s <- r3$session

r4 <- wb_session_run_op(
  session = s,
  bundle = b,
  op_name = "cell_vector_family_reduce",
  inputs = list(
    signal = wb_ref_run(r3$run$run_id, "calibrated_signal"),
    rule = "argmax",
    min_score = 0.8,
    min_margin = 0.1,
    unknown_label = "unassigned",
    ties = "unknown"
  )
)
```

## 9. What Is Still Outside This Recipe

The following are still separate closure items:

- grouped QC
- additional signature-aware helper summaries
- fully benchmarked large-bundle defaults

Those should be added by extending the engine surface, not by changing the
logic of this recipe in clients.
