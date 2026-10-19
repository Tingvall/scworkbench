# Empty capsule recovery: prospective budget before implementation

Implementation base df8db854cbc0311a5f8e809a88993c758887ca7d. Measured baseline
installed source2ebfd47540b2bcca97947fad6e4437077df2bee8 (same runtime), DLL
24bd313535750d6600844541ab8fb7f94725306a68ebe2449836350ce8c9bb6d.
Evidence root: capsule_empty_boundary_2eb_baseline; supervisor.exit0; all12fresh
processes0, all main SQL schema/table identities and scientific payloadSHA exact.
No runtime code had changed when this budget was recorded.

Three plain trials, default256MiB, owned64×1000 sparse fixture:

| Boundary | Median seconds | Whole-process peakRSS medianKiB | Separate census builders/publishers |
|---|---:|---:|---:|
| Fresh writable public open+close |1.209|623468|2/2|
| Private empty recovery/fresh writer owner |.340|623720|1/1|
| Direct existing raw lock/inventory/no-residue assertion |.002|618296|0/0|

Direct reference omits publication/schema/recovery services. No170x equivalent
workflow speedup is claimed. RSS includes package loading and complete setup,
not incremental boundary RAM. Old open/recovery legitimately changed manifest
bytes in8/8cases; direct4/4preserved all filesystem bytes. No false purity claim.

Predeclared candidate budgets: private median<=.034s (>=90% reduction); public
median<=.9672s (>=20% reduction); peakRSS<=matched old+10%; private-empty counts
0builders/0publishers, public-open counts1/1 retaining explicit migration.
Same fixture/installed qualification, separate uninstrumented and census trials.
All timings and count gains remain prospective until measured.

Scope: only existing capsule recovery's empty/no-work publication tail. Retain
fresh raw exclusive lock, inventory/path containment/ID/orphan manifest checks,
final no-residue proof, original returned list/visibility. Any actual removal,
including an empty.pending directory, still publishes(forceTRUE) and performs
the old best-effort checkpoint while exclusion is held. Caller-owned SQLite TX
keeps the original generic writer route; no caller commit/rollback. Error/partial
cleanup does not count as a successful publication. Explicit migration/refresh,
source identity, recipient and checkpoint contracts unchanged; no cache or new
authority. Full engine/Xenopus and graph/space budget MISSES remain unwaived.

Source policy was accepted by Sable before implementation. Exact source review
and focused correctness qualification are still required. No runtime jobs or
benchmarks authorized before the next coordinator release.
