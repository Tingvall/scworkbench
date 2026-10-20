# Trusted native-R source-and-selection observation

Status: reconciled design frozen for Controller adoption decision; no runtime adoption.
Controller approved a versioned observation DESIGN on2026-10-20. This document
does not claim implementation, protocol adoption, performance or final acceptance.
Forge consolidates the single specification; Sable and Quill supply review inputs.
Baseb0d5b9b73d7277b1435d4061b8f3e46ddbd03ee7 (runtimeee2cc8d); PyBenchf815def.
Evidence shorthand T=/tmp/scwb-engine-simplification-forge-20261018.
No official pack, standard profile or scientific parameter changes are proposed.

## Exact evidence change

New mode `trusted_r_source_selection_no_value_bytes_v1` records authenticated
origin plus the exact ordered requested feature/cell selection. It does NOT
hash or attest the numerical values actually returned by that read. Two valid
numeric blocks under the same source/selection can therefore have the same v2
observation. Reader behavior remains tested against independent numerical
references; those tests are not a substitute claim of per-block byte attestation.
Never label this observation `semantic_content_identity` or `content_verified`.

Actual source bytes remain fully authenticated at request issuance and before
publication. Existing before/after block guards, source binding, axes, numerical
domain, partition/coverage, complete output validation, atomic publication,
rollback, generation/checkpoint binding and recovery remain required. No
timestamp authority, hostile-code sandbox, universal cache or new executor.

## Closed version route

Canonical JSONv1 and all current v1 definitions/hashes remain unchanged. No new
top-level ABI/process version is introduced. Four closed nested v2 definitions
coexist with the frozen v1 alternatives in request/receipt schemasv3/v4.

| Node | Closed v2 representation | Self identity scope |
|---|---|---|
|`typed_slice_grant.v2`|v1 grant fields plus required constant observation_mode; source_kind must be bundle_matrix|`grant excluding grant_identity`|
|`typed_slice_result.v2`|v1 result minus semantic_content_identity, plus required mode|`slice result excluding slice_result_identity`|
|`observed_typed_slice_call.v2`|copy resultv2; replace schema, omit source_reference_identity, add call_identity|`call excluding call_identity`|
|`typed_slice_usage.v2`|v1 usage fields with v2 calls; no redundant mode field|`usage excluding usage_identity`|

All schema names have prefix `scworkbench.operation_pack.`. Each self-identity
scheme is its full v2 schema name; hash the complete node excluding ONLY its
own identity. Nested references retain the original unscoped scheme/sha256
projection where v1 used it. Own scoped slice_result_identity remains in call.
No extra observation hash object is introduced.

Result directly binds source-reference and grant identities, ordinal, exact
feature/cell order identities and counts, and dimensions. Grant binds the
authenticated source/input content and declared axes. Usage binds request,
capability, operation definition, grant and complete coverage. A detached result
is NOT independently request-specific: run binding is through its matching usage.
Grant cannot include the later request identity without an identity cycle.

Version is selected from the matching GRANT, including a zero-call usage.
Reject unknown/missing modes, v2 semantic_content_identity, v1 with mode fields,
unknown fields, mismatched grant/usage/call versions, cross-grant substitution
and post-execution downgrade. Different-version grants may coexist only with
exact per-index bijective usage and matching call versions.

## Execution eligibility versus retained verification

Only core can choose v2, before sealing the request. Requirements are a fully
verified symbolic bundle-matrix input, native R registration, and existing
private issuance matching original grant/input record, exact issuing connection,
bundle directory and ordered allowed axes. Backend string alone, a caller flag,
pack declaration or deserialized JSON cannot confer execution authority.

Implementation anchors in R/operation_pack_v3_transition.R:963-979 initial
actual-byte verification;1596-1609 private issuance;2022-2049 current-source
binding;3754-3872 actual native reader;3881-3933 usage;2951/3165 receipt/reopen
reconstruction. Existing owned primitive handoff remains guarded. Shared broker
result construction at R/operation_pack_typed_slice_broker.R:334 stays v1.
Uncertain eligibility selects v1 BEFORE issuance. An issued v2 request cannot
silently produce v1 calls or downgrade its already authenticated grant.

Persisted v2 records MUST remain verifiable after process replacement without
the ephemeral issuance attributes. Closed record verification, full recovery
source/output checks and existing durable stage ledger binding remain authority.
A deserialized record does not create a fresh reader. A resumed next operation
must issue a NEW private grant. Test this with an actual subprocess durable
create/run/checkpoint→replace→resume→continue→promote→finalize→read-only reopen.

Python mirrors schemas and independently reproduces canonical vector identities,
but has NO v2 execution capability. It must explicitly reject v2 grant/usage
before staging/mutation with OPERATION_PACK_PROTOCOL_INCOMPATIBLE even when
schema validation recognizes the shared v2 shape. Its broker/default execution
and historical v1 receipt handling remain unchanged.

## Validation hidden in the removed hash

Preserve actual dimensions and exact axis association before issuing resultv2.
Existing nonnegative_integer_v1 policy and its error precedence remain. The
matrix formatter skipped NA/NaN and signed zeros, rejected Inf, and enforced
its supported exponent range AFTER15-significant-digit rounding. A magnitude
cutoff at1e-307 is not equivalent: a neighboring smaller double can round up.
Reuse the same number() rule for rare boundary values or an equivalent old
validation fallback. Do not silently accept values previously rejected, reject
previously supported values, change numerical precision or suppress errors.
Domain validation is still an actual bounded pass, not claimed to be scan-free.

The source-fragment schedule, first post-MatrixMarket readback, newly written
output-fragment content identities, Python response bytes, models/graphs and
complete sibling/output closure are not eligible for this omission.

## Acceptance and measurement

Before code, retain complete v1 observations from the exact selected runtime for
actual normalization and feature-block read shapes. Budget complete new
observation construction INCLUDING remaining domain and axis checks, not only
the removed hash. Retain all existing whole/component budgets and failures.

Retained Xenopus receipts prove139 native block observations: norm7,HVG124,PCA8.
The147 overall semantic calls additionally include7 new output-fragment identities
and1 source schedule. The29.542/35.689-second inclusive total is an upper bound,
NOT an eligible-cost subtotal or promised saving. Do not prorate it by139/147.

Focused coverage must include:

- Exact cross-language v2 identities, nonlex ordered axes and two ordinals;
  retained v1 vectors; empty usage version and mixed-grant per-index matching.
- Unknown/missing mode, closed fields, mixed call versions, source/grant/request/
  capability/order/ordinal/dimension substitutions, including self-rehashed claims
  rejected by original binding rather than merely observing a changed digest.
- Native private issuance eligibility; no-private-authority execution rejection;
  Python/private-projection/broker exclusions; bounded reads and exact coverage.
- Exact old numeric accepted domain/diagnostics at boundaries, unsupported values,
  value policy, source mutation, zero residue on failure and successful retry.
- Deliberately equal v2 observation for different valid returned numerics under
  the same source/selection, with a corresponding changed v1 value identity.
- Independent aligned-reader science, historical v1 and subprocess v2 recovery,
  complete output/receipt closure, publication faults and recipient purity.

After shared/core stabilization, one coordinated frozen-candidate affected
qualification includes the full original Xenopus lifecycle at documented
defaults, numerical reference checks, timings/RSS/disk and verification counts.
Reviewers reuse its evidence and independently probe affected boundaries.
No merge, push, profile repin, scientific pack edit or image build is authorized.

## Frozen design inputs and lightweight checks

Forge fully read Sable trust/failure and design inputs and Quill protocol input.
Original Quill design-only digest vectors were NOT schema/runtime-validated;
Forge found scoped-reference and placeholder-scheme inconsistencies before
adoption. They remain draft evidence, not authoritative positive fixtures.
The suspected axis-descriptor field difference was NOT a defect: the original
`axis_manifest_identity` is correct, distinct from manifest_identity inside the
axis payload. Corrected vectors supersede only the draft identity table.

The committed [design vectors](trusted_r_slice_design_vectors.json) contain
complete synthetic preimages, not real authenticated runtime records. FileSHA:
`0a20aef5aa10640ff85f527e6d2d072eb32903a8ccca063e6caea266b214128d`.
Canonical parsed-object SHA, independently identical in pinned Python and R:
`308ad380e1e374ea1304ec8f5c6d78d7555edef42566045af72d94dc6cecd293`.

| Positive design node | Expected SHA256 |
|---|---|
|Grantv2|`a140e4923f86e37c72d193c68c2ff8e769b54d66320a60690c871bad57c7d3bc`|
|Result1|`bc5f29071102bbd255fb726c4853254c1b7d7b214b33c1c241eee190bb318a06`|
|Result2|`55ae30c3e31d520533c4fc97fa581264d90c13ff4ac32b3bbfc0cb000703446e`|
|Call1|`96be8f82faea14cf36d3c4009924832b9be8577df85aaaa2eeeef1a97bb426fc`|
|Call2|`82c5d549139418bf6ec94e38da242411dd75fdc1a9d3f62046f2d2ac256a5bd7`|
|Usagev2|`0e3787b253c6bf470614454d85241da06073e343cf23cfb7af772da814f704ee`|

Eight self-rehashed negative preimages are retained for reordered features,
changed ordinal, unknown mode, substituted source/grant/result, changed request,
changed capability and mixed-version usage. Changed digests alone are not proof
of runtime rejection; implementation must test each against original binding.

Quill corrected probe imported the canonical module from the exactf815def source
peer and returned0 in.579s; old unpinned and summary-selection draft outputs remain
separate. Main then ran T/check_trusted_slice_design_vectors.R against installed
ee2 DLL4a076ecaef560011eafe71310bfd68263ade8346e44ecbe87ac386f1dab6b178.
Actual gate trusted_slice_design_vectors_r.exit0:6 positive and8 negative self
hashes match, plus6 positive and2 negative closed-node shape checks using
IN-MEMORY prototype definitions. No shared schema file or runtime changed.
These are lightweight design checks, NOT actual v2 execution/rollback/recovery
qualification, nor proof that placeholder source identities authenticate bytes.

Reference input hashes (review inputs, not competing specifications):

- Sable final trust/failure ledger:
  `708d38800a337260001efb7fc68f8733f3fcb3835b4120179ab891ee1d370e84`.
- Quill correction annex:
  `d826ed39615aa6f5f0fbb9249fee7d5749b6aac9049c73c40cc348a0668c1a5c`.
- Corrected Python probe:
  `d16b1ec89b2402bd5c37982c546495cee36aaedceffef6d8654c16ac445d1ccf`.
- R design-check harness:
  `81e6054b158d42ce676184e19e204b4e5ae0f38ab4eb402debc21562f832d544`.
- R design-check log:
  `3d33287c98fb385780ab3b1cf19f7d450cdbbb7bfe8d37cbb70343b2ff56f402`.

Baseline shared schema files remain byte-unchanged at this design checkpoint:

| File | SHA256 |
|---|---|
|Requestv3|`81f5ef42a3cf35bd8ce92e410d65c4ed3193413d82ad0305fd2f3a2c678d3169`|
|Receiptv3|`492ee6fbdd5ef75f6d00130e0c54ff945b7da8ee1160f11d6234a30f905ceae5`|
|Requestv4|`e95e0dd7e86456edccc3b4097a9d10a9210d3371c64e3ce2e14159053d14bb1c`|
|Receiptv4|`9eb38dc446aa0791d16868660c10901ad5db933ed73ba6cdf03abfd34173aa2e`|

## Adoption boundary

The material change is precisely the omission of returned numerical-byte
attestation for the eligible native-R block observation. Source authentication,
exact alignment and output identities do not substitute for that omitted claim.
Existing v1 bundles are not migrated or rewritten; new code must retain v1
verification. New v2 records require a reader understanding this explicit version;
no promise of recognition by older core/Python execution is made.

Controller approved designing this change, not silent adoption of a new identity.
Freeze this reconciled contract for explicit adoption approval before editing
runtime/shared protocols. No performance-budget waiver or completed-engine
acceptance is implied. After adoption approval, measure/freeze the v1 parent
budget, implement only this scope, issue an immutable schema/fixture checkpoint
for Quill, qualify focused authority/rollback/recovery/parity boundaries and
finally run the one coordinated frozen-candidate workflow qualification.

## Final design-review disposition

Quill and Sable both fully reviewed exact design commit
8a35c4978fbe75926a38f71e24b29480ffd4a48e and returned DESIGN CLEAR, with no
additional guarantee reduction or conflicting specification. Neither disposition
is runtime, performance or whole-engine acceptance. This final status paragraph
adds the review record only; it changes no normative field or policy above.
Remaining Controller choice: adopt this explicit v2 omission and authorize its
implementation, or retain v1 returned-value observations. No runtime/protocol
implementation begins on the strength of design-only approval.
