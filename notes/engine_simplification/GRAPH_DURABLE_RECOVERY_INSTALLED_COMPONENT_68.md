# Durable graph recovery: installed component evidence

This is a correctness component result, not whole-engine readiness or a new
performance result. Source checkpoint:
`68b75b35155f3d76e2995ea47d68c182c403e359`. The documentation-only descendant
containing this note has byte-identical R/src/tests. No primary merge, push,
official pack/Python change, graph authority/grant extension, or identity-scheme
change is represented here. Main `96cb` and official dependencies were not
changed by this local documentation work.

## Distinct actual cohorts (never summed or substituted)

| Cohort | Actual disposition |
| --- | --- |
| Original non-setsid launch | Interrupted before archive/R execution; no numeric terminal exit. Not a test result. |
| Installed524 selection | 15 executed, 11 passed, zero skipped, four failed at first writer's exact marker. Writer status zero alone did not execute/prove recovery. |
| Corrected197 four-test selection | Four executed, three passed, one failed at unsupported unpromoted graph reader. |
| Old installed0a same-process public control | Terminal0 for asserted `GRAPH_SOURCE_AUTHORITY_REQUIRED` on fresh unpromoted graph, unchanged registry. Establishes pre-existing policy, not a new recovery failure. |
| Supported68 distinct four-test retry | Four discovered/executed/passed, zero skipped/failed/excluded. All requested child output is retained in the parent log. |
| Fresh Git-derived68 installed selection | Five files, 15 discovered/executed/passed, zero skipped/failed/excluded. Install, all pre/post guards and outer supervisor0. |

Earlier raw records remain unchanged. The marker footer originally added a
trailing blank through `cat`'s default separator. Initial successful-child
output was lost when the helper cleaned its owned root without printing it;
that loss is disclosed, not reconstructed. The corrected helper prints complete
merged child stdout/stderr and escaped lines before exact status/marker checks.
The later unsupported reader premise was corrected by retaining the explicit
fresh/resumed rejection and continuing only through a promoted artifact.

Evidence root `T=/tmp/scwb-engine-simplification-forge-20261018`:

- Original interruption records: `graph_recovery_5246593_supervisor*` (no terminal sidecar).
- First actual failed selection: `graph_recovery_5246593_setsid_install/`.
- Distinct unsupported-reader selection: `graph_19784ec_four_corrected_tests.{log,exit}`.
- Old authority control: `graph_fresh_unpromoted_0a.{log,exit}` and
  `graph_fresh_unpromoted_0a/actual_result.json`.
- Supported retry: `graph_68b75b3_four_supported_tests.{log,exit}` and its
  `actual_results.csv`, `actual_summary.csv`, `actual_identity.json` directory.
- Definitive fresh installed cohort: `graph_recovery_68b75b3_install/`, plus
  `graph_recovery_68b75b3_supervisor.{log,exit}`.

## Frozen execution and guards

The actual launch was the prepared detached `nohup setsid` supervisor:

```sh
SCWB_GRAPH_RECOVERY_RELEASE=YES bash /tmp/scwb-engine-simplification-forge-20261018/launch_graph_recovery_68b75b3_focused.sh
```

It archives the exact clean Git commit, installs into the NEW immutable
`T/graph_recovery_68b75b3_install/library`, and runs:

```sh
R CMD INSTALL --no-multiarch --with-keep.source -l "$out/library" "$out/source"
Rscript --vanilla "$out/run_graph_recovery_68b75b3_focused.R"
```

The actual wrapper supplies installed-library/dependency paths, explicit
installed-child mode, default256 guard, selected source archive and accepted
Python path. Each install/focus gate is numeric, logged and bounded at890s.
The runner uses the installed namespace, records its actual DLL, imports private
test helpers and discovers the exact selected five files. New process children
also assert the actual installed package path and DLL SHA. Post-failure source,
installed and harness checks remain independent; no source-loaded core is
substituted for this component cohort.

Actual DLL SHA256:
`35305a724bc6e358cdb9cecf56623f5df8e18afc411ce6c55a2185890efe26a6`.

| Retained artifact under definitive OUT | SHA256 |
| --- | --- |
| `focused.log` | `6545a7bd6ba01dabe9aed6a524c8fe691c68a87c9dd8a0ad023d4972b37921cf` |
| `focused_summary.csv` | `fff30aefb1736fe8567d9e9a1955cd18547b6f3fd92069f709e9bce56dd28f90` |
| `installed.sha256` | `60c545c04edc6f5046c8786a2ed8373330e2d1b430d7cc428b5f5a2e5193da5b` |
| `source_code_tests.sha256` | `916217cebc342bff512b6a37fed9e2e73e9afcee32e5efc0f5228908ec7a8932` |
| `install_and_focus_graph_recovery_68b75b3.sh` | `9fb6e85e0a747b396520a1be4b976f5cfa06af741a62e0e88d44f91560943f3e` |
| `run_graph_recovery_68b75b3_focused.R` | `01b934ee211f0e2c02ef1f20e0e3ed826ccd890d38b2d3c3e35e1b2f2304e036` |

`install.exit`, `focused.exit`, `pre_inputs.exit`, `pre_source.exit`,
`post_inputs.exit`, `post_source.exit`, `post_installed.exit`,
`post_worktree.exit` and outer exit are all0. The parent log explicitly expands
11 buffered warnings: one request to call dbDisconnect and ten Already
disconnected warnings. Child matrix-compression warnings also appear in the
retained child output (including escaped replay). Do not claim warning-free
execution, assign an unproven cause, or count duplicate printing as unique
warning conditions.

## Demonstrated scope and limits

New four contracts prove process replacement, pack-free transition list/load,
source authentication before fresh graph imports, original checkpoint bytes
across two opens, current-generation and UNCHECKPOINTED_STATE rejection,
recovered graph promotion, retained-artifact reader continuation in a NEW durable
session, actual new checkpoint, summary promotion and read-only reopen. Negative
cases cover self-rehashed checkpoint claims, changed actual parts, partial
multi-run import cleanup, changed source rejection, restored retry and owned
scratch cleanup. Five-file cohort additionally includes fresh graph handoff6,
durable resumable1, subprocess recovery1 and ABI4 admission3.

The positive graph is unbound, two ordered nodes `c2,c1`, undirected, with empty
edges/incidences/attributes. Its hand-written canonical content preimage yields
literal SHA256 `08a4b33bdb22ee7f0491f3189264737c2bc7fc0b6589ad3d21fd078177f57fb9`.
Content SHA and node order are independently literal. Binding/descriptor checks
call public `wb_graph_identity` on an independently constructed literal INPUT:
this is public-helper consistency, NOT an independently implemented encoder or
a frozen binding/descriptor golden digest.

Source-bound graph process replacement, large/many-output recovery scale,
Python graph process replacement and a fresh whole scientific workflow on this
runtime were NOT executed by this component selection. These are unmeasured,
not inferred from fresh handoff, binding tests or literal unbound recovery.
Current correction retains default full actual contained-record/parts/receipt
and payload-ledger verification; it does not authorize unpromoted graph readers.

## Source review and non-runtime checks

Uncommitted external source-only Sable records under
`/tmp/scwb-sable-graph-recovery-source-a90b234-20261019/`:

| Record | SHA256 |
| --- | --- |
| `review.json` | `0382b784d8a075e67d7a93cec04d85277aad24fa787c025fd0eaad95d086da3c` |
| `wrapper-addendum-e523c5b.json` | `b832d06a7d1cf6e10605d2de72b2da45c27dc869dff6af1f00ba1e7188f6d796` |
| `marker-addendum-19784ec.json` | `cc9d523e8b663ab2c03427a13a4eabc720b7e0e4e641155a2aa02c09f91a02ee` |
| `lifecycle-addendum-68b75b3.json` | `6aac6af1b8f601d08518934e75fbf691152462e24a5847b3751a74c27a89f11b` |

These clear exact source scope for qualification; they are not runtime final
acceptance. Actual `graph_68b75b3_ownership_inventory.{log,exit}` reports0:
597 discovered definitions /233 files /357 introduced /2 moved; frozen242/139
and63 references remain. This is discovery, not597 passed tests. Actual
`graph_68b75b3_generated_docs.{log,exit}` reports0 for `Rscript --vanilla
inst/dev/regenerate_public_docs.R --check` (empty successful log). Neither
check replaces scientific or performance qualification.

Historical whole-engine417.37>171.124s, graph extra17.848>3s, mixed extra6.686>2s
and typed-space5s misses remain UNWAIVED and were NOT remeasured by these graph
contracts. No final engine handoff/readiness or overall performance acceptance
claim is made.
