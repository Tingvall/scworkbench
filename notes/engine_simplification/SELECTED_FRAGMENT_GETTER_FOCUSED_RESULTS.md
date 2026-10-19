# Approved selected-fragment getter: focused measured result

Tested clean source: `0a133a6ff3cf3764862dddd2479294ab98a99944`.
Runtime/tests are exactly the source reviewed at
`226f7c71631c2b648caae41563f98d56e0b72de8`; the child records ownership.
This is component evidence, not a completed engine-wide handoff or a claim
that the earlier full-workflow performance budgets pass.

## Actual execution

Evidence root: `/tmp/scwb-engine-simplification-forge-20261018` (T).
Detached, numeric-sidecar supervisors, one runtime lane:

1. `env SCWB_SELECTED_FRAGMENT_FOCUS_RELEASE=YES bash
   T/install_focus_selected_fragment_candidate.sh WORKTREE COMMIT
   T/selected_fragment_0a133a6_installed`: supervisor/install/focused exit **0**.
   Actual lexical discovery: **12 executed, 12 passed, 0 skipped, 0 failed,
   0 excluded**, three files. Includes the three new selected-fragment tests,
   three existing public sparse-getter tests and six matrix-streaming tests.
2. `env SCWB_SELECTED_FRAGMENT_MATCHED_RELEASE=YES bash
   T/run_selected_fragment_candidate_matched.sh WORKTREE COMMIT
   T/selected_fragment_0a133a6_installed
   T/selected_fragment_0a133a6_matched`: supervisor and every child gate exit
   **0**. Six fresh processes alternate old1/new1/new2/old2/old3/new3.

Here WORKTREE is the dedicated `matrix-getter-selected-fragments-forge-20261019`
worktree and COMMIT is the exact tested source above. Scripts, full commands,
logs, discovery/results and atomic numeric sidecars are retained at T.

Plain four-read medians, identical owned source, all31,535 features and the
first512 cells in128-cell reads, default256MiB dense guard:

| Metric | Parent | Selected candidate | Preset ceiling | Result |
| --- | ---: | ---: | ---: | --- |
| RNA_log_norm reads, seconds | 1.074 | 0.623 | 0.7618 | pass |
| One-fragment counts reads, seconds | 2.756 | 2.597 | 3.0416 | pass |
| Maximum process RSS, KiB | 1,519,316 | 1,497,916 | 1,671,247.6 | pass |

Normalized reads improve42.0% in this bounded public-getter case. RSS includes
the same independent original-RDS verification outside the read timers.
The process is fresh, not a controlled cold-filesystem-cache trial; the host
is nonexclusive. These are not operation-runner or complete-workflow timings.

Every process independently verifies exact ordered axes, actual raw counts,
CP10k/log1p values (absolute tolerance1e-14), unchanged semantic identities and
the full owned source filesystem inventory. No profiling/tracing/namespace
replacement is used in the plain timers. Identity checks and inventory hashing
are outside those timers. Counts identity remains
`516e4a9f0f76b9c15901c372f080c7bcd0d60ee25d7e0c5c6b5faac4fdff7784`;
normalized identity remains
`7196515b475778c0b3d9d6edbadec77af1f8bced570f55d3bac99608a9acf71b`.

## Retained evidence hashes

- Installed DLL:
  `e45513060769918ee84f3a32aa44beb9b3944df20d3bfee54a33c4d3f2c0d374`.
- `selected_fragment_0a133a6_installed/focused_results/actual_results.csv`:
  `7fe65362e446261c05d04ed24da7e8be7712c743ea88e4874526e01bcd7d4556`.
- `selected_fragment_0a133a6_matched/budgets.csv`:
  `0c7ad4f42d879b845bbbb34b7ac05884de0bd22c59a5fe02a15e992c684682d6`.
- `selected_fragment_0a133a6_matched_supervisor.log`:
  `dfb9ec8f5c182a2b17c4e4e2062bcc16ad8a8200cfb1e6319fd1a9dd19adc6d0`.

## Scope and parity

The Controller-approved error-boundary change applies only to ordinary matrix
getters: cell-disjoint fragments no longer require parsing their feature JSON.
Selected feature corruption and undecodable cell axes still reject. Explicit
content and recipient validation continue inspecting every fragment. The new
tests verify both validators report unselected corruption, with complete
finalized/read-only filesystem fingerprints unchanged. No cache or identity
scheme was added and no validator was weakened.

Quill's source review of PyBench peer
`0ef3c56f9d300e7813ac5a555e6d2ac7cb64a57e` found no corresponding fragment-JSON
validation to reorder: `getters.py:252-315` obtains ordered axes from the
features/cells registries and passes selected rows/column chunks to
`tools/read_matrix_chunk.py:29-56`; it does not interpret R matrix_fragments
feature/cell JSON. A virtual fragmented R matrix need not be a Python-readable
matrix directory. No Python behavior, protocol, schema, test or runtime change
is claimed or required for this R-only validation-order change.

Independent selected-boundary runtime review and the committed-revision
generated-document check are pending. Earlier full-core results remain
590 executed/586 passed/3 named skips/1 failed WAL-fixture assertion, followed
by a separately passing correction; they are not relabeled as an all-green
suite. Earlier whole-workflow and other budget misses remain unwaived.
