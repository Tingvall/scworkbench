# Native matrix-axis string decoder: scoped measured result

The runtime/test checkpoint is `f16c235e78d607cafadd277d61a0c1efdc141b92`.
Its prospective budget is the preceding
[native decoder budget](NATIVE_AXIS_STRING_DECODE_BUDGET.md), committed before
implementation. This is a component result, not engine-wide qualification.

`T` denotes `/tmp/scwb-engine-simplification-forge-20261018`.
The exact Git-derived installed package is `T/native_axis_f16c235_install`.
Its focused runner `T/run_native_axis_string_decode_focused.R` discovered and
executed 40 tests in five files: **40 passed, zero skipped/failed**. The log
`T/native_axis_f16c235_focused.log` retains 29 expanded DBI deprecation warnings;
its numeric sidecar is zero. Tests exercise the literal previous decoder,
escaped and unescaped strings, UTF-8 and byte boundaries, actual source mutation,
real resource guards, cleanup, and finalized getter/purity behavior.

The matched triplet command was:

```sh
SCWB_NATIVE_AXIS_TRIPLET_RELEASE=YES bash T/run_matrix_axis_f16_triplet.sh \
 /home/dirk/Projects/.scworkbench-worktrees/native-axis-json-token-forge-20261019 \
 f16c235e78d607cafadd277d61a0c1efdc141b92 \
 T/native_axis_f16c235_install/library T/native_axis_f16c235_install/install.exit \
 T/native_axis_f16c235_focused.log T/native_axis_f16c235_focused.exit \
 T/native_axis_f16c235_triplet_measurement
```

The outer `T/native_axis_f16c235_triplet_supervisor.exit` and all 23 inner
numeric gate sidecars are zero. Fourteen actual fresh runtime processes ran:
nine alternating plain trials across old2c5/middlec826/newf16, three separate
DBI censuses, and two new helper censuses. Older helper censuses are explicitly
hash-locked historical evidence, not newly executed trials.

| Measure | Old2c5 | Middlec826 | Newf16 | Fixed result |
| --- | ---: | ---: | ---: | --- |
| Physical verifier median, s | 1.606 | 0.857 | 0.712 | 2.256x old; 16.92% below middle; pass |
| Combined axis hashes median, s | 0.945 | — | 0.265 | 3.566x; pass |
| Membership queries | 2128 | 76 | 76 | 96.43% reduction; pass |
| Maximum whole-process RSS, KiB | 610304 | 619092 | 615944 | Within old +10%; pass |

The fixed physical ceilings remain 0.803s (old/2) and 0.72845s
(original middle ×0.85). During preparation, before any trial, the comparator
was corrected because it accidentally applied the 15% improvement twice.
`T/NATIVE_AXIS_F16_TRIPLET_PREPARATION.md` preserves that correction; no measured
budget was relaxed. Independent actual helper censuses show 5320 general
strict/graph/canonical JSON parses reduced to zero over five plain physical
verifications. Escaped/control cases still use the unchanged strict parser.
All resource admissions remain; numeric-counter admissions are unchanged from
middlec826. Metadata bytes and both ordered-axis/membership passes remain.

All literal preimages, physical-source checks, ordered axes, scientific values,
actual SQL and complete filesystem comparisons passed. Metadata-byte counters
are not claims about kernel I/O or matrix-value scan counts. No identity,
schema, public parser, storage or scientific setting changed.

The earlier axis-only hash-budget failure and token-only physical-budget
failure remain intact in their original logs and sidecars. The new code change
and fresh triplet close those particular component budgets; they do not erase
the failed experiments. Full Xenopus, graph, mixed and typed-space workflow
budgets still require the assembled-candidate evidence and remain unwaived.
