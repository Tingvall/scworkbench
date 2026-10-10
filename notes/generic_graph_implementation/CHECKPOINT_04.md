# Incomplete normative-corpus, source-purity and framing checkpoint

Implementation remains governed by accepted design `fa929601` and the autonomous
implementation order. This is a local development checkpoint, not final
qualification, a release acceptance or a completed handoff. Use the enclosing
commit as its exact source pin. Nothing is merged or pushed; primary core
`17bdc7bbfe7dd5f2a813d4e69b93d7d1537d1caf` and PyBench
`0e67612a915caf4168a6824084fe5c5446690567` remain clean and unchanged.

## Changes and literal evidence

- Authoritative 23-case corpus mirrors Quill's corrected frozen fixture exactly
  (`90d6cbc098acee167ede37bfc658e31b7b2cf9681bd840554fe6ed6b0762bb38`).
  Gate125 independently checks R content/binding/descriptor roots, public SDK
  writer execution, promotion, exact ordered components and typed attributes,
  lossless/rejected igraph conversion for every case. A finalized relocated
  bundle reopens in a fresh pack-free process: recipient validation and complete
  filesystem SHA-256 fingerprints pass unchanged. Includes the unary undirected
  hyperedge, explicitly rejected by igraph rather than flattened.
- Shared 13-row negative-rehash CSV mirrors Python. Gate139 independently
  recomputes every malicious canonical digest and still rejects malformed
  content. Existing valid roots are unchanged.
- Gate135 focused inventory: `discovered=30 executed=30 passed=30 skipped=0
  failed=0`, exit0. Its parent process loaded before the later UTF-8 marking
  correction and additional CSV assertions; these affected deltas are explicitly
  covered by gates138 and139, not silently attributed to the earlier load.
- Gates103/106 cover compiled JSON string scanning and exact numeric lexeme
  preservation; existing canonical JSON/activation gate104 passed. Ordinary
  unescaped UTF-8 strings use the fast path; heavily escaped strings still use
  the original scanner. No universal performance claim or identity change.
- Gate107 padded mapping cursor passed: scalar fetch prevents row-count-only
  amplification of valid whitespace-padded records. NUL/invalid-UTF-8/trailing
  byte rejection and owned cleanup pass in gate111. Sable found discarded UTF-8
  conversion could be reinterpreted under a non-UTF-8 locale; the corrected reader
  retains the validated UTF-8 result. Gate138 full import and independent hashing
  under native `C` locale pass, including malformed-byte cleanup.
- Fault116/118 showed only `publication.published_at` changed. Trace120 identified
  source-identity authentication's mutation publisher; session snapshotting used
  the same inappropriate publisher too. Both now acquire/release the unchanged
  exclusive writer lock without publishing or checkpointing an untouched source.
  Lock ownership, nesting, backup verification and cleanup remain unchanged.
- Gate128 installed late application failure leaves manifest, artifacts and
  private staging/spill/session inventory unchanged. Gate134 runs existing owner
  substitution and WAL snapshot regressions plus new direct snapshot/source
  authentication purity and actual concurrent-owner rejection/retry:
  `files=2 discovered=4 executed=4 passed=4 skipped=0 failed=0 excluded=0 accounted=4`.
  Gate132 durable source/payload corruption: `discovered=1 executed=1 passed=1
  skipped=0 failed=0`. All these successful gates have numeric exit0.
- Archived method-bearing concurrency gate131 failed before its expected timeout:
  `Operation 'matrix_log_normalize' moved to 'scwbrna::matrix_log_normalize'.
  Install and explicitly activate its operation pack.` Gate136 retains that exact
  diagnostic. The archived method was not restored or its expectation weakened;
  gate134 exercises the generic snapshot under a real external lock owner.
- Generated-reference drift gate133 passed, exit0. Gate141 confirms five shared
  schemas, four authoritative graph assets and the test-only synthetic mixed
  fixture are byte-identical, R syntax parses and `git diff --check` passes.
  Gate140 used an incorrect process4 filename in the new checker; gate141 compares
  the unchanged process5 schema on both sides. No schema repair was required.

All failed development logs/exit sidecars remain intact. Gates119/121/122 are
superseded fixture setup defects (minimum cells, ordinary reader contract, error
handler shadowing), resolved before successful125. No failure is relabelled a pass.

## Focused independent review scope

Sable reviewed exact clean Python `dadec7d06fddecb7211c7015972e7de974f4b7e6`:
corrected normative structures, generator, immutable roots and scenario tests;
no defect found, no suites/edits or broad runtime endorsement. Reviewed hashes:
corpus `90d6cbc098acee167ede37bfc658e31b7b2cf9681bd840554fe6ed6b0762bb38`,
generator `96cd88a35f5af135374c1aac60ce3c44b9a26d7c21fc646a97991aea76dd32d9`,
tests `3a4dcab78892de764d8f77e075c4e562c8793ab29f8cc8a70418d5861a8c0f62`.
Current peer `c3dfdbd51d2e996476205e19665348cc271b8b5f` is a one-line formatter
descendant; Sable's endorsement remains scoped to exact `dadec7d`, not extrapolated.
Its new exact wheel SHA is
`40f49574c1dd05f31b2e9067a6ffa7231fefcae4df53668e51e5020871182cb8`.
Python's installed discovery smoke is not an R/Python live lifecycle pass.

Sable's read-only core review found no exclusion/nesting/cleanup/validation defect
in the lock-only replacements. Reviewed `session_staging.R` SHA
`de59991e0c33fbd8b44c458b59c44562bc82563b3e8764d45edb87bcd343c8f4` and
pre-comment-correction `durable_sessions.R` SHA
`9bbf94b9ff709af1069371cecf2514447e9e7a20cc45a0716a8ff7415a3fa394`.
The stale snapshot-publication comment was subsequently corrected; runtime code
is unchanged by that comment delta. JSON fast-path review found no semantic defect
at hashes `45b20618eecac25f6030daa58a062beec4bbfdc8ee9c75346a01199078263d68`
and `bd07e80a8d074fe4d3462b1f63448a61ba805b9bffdb5691efd4f4ebee4cb6b8`.
Scalar cursor review passed at `a6e635a36574f1df53c46760e642d5d838673bf1e4e1d673cd6943d56a4d2eef`.
Transport review identified the UTF-8 marking correction above; gate138 provides
executable closure, not an unperformed independent reviewer rerun.

## Resource procedure and remaining work

Small nine-cell lifecycles are smoke/diagnostics only. The prospective fixture
uses a native retained vector axis with 90,000 cells and 192-byte ID suffixes,
so the complete original source axis/mapping exceeds the 8 MiB working allowance.
Public source setup is unmeasured, separately logged with an 8 GiB disk reserve
and 1 GiB setup envelope; it must not inflate the fixed small-runtime baseline.
The scale inspector requests up to512 rows within the same256 KiB byte ceiling,
verifies every component/count/order and hashes the entire filesystem before/after.

Controller approved 16 GiB combined disk spill before final measurement. Memory,
cache and partition limits are unchanged. Final baselines, safe peak disk
preflight, >=8x total-process-memory lifecycle/fault measurement and exact installed
core/current-Python live gate remain required. No tmpfs or unrelated deletion.
No full core/Python suite or package check ran: those run once after the complete
tuple stabilizes. Matrix-bound source authority remains fail-closed pending the
Controller certificate decision. Quill's planning-only matrix amendment is not
an authorization, implementation or accepted reduction to committed-only scope.
