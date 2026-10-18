# Complete registry snapshot: terminal5b component measurement

Documentation-only record; no new measurement/test job was run while preparing
this note. This branch descends from frozen source
`1f853b6a3fb18480c1fe8504877f3b8f839d3fd0`; existing5b runtime and83f8c74
terminal242 accounting history remain unchanged. This is neither an overall
handoff nor readiness/performance acceptance.

Compared installed old runtime `242fdf071335b54c8ca78793b23982990733b7d4`
with candidate `5b96cb135d665449d131d06c04e2545b34285e7d` on the **same immutable
final242 Xenopus bundle**. New library is
`T/manifest_5b96cb1/library`, DLL SHA
`3bb765168d7492813474d9c3c07f93895618354031561bc331fdb925bafeb9b7`;
`T=/tmp/scwb-engine-simplification-forge-20261018`.

## Literal results and unchanged budgets

`T/manifest_5b96cb1/focus.log/.exit`:3files,14discovered/executed/passed,
0skipped/failed, exit0. Raw log reports12warnings without expanded warning
messages; this is not a claim of a warning-free run. Measurement root
`T/manifest_5b96_fullsnapshot_measurement`: all8 numeric gate sidecars0;
terminal status explicitly says inspect time/RSS budgets, not automatic
performance acceptance. Harness and installed RDB/RDX/DLL byte checks passed.

Three complete snapshot elapsed replicates:

| Installed runtime | Replicates seconds | Median | Process peak RSS KiB |
| --- | --- | ---: | ---: |
| old242 |12.576 /12.547 /12.923|12.576|202332|
| new5b |5.900 /5.939 /5.825|5.900|214840|

Prospective **≥3× target remains MISS**, observed2.131525×. The memory target
**≤old+10% passes**, ratio1.061819. Timing includes the entire registry snapshot
with its real admission/observation/serialization/finish work. Full source SHA,
opening, GC, independent oracle and traced census are outside these measured
intervals. Old/new timing, old/new census and oracle use separate R processes;
census/oracle allocations do not contaminate matched timing-process RSS. The
default dense guard remains256MiB. No scheme, framing, scientific values or
source authority change is claimed.

The **46 table identities**, row counts and registry-state fingerprint match
across old/new timing processes, both censuses and the independent original
materialized5000-row-fold oracle. Total487202rows,28nonempty tables,18empty
tables. State fingerprint:
`75713650b34d33144914bc13d19e1edfb53cf3e49e8187d2a2f98c5a6d5e24fc`.
Each process independently hashed all113bundle files/848153358bytes before
and after; all inventories match exactly. The oracle used no engine hash,
sanitizer or snapshot implementation: data frames are unchanged by the old
sanitizer, JSON options/header/ordered5000fold are reproduced independently.
Its separate reference-only SQL admission observed maximum cell430224bytes,
maximum logical chunk3998698bytes and conservative carrier/reservation
127984960bytes, below the512MiB reference cap. This cap is not a change to any
ordinary engine guard; no unexpected arbitrary payload was admitted.

## Separate census, not a new timing denominator

Sanctioned manifest hooks plus an untimed jsonlite return trace record actual
UTF8 bytes and pre-admission bounds without replacing installed authority
functions. Old7604events become1001; scalar7586→983, whole-chunk18→18. Both
cover487168rows on22tables. The other34rows and empty/fallback tables are not
represented by these two event kinds; counts must not be called all-IO or
whole-source pass measurements. Histograms show dominant scalar batch size
64old versus512new, while the existing whole-chunk maximum3199rows remains.

Per-call actual encoded bytes sum64775233old/64768630new. The6603byte difference
is exactly the difference in event count: independent JSON calls include their
own brackets/commas, not a changed logical5000-row digest stream. Maximum
encoded bytes194667 and maximum reservation7617320bytes are identical.
Every event asserts actual encoded bytes within its bound and
carrier+8actual/reservation within the existing8P reservation. Maximum admitted
ratio.908055 and maximum actual-carrier ratio.409619 pass; neither is an RSS
proof for every uninstrumented path.

Raw anchors: `old242/timings.csv`, `new5b96/timings.csv`, `budget.csv`,
`rss_budget.csv`, each`table_identities.csv`/`source_before.csv`/`source_after.csv`,
both census`batch_events.csv`/`batch_histogram.csv`, `oracle/oracle_admission.csv`,
all logs/sidecars, GNU-time files and run-local harness SHA ledger under the
measurement root. [MANIFEST_5B_COMPONENT_MEASUREMENT.csv](MANIFEST_5B_COMPONENT_MEASUREMENT.csv)
keeps numerical accounting alongside this prose.

The prior full242 workflow remains769.22s against unchanged171.124s target,
**MISS598.096s**. It has not been rerun on5b, and a2.13× component improvement
cannot be extrapolated into a new full-workflow result. Earlier tiny46table4×,
pager, table1000, mixed/direct, graph/direct and other budget misses remain
recorded. No overall acceptance or completion of the practical-performance
objective follows from these eight correctness gates.
