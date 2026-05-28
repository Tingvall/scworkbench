# Signal-Family Toolkit Smoke And Benchmark

Status: repeatable smoke/benchmark note

Purpose: define a repeatable verification path for the signal-family toolkit so
the workflow can be checked on a real bundle without inventing one-off scripts
or relying on UI-only validation.

Related docs:

- canonical recipe: `docs/signal_family_labeling_recipe.md`
- closure checklist: `docs/signal_family_and_chunking_closure_checklist.md`
- chunking contract: `docs/op_chunking_contract_draft.md`

## 1. Intended Use

Use this note when you want to:

- smoke-test the end-to-end signal-family workflow
- benchmark bundle-scale operability
- compare settings such as chunk size or backend mode

This is a validation workflow, not a production reporting workflow.

## 2. Recommended Smoke Sequence

On a real bundle with registered feature sets:

1. run `ucell`
2. run `cell_vector_family_qc`
3. run `cell_vector_family_calibrate`
4. run `cell_vector_family_reduce`
5. inspect:
   - key summary
   - pairwise summary
   - optional grouped summary
   - decision table
   - label summary

Recommended defaults for a constrained machine:

- `ncores = 1`
- `parallel_backend = "serial"`
- use `chunk_size` for large bundles

## 3. Minimal Session Pattern

```r
devtools::load_all(".", quiet = TRUE)

b <- wb_open_bundle("../demo")
on.exit(wb_close_bundle(b), add = TRUE)

fs <- wb_feature_sets(b, namespace = "immgen", matrix_id = "RNA_counts")
sigs <- setNames(
  lapply(as.character(fs$feature_set), function(nm) {
    wb_feature_set_get(b, feature_set = nm, matrix_id = "RNA_counts")
  }),
  as.character(fs$feature_set)
)

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
  inputs = list(
    signal = wb_ref_run(r1$run$run_id, "signature_scores")
  )
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

## 4. What To Record

Minimum record for a smoke/benchmark run:

- bundle path
- matrix id
- feature-set namespace
- number of cells
- number of signatures
- chunking settings
- backend settings
- wall time
- peak memory if measured
- summary of abstention reasons

This keeps bundle-scale behavior auditable and comparable.

## 5. Benchmark Guidance

Recommended local benchmark command pattern:

```bash
/usr/bin/time -v Rscript /tmp/run_signal_family_smoke.R
```

Prefer a bounded benchmark for uncertain runs:

```bash
/usr/bin/time -v timeout 120s Rscript /tmp/run_signal_family_smoke.R
```

Use bounded runs when:

- you only need an operability/performance lower bound
- you expect a large bundle may take much longer than the interactive budget

## 6. Current Known Constraints

- `ucell` may still trigger the getter warning:
  - `Converting to a dense matrix may use excessive memory`
- on this machine, socket-based BiocParallel backends were unreliable for
  bundle-scale `ucell`
- use `parallel_backend = "serial"` when you want the most stable path

These are engine constraints that should be documented honestly rather than
papered over in client logic.

## 7. Success Criteria

The smoke path is successful when:

- the workflow runs end to end through engine contracts
- no client-only logic is needed
- the outputs are sufficient to diagnose score quality, redundancy, calibration,
  and abstention behavior

The benchmark path is successful when:

- settings and resource usage are recorded clearly enough to compare runs later
- large-bundle limitations are visible rather than hidden
