# Support And Issues

Use the project issue tracker for reproducible defects and capability requests:
<https://gitlab.liu.se/hende58/scworkbench/-/issues>.

For defects, include the scworkbench version or commit, SIF SHA-256 when a
container is involved, operation name, public interface output, exact error,
and the smallest shareable bundle or reproduction. Do not attach sensitive
biological data. Recipient-side reports should include read-only validation,
runtime attestation, and relevant birth certificates or DAG paths.

Security or data-boundary concerns should not include exploitable details in a
public issue. Contact the maintainer at `dirkdeweerd.work@gmail.com` with a
minimal description and affected release identifier.

Usage questions should first consult the installed onboarding guide and public
operation interfaces. Scientific interpretation and project-specific analysis
design are outside package support unless they expose a reusable engine defect.

## Target plan vocabulary

`wb_target_reproduction_plan()` resolves provenance without running scientific
computation. Its compatibility fields `status="ok"` and `reproducible=TRUE`
mean that a target's run closure is resolved and acyclic. They do not promise
that the plan can execute or that a replay has matched its original outputs.
For example, an acyclic legacy output can carry a `legacy_not_comparable`
diagnostic and still have those structural fields; script emission rejects its
unsupported equivalence policy. `cyclic`, `ambiguous` and `source_state` plans
do not provide an eligible replay closure.

`wb_target_emit_r_script()` checks static eligibility; emitting a script is not
execution. `wb_target_execute_plan()` also checks the chosen writable source
clone and immutable prerequisites, executes operations, and compares terminal
outputs under their declared policies. Successful demonstrated replay is reported
by `status="promoted_and_verified"` together with passing verification receipts.
Clients must distinguish those receipts from a plan's `reproducible` field.
