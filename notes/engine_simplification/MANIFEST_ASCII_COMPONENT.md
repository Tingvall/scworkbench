# Same-byte registry ASCII eligibility: improvement, budgets missed

Runtimeee2cc8d3f83b34d07b6200f3291e573b2bbb2e7d, parent4187774.
T=/tmp/scwb-engine-simplification-forge-20261018. No protocol/identity, numerical
format, scientific method or trust-boundary change.

Actual read-only profiling found118791 cell_set_membership rows the largest
retained registry table cost (1.719 seconds in a sampled observation). Imported
descriptions contain `sample=SIGAA10`; old native eligibility excluded `=` and
returned to the existing serializer. New eligibility admits92 printableASCII
bytes32..126 excluding34/60/92. Digits-only rownames are unchanged. `<` remains
in fallback because actual pinned jsonlite1.8.8 renders `</` as `<\/`.
Source/schema/carrier/encoding/256-byte/resource bounds and the exact pinned
R4.4.1/jsonlite1.8.8 production gate remain unchanged. All actual output bytes
and the logical5000-row hash fold remain the original representation.

Before code: jsonlite_ascii_probe exit0 checked all92 characters independently
and combined. Parent command manifest_ascii_parent exit0 verified sourceSQLite
SHA, old full materialized membership oracle and six recorded fingerprints.
Prospective caps were fixed in MANIFEST_ASCII_PROSPECTIVE_BUDGET.md, not revised.

`bash T/run_manifest_ascii_candidate.sh` built/installed clean Git-derivedee2.
Focused25/25PASS,0skip/fail/excluded in6files. New tests cover all92 characters
in values AND field names; escapes/control/HTML/DEL/nonASCII/257-length fallback;
strict digit-only rownames; actual10020-row SQL fold, mutation and file purity.
The old apostrophe admission-negative was explicitly replaced with a positive
byte-oracle case; unrelated negatives were retained.

All6 parent fingerprints, sourceSQLite SHA and complete materialized membership
oracle match. FIVE gate sidecars are0 (install/focused/measure/inputpost/installedpost),
budget.exit1; original=1 postguard_failed=0 remains preserved. No unchanged rerun.
Installed DLL SHA4a076ecaef560011eafe71310bfd68263ade8346e44ecbe87ac386f1dab6b178.

| Metric | Parent | Candidate | Frozen ceiling | Result |
|---|---:|---:|---:|---|
|Membership median seconds|1.563|1.232|.7835|MISS|
|Full snapshot median seconds|3.874|3.369|3.2949|MISS|
|PeakRSS KiB|213992|211084|290227.6|PASS|

Membership improved21.18%, snapshot13.04% in these sequential observations,
but neither requested improvement budget passed. These are one parent process
and one candidate process with three observations each, not randomized cold
trials. The installed component is not represented as budget-accepted or as
evidence of a whole-workflow speedup. Sable/Quill reviewed exact source only;
no independent runtime rerun or whole-candidate acceptance is claimed here.
The general ordinary JSON and all original whole/graph/mixed/space budget
limitations remain. No source-hash reuse or file timestamp authority was added.

Current-only ownership regeneration exits0 with647 definitions in243 files,
407introduced/2moved relative to the frozen242-definition baseline. This is
AST/discovery accounting, NOT647 executed tests. Earlier complete618/618 belongs
to a194, not this descendant. The numeric24-pass and manifest25-pass focused
cohorts are separately stated; no complete-current-suite claim is made.
