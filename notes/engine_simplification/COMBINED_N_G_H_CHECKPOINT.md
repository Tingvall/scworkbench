# Selected N/G/H assembly before final qualification

Runtime checkpoint `9ce055d3b730618d4f8edc5d80284ac00b4f7ab5` combines the
previously assembled N/G candidate with Forge's own H commits c98d011,
3a9ce3f, 4611dd6, f92cc77 and ab33e95. No audit branch, official pack, profile
or Python source was integrated. This is not final acceptance.

Source comparisons returned zero: H's manifest R, native sources and selected
manifest tests equal ab33e95; G's six runtime files equal 649c740. The manifest
R SHA is `3880fcb50b9b8c71d78f327d0bf77524aa72279fef172b4e1c4ccc79a16bb807`;
the whole-chunk test SHA is
`f851dc5e179f639d71983f4951976524782cc12b1151abcc35d51a571f107d3e`.
The C encoder and registration remain byte-identical to c3960db. These
comparisons are integration evidence, not combined execution evidence.

## H's actual installed results and selection

`T=/tmp/scwb-engine-simplification-forge-20261018`.
`T/manifest_native_whole_ab33e95_install` discovered and executed 24 tests in
seven files: **24 passed, zero skipped/failed/excluded**. Its eight numeric
gates and outer supervisor are zero. Focus log SHA
`329d8fe6073c089f8df5645863e8c080343cc42aeca42d27420f6b618f096464`;
actual installed DLL SHA
`534dd3eea5098e1c892e25db8fcc933ca5b345329313da3fcb0f6c007f3247a8`.
This is a separate H component, not 24 tests executed on the assembled source.
The earlier 4611 installed result remains 22/24 passed, two failed, outer1.
Its invalid fixture premises and independent old-path diagnostics are retained
in NATIVE_WHOLE_FOCUSED_FIXTURE_CORRECTION.md and the raw evidence.

`T/manifest_native_whole_ab33e95_candidate_measurement` ran six fresh plain
processes, then a distinct existing-hook census. Large times were
3.499/3.372/3.368s (median **3.372**), tiny .357/.339/.337s (median **.339**),
maximum whole-process RSS **193132 KiB**. Relative to the fixed c396 baseline
3.542s, the observed large improvement is **4.8%, not the required 15%**:
3.0107s MISSES. RSS219599.6 and tiny.4204 pass; historical tiny.160 still
MISSES. Fifteen of seventeen unchanged budget rows pass. Numerical comparison
and outer supervisor remain **1**; the other sixteen numeric gates, including
the separate census and all byte/purity guards, are zero. No retiming or waiver.

Fixed budget CSV SHA
`d23a23e8a4ae3b7051142e0938628b0fba9c424ed35c10e96e28bdf5afa02a31`;
six-trial CSV SHA
`356fc0a7496408fecb1510e18fdc11e72aac9118f498fa954d011b3d5914f2d1`.
All 46 table/487202 row identities and the old independent state fingerprint
match. Original and owned SQLite/filesystem bytes and policies remain exact.

The separate census observed 70 successful whole chunks, 348070 rows and
30848654 JSON bytes; 150 scalar attempts (12 native, 138 fallback). Whole
attempts that fall back are not unique row coverage. Whole plus scalar-native
coverage is the same 360490 rows observed in c396. Different framing means
encoder-call byte sums are not a new content identity or physical I/O count.
Every observed allocation ledger stays within the original reservations.

Forge selects this narrow existing-encoder reuse because it avoids token-file
routing for those 70 chunks and consistently reduces observed time and RSS
without a cache, identity scheme, authority boundary or additional native
implementation. Selection does **not** satisfy its prospective speed target or
establish practical whole-engine performance; the miss remains a failed gate.

## Ownership and remaining qualification

Four explicit generic-core ownership rows retain the 4611 ownership decision
and pin the corrected f92 test source. The original current-only generator
actually reports **590 definitions/231 files, 350 introduced, two moved**;
254 explicit engine-addition rows. The ownership contract and comparison of
the frozen 242/139 baseline, 63 migration references and 85 historical addition
rows return zero. Raw gates are `T/combined_ownership_9ce055d`. These are source
discovery/accounting results, never 590 executed passes. Earlier e81 graph39
and metadata20 results remain distinct from H24, with no aggregated suite claim.

No additional source-observation cache or policy authority was introduced.
The proposed publication-handle cache remains held, not implemented. The
source-only pre-existing graph durable-rehydration concern remains unmeasured;
ephemeral graph39 does not qualify process replacement. Unsupported Python
typed-space execution and other unmeasured primitive/backend routes retain
their explicit limitations. Historical 392 full Xenopus462.58s/171.124s MISS,
typed-space5s, graph direct-overhead, tiny and other component misses remain.

One frozen installed complete-core run, current default-guard full Xenopus and
independent scientific comparison, representative lifecycle checks, current
protocol/documentation checks and independent Sable/Meridian dispositions are
still required. Preserve all old raw evidence. No merge, push, profile change,
container build or protected experimental-evidence modification is authorized.
