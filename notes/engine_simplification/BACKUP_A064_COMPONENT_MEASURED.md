# Scoped backup continuity: measured component checkpoint

Source/runtime e29dd00b85bc1be35990d8005890c02b00ccd2b9; test-only descendant
a064cf836139acb46b724468b3077f4cb95686af. Reused immutable
`backup_e29dd00_install/library` (no recompilation); R/src diff is empty.
Actual DLL SHA256 is
`9f41e0762f3ffc0e1b264001f8ec7670ebfef714281252e71d049b10dfc11efc`,
retained in installed.sha256 and both measurement input locks.

Evidence task root `/tmp/scwb-engine-simplification-forge-20261018`:
`backup_a064cf8_component_measurement` status
`COMPLETE_MATCHED_BACKUP_COMPONENT_ALL_FIXED_AND_FRESH_BUDGETS`; all14 numeric
gate exits0 and outer supervisor0. Six alternating fresh plain processes plus
two separate instrumented censuses; no census timing enters medians.

| Metric | Matched old2eb | e29 | Prospective target | Result |
|---|---:|---:|---:|---|
| Public session create median,s |1.552|1.313|≤1.4076 and ≥10% below fresh old|PASS|
| Observed whole source-check/create/check cycle median,s |1.868|1.635|≤1.6848 and ≥10% below fresh old|PASS|
| Whole-process maximum RSS,KiB |611252|610716|≤672113.2 and ≤fresh old×1.10|PASS|
| Actual source snapshots |2|1|2→1|PASS|
| Stage snapshots |2|2|unchanged2|PASS|

Create reduction15.40%; observed cycle reduction12.47%. Complete source-file
SHA inventories, exact original source observation/actual epoch, source/stage
ordered SQL/schema/native identities and physical getter values/axes pass.
The direct SQLite copy remains a fewer-services observation, never a
service-equivalent framework denominator. All larger-workflow budgets remain
unchanged; this is not engine-wide performance or acceptance evidence.

Qualification chronology is retained without relabelling: original no-baseline
attempt discovered19/executed0,exit1; actual original run executed19,passed17,
failed2,skipped0,exit1 (two documented fixture premises). Corrected retry ran
only the five new tests:5/5 passed,0 skipped/failed,exit0. The existing14 passing
contracts plus corrected5 provide distinct combined coverage, not a fresh19-pass
execution. Raw failures, correction note, retry log and measurement guards remain
immutable.
