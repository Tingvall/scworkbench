# Invocation registry snapshot budget (before implementation)

Repaired baseline 8f53e950 calls the full snapshot directly at three shared
operation-pack request/source/lineage callsites. Repeated calls inspect the
same registry within one active mutation context; benchmark before/after with
five requests at one unchanged SQLite epoch. Target one full snapshot instead
of five, elapsed <=0.35 times baseline +0.02 seconds, unchanged fingerprint.
After same-connection write, rolled-back write, external-connection commit or
schema change, the next request must recompute (conservative invalidation).
No cache across context exit, connection replacement, recovery or explicit
manifest/content validation. File-byte authority is not represented by this
cache. Measured 300-cell history operation budget remains the predeclared
<=1 second overhead; no retrospective relaxation if this alone misses it.

Fresh transition proposal budget (before implementation): native-R-only final
path byte verification stays mandatory, while duplicate semantic reconstruction
after our writer sealed exact bytes is removed. Target zero calls to the
ordinary primitive semantic decoder inside immediate record revalidation,
but unchanged post-rename corruption rejection and rollback. Full persisted
semantic checks stay on recovery, Python and graph paths. Small complete
workflow overhead budgets in baselines/BUDGETS.md remain authoritative.
