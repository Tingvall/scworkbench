# ASCII admission experiment: not selected

Source `f74f7ec36df6003457b872cce55ecc2047ff99a8`, isolated branch
`perf/manifest-ascii-token-bounds-forge-20261018`, is preserved but NOT integrated.
It applies an exact JSON string-size bound to a strict ASCII whitelist, gated
on the reviewed loaded jsonlite version, with conservative fallback otherwise.

Commands (both terminal exit0):

```sh
SCWB_MANIFEST_ASCII_RELEASE=YES bash /tmp/scwb-engine-simplification-forge-20261018/run_manifest_ascii_focus.sh
SCWB_MANIFEST_ASCII_MEASURE_RELEASE=YES bash /tmp/scwb-engine-simplification-forge-20261018/run_manifest_ascii_measurement.sh
```

Focused discovery/execution: 16/16 passed, four files, zero skips/failures;
12 warnings remain in the raw log. Complete immutable registry snapshot median
5.513s versus retained 5b baseline5.900s: 6.56% reduction, **MISS** the prospective
25% requirement. Original242 median12.576s: also **MISS** its 3x requirement.
Peak RSS221344KiB versus214840KiB: passes+10%. Every table/state identity,
independent materialized oracle and full source inventory matched exactly.

The five measurement gates passed parity/immutability checks; their exit0
does not turn the separately recorded speed misses into passes. The version-
specific fastpath complexity is not justified by this measured improvement.
Keep the simpler admitted scalar-batch implementation in the assembled engine.
Raw source, harness locks, installed hashes, timing/census logs, sidecars and
budget booleans remain under `manifest_ascii_f74` and
`manifest_ascii_measurement` in the task evidence directory. No claims about
new combined workflow timing follow from this experiment.
