# Phase 3A Statistics Amendment 01 — scworkbench report

## Revision boundary

- Rejected parent: `8646fb9191589512ded04c345751f0a5a2622e90`
- Corrected implementation descendant: `a94f3ac2bb07b18e2645bde2960eb63613ae99eb`
- Read-only PyBench authority: `0cf2b4329b3393a9836d07c76558bb86aeb45cb3`
- Companion `scwbStatistics` implementation: `2e3da682198e7e993fd66024cfb106ff05135f06`

The implementation commit changes `R/operation_pack_migrations.R`,
`R/operation_pack_v2_transition.R`, `R/operation_packs_v2.R`, `README.md`,
`docs/operation_pack_v2_protocol.md`, the ABI v2 schema and identity fixture,
the contract runner, and focused operation-pack contract tests. The closure
commit also records this report and aligns the late-admission rollback test
with a manifest-semantic failure.

## Contract correction

The authenticated ABI v2 definition now optionally owns its public interface,
generic parameter bindings, closed output-dimension policies, chunk contract,
and retained-parameter projections. All fields participate in canonical
definition identity and are validated before catalog or handler mutation.
Core no longer selects statistics semantics by namespace or qualified
operation name. Its only remaining historical-name map produces the private
`OPERATION_PACK_REQUIRED` diagnostic.

Dynamic terminal-table dimensions require the closed
`data_dependent_table_v1` policy on a compatible admitted output. Chunk
declarations bind an admitted matrix input, feature sequence parameter,
integer size parameter, terminal table output, and closed global merge rule.
Observed typed-reader calls—not arithmetic inferred from requested size—are
retained and checked before publication.

The shared ABI v2 schema changed, so this is an R-side checkpoint and must stop
for Quill protocol synchronization:

- old `operation-pack-v2.schema.json`: `8343f8ea40ce3cc57027b0810c4d05b4df00196edd544361d15dc1fd59fe96aa`
- new `operation-pack-v2.schema.json`: `d6756c057704820f2b6f1069035546a85fa2cbf504885f519bfe4535550f727c`
- transition request schema: `81bf35b2827778f149aee3e3ca2e921332f22415a290b5e9c704af37b7e1aed2`
- transition receipt schema: `2cd5e6192daa799bd4562dd1f0d4761eb1a7e8847ff048b3880783a0db0fba1b`

## Executable evidence

Evidence is retained under
`coordination/evidence/2026-09-15_phase3a_statistics_amendment01/`.

- Focused core: 6 files, 21 discovered/executed/passed, 0 skipped/failed.
- Canonical core: 170 files, 240 discovered/executed/accounted, 231 passed,
  9 named skips, 0 failures.
- ABI v2 protocol focus: 11/11 passed.
- Comparator: 6 field-level interfaces and 9 execution cases passed.
- Catalogs: 53 core operations before pack activation; 59 after activation.
- Historical read-only inspection: 2 bundles, 11 runs, 20 outputs; RC37 and
  RC38 fingerprints remained unchanged.
- Core `R CMD check --no-manual`: `Status: OK`.
- Both source-build memberships and extracted trees were deterministic after
  removal of only generated `Packaged:` metadata.
- Generated-document, syntax, JSON/CSV, link, installed-package content,
  offline-install, and logger negative-self-test gates passed.

The canonical skips are the two unconfigured installed ABI v1 Python fixtures
and seven Phase 2C composite Python fixtures. They are not counted as passes;
Quill must synchronize and qualify Python parity for the changed shared ABI.

## Identity reconciliation

- Core catalog: `1f5ac0500da5bfef292ddd877a1f5ba60583d9008177a617e069d00d8f8bbca4`
- Activated catalog: `6fa9b1eaf474b47e3ade891ffd8f571262d5cd87b5a35ef609f1a47f864c6c4d`
- Manifest source: `14b4610595e255f199c58748e387981b294825a145a3ffffa2e0c5e309c175ad`
- Manifest: `96f4fbe8f12d1842e7d57da142fb4942dd5b023cce02b7f1f5f9bbc90e26d0cb`
- Installed distribution: `d5f05fdd0ae14192d504834ffefc9788c9d43a1bdb96d01603bab70644ee3337`
- Entry point: `fc66ea2a37b421f4e04836745be756a3c4d77785e73c72d44d68b537c1cfa06c`
- Installed pack: `715a7c07d12459e0f0c8246aecbcd5b9a318c7dee3d7ead256c2cbbb8cf9b30c`

The six definition identities, raw logs, atomic exit sidecars, exact commands,
and evidence hashes are recorded in the coordination evidence ledger and final
handoff.

## Composite qualification addendum

Quill synchronized the shared ABI v2 protocol and added authenticated Python
chunk-reader observations in PyBench commit
`11232d000ee42aa1344c9d6fb25a73acb1d88fe2`.  Core integration commit
`3fada7831383406348f2393a9342c25b13011333` copies the accepted Python runtime
sidecar schema byte-for-byte, pins that PyBench revision, independently
validates every observation binding, and projects the validated observation
into the existing durable `params$chunking` contract.  The shared transition
receipt remains unchanged.

The R-side audit requires an observation exactly when the authenticated
operation declares chunking.  It verifies the observation self-identity plus
request, execution-capability, operation-definition, input-descriptor, input,
axis, sequence-parameter, size-parameter, requested-size, call-count, exact
ordered batches, and batch-size bindings.  Missing, smuggled, substituted, or
reordered observations fail in the receipt phase before transition
publication.  Fault-injection tests assert identical registry and filesystem
preimages and no pending transition residue after each rejection.

Composite protocol identities are:

- operation-pack v2 schema:
  `d6756c057704820f2b6f1069035546a85fa2cbf504885f519bfe4535550f727c`
- transition request schema:
  `81bf35b2827778f149aee3e3ca2e921332f22415a290b5e9c704af37b7e1aed2`
- transition receipt schema:
  `2cd5e6192daa799bd4562dd1f0d4761eb1a7e8847ff048b3880783a0db0fba1b`
- operation-pack v2 identity fixture:
  `2bbb704a50c9c3fbed15c305e1767b953520df8a471613b493ba7f3f4b27925d`
- canonical JSON case corpus:
  `6c3da09b7840be621aae02e2bc17ac38435124992864da50e4c06819829e5d0c`
- Python runtime sidecar schema:
  `59fbaf6456d010bf777323e113ea0e36f94c5b41e75657148ae8cd0aeb9b0b7d`

All six files compare byte-for-byte with the accepted PyBench worktree.  Final
qualification results were:

- focused Python composite contracts: 1 file, 8 discovered/executed/passed,
  0 skipped/failed;
- complete scworkbench suite: 170 files, 241 discovered/executed/accounted,
  239 passed, 2 named ABI v1 fixture skips, 0 failed;
- fullstack: metadata, golden bundle, KG export, engine smoke, generated
  catalogs, payload parity, and 254/254 PyBench tests passed;
- core and `scwbStatistics` `R CMD check --no-manual`: exact `Status: OK`;
- clean extracted install: 53 core operations and 59 after pack activation,
  followed by all pack contracts;
- generated-document drift, protocol/fixture byte comparison, source-package
  membership/tree reproducibility, and final diff checks passed.

The evidence directory retains the complete successful logs and atomic status
sidecars.  It also retains failed development diagnostics: early focused test
assumptions, an incorrect protocol filename, and an initial clean-library
command that hid the dependency library.  Each was corrected by the named
retry; no failed diagnostic is represented as acceptance evidence.
