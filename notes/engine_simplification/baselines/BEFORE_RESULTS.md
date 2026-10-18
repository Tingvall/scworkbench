# Repaired-engine bounded BEFORE measurements

Runtime: repaired `d7232f800190e1c1cb78af0e4591fa53e9003087` installed at
`/tmp/scwb-matrix-streaming-forge-20261018/verified-library`; parent delivery
`8f53e950e6eda4c86b0f4ce6623bc14a1f2e637e`. No runtime changes by this helper.
Prospective budgets are in BUDGETS.md; exact scripts and successful raw logs,
numeric sidecars and phase/IO CSVs are adjacent. Original raw logs remain under
`/tmp/scwb-engine-simplification-forge-20261018`; committed log copies use gzip
with deterministic header, not rewritten content.

Host: x86_64 Linux, Intel i7-1360P, 16 visible CPUs and affinity 0–15; ext4
`/dev/mapper/data-root`. Each R process used approximately one CPU. Warm OS
caches are not dropped. RSS is process-wide maximum from `/usr/bin/time -v`,
not attributable to one phase. `/proc/self/io` rchar/wchar are logical syscall
bytes, not scientific payload scans; physical read_bytes were mostly zero.
Full-source pass counts were not measured by these scripts.

| Case | Elapsed seconds | Peak RSS KiB |
| --- | ---: | ---: |
| All history fixtures, including constructing 20 prior runs | 107.08 | 621,884 |
| Mixed primitive synthetic storage lifecycle, including direct comparator | 14.17 | 628,368 |
| Table hash microbenchmark and object-fold chain | 7.30 | 87,592 |

For 300 cells, final durable metadata-vector execution after 0/5/15 prior runs
was 1.988/2.702/2.475 seconds. Promotion was 3.598/4.103/4.477 seconds;
finalization plus read-only reopen 1.417/1.709/1.608 seconds. The direct complete
SQLite metadata import/read/compute/output write/close/reopen comparison was
0.016 seconds. The <=1-second absolute-overhead budget is MISSED; <=1.5 times
empty history plus 0.1-second growth budget PASSES at this small history size.
No inference about thousands of previous runs follows. Session-view connection
GC emitted one dbDisconnect warning; lifecycle/value assertions and gate exit
were successful.

Mixed primitive storage fixture: vector, family, feature table, observation
table, path and contained model, with retained source space. Direct complete
SQLite/RDS read/compute/write/reopen was 0.294 seconds. Engine initialization
and source import 7.475 seconds, compute <0.001-second timer resolution,
atomic promotion 4.075 seconds, finalization/read-only reopen/all-output loading
2.131 seconds. <=2-second framework-overhead budget MISSED. Outputs recovered
with their asserted values and metadata. Both fixture RSS budgets PASS.

The mixed case deliberately uses synthetic run objects with the core catalog's
promotable terminal name `vector`; each actual primitive kind selects its
existing promoter. This is a storage/atomicity timing fixture, NOT evidence of
valid scientific operation dispatch or pack execution. The direct storage
schema differs and provides no provenance/recovery/atomic-publication services.
Its timing is a lower-service reference, not a claim of identical functionality.

Table hash totals at 100/1,000/5,000 rows were 0.086/0.765/4.055 seconds;
two-hex-digest object-fold-only chain 0.032/0.339/1.690 seconds. Fixtures contain
numeric/integer/character/logical data, missing values, Inf, Unicode and escapes.
Expected SHA-256 values are retained verbatim in table_before.csv. This is an
identity microbenchmark and must not be substituted for a complete workflow.

Harness pilots remain retained: representative initial test checked the wrong
field (`values` instead of `value`); mixed pilots used an unregistered op label
and then requested outputs absent from that op's terminal policy. Fixed final
scripts use explicit storage-only synthetic runs and recover all outputs.
A later exact table comparison also exposed existing default four-decimal
JSON persistence: mean -0.0079302032871361693 reloaded as -0.0079. The final
storage fixture explicitly declares round(mean,4) before both direct/engine
execution. This does not repair or conceal arbitrary numeric table precision;
the failed pilot remains in before_mixed_v3.log/.exit. No identity/schema/value
contract was changed. Root was informed; broad table precision changes are
outside this benchmark helper's scope.

## Literal successful commands

All were prefixed with `inst/ci/run_logged_gate LOG EXIT -- /usr/bin/time -v`:

```
Rscript notes/engine_simplification/baselines/table_identity.R /tmp/scwb-matrix-streaming-forge-20261018/verified-library /tmp/scwb-engine-simplification-forge-20261018/before_table_identity
Rscript notes/engine_simplification/baselines/representative.R /tmp/scwb-matrix-streaming-forge-20261018/verified-library /tmp/scwb-engine-simplification-forge-20261018/before_representative_v2
Rscript notes/engine_simplification/baselines/mixed_publication.R /tmp/scwb-matrix-streaming-forge-20261018/verified-library /tmp/scwb-engine-simplification-forge-20261018/before_mixed_v4
```

All three numeric sidecars are 0. Script parsing passed. No complete suite,
full-size Xenopus run, source/pack changes, merge, push or image work occurred.
Not measured here: matrix/scientific direct baseline (root-owned), graph,
large families, external adoption, nullable/sparse-family special storage,
Python transport, large unrelated histories, recovery costs or all backends.
