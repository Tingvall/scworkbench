# Bounded affected-workflow development attribution

This is NOT the final coordinated qualification, a full-size Xenopus result or
a complete direct-workflow comparison. It locates remaining shared framework
cost before freeze. No runtime change occurred during this probe.

Input: 4,000 features x1,000 cells, sparse density.05, positive integer counts,
one deliberately zero-library cell. Exact original settings: CP10k/log1p with
chunk2000; HVG2000 vst/chunk256; PCA50 irlba centered/scaled/chunk256 seed1;
UMAP dimensions1:30, neighbors30, min_dist.3, spread1, Euclidean/nndescent,
seed1. Public durable sessions, official pinned RNA/Representation packs,
promotion, finalization and read-only reopen. Default dense guard256 unchanged.

Command:

```
inst/ci/run_logged_gate /tmp/scwb-engine-simplification-forge-20261018/bounded_development.log /tmp/scwb-engine-simplification-forge-20261018/bounded_development.exit -- timeout --signal=INT --kill-after=30s 600s /usr/bin/time -v Rscript notes/engine_simplification/bounded_development_workflow.R /tmp/scwb-engine-simplification-forge-20261018/library_dev1 /tmp/scwb-matrix-streaming-forge-20261018/verified-library /tmp/scwb-engine-simplification-forge-20261018/bounded-development
```

Exit **0**, marker
BOUNDED_DEVELOPMENT_DURABLE_FOUR_OP_PROMOTE_FINALIZE_READONLY_OK.
Wall **173.43 seconds**, user171.09/system1.09, peak RSS**967,684 KiB**.
No other R process was running at launch; CPU use approximately one core.
Per-phase .01-second Rprof and macro-function traces are instrumentation, not
an uninstrumented speed comparison. Library .rdb/.rdx/.so SHA identities were
recorded and checked identical at the end. Installed library remained untouched.

| Phase | Seconds |
| --- | ---: |
| Initialize/import source matrix | 6.507 |
| Durable session create | 3.360 |
| Normalization | 4.284 |
| HVG | 9.549 |
| PCA | 82.434 |
| UMAP | 10.680 |
| Independent complete normalization comparison | .252 |
| Promotion | 49.787 |
| Finalize/close | 3.176 |
| Read-only reopen | 1.037 |

Every normalized value matched the independent R reference within1e-14 with
exact axes; zero-library count exactly1. All promoted outputs succeeded, and
both new spaces reopened. A harmless already-disconnected warning arose from
the harness's cleanup attempting to close the already-closed final handle;
not a failed lifecycle gate or a new runtime repair.

## Dominant remaining work

PCA82.434 seconds is overwhelmingly canonical serialization, not fitting:
sampled canonical_json71.16 seconds (86.37%), receipt_builder36.49,
record_validate28.94, observed_descriptor24.25, canonical_string35.11;
irlba::prcomp_irlba1.92. These inclusive times nest and are not additive.
Input descriptors2 calls4.255 seconds, matrix source-content identities3
calls.101, eight chunk semantic hashes.082, table provenance identities6
calls3.809, manifest snapshots4 calls4.863. Checkpoint itself only.340 seconds
and JSON28KB. A live-tail observation initially pointed at checkpoint work;
completed profiles disproved that hypothesis and root was corrected promptly.

Promotion49.787 seconds: record_validate27.08 sampled seconds, canonical_json
26.08; transition-payload preparation27.09. Census: twelve table-content hashes
7.667 seconds; manifest snapshots3 calls3.816; schema32 calls.865. Normalization
and HVG source-byte integrity is not the large cost here: HVG's three consumed
source identities totaled.070 seconds and sixteen bounded chunk hashes.176.
HVG canonical_json6.83/9.54 sampled seconds; registry_reads_assert_current2.13.

UMAP10.680 seconds: uwot compute2.54 sampled seconds; canonical_json2.58;
inherited dependency payload validation3.681 elapsed seconds, almost entirely
table provenance hashing3.673. Its checkpoint.332. This is a concrete case
where an operation is paying for unchanged inherited table output validation.

Sources to inspect: R/operation_pack_v2_transition.R input/observed descriptors,
receipt construction and record validation; R/operation_pack_v3_registry_reads.R
registry snapshot identities/assert_current; R/durable_sessions.R dependency
payload validation; promotion's prepare_transition_payloads. Changes must retain
receipt/payload/source/closure authority, follow the reviewed trusted execution
boundary, and must not silently change canonical bytes or identity schemes.

All macro counters and per-phase profiles are retained. Approximate-zero
negative duration around1e-15 in one census bucket is floating timer subtraction,
not negative execution work. Byte counters are syscall logical/physical IO,
not inferred whole-source pass counts. No peak-disk or native-only compute
comparison was measured. Raw Rprof files remain in the isolated chamber;
compressed log, timings/census and profile CSVs are adjacent durable evidence.

Installed code identities:

- R/scworkbench.rdb:
  f3eed7ae1e4776b44f05f3589a8230c224e2a3175a308714675f4113bccbc661
- R/scworkbench.rdx:
  035cbff95cc03d2f547ef5bdcf19020ca1c89c077562eb35f650768fa2d0148f
- libs/scworkbench.so:
  666f53c0a6228f2898975a83be0e7de5b635334942bb8f81b8522fb5e2c2585d

This development probe supplies attribution, not a claim that low-overhead
budgets or engine-wide acceptance have passed. Full real direct reference and
prospective budgets are retained separately; root owns further changes/freeze.
