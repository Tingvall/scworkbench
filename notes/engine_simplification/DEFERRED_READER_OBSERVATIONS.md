# Deferred trusted native-R reader observations

Status: FUTURE WORK ONLY. Neither alternative is adopted or implemented.
The Controller's 2026-10-20 delivery order accepts the practical retained
392.28–427.76-second Xenopus performance and stops further optimization.
Historical budget failures remain failures, but no longer gate this delivery.

The [per-read v2 design](TRUSTED_R_SLICE_OBSERVATION_DESIGN.md), reviewed at
8a35c4978fbe75926a38f71e24b29480ffd4a48e and status-frozen at
07e6b749e36c096c2acb1a7ecea21751d64276dc, is preserved as historical design-only
evidence. Its four proposed record shapes are not current protocol definitions.
Design vector/prototype checks are not runtime qualification.

For a separately authorized task, prefer the smaller alternative: enforce
selection, alignment, size, numeric-domain and exact coverage invocation-locally,
using bounded counters/cursors or coverage state; explore one versioned
completion observation per reader grant, binding authenticated source/request,
coverage, call count and completion status. Do not require persisted records or
value digests for every trusted native read merely to defend against arbitrary
native pack behavior. This recommendation is also deferred, not implementation
approval or a selected schema.

Preserve returned-value validity checks currently embedded in identity
calculation, including dimensions, integer/finite-domain rules and existing
numeric-format error behavior. Retain request/publication source authentication,
output content identities, complete sibling/output closure, recovery verification
and atomic rollback. Historical receipt semantics remain unchanged. Treat
cross-process Python transport separately. Introduce no executor, universal
cache service or replacement validation framework.

There are139 potentially eligible native reads in the retained workflow.
The30–36-second inclusive measurement covers ALL147 matrix semantic identities,
including output and other identities that must remain. It is not measured
eligible savings. Even removing that whole bucket would remove only about8%
of observed workflow time; neither proposal alone resolves most remaining cost.
Registry snapshots and publication/receipt processing are additional future
targets, subject to measurement and separate prioritization. Any future change
must justify complexity removed and end-to-end benefit, not just a fast kernel.
