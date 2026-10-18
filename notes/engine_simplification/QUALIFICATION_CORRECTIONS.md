# One coordinated qualification: original failures and corrections

The complete core run used immutable `fff50517c9838481ff2a49bb1ebd8f5f20ead8dd`.
Its literal result was **files=184 discovered=382 executed=382 passed=370
skipped=3 failed=9 excluded=0 accounted=382**, exit **1**, wall **2:16:51**,
peak RSS **3216864 KiB**. The runner's `executed` includes its three skipped
invocations; it does not mean 382 non-skipped tests passed. Raw evidence is
`/tmp/scwb-engine-simplification-forge-20261018/final-qualification-fff5051/logs/01_canonical.log`
and its atomic numeric `.exit`; these are not overwritten by correction runs.
The original supervisor's text status remained `RUNNING 01_canonical` because
its ERR trap was not inherited inside its gate function; both processes ended
and the numeric sidecar is authoritative. The continuation enables ERR
inheritance and does not rewrite the original text status or raw evidence.

The later installed affected run is a separate descendant qualification, not
a replacement or a passing full-suite result. New tests also change discovery;
their counts must not be substituted into this original 382-test record.

| Failed test | Diagnosis and correction | Evidence boundary |
| --- | --- | --- |
| `test_object_primitive_family_durable_roundtrip_contract` | Old fixture privately inserted retained objects without independent provenance output authority. Use an explicitly synthetic public run/promotion; retain metadata, order, scientific type, identity and mutation assertions. | Same authority failure reproduced on repaired baseline; corrected fixture tested on both baseline and frozen original candidate. No scientific method execution claimed. |
| `test_derived_cell_set_lifecycle_contract` | Same obsolete private promotion shortcut. Public synthetic promotion preserves selector, recipe, lifecycle and rollback coverage, with explicit source mutation rejection. | Corrected baseline and original-candidate focused runs retained. |
| `test_durable_session_subprocess_recovery_contract` | Supervisor set installed-child identity flags while the whole-suite parent used source `load_all`; source namespace has no installed DLL path. | Separately retained actual installed parent/children run passed process replacement and generation race. Final affected runner uses the actual installed namespace. No identity assertion weakened. |
| `test_foundation_hardening_1to5` | Same obsolete private fixture authority. Public synthetic promotion retains vector values, types, order and all other sections. | Corrected baseline and frozen-candidate runs retained. |
| `test_graph_bounded_legacy_compact_rows_public_predecode_admission_contract` | Positive tail rewrote retained metadata while retaining the original certificate. Keep corrupt-state rejection and put the positive case in a separately, publicly promoted fixture. | Original unsafe predecode admission assertions remain. Explicit fixture carrier budget is not a real-workflow guard increase. |
| `test_graph_bounded_legacy_duplicate_rows_public_predecode_contract` | Same invalid positive authority; unsafe duplicate admission must still reject before decoding. | Corrected baseline and candidate focused runs retained, including failed development fixture attempts. |
| `test_operation_pack_v1_cross_language_lifecycle_contract` | Test expected the old composite-release peer rather than the explicitly configured current peer. A separately supplied strict 40-hex candidate pin changes only the expected test assertion; no runtime/profile pin changes. | Baseline reproduces the stale assertion. Default still uses release pin; malformed and wrong observed pins reject. Final lifecycle must execute against the independently pinned peer. |
| `test_operation_pack_v3_derived_fitted_axis_protocol_generation_is_stable` | Fast canonical-array helper was placed in a file absent from standalone generator loading. Move existing byte-identical helpers beside the canonicalizer with self-contained errors. | Actual generator failed before repair, then passed with no protocol-byte changes. This was an implementation defect, not a stale fixture. Final generator/parity gates repeat the executable path. |
| `test_phase8_test_ownership_inventory_contract` | Current discovery ledger omitted later generic tests. Preserve frozen historical ownership and explicitly classify additions in a separate ledger, then regenerate current discovery. | Final ownership check must reject unknown/duplicate/moved identities; changing a count alone is not a correction. |

Detailed independent baseline/fixture commands and hashes remain in
`/tmp/scwb-engine-simplification-forge-20261018/FOCUSED_STALE_FIXTURE_DIAGNOSIS.md`.
Final commands, exact source/install pins, terminal results and added-test
accounting belong in the final evidence ledger, not inferred from this diagnosis.
