# Source-only backup continuity: measured budget before implementation

Base df8db854cbc0311a5f8e809a88993c758887ca7d; actual baseline installed
2ebfd47540b2bcca97947fad6e4437077df2bee8, byte-identical runtimeR/src.
Raw evidence /tmp/scwb-engine-simplification-forge-20261018/backup_source_2eb_baseline.
Three fresh plain public64×256 source→source-check→wb_session_create→source-check
cycles: create1.580/1.564/1.529s, observed cycle1.884/1.872/1.823s.
The initial actual source check median.296s is retained. Separate census proves
two actual source snapshots and two stage snapshots, with the populated source
slot cleared by backup although actual complete source epoch is unchanged
(total_changes1697,data_version2,schema_version335). Fifteen source-file SHA
inventories and all-table/schema/native/physical value parity pass unchanged.

Prospective targets, committed before runtime changes:

- Source snapshots2→1 over the same cycle; stage snapshots stay2.
- Public create median≤1.4076s (10% below1.564s).
- Observed source-check/create cycle median≤1.6848s (10% below1.872s).
- Whole process RSS≤672113.2KiB (baseline maximum611012KiB+10%).

Direct SQLite copy/quick_check/RO reopen/all-table readback median.076s omits
engine exclusion, manifests, source identity, workspace/checkpoints and payload
links, so it is not a service-matched framework denominator. No source authority
or compatibility/identity change is proposed. Original Xenopus171.124s and
graph/mixed/space budgets remain unchanged and unwaived.

Policy: Sable assessment /tmp/scwb-sable-backup-source-continuity-ca8e-20261019/assessment.json.
Save only the original actual source slot, still forget ALL observations at
entry, restore only after successful ordinary core-owned read-only backup and
all fallible cleanup, with same valid connection/directory, unchanged safe exact
original three-counter epoch, no transaction, held owner exclusion and no hook.
Never rebase evidence or restore destination/publication/schema/graph/context
slots. All errors, hooks, source changes, unknowns and other forget boundaries
retain fresh observation. This is the existing trusted-R source-cache model,
not new hostile-code schema-cookie or out-of-band write protection.
