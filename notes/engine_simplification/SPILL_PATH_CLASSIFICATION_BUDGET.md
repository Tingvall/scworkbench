# Prospective byte-exact spill-path classification optimization

Baseline source3922292b0572ac8aa0cb91cfe1e56239e495623d/runtime3009a196a36ed9cec8c471336983a5fd4b7de867.
This budget precedes runtime changes. No implementation or measured benefit
is claimed by this document.

The actual small public ABI4 graph profile records21.89 sampled seconds during
execution (20.828s in the separate plain trial). `grepl` accounts for2.51s self;
most of those samples are the two per-descriptor ownership-prefix tests in
`.wb_graph_transient_usage`. Profile-inclusive costs overlap and are not a
lower bound or an all-engine attribution. The plain complete lifecycle44.694s
versus direct parts/SQLite0.131s misses the unchanged+3s goal. Setup1.4s is
separately excluded; the observed lifecycle also includes2.169s outside named
engine phases. Do not attribute that gap to engine validation.

Proposed scope: replace only classification of a previously read actual file
descriptor target by a compiled byte-prefix predicate equivalent to the two
existing `(^|/)` patterns. No scan, readlink, stat, inode deduplication, actual
byte observation, resource admission, source authority, rollback or recovery
check is removed or cached. No new representation, identity or public API.
Unsupported carriers retain the original R predicate. Preserve temporary
precedence when a target contains both a temporary and stage prefix.

Numerical targets, measured before making any further implementation change:

- Complete classification of a fixed100000-target corpus at least5x faster,
  with exact literal old-pattern results and no changed error/fallback behavior.
- Whole-process peakRSS no more than matched old+10%.
- At least10% improvement in the complete public ABI4 run phase; record a miss
  if this local change cannot deliver it. Full observed-lifecycle+3s, native
  graph+3s, mixed+2s, typed-space5s, and Xenopus171.124s budgets remain unchanged
  and unwaived. A component pass cannot establish any of those workflow passes.
- Require actual compiled-path use, literal pattern parity for ordinary and
  unusual/deleted/byte-encoded targets, and exact actual descriptor-inventory
  ownership and resource/fault behavior. Independent existing lifecycle gates
  remain separate from this classifier qualification.

Keep profile and separate call census explicitly instrumented, not new plain
budget timings. Do not resume full suites or image work for this narrow change.
