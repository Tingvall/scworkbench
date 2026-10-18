# Repaired-baseline fresh source-aware import

Exact repaired installed core d7232f8 (delivery 8f53e95), public
wb_source_input + wb_source_preflight + wb_bundle_from_sce(source_identity=...),
source ID aztekin_tail_2019_sce_rds, accession not_supplied, external_file,
original approved RDS. No modified source or historical evidence. Default dense
guard 256 MiB; no scientific pipeline rerun.

```
inst/ci/run_logged_gate /tmp/scwb-engine-simplification-forge-20261018/before_source_import.log /tmp/scwb-engine-simplification-forge-20261018/before_source_import.exit -- /usr/bin/time -v Rscript notes/engine_simplification/baselines/source_import.R /tmp/scwb-matrix-streaming-forge-20261018/verified-library /tmp/scwb-engine-simplification-forge-20261018/before-source-import
```

Exit **0**, FRESH_SOURCE_IMPORT_FINALIZE_READONLY_RECIPIENT_OK.
GNU wall **161.05 s**, user **154.20 s**, system **2.53 s**, peak RSS
**1,503,984 KiB**.

| Phase | Seconds | Source SHA calls |
| --- | ---: | ---: |
| wb_source_input | 0.751 | 2 |
| explicit wb_source_preflight | 0.374 | 1 |
| import | 92.164 | 2 |
| finalize/close | 11.849 | 0 |
| readonly reopen/inspection/close | 0.403 | 0 |
| explicit recipient validation report | 55.282 | 0 |

Five source SHA-256 calls hash 365,874,915 source bytes in total. This census
covers wb_source_sha256, not every payload/registry/content hash elsewhere.
Per-phase logical/physical IO is retained in import_before_timings.csv; source
import rchar 1,368,654,130, recipient validation rchar 1,661,665,481. Warm-cache
read_bytes were zero; rchar is not a physical scientific-payload scan count.

Recipient status **ok_with_warnings**, no errors. Five warnings are precisely
EXTERNAL_SOURCE_UNVERIFIABLE: the declared external source is outside the
recipient trust boundary and is not inspected. Source authentication did occur
at admission as counted above; validation does not claim external-byte
reinspection. Pre/post bundle fingerprints identical:
9963c28dd5b7e1123426a53a79327055a259f7ccb34737443887fbee133c3875.

The actual public wrapper is wb_validate_bundle(path, read_only=TRUE), not
wb_validate_bundle(level='recipient'). This benchmark calls its same structured
authority once via wb_bundle_validation_report(path, level='recipient') to
retain diagnostics/timing without duplicating the complete validation scan.
Report RDS and original raw logs remain in the isolated temporary chamber.

The future final-candidate harness is
notes/engine_simplification/full_engine_xenopus.R: written/parsed, not executed
by this helper. It combines source-aware fresh import, exact original settings,
durable sessions, complete scientific comparison against direct data, promotion,
finalize, readonly inspection and explicit recipient validation. Root owns its
review, freeze and one coordinated final run. It intentionally avoids visible
printing of large returned bundle/model objects.
