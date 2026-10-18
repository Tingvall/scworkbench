# Fresh initializer: measured constructor reuse

Source `1ce748d05f000478d81496fe9cefc7bef97a343f`, clean Git-derived installed
namespace, versus installed242/1f. Five focused contracts all passed, including
fresh assembly/finalize/recipient behavior, changed-publication fallback,
schema/connection checks and exact nested caller-lock ownership on faults.

Final measurement command, terminal exit0:

```sh
SCWB_INITIALIZER_RETRY2_RELEASE=YES bash /tmp/scwb-engine-simplification-forge-20261018/run_initializer_1ce_measurement_retry2.sh
```

Three complete constructors in independent new directories per implementation:
median1.802s ->1.094s (39.29% reduction, prospective25% budget passed).
Whole-process RSS119936 ->119572KiB (old+10% budget passed). Timing excludes
independent post-constructor checks and finalization; process RSS includes them.
Fields, schema, migration IDs, settings, namespace, formals, exports, stable
manifest values and nonclock registry contents match. EACH actual published
state independently equals a fresh SQL snapshot. NEW returned manifest equals
the published parsed manifest exactly. No ordinary open/recovery work is skipped.

Two initial comparison failures are retained, not relabeled:

- `initializer_1ce748d_qualification`: all5 focused tests passed, then old242
  measurement rejected the baseline's stale in-memory publication timestamp.
  Untimed diagnostic proved ONLY `publication.published_at` differed between
  that returned manifest and its actual published manifest.
- `initializer_1ce748d_measurement_retry`: old cross-instance comparison rejected
  `metadata_fields` hashes. Retained SQL proves only registration `created_at`
  and `updated_at` differed across those independent empty bundles; all15 other
  columns match. Migration `applied_at` also varies by construction.

The final comparator retains all raw clocks, table digests and state digests;
it does not rewrite hashes or claim equality of clock-dependent identities.
It compares each actual published identity to that instance's actual SQL,
and compares all nonclock fields across implementations. Only the proved old
returned publication-clock divergence is normalized for that specific assertion;
new returned-manifest equality remains strict.

All logs/atomic sidecars, diagnostics, raw instance metadata, harness locks and
installed hashes remain under the named directories in
`/tmp/scwb-engine-simplification-forge-20261018`. This component gain is not a
new combined workflow result. Source review also caught and corrected an
initial double-release cleanup route before runtime qualification (d265→1ce).
