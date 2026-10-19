# Actual parent measurements frozen before implementation

Parent: `30f5a4c377587e2cc3ed36e37ac8ba7fa94a5091`.
Evidence: `/tmp/scwb-engine-simplification-forge-20261018/manifest_json_batch_parent_30f5a4c`.
All 15 numeric gate sidecars and outer supervisor exit are zero. One clean
Git-derived install; six fresh plain processes, no warm snapshot, instrumentation
or native-helper preinitialization. Copy/open/GC/independent oracle loading and
verification are outside the snapshot timer; first-call initialization is inside.

| Criterion | Parent | Frozen candidate ceiling |
| --- | ---: | ---: |
| Complete large 46-table / 487202-row snapshot median seconds | 5.203 | 4.42255 |
| Maximum whole-process peak RSS KiB, all six processes | 202416 | 222657.6 |
| Actual 46-table / 46-row tiny snapshot median seconds | .448 | .5128 |

Large observations: 5.610 / 5.203 / 5.152 seconds. Tiny observations:
.506 / .448 / .375 seconds. Whole-process RSS includes common setup and
independent oracle/proofs, not an incremental algorithm allocation measurement.

The large independent original fingerprint is
`75713650b34d33144914bc13d19e1edfb53cf3e49e8187d2a2f98c5a6d5e24fc`;
tiny is `41f858d891fc7dbd0e98b646563a6293b5cd7df3225ea88ea7e44e04c10d707a`.
Every owned copy and original SQLite file is byte-unchanged after closing;
original fixtures were never opened through SQL. Actual tiny rows, not empty
tables, were independently inspected after timing.

The CSV `FROZEN_PREIMPLEMENTATION_ABSOLUTE_CEILINGS.csv` SHA-256 is
`d161e752fa2bb8aa738438282cd0a33369305e399482933313c85d43e0ab8f12`.
`all_six_fresh_plain_parent_timings.csv` SHA-256 is
`d180ad2b51caf19e18cd255ece7e378fbc16e7f8b1f4edb339a2eb195da808a6`.
Future candidate measurements must preserve this preparation and scope.

Historical 4.192-second large and .160-second tiny ceilings remain missed and
unwaived. These measured prospective ceilings do not replace those obligations
or establish whole-engine acceptance. No batching implementation existed when
these results were produced and committed.
