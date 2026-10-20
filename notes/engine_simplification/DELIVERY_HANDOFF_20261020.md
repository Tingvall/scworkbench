# Engine simplification — final local delivery, 2026-10-20

DELIVERED LOCALLY under the Controller's delivery/deferred-observations order.
Optimization is stopped. No concrete unresolved correctness/recovery blocker
is identified by the retained evidence. This is not release qualification or
independent whole-candidate acceptance. No merge, push, profile repin, image
build or publication is performed or authorized.

## Frozen candidate and dependencies

- Branch: `perf/trusted-r-slice-observation-forge-20261020`.
- Worktree: `/home/dirk/Projects/.scworkbench-worktrees/trusted-r-slice-observation-forge-20261020`.
- Runtime: **ee2cc8d3f83b34d07b6200f3291e573b2bbb2e7d**.
- Pre-delivery documentation/design descendant: **07e6b749e36c096c2acb1a7ecea21751d64276dc**.
  This handoff's containing commit is the final documentation-only delivery
  revision; resolve it with `git log -1 --format=%H -- notes/engine_simplification/DELIVERY_HANDOFF_20261020.md`.
  R/src/tests are identical to runtimeee2. Existing post-ee2 inst changes are
  SDK documentation and the two test-ownership CSVs, not runtime/protocol changes.
  Candidate was clean before
  close-out; the final close-out checks confirm cleanliness after commit.
- Unchanged Python peer: **f815def0127b7a63a5e81455c270cff6572dc8ea**, clean at
  `/home/dirk/Projects/.pybench-worktrees/engine-transport-s1-stream-precode-quill-20261019`.
- Whole-workflow-measured core runtime: **680fc617442e7226c8d5aa1d6332a60287342e4e**;
  source/documentation checkout **d0db42ef81b6555fc5489adce219b8b3262bc2c1**.
  Its timings are NOT timings of ee2 or this documentation descendant.
- Scientific packs unchanged: RNA **151dd29211b219343dce6247c5e48fc932b4c83d**;
  Representation **be51127ca0d7c11a0667be826c24449a5c7e8912**. Retained installed
  library: `/tmp/scwb-matrix-streaming-forge-20261018/verified-library`.
- Measurement dependencies: R4.4.1/jsonlite1.8.8, BPCells0.3.1, Matrix1.7.0,
  rhdf5 2.48.0, irlba2.3.5.1, uwot0.2.2, rnndescent0.1.8. Retain these for
  comparison; guarded native encoders preserve existing unsupported fallbacks.
- The primary core checkout remains outside this isolated candidate; no
  development-branch integration is claimed.

## Delivered changes and guarantees

Bounded source preparation/readers, feature-oriented indexing, reduced
conversions/copies, scoped registry/schema/manifest observations, consumed-output
dispatch checks, boundary source authentication, streaming byte-identical hashes,
batched canonical/table serialization, scoped promotion observations and
installed-metadata provenance are retained. Principal runtime areas are getters,
operation-pack dispatch/readers/writers, sessions/provenance/promotion and native
matrix/registry emitters. Tests and explicit test-ownership records accompany
these changes; no official scientific pack or standard profile is modified.

Keep exact ordered axes, valid selections and coverage, source associations,
output contracts/identities, complete promotion closure, collision/overwrite
rules, generation-bound recovery, provenance, atomic publication and rollback.
No identity scheme is silently changed. Native R packs are trusted software,
not a hostile-code sandbox: source bytes are authenticated at request and before
publication, with lightweight checks between reads. A transient mutation restored
before final authentication is not guaranteed detected. Controller also approved
selected-fragment getter checks, consumed-predecessor checks at dispatch and
BPCells installed-version metadata rather than a loadability attestation.
Explicit validation/recovery/promotion retain their broader verification duties.

## Retained qualification, not rerun for delivery

Let `T=/tmp/scwb-engine-simplification-forge-20261018`. Commands below identify
the actual retained executions; DO NOT rerun them just to recreate this handoff.
Logs and numeric sidecars remain authoritative, including failed attempts.

| Command / evidence root | Literal result and scope |
|---|---|
| `bash T/run_final_affected_d0db42e.sh`; `T/final_affected_d0db42e_f815def` | original=0, postguard_failed=0;80/80 root focused tests,0 skips/failures, plus separate registry composite pass; documentation pass;44/44 protocol files exact; full Xenopus science/lifecycle pass |
| `bash T/run_final_plain_d0db42e.sh`; `T/final_plain_d0db42e_f815def` | original=0, postguard_failed=0; plain full Xenopus science/lifecycle pass |
| Both preceding roots' `logs/literal_budget*.exit` |1: original171.124s ceiling missed; v2 attribution corrects the HVG callback classification, not a runtime rerun |
| `bash T/run_numeric_partition_corrected.sh`; `T/numeric_partition_4187774` |24/24 focused passes,0 skips/failures;7 numeric sidecars0; exact9 byte/hash observations; component limits pass |
| `bash T/run_manifest_ascii_candidate.sh`; `T/manifest_ascii_ee2cc8d` |25/25 focused passes,0 skips/failures;5 functional/guard sidecars0; budget.exit1, unchanged six fingerprints and independent materialized oracle |
| `T/final_a194b57_f815def_setup_retry01/complete_core/complete_actual_summary.csv` | Earlier a194b5738c8f9f92af5b8d9898cac1cc74d74b65:618 discovered/executed/passed,237 files,0 skips/failures;41 listed warnings; embedded optional H5AD checks unexecuted |
| Same older root, `logs/06c_complete_python.log` | Peerf815:776 passed,9 named skips,3 warnings; lint/format/import gates0; skips are not passes |

The current647 definitions/243 files are discovery/ownership accounting, NOT a
647-test complete run. Do not combine separate focused cohorts into a new suite
total. See component documents and `T/FINAL_A194_F815_LITERAL_RESULTS.md` for
warnings, bootstrap/source-loading scope, historical failures and named skips.

Existing review dispositions are scoped: Sable/Quill source checks for the
selected components; Meridian independently ACCEPTED680's owned-dense component
and418's numeric partition component (report commit
dbdf6b7601a28a5a4636614a040f7df88a2445ae). ee2 has source review and retained
owner component evidence, not an independent runtime/full-candidate acceptance.
See [dense](OWNED_DENSE_COMPONENT.md), [numeric](NUMERIC_PARTITION_COMPONENT.md)
and [ASCII](MANIFEST_ASCII_COMPONENT.md). No new review round is initiated.

## Performance and correctness interpretation

| Measured scope | Profiled680 | Plain680 | Direct, fewer services |
|---|---:|---:|---:|
| Four analytical operations |212.463s|232.033s|53.467s|
| Complete process |392.28s|427.76s|85.48s|
| Peak RSS KiB |4490472|4412236|4202032|

The original scientific settings and default256MiB guard are unchanged.
Fresh import, normalization/HVG/PCA/UMAP, seven-terminal promotion, finalize,
read-only reopen and recipient validation complete. Both runs meet original
scientific-reference criteria:106 normalization blocks with maximum absolute
difference0, exact PCA/UMAP coordinates at the checked precision and declared
HVG tolerances. Each recipient report records24 content_verified,
5 external_uninspected,5 EXTERNAL_SOURCE_UNVERIFIABLE warnings,0 skipped;
filesystem fingerprints are identical before/after inspection.
Raw104-block source alignment checks also passed; the historical cluster
column-sum discrepancy's original cause remains unproven, not dismissed.

Profiled phase seconds: import43.357, session4.564, normalization54.979,
HVG67.309, PCA56.374, UMAP33.801, reference comparison37.602,
promotion42.933, finalize4.470, reopen3.068, persisted inspection12.648,
recipient23.480. Inclusive registry61–69s, matrix identity30–36s and table
fold14–15s costs overlap and must not be summed. Six physical matrix-source
checks occur at lifecycle boundaries, not once per partition. The147 matrix
identities are not147 full-source passes. Five raw-source SHA calls cover
365874915 bytes; generic file-hash counters also overlap other observations.
Sampled peak workspace allocation is about1.51GB, a five-second sampled lower
bound rather than a continuous maximum.

Direct evidence: `T/final_ba351cd_measurements/direct-xenopus-efficient` and
`time/08_efficient_direct.txt` under that root. It includes metadata/reductions,
read/write/reopen and scientific checking, but omits categorical-set registry,
provenance, durable recovery, atomic publication and recipient validation.
The gap is not entirely removable framework overhead. Shared heterogeneous
hardware/cache/CPU allocation and sequential observations limit causal claims.
The earlier repaired baseline's matched four-op scope was1276.093s; its whole
process scope differs and is not a matched end-to-end denominator.

Later418 numeric canonicalization improves the actual PCA primitive component
5.737→.708s. ee2 registry snapshot improves3.874→3.369s but misses its original
component target. Neither result establishes a newer full-workflow timing.

Controller now accepts the measured practical performance for delivery. Original
workflow, graph, mixed-primitive, typed-space and ASCII-component budget misses
remain recorded as misses; they are not retrospectively passes or current
delivery blockers. No engine-wide performance qualification is inferred from
this workflow. Large-history scaling, unmeasured primitive/backend combinations,
cross-platform behavior and actual asynchronous native interrupt delivery remain
limitations, not implied coverage.

## Deferred work and close-out

Both observation alternatives are explicitly [deferred](DEFERRED_READER_OBSERVATIONS.md):
the historical per-read v2 design AND the smaller per-grant completion proposal.
Neither changes the delivered schemas, receipt behavior or Python transport.
No further optimization, full suite or benchmark is run for this delivery.

Close-out is documentation-only: deferred-status/link checks, exact runtime
R/src/tests comparison againstee2, explicit inst documentation/ownership delta,
pinned-peer cleanliness, `git diff --check` and
post-commit cleanliness. Literal close-out results and the final local commit
are reported with this handoff. No additional implementation/review campaign,
source integration, push, profile repin, SIF or release action is implied.

Literal close-out results: local Markdown links0; retained sidecar/test-count
reconciliation0; R/src/tests equality with ee2 plus explicit three-file inst
documentation/ownership delta0; exact clean PyBench peer0; read-only
`python3 notes/engine_simplification/final_protocol.py . /home/dirk/Projects/.pybench-worktrees/engine-transport-s1-stream-precode-quill-20261019`
prints `FROZEN_PROTOCOL_PARITY 44/44 PASS; Python-only runtime schema unchanged`
and exits0. The first documentation assertion incorrectly included all inst
files in runtime equality; it was corrected to disclose the existing SDK and
ownership changes, without changing runtime or rerunning scientific tests.
