# Meridian-9: focused graph memory-admission review

Disposition: correction required for aggregate admission accounting. This is a
bounded read-only source review, not runtime acceptance or complete memory
qualification. No measured RSS breach is asserted.

## Finding

The inspected native file-name allowance subtracts one SQLite cache, eight
partition buffers and 64 KiB from the working budget
(`R/graph_source_matrix.R:46-52`). At the supplied settings it permits:

```text
8 MiB - 2 MiB cache - 8 * 256 KiB partitions - 64 KiB
= 3.9375 MiB file-name reservation
```

Source and staged-graph connections can coexist at writer finish
(`R/operation_pack_v4_graph_adapter.R:102-114`) and promotion
(`R/graph_lifecycle.R:87-96`). Each independently receives the configured cache
(`R/graph_storage.R:30-54,221-245`). Native verification additionally owns a
selector connection with a 64 KiB cache (`R/graph_source_matrix.R:158-162`).
With two 2 MiB caches, eight 256 KiB partitions, that selector reservation and
the permitted file-name reservation, aggregate reservations total 10 MiB, not
8 MiB. There is no demonstrated shared reservation ledger or cache subdivision
in these inspected helpers. Decoder, conversion and native-sort peak overhead
coverage also remains unproven. SQLite cache_size is not a complete process
memory bound.

## Additional finding: provenance loses admitted writer policy

`R/promote_primitives.R:332-348` derives the promotion policy from graph-stage
budgets and scopes the source connection before publication. Nevertheless,
`R/provenance_store.R:1623` calls `.wb_graph_sql_identities(con, art_id)` without
that policy. Its default (`R/graph_bindings.R:148-150`) is
`.wb_graph_budgets()`: 64 MiB working memory, 8 MiB SQLite cache and 1 MiB
partitions (`R/graph_storage.R:5-9`). The nested scoped helper therefore replaces
the outer 2 MiB cache with 8 MiB during retained-certificate hashing and selects
larger partitions. Later restoration does not undo allocations at peak.

The retained-reference path has the same policy omission:
`R/provenance_store.R:578` calls `.wb_graph_retained_identities()` without budgets;
`R/graph_lifecycle.R:1-4` reconstructs defaults. The private-stage path at
`R/provenance_store.R:579-581` does explicitly pass `state$budgets`, so this is
not a claim that every provenance hash loses its policy.

Carry the actual stage/output policy, or an equivalent explicitly admitted
aggregate publication policy, through snapshot/certificate and retained-source
hashing. An inner helper must not silently enlarge the active admission.
Reconcile mixed outputs under the aggregate budget rather than using each
output's default independently. This is a confirmed source correction
requirement, not a demonstrated explanation for the live measurement below.

## Required correction and boundary

Preserve the fixed total-process ceilings, canonical floors and unchanged
declared limits. Partition reservations across every concurrently owned cache,
selector and buffer, including still-live staged graph connections, or reject
aggregate admission fail-closed before allocation. Do not resolve this finding
by raising memory limits. Account for peak native name conversion/sort storage
and distinguish explicit reservations from measured runtime memory.

The inspected matrix-source authorization branch still rejects before invoking
the native verifier (`R/graph_sources.R:151-153`). This review does not establish
that live gate 175 exercised native matrix verification with overlapping caches.
A broad RSS ceiling below 700 MB would not independently close the 8 MiB
working-reservation defect.

## Separate live-gate diagnostic

During this follow-up, read-only `rg '^(Name|State|VmHWM|VmRSS):'
/proc/274696/status` observed the R process still running, with
`VmHWM: 887336 kB` (908,632,064 bytes) and `VmRSS: 829088 kB`. The supplied earlier
observation was 811,032 KiB (830,496,768 bytes). Both high-water readings exceed
the exact 699,392,000-byte ceiling. That ceiling is independently present in
`notes/generic_graph_implementation/evidence/175_native_2x_development_lifecycle.log.tmp.jU8Tx0`
along with the frozen core pin and exact installed package path. These are live
diagnostics, not a completed sidecar/result or proof of the cause of growth.
The CSV records disk usage, not RSS. Do not label this run a bounds pass; no
root cause, complete lifecycle outcome or linkage to the dirty helper is proved.
The reviewer did not signal, stop or otherwise modify the process.

## Exact inspected source

Worktree:
`/home/dirk/Projects/.scworkbench-worktrees/generic-graph-implementation-forge-20261010`.
HEAD was `9a11d1fe988780041daa258eff987e9a1c7b2276`, with dirty and untracked
implementation files. Findings apply to these actual file bytes, not merely
the committed HEAD. The native verifier was untracked.

| File | SHA-256 |
| --- | --- |
| `R/graph_storage.R` | `537eb5dc72e06b4d65b39db9d0a354cc2fe9360b8635b9cd4a054d7f6cd64b82` |
| `R/graph_source_matrix.R` | `71faffe4f667887c5bea6f9e58fc5cf07a587fa1aeae72cb6ee16d9d2ff70d81` |
| `R/graph_lifecycle.R` | `1c9754e259e2c214208311b53e9ab31f41c86399867f86c8da7f867384e75c9d` |
| `R/operation_pack_v4_graph_adapter.R` | `f631c5dbb9823afea18a0a4ec268ff62b5e4a9f8ad7ca57fd579ec97e1ee1a79` |
| `R/graph_sources.R` | `f6eb91d8ff7788a34c1f251c5c64ace363901af2babfa42499de3674713962c4` |
| `src/graph_native_source.c` | `d0f566460103e703f9736a7da8886db14e62003b4080be10bb9a52bf81957e1a` |
| `R/graph_bindings.R` | `8e4aa2475311b099088a8943da73ce6a3c2a62be9f5a67b8d78be72b51acc2ce` |
| `R/provenance_store.R` | `c079b21a5f59ae7dc98b8aa6f969f0c72f280b5a53bf191a6332da0e27d69231` |
| `R/promote_primitives.R` | `c9b9f91edfa266b1bca4eea9033490b4490868c071b9a42f7ca6b189e093f89f` |

Read-only commands: `git rev-parse HEAD`, `git status --short`, targeted `rg`,
`sed -n`, `nl -ba`, and `sha256sum` over the files above. No runtime probes,
full suites, candidate edits, new authority design, build, merge or push were
performed. Only this report is added in the isolated audit worktree; it remains
uncommitted pending the authorized correction and focused re-review.

## Focused correction re-review (2026-10-11)

Disposition for the two original source defects: CLOSED within the inspected
graph accounting/provenance paths, not complete memory or native-matrix
qualification. Historical findings above remain a record of the earlier bytes.

The new aggregate helper splits the configured cache reservation among distinct
live connections and reserves 64 KiB for the native selector. Writer open and
promotion enumerate known bundle/stage connections. Nested identity hashing
clamps effective policy and cache share to the active connection policy rather
than substituting larger defaults. Snapshot writing explicitly derives and
passes the graph output policy to payload and retained-certificate hashing.

Independent installed rerun: aggregate/nested-policy/provenance branches,
late-transaction admission rejection, and publication-budget rollback: 3/3
passed, exit 0. The aggregate test observes all three stage-payload,
published-certificate and retained-reference branches under the 8 MiB policy,
and verifies cache caps and restoration. Critical installed function bodies and
formals matched the current source for aggregate/scoped/effective budget helpers,
SQL identities, provenance payload identity and snapshot writer. Library:
`/tmp/scwb-graph-forge-resume.voZ26I/library/scworkbench`.

Reproduction: with that library first in `.libPaths()`, load scworkbench, source
`tests/test_graph_resource_accounting_contract.R`, and call
`test_graph_resource_aggregate_cache_and_nested_policy_contract()`,
`test_graph_resource_late_transaction_admission_rejects_contract()`, and
`test_graph_resource_publication_budget_rollback_contract()`; each returned TRUE.
Function parity was checked against parsed source assignments with identical
`body()` and `formals()`. No candidate files were written by the reviewer.

Retained evidence 198 reports 12/12 and 201 reports 4/4, both exit 0; these are
author reruns, distinct from the independent 3/3 above. Candidate `git diff
--check` passed. All seven supplied source hashes matched before and after
the focused rerun:

| File | Corrected SHA-256 |
| --- | --- |
| `R/graph_storage.R` | `151999d756a04a13c783a1c81addd3117e2c665e756b602e6af14d021ebb217a` |
| `R/graph_bindings.R` | `f60732f1ddf9182e2c75873be66f63561152349482036571200a845441666bed` |
| `R/graph_lifecycle.R` | `11eb2f365660ae9162d0bf21c3aaca9e9a17c993662211bbce6d91241706c870` |
| `R/graph_source_object.R` | `43809cf03d9b363d283cf5218b95408ee8111355c541e1119e297fada7030a00` |
| `R/promote_primitives.R` | `37d9bd56c614abd5f970725f19195f46d69193442d328adedc32ff02ea130120` |
| `R/provenance_store.R` | `2f4e9e12710e608341d9b4ba5f4943c53c9a6bf67e1f9f317363b03a60b9a161` |
| `R/operation_pack_v4_graph_adapter.R` | `62a77fef7d957a6cab7f201d98058c2f6d355e402f794e8b4c8f59325d8f7129` |
| `tests/test_graph_resource_accounting_contract.R` | `2e7aa5f4b30f6d02f0840adb8ab0eaf78c56722a7241f5e540ed5b0b76be2fe7` |

Evidence paths are under the candidate's
`notes/generic_graph_implementation/evidence/`:

| File | SHA-256 |
| --- | --- |
| `198_aggregate_budget_fixture_retry.log` | `f4f900608af783397b045fdd85e05595ef498e1943088e4a1984b83a9f2da750` |
| `201_provenance_budget_branches_and_late_admission.log` | `b0c1a35f7123d116f335247d5bb84a8a748faa33bfb74551afd91db1300fef8d` |
| Both corresponding `.exit` files | `9a271f2a916b0b6ee6cecb2426f0b3206ef074578be55d9bc94f6f3fe3ab86aa` |

Native matrix binding remains disabled. The incremental byte bridge and hidden
SQLite TEXT allocations were not reviewed or qualified here. Fixed process
ceilings, declared budgets and canonical floors remain unchanged; Attempt 175
remains functional PASS/resource FAIL and no cause is inferred. No large rerun,
full suite, final qualification, merge or push. Report remains uncommitted.

## Checkpoint 215 owned-stage and auxiliary-reservation follow-up

Focused resource disposition: owned, previously unstaged promotion reservation
gap CLOSED at the fingerprints below. Not native authority/byte-bridge,
manifest compatibility, measured RSS or final qualification acceptance.

`R/graph_lifecycle.R:90-99` now admits source plus one additional connection
before constructing an owned stage, passes the derived cache share to
`stage_small`, and applies aggregate admission during publication. Stage creation
uses the share directly before schema writes (`R/graph_storage.R:275-296`), rather
than briefly configuring the full cache first. The aggregate reservation now
subtracts 128 KiB (`R/graph_storage.R:42-48`) for selector and read-only byte-reader
caches of 64 KiB each. At a 2,048 KiB aggregate budget and two shared connections,
the shares are at most 960 KiB each; 960 + 960 + 128 = 2,048 KiB. The byte-reader
cache setting was inspected at `src/graph_sqlite_bytes.c:79`; its broader bridge
behavior was not qualified in this review. Native file-name admission still
subtracts the full aggregate cache reservation, so this change does not expand
that name allowance. Declared memory/process ceilings and canonical floors are
not raised by this correction.

Independent rerun against checkpoint-215 installed package:
`/tmp/scwb-graph-forge-owned-stage.kH6rcm/library/scworkbench`:

- `test_graph_resource_unstaged_public_promotion_cache_contract()` passed,
  including concurrent caps observed at stage configuration, injected publication
  rollback, owned-stage cleanup, retry and caller-policy restoration.
- `test_graph_resource_aggregate_cache_and_nested_policy_contract()` passed,
  including provenance branches and nested policy restoration.

Result: 2/2, exit 0. Installed function bodies/formals matched parsed current
source for aggregate connection admission, graph configuration, stage creation
and graph promotion. Source the resource test file after loading that exact
installed library to reproduce the two function calls. Author evidence 216
separately reports 21/21 with zero failures/skips; no claim is made that the
reviewer repeated its native or manifest tests. Candidate diff-check passed.

| Checkpoint object | SHA-256 |
| --- | --- |
| `R/graph_storage.R` | `af194df76772e82f863bc8cd005935720b259233f98250f37fab735fdb55295a` |
| `R/graph_lifecycle.R` | `a6f53dd809189f57600ce1f2a2389f3e3e625d36a750c7c411c6d9a0cae0df58` |
| `src/graph_sqlite_bytes.c` | `26c6813cf7599c4765b3a2f846774425c9aece329b95c5dc6cfb0732e15931a2` |
| `tests/test_graph_resource_accounting_contract.R` | `9d57db368f7fe8420ecf1d81441800a12018e1decdcb8807aefec5869fce91d5` |
| `evidence/215_owned_stage_checkpoint.sha256` | `fbfa79101d4c1ad1be283193e0f9d1befef2fdd53493a8a3d87c84af1f662659` |
| `evidence/216_owned_stage_native_manifest_focused.log` | `7df17daa316b3beac033d57bc4432ef78f5d62aa690d786db0461ca3cc5863d5` |
| Corresponding 216 `.exit` | `9a271f2a916b0b6ee6cecb2426f0b3206ef074578be55d9bc94f6f3fe3ab86aa` |

Evidence paths above are relative to `notes/generic_graph_implementation` in
the implementation worktree. Other checkpoint-215 source hashes matched its
recorded ledger; later manifest compatibility work is outside this review.
No implementation edits, large rerun, full suite, commit, merge or push.
Attempt 175 remains resource FAIL.

## Checkpoint 220 byte bridge and manifest review

Bounded disposition: the inspected incremental byte bridge and manifest framing
passed the independent checks below. This is not acceptance of matrix dispatch,
the subsequently amended lifecycle, measured process memory, or final runtime
qualification. Checkpoint 220 has since been superseded in two source files.

Findings, in severity order:

1. **Source compatibility correction required before matrix dispatch.** Frozen
   `R/getters_matrix_bounded_verify.R:107-111` rejected every cross-fragment cell
   overlap. The existing getter supports `prefer_newest` overlap resolution;
   this restriction was not supported by the native-reuse planning contract.
   The reviewer raised the conflict directly. Forge confirmed no authoritative
   restriction and reports removal of the blanket rejection, with a getter/hash
   parity regression forthcoming. That later correction is not independently
   accepted by this checkpoint review. Preserve per-fragment physical and
   membership checks without inventing a new disjoint-source validity rule.
2. **Owned-stage cleanup correction remains separately pending.** Forge reports
   that Sable found direct nested policy restoration ordering masked by the
   public outer scope. A later explicit inner-before-outer cleanup and direct
   transaction rollback/retry test supersede checkpoint-220 lifecycle bytes.
   The earlier two focused promotion tests did not establish this direct-path
   behavior. No acceptance of that correction is inferred here.
3. No additional bridge or manifest identity defect was reproduced in the
   bounded independent selection. A configured SQLite cache allowance is not
   proof of a process RSS ceiling; Attempt 175 remains resource FAIL.

All 25 checkpoint-220 source/test ledger entries verified before the independent
reruns with `sha256sum -c
notes/generic_graph_implementation/evidence/220_review_checkpoint.sha256` in the
implementation worktree. Ledger SHA-256:
`1d5d849e6858a434985e306f039fb4186a97e2e4ef36fade353a7e9a3d081825`.
The new unused `graph_source_matrix_selection.R` was outside that freeze and
excluded. Matrix dispatch remained disabled in the frozen source.

`src/graph_sqlite_bytes.c:79,138,199-208` uses a read-only snapshot, a 64 KiB
cache setting, bounded incremental byte reads (at most 65,536 bytes per call),
and an end-of-observation data-version check. It does not fetch a whole TEXT
field merely to obtain its bytes. The R text reader bounds UTF-8 carry and
rejects malformed/NUL-containing identity input. Native matrix identity retains
the existing typed serialization and lexical axis identity, rather than defining
a replacement identity. The SQLite per-field integer-size domain remains a
backend limitation, not universal support for arbitrary field lengths.

`R/bundle_manifest_stream.R:5-18,34-49,110-116,160-166` preserves the legacy
5,000-row logical chunk framing, admits projected row carriers before fetching,
accounts for concurrent observer/selector cache reservations, and rejects active
graph-policy observation of an unsupported transaction/in-memory source rather
than silently taking a whole-table fallback. Legacy fallback remains outside
active graph-policy mode. The parity fixtures cover SQL scalar coercion,
extended types, mixed BLOBs, external mutation and transaction rejection.

Independent installed library:
`/tmp/scwb-graph-forge-review.o9ycZ1/library/scworkbench`.
Load that library first, source
`tests/test_manifest_stream_identity_contract.R` and
`tests/test_graph_native_matrix_identity_contract.R`, and call:

- `test_manifest_stream_scalar_and_sql_type_parity_contract()`;
- `test_manifest_stream_extended_types_and_mixed_blob_contract()`;
- `test_manifest_stream_late_mutation_and_transaction_contract()`;
- `test_graph_native_matrix_incremental_text_and_axis_contract()`;
- `test_manifest_stream_huge_single_text_contract()`.

Independent result: **5/5 passed, exit 0**. The huge-TEXT legacy oracle is outside
the measured streaming path; this rerun establishes identity parity, not a peak
RSS qualification. Parsed source bodies and formals for all six functions in
the byte-reader, manifest-stream and bounded matrix-identity files matched the
installed functions exactly.

Author gate 221 separately terminated with 22 discovered/executed/passed,
zero failures/skips and exit 0. Its log SHA-256 is
`e07300236debccf64746b8814753f1510fd84e2900c6e222ed76a5b4877de246`;
its exit-file SHA-256 is
`9a271f2a916b0b6ee6cecb2426f0b3206ef074578be55d9bc94f6f3fe3ab86aa`.
Those retained results are not attributed to the subsequent corrections.

Only this audit report was written. No candidate edits, full suite, large rerun,
dispatch enablement, commit, merge, push or final qualification was performed.

## Checkpoint 226 focused correction re-audit

Focused disposition: the two checkpoint-220 correction findings above are
**CLOSED at checkpoint 226**. This supersedes their pending status, not the
historical findings or the broader qualification exclusions.

All 27 entries in `evidence/226_review_checkpoint.sha256` verified before the
reruns. The lifecycle now has one explicit exit cleanup block
(`R/graph_lifecycle.R:91-95`): discard the owned stage, restore the inner
aggregate policy, then restore the outer owned-stage reservation. This ordering
preserves the caller's original policy instead of restoring the intermediate
reservation last. The direct transaction regression exercises failure and retry
without relying on a public outer scope; cache, policy, cap and temp-store
settings match their originals and both owned-stage paths disappear.

`R/getters_matrix_bounded_verify.R:108-133` now authenticates each fragment and
the complete logical axis union without rejecting overlap solely because a
cell occurs in multiple fragments. Per-fragment ordered identities, physical
shape/names and membership checks remain. The regression constructs an explicit
legacy overlapping-fragment fixture, checks `prefer_newest=TRUE` and `FALSE`
against their different expected values, and checks native identity against the
unchanged legacy `matrix.fragment-tree.v2` identity. No alternative identity or
new disjointness rule was introduced.

Independent installed library:
`/tmp/scwb-graph-forge-restoration.Mrihjd/library/scworkbench`.
With that library first in `.libPaths()`, load scworkbench, source the resource
and native matrix identity test files, then call:

- `test_graph_resource_unstaged_direct_transaction_restoration_contract()`;
- `test_graph_resource_unstaged_public_promotion_cache_contract()`;
- `test_graph_native_matrix_overlapping_fragment_getter_parity_contract()`;
- `test_graph_native_matrix_physical_and_membership_verification_contract()`.

Independent result: **4/4 passed, exit 0**. The last test also rejected foreign
physical names, reordered declared axes and duplicate declared IDs. Tiny fixture
dense conversions were test oracles, not evidence of bounded large-data RSS.
All seven installed function bodies/formals in lifecycle and physical verifier
matched parsed source. Candidate `git diff --check` passed. Author gate 227 was
still live at inspection; no terminal result is claimed here.

| Frozen object | SHA-256 |
| --- | --- |
| `R/graph_lifecycle.R` | `8dbae54af18b7e80d2d3210d9a0ce5523c3b99de4786ddead898549c0ea5e5f6` |
| `R/getters_matrix_bounded_verify.R` | `dc4e1d26af33de1c898a121f5ef731fcfb31b1c7c0c0d6753b2ffd13788164e5` |
| `tests/test_graph_resource_accounting_contract.R` | `be5d2dadeedcec66ede64b09791e762c6c4eaeb5f0600fc90ff12e143cfdbd26` |
| `tests/test_graph_native_matrix_identity_contract.R` | `d89fe4324724913dc8c6c2274603bdda894c601ffe05b07456d7e46a6f3b54af` |
| `evidence/226_review_checkpoint.sha256` | `419ceabb9f93573193a8041f75be57f0b21514fd971aa8c04056bb91fee29f4c` |

The new producer-selection file is frozen but unused and was not qualified by
this correction review. Matrix dispatch remains disabled. This does not accept
an eventual source-binding route, final qualification or RSS compliance;
Attempt 175 remains resource FAIL. Only this uncommitted report was changed;
no candidate edits, large rerun, full suite, commit, merge or push.

Post-rerun freeze check: the lifecycle, physical verifier and both correction
test files still matched checkpoint 226. The complete ledger no longer passed:
`R/graph_source_matrix_producer.R` and `R/graph_source_matrix_selection.R` changed
concurrently after the initial 27/27 verification. Those producer-selection
changes are outside the two correction findings and are not covered by this
result. Do not apply checkpoint-226 acceptance to the entire current dirty tree.

## Checkpoint 231 preactivation source-helper review

Bounded disposition: **PASS for the inspected standalone source helpers at
checkpoint 231**. No new helper defect was reproduced. This is not public
matrix-source activation, an end-to-end G2 lifecycle, or memory qualification.

All 29 checkpoint-231 ledger entries matched before and after the independent
reruns. The public matrix authorization branch remained fail-closed
(`R/graph_sources.R:152-153`); the new authority and precheck helpers were
unwired. No dispatch/schema acceptance is inferred from calling them directly.

`R/graph_source_matrix_producer.R:12-54` now owns an effective aggregate resource
scope before selectors or the read-only byte observer, including standalone run
hash calls. Selector fields are admitted before decoding. The producer requires
one exact-snapshot matrix output joined to its MATERIALIZES binding and retained
run, agreement of output/binding content schemes and hashes, verified output
status, and recomputation of the existing run-integrity hash. Native authority
(`R/graph_source_matrix_authority.R:3-21`) checks the exact retained snapshot,
physical fragments and full logical axes, then compares actual native payload
identity to that producer and both declared axis identities.

`R/graph_source_matrix_selection.R:4-72` scopes standalone selection and
snapshot verification. It selects the actual matrix/run/output tuple, rejects
ambiguous producers and pending references, and remains stable when an unrelated
later head is published. It does not adopt a session receipt or invent another
source certificate. `R/operation_pack_v4_matrix_source_precheck.R:26-62` rejects
a known pending producer sharing the same logical matrix ID even when input is
a direct ID or primitive. This is a helper-level early-rejection result only;
its placement before public staging still requires the later wired-route audit.

Independent library:
`/tmp/scwb-graph-forge-preactivation.ccgwBW/library/scworkbench`.
With that library first in `.libPaths()`, load scworkbench, source
`tests/test_graph_matrix_source_selection_contract.R` and
`tests/test_graph_native_matrix_producer_contract.R`, then call:

- `test_graph_matrix_promotion_first_precheck_contract()`;
- `test_graph_matrix_native_existing_source_authority_contract()`;
- `test_graph_matrix_existing_producer_selection_contract()`;
- `test_graph_native_matrix_producer_run_frame_parity_contract()`.

Independent result: **4/4 passed, exit 0**. These include pending-same-ID
rejection through active reference/direct ID/primitive/default input, unchanged
registry/no staging, source/axis substitution, retained-run parameter tampering,
policy restoration, unrelated-head stability, and legacy run hash parity for
NULL, Unicode and a TEXT field larger than 8 MiB. Seven installed function
bodies/formals across the four reviewed helper files matched parsed source.
Large-TEXT construction and its legacy oracle are fixture work, not evidence of
streaming peak RSS compliance. Candidate diff-check passed.

| Checkpoint object | SHA-256 |
| --- | --- |
| `R/graph_source_matrix_producer.R` | `097337b568b4fa6b1331bb1ab4d66b1bf2c35e459f985ad708c12dc23b5337e5` |
| `R/graph_source_matrix_selection.R` | `2160e64c5eff38c702692d6cfe3d451cff1fe2d9085f4aedafbc3f8dc200490d` |
| `R/graph_source_matrix_authority.R` | `3b38ec61c51b8c5b1393ab6fd8e7de390478bc769061d1cb04ec6e8d08ba6cb8` |
| `R/operation_pack_v4_matrix_source_precheck.R` | `ef8f6436d6162e06b971fdc87209c53709777bd1ecc7e94f232bddf37c69e1e4` |
| `evidence/231_review_checkpoint.sha256` | `5af5ea75487f3fae3fd6850d77e44f6ea0d2fdb2d92129ce5e07cd4e319ec5fe` |
| `evidence/232_preactivation_source_helpers_installed_focused.log` | `50f6e1e48945c348beba02e8ca9866cce8925de35106150a894a0babe103875f` |
| Corresponding 232 `.exit` | `9a271f2a916b0b6ee6cecb2426f0b3206ef074578be55d9bc94f6f3fe3ab86aa` |

Author gate 232 separately reports 6/6 with zero failures/skips and exit 0;
it is not the independent four-test result. The proposed 90,000-source memory
diagnostic was not performed or qualified by this reviewer. Public promotion,
binding, run, graph publication, relocation and recipient reopening remain for
a later frozen activation checkpoint. Attempt 175 remains resource FAIL.
Only this report was written and remains uncommitted. No candidate edits,
full suite, large diagnostic, dispatch enablement, merge or push.

## Checkpoint 238 real promoted G2 coverage correction

Focused disposition: **PASS for the corrected native cell query and real G2
source-helper regression at checkpoint 238**. The optional-index coverage defect
is closed for this tested lawful materialization. Public graph binding/dispatch,
graph publication/relocation and process-memory qualification remain outside it.

The former matrix cell query relied on optional `matrix_cells`, which is empty
for the tested publicly promoted RNA normalization output. The corrected query
(`R/graph_sources.R:74-80`) uses an EXISTS join through fragment cell membership
and returns each matching cell in canonical bundle order. Together with physical
fragment and complete-union verification this supports the tested coverage
without introducing a new producer, certificate or identity scheme. The lawful
fixture's membership/order agrees with `wb_cells_with_matrix`; this does not
claim identical behavior for every malformed or historical source profile.

All 30 checkpoint-238 hashes matched before and after the independent selection.
The installed axis-query body and formals matched the frozen source. Independent
library: `/tmp/scwb-graph-forge-real-g2.9EFs2q/library/scworkbench`.
With that library first in `.libPaths()`, load scworkbench, source
`tests/test_graph_native_matrix_real_g2_source_contract.R` and
`tests/test_graph_matrix_source_selection_contract.R`, then call:

- `test_graph_native_matrix_real_promoted_g2_source_contract()`;
- `test_graph_matrix_native_existing_source_authority_contract()`;
- `test_graph_matrix_promotion_first_precheck_contract()`.

Independent result: **3/3 passed, exit 0**. The real G2 test installed scwbRNA
from clean commit `151dd29211b219343dce6247c5e48fc932b4c83d`, ran the public
normalization, rejected its unpromoted producer, then used the lawful public
terminal-summary promotion path. It explicitly asserted zero optional-index
rows for `RNA_log`, complete canonical three-cell getter coverage, and exact
retained run/output selection. Both source-helper axes passed: three cells and
two features, with native payload identity matched to the retained producer.
The other tests independently reran substituted source/axis/run-parameter
rejections and pending-same-ID rejection without registry/staging residue.

| Checkpoint object | SHA-256 |
| --- | --- |
| `R/graph_sources.R` | `ca300373461e73ba65c023f01c1671a4b0186f27c38547e8dfd2ff8057ce1f28` |
| `tests/test_graph_native_matrix_real_g2_source_contract.R` | `2a240233e0c91f1f6113252c729e74d408c3e8366ea521d737804ddcdf1b1482` |
| `evidence/238_review_checkpoint.sha256` | `32407c070a71195627d04b6aaf4efe8f01ae55317e02aa74b7325d6e1db9746c` |
| `evidence/239_real_g2_getter_equivalent_installed_focused.log` | `c72cd36c0f996fe6919b8ad5dd2dffc73a37a4a45483777d163f1e051a5cb3de` |
| Corresponding 239 `.exit` | `9a271f2a916b0b6ee6cecb2426f0b3206ef074578be55d9bc94f6f3fe3ab86aa` |

Author gate 239 separately reports 8/8 with zero failures/skips and exit 0.
Candidate diff-check passed. The throughput prototype and immutable-231 memory
diagnostic were not audited here. Native dispatcher/schema activation remains
disabled. No end-to-end public G2-to-graph lifecycle, peak RSS or final runtime
acceptance is inferred; Attempt 175 remains resource FAIL. Only this uncommitted
report was written. No candidate edits, large rerun, full suite, merge or push.

## Checkpoint 246 admitted-small-row manifest batching

Focused disposition: **PASS for the inspected batching descendant**. No new
identity, admission or restoration defect was reproduced. This does not accept
native activation, final gates, performance at scale or a measured RSS ceiling.

All 31 checkpoint-246 ledger hashes matched before and after the independent
rerun. The installed manifest function body/formals matched the source. Source
authority bytes from checkpoint 238 remain unchanged. The batching change is
confined to already admitted small scalar rows; deferred TEXT/BLOB still takes
the existing byte-stream path. The 5,000-row logical hash boundary is unchanged.

`R/bundle_manifest_stream.R:136-194` checks a fixed setup/candidate allowance
before constructing at most 64 candidate indices. Deferred rows stop a batch.
Per-row encoded charge uses six-byte worst-case text escaping and conservative
numeric/type allowances. Selected dataframe/type carriers, candidate vectors
and eight encoded copies must fit within the existing eight-partition reserve
before serialization; no budget is raised. Actual encoded size is checked
against the admitted estimate. The live fetched batch/cache allowances remain
separately precharged. At tiny partitions the candidate path is skipped rather
than allocating a batch and checking only afterward. These are declared
admission checks, not proof of the R/SQLite allocator's peak physical footprint.

Independent reproduction:

`Rscript --vanilla notes/generic_graph_implementation/resume_manifest_batch_focused.R /tmp/scwb-graph-forge-manifest-batch.up7s1ke0`

This ran all six manifest contract functions independently against the exact
installed package: **6/6 passed, zero skips, exit 0**. Coverage includes legacy
SQL scalar/type coercion, extended types/mixed BLOBs, huge single TEXT, external
mutation/transaction behavior, 4,999/5,000/5,001-row framing, and the new aggregate
admission/fault-restoration regression. That regression checked 128-byte,
4-KiB and 256-KiB partitions, no small-batch emission at 128 bytes, bounded
reservations at batching sizes, and exact cache/temp/policy/cap restoration after
injected failure. Subsequent SQL queries succeeded. Injection emitted two
cleanup warnings (pending result closed; expired result already closed); it did
not change the intended error or the restored caller state. Huge-TEXT legacy
oracle construction remains outside any resource measurement.

| Checkpoint object | SHA-256 |
| --- | --- |
| `R/bundle_manifest_stream.R` | `8a87ce746a1a04fed5b37dcc8394fa0f458ab0ba259993944c09bd1addec69e0` |
| `tests/test_manifest_stream_identity_contract.R` | `a74e258ca2dae1efed4254acb44a346c73ae54d778a21d9332d0dd06370d468e` |
| `evidence/246_review_checkpoint.sha256` | `1fc96759504b126b62cfb7b4c9ca0a0c8f68820995e6a5cf1d4e81979a0a2443` |
| `evidence/247_manifest_batch_installed_focused.log` | `c79aba898c2dafa978a592309c8bcc53509fb7f79ce83532e1bc67e38fac7a8a` |
| Corresponding 247 `.exit` | `9a271f2a916b0b6ee6cecb2426f0b3206ef074578be55d9bc94f6f3fe3ab86aa` |

Author gate 247's 6/6 is separately retained, not substituted for the independent
rerun. Prototype timing improvements are not independently qualified here.
Interrupted diagnostic 234 is not acceptance evidence. Attempt 175 remains
resource FAIL. Only this uncommitted report was changed; no candidate edits,
full suite, large rerun, native activation, merge or push.

## Checkpoint 263 ordered-object source batching

Focused disposition: **PASS for the inspected batching path under the admitted
caller resource scope**. No new canonical identity, byte-admission or cleanup
defect was reproduced. This is not a standalone cache-scope guarantee for every
private helper call, public native activation, or process-memory qualification.

All 33 checkpoint-263 ledger entries matched before and after the independent
rerun. Seven installed object-source function bodies/formals matched parsed
source. Library: `/tmp/scwb-graph-forge-object-batch.hf4z4hix/library/scworkbench`.
Independent command:

`Rscript --vanilla notes/generic_graph_implementation/resume_object_batch_focused.R /tmp/scwb-graph-forge-object-batch.hf4z4hix`

Result: **1/1 contract passed, zero skips, exit 0**. This substantial single
contract covers both retained kinds, 0/1/63/64/65/5,001 rows, a materialized
normative canonical-JSON oracle, ordered finite-f64/null values, escaping and
UTF-8, scalar fallback, precharged batching and injected failure. Its wrapper
explicitly installs/restores the aggregate connection scope; the closure helper
itself does not newly own that scope. Caller cache/temp/policy/cap and private
token/metadata-file sets were unchanged after failure.

`R/graph_source_object.R` admits source bytes before decoding. At most 64 rows
are fetched; the carrier allowance plus eight worst-case encoded copies must
fit the existing eight-partition reserve. SQL repeats the admitted byte bound
and numeric-type restriction; observed dense ordinals and final row count must
match the admitted closure. A later-grown record therefore cannot silently be
excluded from a valid result. The independent regression injected such growth
between admission and cursor creation and observed rejection. Missing string,
invalid UTF-8 and too-small partition cases also rejected, while numeric SQL
NULL preserved canonical null. The original scalar route remains available when
batch admission fails. These checks preserve the existing ordered-object
canonical-JSON v1 preimage, not legacy R-object identity or universal snapshot
isolation against all concurrent mutations.

| Checkpoint object | SHA-256 |
| --- | --- |
| `R/graph_source_object.R` | `80b6c1b963a8bdf3cc0c60f4c8c836b48ffaeba8c3410e0ae231cefbdfad6c3a` |
| `tests/test_graph_object_source_batch_contract.R` | `652678b646b4cd9cf03719267f0cb4e4441b744e35ac10d38222c37d9958f0a5` |
| `evidence/263_review_checkpoint.sha256` | `bf6c9640ec9113a2242073ce2f6b0e69a855c1dd0aa0402624cea7649e29ca8e` |
| `evidence/263_object_batch_installed_codefield_retry.log` | `54fbd3c351aacdc362d81467f6ad40de173f007a182500676ba997c8a3d95dbc` |
| Corresponding 263 `.exit` | `9a271f2a916b0b6ee6cecb2426f0b3206ef074578be55d9bc94f6f3fe3ab86aa` |

Author gate 263's 1/1 is distinct from this independent rerun; failed earlier
test-assertion evidence remains historical, not acceptance evidence. Prototype
90,000-row timing and concurrent runtime 250 were not audited. Fixture/oracle
materialization and test elapsed times are not peak-memory qualification.
Attempt 175 remains resource FAIL. Only this report was written, uncommitted;
no candidate edits, full suite, large rerun, activation, merge or push.

## Checkpoint 272 source-scoped snapshot correction

Focused disposition: **PASS for the inspected source-scoped snapshot lookup**.
The unrelated-head admission defect is closed in the independent selection.
This does not accept public native activation, the live public lifecycle gate,
the bounded-collector work still pending, or process-memory qualification.

All 37 checkpoint-272 entries matched before and after the independent tests.
Fourteen installed function bodies/formals across `graph_sources.R`, matrix
selection/authority and `operation_pack_v4_transition.R` matched parsed source.
The lookup now restricts candidates with private exact snapshot, matrix-producer
or artifact-output selectors before decoding head fields. Public binding/grant
identities are unchanged. Unadmitted candidate headers cannot authenticate a
requested identity; skipping them is not permission to substitute a later head.
Admitted matching heads still undergo declared-run and provenance-count checks.
Matrix selection passes both its selected snapshot and matrix source; graph read
issuance/revalidation passes the artifact selector. These selector changes were
inspected, not treated as an independent full transition qualification.

Independent library:
`/tmp/scwb-graph-forge-snapshot-scope-corrected.uy2injsn/library/scworkbench`.
Load that library first, source `tests/test_graph_source_snapshot_scope_contract.R`
and `tests/test_graph_matrix_source_selection_contract.R`, then call:

- `test_graph_source_snapshot_unrelated_head_scope_contract()`;
- `test_graph_matrix_native_existing_source_authority_contract()`;
- `test_graph_matrix_existing_producer_selection_contract()`.

Independent result: **3/3 passed, zero skips, exit 0**. Unrelated oversized and
malformed heads were not visited. A forged exact identity rejected; an oversized
requested producer head rejected; restoring that head restored the same exact
selection. Source/axis/retained-run substitutions rejected, while an unrelated
later genuine publication did not replace the chosen producer snapshot.
Candidate diff-check passed. Author gate 273 was still live at inspection and
is not claimed as terminal evidence here.

| Checkpoint object | SHA-256 |
| --- | --- |
| `R/graph_sources.R` | `20db2ab8af84250384eccd2aadae3c5923bbbef8826b1524280da9c5ff202f10` |
| `R/graph_source_matrix_authority.R` | `82def315a0350df6c0b3c642d1e51f6351004a3c00ee5ad40cc481bae0162a94` |
| `R/graph_source_matrix_selection.R` | `94931692c4de8e9b2dbba440924a51c71af49b8c9441c6f60ff34de6ccfd1727` |
| `R/operation_pack_v4_transition.R` | `3820ac966b8293da318e7820202079b704dfaad32fc8c081f5acf3a9150a2e75` |
| `tests/test_graph_source_snapshot_scope_contract.R` | `9bf2ed32b3f0c30369c7cea476e7a6933eaff4e8f07adb51e8b1aa31cb7e0716` |
| `evidence/272_review_checkpoint.sha256` | `ad43206ff6b8298187a8019a833ca46549b8c6eb59406ff268346d0a070eefd6` |

Author-reported run 250 remains functional PASS/resource FAIL at 795,276 KiB;
recipient run 270's separate PASS does not repair that failure. Diagnostic 269's
allocation observations are not independently qualified or assigned causality
here. No lifecycle rerun or collector fix was performed by this reviewer. Only
this report was written and remains uncommitted; no candidate edits, broad gate,
large rerun, activation, merge or push.

## Checkpoint 330 native public route, bridge and owned-copy review

Scoped disposition: **REJECTED — publication temporary-spill admission omits
the private session-copy reservation.** This is a bounded checkpoint rejection,
not a claim that functional native lifecycle or all source authority is invalid.

### Blocking finding and exact correction

`R/graph_storage.R:180-184`: when `.wb_graph_disk_admit` receives a non-NULL
publication baseline, its temporary-spill check compares temporary bytes alone
to `token_bytes`. The combined check including the owned-copy reservation runs
only for a NULL baseline. This contradicts the checkpoint's stated requirement
that the admitted private copy participate in subsequent temporary-spill limits.

An independent exact-installed probe reproduced **ACCEPT** with:

```text
token_bytes = 4096
wb_graph_session_copy_bytes = 4096
open scwb_graph_identity_ temporary file = 4096 bytes
baseline = current database usage (publication mode)
combined reserved copy + live temporary bytes = 8192 > 4096
```

Reproduction: load the checkpoint-330 library first; create a temporary SQLite
database/table; record `.wb_graph_disk_usage(con)` as the baseline; construct
`.wb_graph_budgets(list(token_bytes="4096"))`; set its private
`wb_graph_session_copy_bytes` attribute to 4096; keep a `scwb_graph_identity_`
temporary file open with 4096 flushed raw bytes; call
`.wb_graph_disk_admit(con, budgets, baseline)`. Procfs measured the live temporary
bytes as 4096 and the call returned successfully. The probe then closed/deleted
only its own temporary file and connection.

Required correction: add `.wb_graph_session_copy_reservation(budgets)` to the
temporary-spill admission irrespective of baseline, while retaining the existing
scratch-database combined check and publication-growth limit. Add a regression
with a non-NULL baseline and live temporary spill that rejects the combined
over-budget case, accepts the exact boundary, and verifies promotion rollback
and caller-state restoration. Do not raise budgets or reclassify copy bytes as
free. No causal inference about earlier RSS failures follows from this finding.

### Verified alignment and bounded positive evidence

All 61 checkpoint-330 entries verified at initial inspection and after the
completed helper checks. Fifty-eight installed R function bodies/formals across
staging, bundle-open, storage, byte bridge, authority/precheck and transition files
matched parsed source. Installed library:
`/tmp/scwb-graph-forge-missing-connection-recovery.rf_6q6gv/library/scworkbench`.
The shared object matched its recorded hash. `ldd` showed no libsqlite3 dependency;
`nm -D --undefined-only` showed no unresolved direct SQLite calls.

The bridge now bootstraps an RSQLite API table using its own private in-memory
connection, not the caller's live cursor or extension permissions. The independent
same-engine contract passed: caller extension loading stayed disabled, an open
cursor continued, versions matched, transaction commit/rollback remained valid,
late mutation and closed-reader reuse rejected. Read-only observer access and
API-unavailability rejection were inspected in source; no sole-cause assertion
about old same-process locking failures is made.

The owned-copy and aggregate-budget contracts independently passed. They verify
pre-copy rejection, exact owned tree bytes/modes and private modification,
combined spill admission in the non-publication path, and raw NULL/empty-classed
source reopen without adopting either as authority. The existing transition
tree is copied; other payload roots retain immutable overlays. Private open
admits invocation cache policy before migration/recovery, while public
`wb_open_bundle` formals remain unchanged. Source/stage policies clamp active
limits and preserve copy reservations through effective-budget projection.
Those passing checks do not cover the omitted publication branch above.

Independent completed reruns total **10/10 passed, zero skips, exit 0**:

- Same-engine byte bridge, owned session-copy admission, aggregate cache/nested
  policy (three functions sourced from the byte API/resource contract files).
- Durable generation recovery, source-payload corruption recovery and matrix/model
  source-reopen authentication (three functions with the installed contract
  runner's helper environment and its skips converted to errors).
- `Rscript --vanilla notes/generic_graph_implementation/resume_native_matrix_public_focused.R /tmp/scwb-graph-forge-missing-connection-recovery.rf_6q6gv`
  (four contracts, including the complete public native fixture lifecycle).

The public fixture independently passed genuine normalization/promotion, early
unpromoted-source rejection with no clone allocation, fresh and reused staging,
full source axes versus subset mappings, three promotion and six execution
fault/retry boundaries, post-issuance durable source-description tampering,
subsequent graph read/run/promotion, finalization, relocation and a pack-free
read-only recipient with unchanged fingerprint. Captured read identity budgets
were exactly 8,388,608 bytes / 262,144-byte partitions / 256 rows. This is bounded
fixture functionality, not universal scientific or memory equivalence. The
independent reruns emitted the same categories of warnings described below;
they were not silently counted as absent.

Control-chain correction: the initial 61-file ledger omitted changed runtime
`R/operation_pack_v4_graph_axes.R` and `R/sdk_native.R`. The owner retained the
historical ledger and supplied
`evidence/337_candidate_330_runtime_freeze_addendum.sha256` (SHA-256
`1269de7942f38e8d66fe4a0a5259622607beb41c2b859f9811c5de6f71a0e14e`).
Both added file hashes verified; the five axis-authority functions matched the
installed package's bodies/formals. The issuer's full native producer/axes
authentication and durable/staged revalidation were inspected in these exact
bytes. Treat the source freeze as **330's 61 files plus this two-file addendum**,
not as proof that the original ledger already covered those files. No source or
installed bytes changed for this addendum. This control correction does not
close the publication accounting blocker.

All 16 shared assets and four actual checkpoint-330 request/receipt samples in
`evidence/336_shared_protocol_fixture_freeze_330.json` matched independently and
the samples parsed. This verifies bytes/provenance alignment, not Python runtime
qualification or permission to transfer rejected whole-checkpoint acceptance.

Retained author gates 331/332/333 terminate with respectively 8/8, 3/3 and 4/4,
zero skips and numeric exit 0. Their warnings were inspected and remain retained:
missing checkpoint-file warnings in adversarial generation cases, connection
finalizer reminders, matrix compression/dense-oracle warnings, and an already
disconnected connection warning. Parent failures 320/324 and earlier locking
observations/controls remain historical; their results are not reassigned to 330.

| Evidence | SHA-256 |
| --- | --- |
| `R/graph_storage.R` | `280318203f2673e73bf74317a001c72c1988182a818e3186d5ec6cea1682eaf3` |
| `evidence/330_review_checkpoint.sha256` | `235d33841044bd732b932ab756feff67018e29bbba38cf9d61d8ba21831df85e` |
| Installed `libs/scworkbench.so` | `7a054d35e2335dfe97e139e1e44f9fbc11845097546365056975fc7fa0a313c8` |
| `evidence/331_missing_connection_transition_regression_focused.log` | `34cd1b9343e0af0138221b4d3976563bae5344b513bbaa8db5318dba66337692` |
| `evidence/332_missing_connection_resource_focused.log` | `626c283ec77a8b8fc9794380fb77b6181cf925420ab5f92ff63c727f0d4c761b` |
| `evidence/333_missing_connection_native_public_focused.log` | `de190d40746904551089e3fe1643d1f65519ce07b41f70504776604cbcde8d79` |
| Each corresponding numeric exit file | `9a271f2a916b0b6ee6cecb2426f0b3206ef074578be55d9bc94f6f3fe3ab86aa` |

Prototype collectors/serializers, full suites, final RSS/disk/8x lifecycle and a
clean committed tuple remain outside this audit. Run 250 remains resource FAIL;
recipient success is a different gate. Only this uncommitted report was written;
no candidate edits, large lifecycle, merge, push or release.

## Checkpoint 341 narrow aggregate-spill and child-identity re-audit

Focused disposition: **ACCEPTED for the two corrected accounting boundaries and
exact installed child-recovery evidence at checkpoint 341**. The checkpoint-330
publication finding is CLOSED here, not retroactively accepted at 330. The live
stage/selector omission raised separately by Fresh Sable is also independently
closed in this selection. No whole-candidate, final RSS or large collector
qualification follows.

Findings: no remaining defect reproduced in the inspected narrow correction.
`.wb_graph_disk_admit` now checks the sum of live owned spill, any unobserved
explicit stage growth and private copy reservation for both publication and
staging modes. Publication database growth and journal budgets remain separate.
The prior 4,096-copy + 4,096-token case rejects under 4,096 and accepts at 8,192;
after token cleanup it accepts the 4,096 copy-only boundary.

Transient, explicit-scratch and disk admission now inventory concurrently open
graph stages, selectors/tokens and SQLite temporary files rather than omitting
the graph stage while admitting a selector. Device/inode strings identify one
physical object without floating-point inode conversion; explicit scratch and
logical stage growth add only the unobserved remainder. Hardlink/multiple-handle
deduplication and cleanup boundaries passed independently. Aggregate connection
policy deduplicates handles and sums separately owned clone reservations once.
These conclusions concern the tested core-owned paths, not arbitrary untracked
filesystem objects or universal process-resource enforcement.

Procfs descriptor names are admitted by bounded native directory enumeration
before allocation. `src/graph_native_source.c:13-55` uses an 8,192-byte stack
readlink buffer, rejects truncation/exhausted admission before R target strings,
and distinguishes vanished descriptors from other IO failures. A dedicated
finite metadata reservation is subtracted from source-tree filename allowance
so those inventories do not both consume the same declared remainder. Excess
open-descriptor metadata rejected and cleanup restored admission in the test.
No measured physical RSS bound is inferred from this reservation arithmetic.

All **63** checkpoint-341 hashes matched before and after the independent checks.
The terminal-evidence ledger verified completely. Fifty-nine installed function
bodies/formals across storage, source-tree inventory, staging, bundle-open and
byte-reader files matched parsed source. Exact installed library:
`/tmp/scwb-graph-forge-bounded-fd-owned-spill.3vly243i/library/scworkbench`.

Independent completed contracts: **7/7 passed, zero skips, exit 0**:

- `test_graph_resource_publication_copy_and_temporary_overlap_contract()`;
- `test_graph_resource_live_stage_and_selector_spill_overlap_contract()`;
- `test_graph_resource_owned_spill_alias_and_fd_metadata_admission_contract()`;
- `test_graph_resource_owned_session_copy_admission_contract()`;
- `test_graph_resource_publication_budget_rollback_contract()`;
- `test_native_sqlite_byte_same_engine_contract()`;
- `test_durable_session_subprocess_recovery_contract()`.

Reproduction: load the exact library first; source the resource and byte-API
test files for the first six. For the last use an environment parented by the
installed scworkbench namespace, source `inst/tests/contract_test_runner.R` and
the subprocess test, set `R_LIBS` to the installed library paths and
`SCWB_CONTRACT_INSTALLED_LIBRARY` to the exact checkpoint library, and make any
contract skip an error. The actual interrupted and race children independently
recorded and matched package path, installed DLL SHA-256 and all six selected
body/formal digests. Both MATCH records were observed in this reviewer rerun,
not merely a separate probe process. The original race deadline was unchanged.

One additional independent probe verified distinct connection reservations
5,000 + 7,000 sum to 12,000 even with a duplicate first handle supplied, and
restoration leaves both original policies unset. This is a probe, not an added
claimed canonical-suite test. Promotion rollback and copy isolation also passed.

Retained exact-candidate gates were inspected, not all rerun: resource/mixed
342 **13/13**, recovery 343 **8/8**, native public 344 **4/4** and same-engine
344 **1/1**, each terminal with zero skips and exit 0. Actual-child attestations
in 343 match the corrected installed DLL; historical 308/331 mutable-child
results are not substituted for them. Native public 344 includes the full
promotion-first/fault/tamper/read-budget/recipient checks. Sixteen shared assets
still match their prior freeze; all four separately retained 341 request/receipt
sample hashes verified and JSON parsed. No 330 samples were relabeled as 341.
Warnings and historical failures remain retained. Candidate diff-check passed.

| Checkpoint object | SHA-256 |
| --- | --- |
| `R/graph_storage.R` | `98fd2052e04dbe585c71a06e31dc4f8a9441f5aab3e53cc4664d9c5c44b5e163` |
| `R/graph_source_matrix.R` | `6d700b44701e6f8cad251c57a8e1602d1af4bac7499e4efb71a7edfda4584b7f` |
| `src/graph_native_source.c` | `55e6950c1657c3ef3cc9210a6819aa694f9cdc40210e6e797f245c1f72af22a0` |
| `tests/test_graph_resource_accounting_contract.R` | `f208b1a5265249db7342e24fcbe4e2e3703715013faea4672ea653da9804c14a` |
| `tests/test_durable_session_subprocess_recovery_contract.R` | `3e9733ce18887943ffe47ac7c24bb05dabecd9c7c7cfd0793e94b8704f1060e7` |
| Installed DLL | `435b639ba0ef18620051159b9612bbeac0215a85c6ac3bc53a94ebd7e2f5a902` |
| `evidence/341_review_checkpoint.sha256` | `34b78e2f69891f4a0308075f61480d7bc810dd35688b1d68598b734de89c840f` |
| `evidence/344_candidate_341_terminal_evidence.sha256` | `8eacf114188f83a1e055e53b7139c053a37b14e5aee5764917c21069425b1fea` |

Run 250 remains resource FAIL and large legacy collectors remain held. No final
8x lifecycle, broad package/Python suite, SIF, clean committed tuple or release
acceptance is asserted. Only this audit report was changed; it remains
uncommitted. No candidate edit, merge or push.

## Focused tuple400 collector review — 2026-10-11

**REJECTED within this collector-admission scope.** One independently reproduced
blocking defect remains. This does not revoke the earlier scoped341 accounting
result or assert that the historical250 lifecycle memory failure has this cause.

### Blocking: compact metadata can expand before resource rejection

`R/getters_artifact_metadata.R:46` audits encoded types and selected decoder
hazards, but does not pre-admit compact `row.names` expansion. Lines79–80 invoke
the old decoder and serializer before lines81–82 reject oversized results.
Consequently an eventual `GRAPH_RESOURCE_EXCEEDED` does not establish bounded
execution: the offending allocations have already occurred.

Independent installed-runtime reproduction through
`.wb_getter_metadata_canonical_hash`, with memory8388608, partition262144,
SQLite-cache2048KiB, partition-rows256 and collect4194304:

```json
{"type":"list","attributes":{"row.names":{"type":"integer","attributes":{},"value":[null,-2000000]}},"value":[]}
```

The input is112 bytes. After a warm-up call, `Rprofmem` records a16000048-byte
`num_to_char` allocation and a14889048-byte `collapse_object` allocation, both
inside `jsonlite::serializeJSON` reached from the admitted codec, before the
encoded-result resource error. Each individually exceeds the declared8MiB
memory budget; neither is evidence of total lifecycle RSS. A smaller independent
probe with50000 rows,110 input bytes and partition4096 likewise allocates400048
bytes before rejection, exceeding its32768-byte decoded-carrier admission.
No data-frame class is necessary. Sable independently reported the same hazard.

Required correction: account for semantic expansion **before** calling the old
codec or serializer, recursively through supported values and attributes, or
reject transformations without a bounded proof as operational resource failures.
Cover compact row names, coercions and any supported attribute aliases; preserve
old-preimage parity for genuinely admitted inputs. Do not raise the resource
budget or treat post-allocation rejection as closure. Add regressions exercising
the canonical-hash entry point at the standard policy, including nested metadata,
and verify that unsafe decoding/serialization was never entered. Freeze and
re-audit the amended installed runtime separately; tuple400 remains immutable.

Reproduction command structure (exact installed library first):

```r
.libPaths(c('/tmp/scwb-graph-forge-bounded-legacy-review-399.qgqe6cr5/library', .libPaths()))
library(scworkbench)
p <- scworkbench:::.wb_graph_budgets(list(memory_bytes='8388608',
  sqlite_cache_kib=2048L, partition_bytes=262144L,
  partition_rows=256L, collect_bytes=4194304L))
f <- scworkbench:::.wb_getter_metadata_canonical_hash
path <- tempfile(); prof <- tempfile()
writeBin(charToRaw('{"type":"list","attributes":{},"value":[]}'), path)
invisible(f(path,p))
text <- '{"type":"list","attributes":{"row.names":{"type":"integer","attributes":{},"value":[null,-2000000]}},"value":[]}'
writeBin(charToRaw(text),path)
Rprofmem(prof)
result <- tryCatch(f(path,p),error=identity)
Rprofmem(NULL)
print(result)
lines <- readLines(prof)
sizes <- suppressWarnings(as.numeric(sub(' .*','',lines)))
print(head(lines[order(sizes,decreasing=TRUE,na.last=NA)],3))
unlink(c(path,prof))
```

### Independently verified checks and exact attribution

The audit target is the frozen dirty77-asset tuple400, not clean HEAD
`9a11d1fe988780041daa258eff987e9a1c7b2276` alone. Both pre-review and current
post-review `sha256sum -c` checks pass77/77 against
`notes/generic_graph_implementation/evidence/400_collector_complete_review_tuple.sha256`
(ledger SHA256 `f2f4ef55493fc3d93bb88819f1de4010f7a900fb27641cb175e30b314d90eb20`).
The terminal418 evidence ledger also verifies completely; its SHA256 is
`b142fa700df717588211937b791146661cff0621f43ec213bc7c2e57d53d0065`.
Installed399 DLL SHA256 is
`ead7462807fb7920e924aa8995ec3ddb26ecbf87dd2c2d4b6ccf21f3b7a1bd56`;
all15 functions in the four collector files have matching installed bodies and
formals. Dependency scope is jsonlite1.8.8.

Completed independent `Rscript --vanilla` reruns from the frozen source worktree:

- `notes/generic_graph_implementation/resume_collector_focused.R /tmp/scwb-graph-forge-bounded-legacy-review-399.qgqe6cr5`:4/4 passed, zero skips, exit0. These cover public certificate/content parity and cache transitions, injected-fault cleanup, provenance parsing/fileless admission, and large structure-transform rejection with admitted small parity.
- `notes/generic_graph_implementation/resume_installed_metadata_codec_pinned.R /tmp/scwb-graph-forge-bounded-legacy-review-399.qgqe6cr5`:53/53 passed, exit0 (normal19, edge15, hostile/emitter15, boundary4). The conditional-class fixture emits its retained non-failing `makeExtends` replacement warning. No skipped or incomplete case is counted as a pass.
- The two additional independent compact-row-name probes above fail admission only **after** oversized allocations. Existing passing tests do not close that defect.

Retained current-candidate evidence inspected, not independently repeated in full:
401 codec53/53;402 collector4/4;403 affected-core5/5;406 same-engine API1/1;
408 accounting/mixed13/13;409 native-public4/4;412 recovery8/8, each zero skips
and exit0. Recovery includes two actual-child identity MATCH records. Public
full original90000-cell certificate404 matches the entire saved269 object;
full DAG419 matches saved272. Their source-DB checks pass and their after-opening
HWM observations are not whole-lifecycle memory qualification. Exported348
formals and16 shared assets remain unchanged; the four400 native samples retain
their actual producer attribution. Historical failures, including397's missing
archived pack activation, remain failures and are not relabeled as passes.

Code inspection covers all four collector files, native JSON scanner and shared
byte-reader header, affected getter/certificate/DAG integration, local jsonlite
unpack semantics and focused runner/test definitions. Descriptor/physical-row
comparison, selector/cache lifecycle, snapshot/source-mutation rejection and
provenance resource-error propagation are supported by the reviewed code and
bounded tests; this is not a claim of universal codec or scientific equivalence.
Candidate `git diff --check` passes. The implementation worktree intentionally
has frozen uncommitted implementation/evidence, not a clean committed candidate.

No broad suite, large lifecycle, SIF, publication, merge, push or resource-limit
increase was performed. Original lifecycle90000 remains held. Only this audit
report was added to the isolated audit worktree; substantive findings remain
uncommitted.

Final review release: both independent workers are terminal with exit0; the
77-file source ledger verifies again after their completion. Source and installed
DLL hashes remain those above. Freeze400 may be released **for the already
identified narrow correction**, not for lifecycle execution or acceptance.
Sable separately reported public `wb_entity_certificate` reachability using a
fresh fixture with consistently amended physical metadata and descriptor at the
same policy (`/tmp/scwb-sable400-review/public-hostile.R`); that corroboration
was not rerun or counted as a Meridian test. Forge's outside-freeze423 prototype
is not audited here and is not accepted by this report. Its next installed
descendant requires separate allocation/predecode, nesting, public-entry and
parity review before the original lifecycle hold can be reconsidered.

## Focused tuple429 compact-row correction re-audit — 2026-10-11

**REJECTED within the narrow metadata admission scope.** The original single-key
finding is addressed for the tested recursive/coercion cases, but a duplicate
attribute bypass remains independently demonstrated, including the public path.
Parent/prototype acceptance is not transferred. This is not lifecycle-RSS review.

### Blocking: first-key admission differs from legacy effective attributes

`R/getters_artifact_metadata.R:86` uses
`object$attributes[["row.names"]]`, selecting the first matching named entry.
The old codec retains duplicate attribute entries and `structure()` applies the
later row-name value. Auditing the attribute children at line106 does not restore
their enclosing row-name context. Thus a small first occurrence masks a dangerous
later compact expansion before the decoder at line114 and serializer at line115.

Exact176-byte reproducer:

```json
{"type":"list","attributes":{"row.names":{"type":"integer","attributes":{},"value":[null,0]},"row.names":{"type":"integer","attributes":{},"value":[null,-2000000]}},"value":[]}
```

Independent installed428 direct-codec probe (exit0 of the diagnostic process)
observes eventual `GRAPH_RESOURCE_EXCEEDED` only after a16000048-byte
`num_to_char` allocation and a14889048-byte `collapse_object` allocation. The
same input in a fresh, consistently amended physical-metadata/descriptor fixture,
through public `wb_entity_certificate`, invokes `unserializeJSON` **once** and
records16000048 bytes in `num_to_char` before that late error. The observed public
stack includes `.wb_getter_metadata_admitted_codec`, canonical work/hash,
physical metadata stream, legacy getter, certificate identity and
`wb_entity_certificate`. Its second observed large allocation is14888992 bytes.
Policy remains memory8388608, partition262144, SQLite cache2048KiB,
partition-rows256, collect4194304. Individual allocations exceed the memory
budget; this is not an aggregate-allocation or full-lifecycle RSS measurement.

Required correction: enumerate all named sensitive attribute candidates before
decoding, rather than looking up only the first, and apply global accounting
recursively. Conservatively reject any candidate lacking an admission proof or
account for the exact codec's effective/intermediate attribute semantics.
Apply the same duplicate-aware reasoning to the existing class/`.Class` safety
guards at lines94–98; this audit proves the row-name defect, not a separate class
exploit. Preserve old canonical parity for small admitted ordinary duplicates
and inert aliases. Include duplicate/reordered/escaped-name and nested direct
and public-path regressions with decoder-entry and actual allocation assertions.
Do not waive the finding because JSON keys are duplicates: the current parser
and legacy codec accept this input and the public path reaches the expansion.

Independent reproduction commands use `Rscript --vanilla`, the exact library
first, and these installed entry points. For the public probe:

```r
.libPaths(c('/tmp/scwb-graph-forge-compact-row-admission-428.wwmjo8v8/library', .libPaths()))
library(scworkbench)
e <- new.env(parent=asNamespace('scworkbench'))
sys.source('tests/test_graph_legacy_metadata_expansion_admission_contract.R',e)
p <- e$.graph_compact_policy()
root <- tempfile(); b <- wb_init_bundle(root); wb_define_cells(b,'c1')
prim <- wb_prim_cell_vector(c(c1='a'),meta=list(x=1L))
r <- wb_new_run('metadata_cell_vector',list(),list(),list(vector=prim))
o <- wb_promote_analysis(b,setNames(list(r),r$run_id),head_run_id=r$run_id,outputs='vector')
id <- o$promoted$artifact_id[[1]]
text <- '{"type":"list","attributes":{"row.names":{"type":"integer","attributes":{},"value":[null,0]},"row.names":{"type":"integer","attributes":{},"value":[null,-2000000]}},"value":[]}'
e$.graph_compact_replace_physical_metadata(b,id,text)
restore <- scworkbench:::.wb_graph_aggregate_connection_budget(list(b$con),p)
f <- function()tryCatch(wb_entity_certificate(b,'artifact',id),error=identity)
invisible(f()) # warm before allocation measurement
calls <- 0L
trace('unserializeJSON',where=asNamespace('jsonlite'),
  tracer=function()calls <<- calls+1L,print=FALSE)
prof <- tempfile(); Rprofmem(prof); result <- f(); Rprofmem(NULL)
untrace('unserializeJSON',where=asNamespace('jsonlite'))
print(calls); print(result)
lines <- readLines(prof); sz <- suppressWarnings(as.numeric(sub(' .*','',lines)))
print(head(lines[order(sz,decreasing=TRUE,na.last=NA)],2))
restore(); wb_close_bundle(b); unlink(c(root,prof),recursive=TRUE)
```

Fixture mutation is limited to the fresh diagnostic bundle; the frozen source,
historical bundles and installed libraries are untouched. This does not assert
that an ordinary current writer emits duplicate-key metadata.

### Independent checks and retained evidence

- Source tuple429 ledger83/83 passes both before review and after all workers
  are terminal. Ledger SHA256:
  `e2bd548149a03570f5e0b1075adf8c9103b6eff3e024828fd9233da934472f8a`.
- Terminal438 evidence ledger24/24 passes; its SHA256 is
  `2d8a14ec7e90ce482c28fda12e57375b6411e4a837232cf2475f644f33d2a6c3`.
- `Rscript --vanilla notes/generic_graph_implementation/resume_compact_collector_focused.R /tmp/scwb-graph-forge-compact-row-admission-428.wwmjo8v8` independently passes6/6, zero skips, terminal exit0. Original direct/public hazards reject before decoding; recursive values/attributes, signs, coercion, aggregate siblings, finite overflow and the33207-byte exact carrier boundary are tested. Public rejections have zero decoder calls,524336-byte maximum observed allocations, cache restoration and temporary cleanup. Admitted public cases match complete certificates and old getter identities. These passes do not cover the new duplicate-key probe.
- `Rscript --vanilla /tmp/scwb-tuple400-collector-attestation.R /tmp/scwb-graph-forge-compact-row-admission-428.wwmjo8v8` independently matches all15 collector bodies/formals. Runtime jsonlite1.8.8, RSQLite2.3.7, BPCells0.3.1, R4.4.1; DLL remains `ead7462807fb7920e924aa8995ec3ddb26ecbf87dd2c2d4b6ccf21f3b7a1bd56`.
- Only the metadata R implementation changes among shared parent400/429 frozen paths. Source SHA256 is `1f1eeaf7501a1c1c179a5899f24726b1504e2fafa2a0c69c6856469140cb3c5b`; new expansion-test SHA256 is `39e9f40cd65295ab482895ef41d51c997ca160d8b2d247a183845869314577e4`. Native DLL, budgets, protocol/schema and public formals are not changed by this correction.
- Retained431 codec53/53,433 affected-core5/5 and432 fresh whole original90000-cell saved269 certificate parity/source-purity gates were inspected, not repeated or relabeled as Meridian reruns. Numeric exits are0. The after-opening HWM238368KiB and unexplained2097200-byte `row_collapse_object` allocation remain explicitly bounded observations, not a lifecycle-memory pass or a zero-large-allocation claim.
- Candidate and audit `git diff --check` pass. Both independent diagnostic processes and the six-contract worker are terminal exit0; diagnostic exit0 means the expected error was captured, not that the candidate passed admission.

Frozen429 source is released **only for the identified duplicate-aware admission
correction** after the final83-file posthash. No acceptance is granted to any
outside-freeze prototype or next installed descendant. Original lifecycle90000
remains held pending separately closed exact-runtime reviews. No broad suite,
SIF, source edit, merge or push occurred. Only this historical audit report was
updated in the isolated audit worktree and remains uncommitted.
