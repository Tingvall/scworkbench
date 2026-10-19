# Backup e29 installed qualification: test-premise correction

Original immutable installed runtime e29dd00b85bc1be35990d8005890c02b00ccd2b9.
Raw `backup_e29dd00_focused_with_baseline.log/.exit` under the task root retains
19 executed,17 passed,2 failed,0 skipped; exit1. Original no-baseline attempt
retains discovery19/executed0 and exit1 separately. Source baseline13-file
inventory was unchanged. Neither attempt is relabelled passed.

The two literal failures were:

- `GRAPH_RESOURCE_POLICY_INVALID: Cache/decoded-partition or collect reservation exceeds working-memory admission.`
- `session_execution mutation authority is available only on an engine-created staging bundle.`

The first fixture requested memory8MiB but inherited collect16MiB and partition1MiB
(cache512KiB+8 partitions also exceeds8MiB). It now explicitly admits partition64KiB
and collect1MiB, retaining the real source-policy restoration/fault assertions.
The second fixture uses a public constructor source assembly, not session staging.
It now uses the legitimate ingestion context to test clearing the same invocation
observation, with unchanged source-slot and other-forget-slot assertions.

Only tests and this note change; runtimeR/src remain byte-identical to e29.
No recompilation or runtime weakening. Retry only the five new definitions using
the same immutable installation. Combined evidence must distinguish original
19/17/2 from corrected5 results; existing14 passed contracts are retained evidence,
not a fictional fresh19-test run. Prospective performance budgets are unchanged.
