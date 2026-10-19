# Invocation-local token accounting: budget before implementation

Parent df8db854cbc0311a5f8e809a88993c758887ca7d; actual installed source
2ebfd47540b2bcca97947fad6e4437077df2bee8; runtime
bc6b0d664dbe2a883358b7e5d0036aa07a75b408. No runtime change in this commit.

The matched matrix-axis gate remains FAILED: physical verification 1.629 ->
.610 seconds (2.670x), 2128 -> 76 membership queries, RSS within budget, but
combined feature/cell hashing .927 -> 1.027 seconds misses the original 2x
target. All eight processes preserved actual identities, SQL and full FS.

Actual subsequent diagnosis is separate from plain timing. Under
`/tmp/scwb-engine-simplification-forge-20261018/matrix_axis_hash_df8_diagnosis`,
five new cell-axis hashes sampled 3.64 seconds: disjoint numeric/int64 work
2.84 seconds (78%), SQL .11, canonical encoding .17, resource checks .05.
Inclusive emit/binattr/integer64 timings overlap and MUST NOT be summed.
The requested 1ms sampling was unsupported: raw profiles actually use 10ms;
corrected derived reports preserve the erroneous initial derived files.
No median budget is passed by those instrumented profiles.

Five cell-axis hashes call add_count 10000 times, graph_i64 30010 times,
token_hash 10 times and transient_admit 80 times. Each token spill revalidates
the SAME immutable token limit and constructs int64 arithmetic carriers for
each actual emitted comma/string. Source-axis counters remain independently
checked; this amendment does not change their implementation.

Proposed implementation: lazily retain an ordinary invocation's validated
token limit; for valid plain quotas <=2^53-1 use exact numeric byte accounting.
Accepted additions must satisfy length(bytes) <= limit-count BEFORE adding.
On crossing, restore exact int64 state and execute the old increment/rejection
path, permanently retaining fallback, including when an emitter catches an
error and continues. Larger/attributed/reference-like policies retain int64
behavior. Preserve first-emission conversion/error/write order, every actual
byte/overflow/limit check, spill thresholds, final admission, cleanup and SHA.
No content cache, new identity, changed primitive, executor or public contract.

Budgets fixed before implementation:

- Retain the original >=2x complete combined source-axis-hash target against
  old2c5, >=2x physical verification and >=90% query reduction; do not replace
  the failed df8 median with a profiler estimate or weaken its ceiling.
- Reduce graph_i64 calls from 30010 to 10010 over the SAME five-cell-hash
  census (source-axis add_count remains 10000; token limit parsed once per hash).
- Whole-process peak RSS <= old2c5 +10%, actual source metadata bytes and both
  ordered/membership passes unchanged, all identities and lifecycle assertions.
- Full Xenopus 171.124s and graph/mixed/space budgets remain unwaived. This
  component alone cannot establish engine-wide acceptance.

Source agreement requires exact counter/error-state, scalar fallback and
adversarial tests before measurement. In particular, zero-byte/empty emitters,
quota boundaries, caught failed emissions, >2^53 quotas, attributed policies,
write/spill faults and original canonical bytes must be tested independently.
