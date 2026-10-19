# Nonloading informational runtime provenance: literal affected results

Coordinator-reviewed results record for a documentation-only commit.
No runtime, test, schema, protocol, package or budget change accompanies this
note. No performance selection, readiness or whole-engine acceptance is claimed.

## Exact scope and checkpoints

The pre-code plan/budgets are in `NONLOADING_PROVENANCE_PLAN_AND_BUDGETS.md`
at2d26fd8cb520870b7a9790901ec8d43080d6f4fd. The Controller explicitly approved
the informational meaning change. Runtime/tests/docs checkpoint509c2c04933521b60eb8b1a053f1cf93803acdd7
changes only the runtime fingerprint to `scworkbench.runtime_attestation.v2`
and obtains BPCells version through the existing no-load installed-metadata
helper. The v2 field is NOT proof of package loadability, actual native image,
scientific execution or backend support. Per-run environment/pack/receipt fields
remain fresh; historical v1 records remain readable without rewriting.

Actual clean Git-derived installation is
fc4a0c56f83a1198ae33eaf9924eae1154ac88ea. Actual loaded DLL SHA256 is
`af4f0be00cd8464f2c6d58b0015ebc04f128bdbdaefbcbd66b01b9408326e12f`.
Test-only corrected source is b0c65edeb48975ae4b052a889de1b8735df7cc76;
its R/src diff from fc4 is EMPTY. All subsequent tests/measurements reuse the
same attested fc4 library: there was no second install or new runtime DLL.
Parent library is actual f1b61b0f2e1e32cd6c7edd5d8a773496097a13e2.

T below is `/tmp/scwb-engine-simplification-forge-20261018`.

## Installed qualification: original failure and distinct correction

| Actual cohort | Files / executed / passed / skipped / failed | Numeric result |
|---|---|---|
|`T/nonloading_fc4a0c5_install` original|3 /8 /7 /0 /1|focused1, supervisor1; all EXIT postguards0|
|`T/nonloading_b0c65ed_affected_one_retry`|1 /1 selected /1 /0 /0; declared4 in file|focused0, supervisor0, all postguards0|
|`T/nonloading_b0c65ed_corrected_eight`|3 /8 /8 /0 /0|focused0, supervisor0, all postguards0|

All cohorts have zero exclusions. The original failing test was
`test_engine_runtime_metadata_v1_readonly_checkpoint_certificate_contract`:
the owned historical fixture performed `UPDATE prov_runs` followed by
`wb_refresh_manifest(b)` on a committed bundle without a mutation context.
The engine correctly rejected: “Bundle manifest mutation cannot write directly
to a committed bundle.” The test-only correction wraps only this fixture
UPDATE+refresh in the existing declared ingestion context; finalization,
checkpoint preservation, v1 certificate/RO getters and exact file inventory
assertions remain unchanged. No mutation guard was relaxed.

The affected-one pass took7.190s; its log explicitly distinguishes DECLARED4
from SELECTED1. The corrected eight-test run is a separate full affected cohort,
not a relabeling of the failed first run. Four expanded warnings remain in its
raw output (dbDisconnect plus three deliberate incomplete-generation missing
session.json observations); do not claim warning-free qualification.

The new tests cover no-load metadata, owned unloadable/onLoad/loaded-versus-
installed fixtures, missing metadata and fresh environment/pack fields. Owned
loaded-version metadata updates BOTH DESCRIPTION and Meta/package.rds, while
the namespace retains its original version. No real dependency is modified.
Historical v1 evidence is an explicitly owned synthetic fixture, not a claim
that an actual old executed scientific receipt was generated or replayed.

## Complete metadata-only public lifecycle: elapsed MISS, RSS PASS

Evidence: `T/nonloading_b0c65ed_metadata_matched`. Plain order was
old1,new1,new2,old2,old3,new3, followed by two DIFFERENT separately timed
attribution-only census processes, excluded from performance medians/RSS
budgets. All eight case gates are0; scientific values/ordered cells,
checkpoint/receipt/provenance semantics, recipient checks and RO filesystem
purity passed. All source/installed/harness/dependency/qualification/worktree
postguards are0. Component-budget gate80 and supervisor are1:
`postguards.txt` is `original=1 postguards=0`.

| Plain trial | Parent elapsed s / RSS KiB | Candidate elapsed s / RSS KiB |
|---|---:|---:|
|1|10.348 /617560|7.370 /183304|
|2|10.589 /616796|7.470 /185460|
|3|10.584 /617012|7.450 /183456|

| Frozen criterion | Parent | Candidate | Ceiling | Result |
|---|---:|---:|---:|---|
|Complete public median, fixed seconds|10.584|7.450|7.3248|MISS by .1252|
|Complete public median, fresh70% seconds|10.584|7.450|7.4088|MISS by .0412|
|Maximum process RSS, fixed KiB|617560|185460|678669.2|PASS|
|Maximum process RSS, fresh110% KiB|617560|185460|679316|PASS|

The fixed elapsed/RSS ceilings derive from the BEFORE-code parent baseline
median10.464s and maximum616972KiB, not from these fresh parent samples.
Neither fixed nor fresh elapsed threshold is retuned. No unchanged retake.

The complete timer begins before core loading and includes metadata source
construction, durable session creation, core metadata operation/checkpoint,
close/reopen/resume, terminal promotion/receipt, finalization, RO artifact and
provenance reads, recipient validation/close. An additional symmetric RO audit
is outside the complete timer but inside process RSS. No matrix/space or
scientific pack is used. Real dependencies are unchanged; candidate plain and
census results prove BPCells was not loaded for this metadata-only workflow.
The metadata implementation still performs all original authority services.

Separate actual census schedules agree exactly across revisions, including:
13 `.wb_manifest_registry_snapshot`,5 `.wb_prov_runtime_fingerprint`,3
`.wb_session_checkpoint`,8 `.wb_refresh_manifest_committed`,1
`.wb_promote_analysis_locked`,7 `.wb_prov_payload_identity`,3
`.wb_prov_write_snapshot` and33 `.wb_prov_sha256_file` entries. These are helper
CALLS, not33 source scans or physical-I/O passes. Inclusive census timings are
not plain medians and are not added together.

## Independent mixed affected lifecycle: nonregression PASS

After the metadata elapsed MISS, root separately authorized this affected
matrix/space/ordinary mixed cohort. It was NOT automatic continuation or a
waiver. Scope authorization is preserved in
`T/NONLOADING_B0_MIXED_INDEPENDENT_RELEASE_SCOPE.md`.

Evidence: `T/nonloading_b0c65ed_mixed_matched`. All six fresh alternating plain
case gates, budget comparison and supervisor are0; all always-EXIT postguards0,
`postguards.txt` is `original=0 postguards=0`.

| Plain trial | Parent elapsed s / RSS KiB | Candidate elapsed s / RSS KiB |
|---|---:|---:|
|1|7.884 /623236|7.646 /661568|
|2|7.839 /622916|7.625 /661560|
|3|7.920 /622516|7.525 /660840|

| Criterion | Parent | Candidate | Ceiling | Result |
|---|---:|---:|---:|---|
|Complete public median, fixed seconds|7.884|7.625|8.2733|PASS|
|Complete public median, fresh110%+.02 seconds|7.884|7.625|8.6924|PASS|
|Maximum process RSS KiB|623236|661568|685559.6|PASS|

The unchanged frozen physical/scientific fixture is the corrected reference
`T/mixed_backend_reference_0a_scalar_shape_corrected`:300 cells/25 zero-count
features, BPCells counts, HDF5 latent space, continuous vector, family,
feature/observation tables, path and retained model. This is generic public
storage/promotion, not scientific dispatch. Timer includes cold core load,
source read/import, source read/primitive construction, atomic promotion,
finalize/close and RO source/output reads. Actual ordered values/types/metadata,
backend schemas and SQLite policies agree; symmetric extra RO full-FS proof
is outside the timer. BPCells is legitimately loaded for matrix IO here, unlike
the metadata-only case. Retained compression warnings are not erased.

The old independent direct reference median3.322s versus corrected0a engine
7.503s (overhead4.181s) is historical, not a freshly matched direct trial for
this parent/candidate cohort. It lacks engine authority/provenance services.
Original direct+2s remains unwaived; this nonregression pass does not establish
that budget or service-equivalent framework overhead.

## Evidence integrity and remaining limits

Every case is a fresh R process on the local serial host; no controlled
cold-filesystem-cache/hardware normalization is claimed. Process RSS includes
setup and verification. `/proc/self/io` fields describe logical/physical
counters separately and do not count all semantic scans. Plain runs have no
trace/namespace replacement; census traces are separate and restored. The
earlier three-case frozen baselines and all failed logs/harnesses/sidecars are
unchanged. Library/source/input maps are checked before and on EXIT even on
budget failure. Source/test branch stayed b0 throughout both matched cohorts.

Selected compact evidence hashes (all full logs/maps remain at the paths above):

- Original focused log: `e0d831ff152f0cfc4c3e1991a75a6179fbf373cc7c3fb50d2d0e68c5136ad786`.
- Affected-one log: `0b7aaa10497d2776230de4400d2e5f461e4ed2a002491cc2719b62b134ae44e1`.
- Corrected-eight log: `38d9d83cb22a637a6f01b764d5c210723c451a94340b145cbb88307533ff0c4d`.
- Metadata component_budgets.csv: `6bd5a7102ebde3fa7fb66371f74546a20e8fe2a31d97ec2cc11eb3643bfd67f9`.
- Metadata actual_census_invocation_counts.csv: `e41852ce89c6271d03a73e852a61e44fd8e9c5f2a9fd1a84aecd213d8ed1a07d`.
- Mixed component_budgets.csv: `25e31f462f4e25b4a018867307ec34a6f1859cba46437e3f5a54d73d9163af2d`.
- Mixed all_plain_samples.csv: `b6b4ac516257b18abf9b66c327d55904ca24fafadc9f9bacded64c75e643a66a`.

Disposition: affected correctness qualified, metadata elapsed criteria MISS,
mixed nonregression PASS. No performance selection or full-workflow gain is
inferred. Historical5s typed-space,171.124s full-Xenopus and graph/mixed direct
overhead misses remain unwaived. New fingerprint metadata meaning does not
upgrade historical/native/Python execution evidence or external-source coverage.
