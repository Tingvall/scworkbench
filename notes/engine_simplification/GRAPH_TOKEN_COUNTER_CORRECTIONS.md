# Token-counter first qualification and source-review corrections

The budget-first commit is 0c699a3d1e3a1b3e2c1335bb1a07c693ef0eb3c2.
The initial runtime/test candidate ffc66c2b6c286e33458ded3b7a9ca595dcb925a1
was installed from its clean Git archive. Local source review permitted focused
execution while the external Sable review was still pending. That external
review then identified an additional unsupported-policy evaluation-order defect.
Source review is not a guarantee that a candidate has no defects.

The first installed focused command is retained under
`/tmp/scwb-engine-simplification-forge-20261018/token_ffc66c2_focused`:
35 discovered/executed, 34 passed, zero skipped, one failed, exit 1. The failed
test attempted to obtain `+.integer64` before loading the bit64 namespace;
the alphabetically first test had not yet performed any bit64 operation.
An explicit namespace-load diagnostic confirmed that the method exists.
The raw log also expands 29 DBI deprecated-result-list warnings. This was
neither a passing nor a warning-free gate.

Separately, the initial eligibility predicate checked `length(token_bytes)`
before excluding classed/attributed quotas. A classed character quota could
therefore dispatch its length method an extra time, despite being ineligible
for the fast path. The correction excludes attributes before that dispatching
inspection. A new old/new classed-quota side-effect/error oracle must exercise
this behavior; the initial six tests did not expose it. This is a runtime
correction, not a test-premise reclassification.

Subsequent source review found the analogous dispatch risk for a classed
private copy-reservation attribute: `is.numeric()` is an internal generic.
Its attribute exclusion now also precedes generic inspection. A test installs
a throwing method, proves that it dispatches outside the helper, and requires
zero such calls for both old/new real-spill executions. Unsupported carriers
therefore keep the old path without extra predicate-method side effects.

No performance measurement was run on ffc66c2. The original matrix-axis hash
budget miss remains unwaived until a corrected frozen candidate passes both
focused qualification and the unchanged matched component budgets.
