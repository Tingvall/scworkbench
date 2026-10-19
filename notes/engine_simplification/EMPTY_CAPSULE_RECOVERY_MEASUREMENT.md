# Empty capsule recovery: scoped measured result, not a final handoff

Budget-first 37484b7b450f0f6bcc6fcae6f993e405aee53dd2; runtime
4d1f5312bba153910bbc88a975e047c43c42f01e; installed source
67f29a10361019fb16e9b6d20b74a918dea0876c; corrected test source
75799e967cc70c64a4fccc2f756ec0e9afdca5f7. The latter changes only tests/docs:
`git diff 67f29a1 75799e9 -- R src` is empty. Reused immutable installation:
`/tmp/scwb-engine-simplification-forge-20261018/capsule_67f29a1_install/library`.
Actual DLL: 4a380bd6559d137d680ffc1d22ec6bd652215defdeec06f84d341b59bb0fc897.

Original focused10 executed:5 existing lifecycle/security/process-death/recipient
tests passed;5 new tests failed (exit1, two cleanup warnings). Actual old/new
ownership diagnosis (two processes,12 events, exit0) showed initializer assembly
ownership is retained, while public close/reopen is unheld. Test-only corrections
establish that intended boundary and separately assert assembly-owner preservation.
The first corrected5 retry passed4/5, failing on a correctly forbidden direct
manifest refresh. The final test uses authorized public writable reopen instead;
corrected5/5 pass, zero skips/failures, no warnings printed. These are separate
retained runs, NOT a fresh10/10 execution. Runtime was unchanged throughout.

All24 matched trial processes passed:18 alternating fresh plain processes
(three per variant/route) plus6 separate censuses. The initial comparator failed
before evaluating budgets because it inherited full-file-inventory data-frame
row labels:3:13 for closed-source open vs5:15 for already-open WAL/SHM recovery.
A separate metadata diagnosis proved all24 ordered11-leaf path/size/SHA columns,
column types, other attributes, actual semantic identities and SQL proofs exact.
Only those incidental row labels differed. A NEW posthoc comparator resets only
those labels; no trial, timing, payload, original comparator or budget was changed.
All original evidence and derivatives are SHA-guarded before/after comparison.

Matched plain medians (seconds):

| Route | Old | New | Actual builders/publishers old→new |
| --- | ---: | ---: | --- |
| Public writable open/close | .928 | .608 |2/2→1/1 |
| Private empty recovery | .350 | .003 |1/1→0/0 |
| Direct lock/inventory/assert | .003 | .003 |0/0→0/0 |

Public reduction34.48%; private reduction99.14%. The tiny private/direct timing
is near timer resolution. The direct route supplies fewer services and is not a
service-equivalent framework-overhead denominator. Both fixed original-baseline
ceilings (.9672s public, .034s private) and fresh matched20%/90% improvement
requirements pass. RSS median ratios pass+10%; additionally ALL9 plain-process
peak maxima are625516KiB old and618072KiB new (including fixture setup).
Explicit migration publication remains. Actual cleanup still forces publication
under exclusion and preserves the existing checkpoint behavior. Empty recovery
still inventories and validates all residue; no cache or fast return bypasses it.

Evidence root `/tmp/scwb-engine-simplification-forge-20261018`:

- `capsule_67f29a1_focused`:10/5P5F, exit1 (preserved).
- `capsule_fixture_ownership_diagnosis_supervisor`:exit0, old/new records retained.
- `capsule_a575c69_corrected_retry`:5/4P1F, exit1 (preserved).
- `capsule_75799e9_corrected_retry`:5/5P, exit0.
- `capsule_75799e9_matched_measurement`:all24 trials exit0; original comparator1.
- `capsule_payload_comparator_diagnosis`:exit0, all24 exact-column proof.
- `capsule_posthoc_rowlabels_comparison`:outer/comparator0, all unchanged budgets
  pass; `all_original_evidence_and_derivative.sha256` guards original inputs.

This scoped result does not waive Xenopus171.124s, graph/mixed/space, matrix
physical-verification or other remaining budget misses. No combined-candidate
qualification or engine-wide acceptance is implied.
