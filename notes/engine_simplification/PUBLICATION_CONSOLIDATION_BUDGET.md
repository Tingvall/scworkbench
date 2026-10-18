# Prospective publication consolidation budgets

Before implementation, base `e9e561c940b482138456854f67970eca256966e7`.
One profiled mixed-storage diagnostic observed engine phases 19.332 s versus
direct .407 s: overhead 18.925 s, a MISS against the existing <=2 s goal.
Snapshot cost 11.85 s is inclusive sampled time across disjoint phases, not an
additional elapsed phase. Source and raw evidence: external
`/tmp/scwb-engine-simplification-forge-20261018/MIXED_E9E_ATTRIBUTION.md`.

Planned changes retain existing identity schemes and atomic writer/workspace
authority. Snapshot-local observer sharing is a separate implementation.

- Exactly one authoritative manifest publication after successful public
  promotion, including target reproduction; no terminal success on publication
  failure. Assembly lifetime-lock nesting must still publish ordinary APIs.
- Exactly one explicit full artifact migration per ordinary promotion, not one
  per output. Private subwriters still check current ledger/exact live schema
  and foreign-key enforcement. Explicit public migration and graph-policy
  fallback retain full checks. DDL/TEMP changes and recovery must not inherit
  an unchecked verdict.
- At least 3x faster plain-character ordered-key equality for 8000 rows, exact
  equivalence to the old per-row serialization comparator; factors, attributed
  or unsupported columns keep the original comparator. Retained descriptor
  tokens and content identities are not changed.
- Unchanged finalized close may reuse only a successfully published manifest
  bound to the same live connection, current writer owner and SQLite epoch,
  and independently matching manifest bytes. Direct SQL/rollback/DDL/TEMP /
  attachment/connection/owner/manifest changes must force rebuilding.
- The mixed <=2 s overhead budget remains a target, not waived or relabeled
  after this diagnostic. Report timing misses, cold attestation/backend service
  differences and remaining passes honestly. No performance acceptance is
  established by source review or focused correctness tests.

## Focused development evidence

Own installation `library_publication_dev` under the external task root:
`publication_dev_focused.log/.exit`: seven discovered/executed/passed, no skips
or failures (four publication/key tests and three snapshot tests). The target
reproduction test initially omitted its required `vector_name` parameter; that
fixture failure remains in `publication_target_dev.log/.exit`. Corrected fixture
`publication_target_dev_retry.log/.exit`: public metadata-vector execution,
promotion, source-only clone and target replay passed with exactly one manifest
publication after receipt insertion and a complete verification receipt.

`publication_key_benchmark.log/.exit`: 8000 ordered keys, original comparison
7.863 s, installed comparison mean .0042 s over 100 calls, 1872.143x; exact
comparison true and >=3x budget met. This is a comparator microbenchmark, not a
complete storage workflow performance claim.

The independent cleanup steps and source-forget witness invalidation were added
after this development installation and require final installed qualification.
