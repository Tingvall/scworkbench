# Owned public graph promotion: source checkpoint

Pre-code plan/budgets: `13e4222`,
`GRAPH_OWNED_PROMOTION_SINGLE_CLOSURE_PLAN.md`, before this runtime change.
No execution, installation, syntax test, matched timing or pass is claimed here.

Only `.wb_graph_stage_small` gains a private default-FALSE deferral argument.
Its ordinary/native caller still performs the original complete SQL content
closure and returns `state$content`. The locally owned new-stage path in
`.wb_promote_graph` selects deferral and immediately performs the unchanged
`.wb_graph_sql_identities`: full actual SQL validation/content/binding/descriptor
before destination artifact/header/component writes. No expected digest is
reused. Aggregate policy/disk setup between construction and that closure stays;
all quotas, both source assertions, borrowed-stage seal comparison, copy order,
transaction and cleanup remain. The existing lexical stage owner is sufficient;
no promotion-workspace stage registry, authority cache or lifecycle service is
introduced. No stage escapes this promoter-only route before the full closure.

Source audit of R/src found `state$content` only at its assignment; no native C
code consumes that environment member, invokes stage_small, or changes its
closure. Runtime callers are `.wb_promote_graph` and ABI4 `write_graph` in
`operation_pack_v4_graph_adapter.R`; the latter is unchanged and uses default
validation. Direct tests/helpers also keep the default. Existing full retained,
recovery and recipient paths receive no deferral. Canonical identity machinery
and C source are unchanged.

Current attribution before code measured the same owned SQL stage's complete
hash twice (2.285s and2.479s, identical141165-byte preimage/78cee45a...); those are
instrumented nested observations, not a saving estimate. The exported attached
public function did not receive the namespace tracer, so no Rprof was generated;
no sampling attribution is claimed. The frozen plan's matched 10% promotion
target/RSS10%/unaffected1.10+.02 and original whole3s/20%/171s criteria remain
unwaived. Fresh matched evidence is required before selection.

Five new source tests in `test_engine_graph_owned_promotion_closure_contract.R`
cover default closure plus exactly one promoter hash and both source assertions,
independent literal two-node content/ordered nodes, default-versus-deferred
malformed actual SQL failure, identity/resource/copy faults and restored retry,
actual aggregate cache allowance and exact policy restoration, competing
primitive/resource single-boundary precedence, borrowed seal mutation rejection,
actual destination UNIQUE collision, nonempty independently retained cell-source
bindings, stale-source rejection and restored successful binding identities.
These are proposed test assertions, not results. Binding/descriptor comparisons
are independent-input public-helper consistency, not an independently implemented
hash encoder. All fixture-owned stages, namespace spies and options are restored
before bundle/root cleanup. The deferral intentionally moves the SQL closure
past aggregate setup/disk observation; no universal competing-fault error-order
equivalence is asserted. Exact current single-boundary diagnostics are retained
and tested; further combinations require explicit review rather than a waiver.

The trust documentation now points to the scoped installed68 recovery evidence,
without claiming source-bound/Python/scale process replacement was measured.
