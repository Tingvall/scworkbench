# Native bounded metadata JSON: preimplementation experiment

Parent: `3a9c7d13a11a5f0fce94e136fa10fd164ae44a90`, the full-fetch-capacity
projection admission on f6 batching, with **no** rejected R ASCII serializer,
graph handoff, numeric memo or same-owner SQL reuse.

## Actual measurements retained, not retimed

`T` = `/tmp/scwb-engine-simplification-forge-20261018`.
Parent installed focused gate: `T/manifest_projection_admission_3a9c7d1_install`,
16/16 tests across five files, zero skipped/failed. Log SHA-256
`704f481729e34b7340d56707d4e9e321cfe5fe479567886144435cd01561dac3`;
DLL `094f91dfa0004c06c51906d73abebf7d9ef972537a12228d7fe327ea82a3740e`.

Matched parent six-process evidence:
`T/manifest_projection_admission_3a9c7d1_candidate_measurement`.
Large4.774/4.389/4.501 seconds, median**4.501**, missed4.2516. Maximum
RSS**199696 KiB** passed219599.6; tiny median**.364 seconds** passed.4457.
Fourteen of fifteen gates exited zero; fixed-budget comparison and outer exit
one remain. Separate census passed:122 coarse admissions, zero exact admissions
in this fixture,487202 actual decoded rows, every coarse reservation full5000.
Twenty-eight short reads retained the full requested capacity. Exact fallback
was exercised by focused tests, not invented as a production census hit.
All original fingerprints and filesystem inventories remained identical.
Fixed-result CSV SHA-256
`f3cea88c26633fbbe8daa02c24e72febd56691ac9ed68421bcddbfc9901b93d3`;
six plain observations CSV
`4cb94e3b686c80c41363947268b3ee9965cffd6c561a38ffa7eb51e6e50be6dc`.

These changes remain unselected pending the combined experiment. The rejected
R-vector ASCII serializer's actual5.901-second median is retained separately;
its149 successful batches/360490 rows prove it ran, not that it helped. Its
timing cause was not profiled, and no inferred explanation replaces that miss.

## Prospective numerical limits BEFORE native code

| Criterion | Frozen ceiling |
| --- | ---: |
| Complete large snapshot median seconds | .90*4.501 = **4.0509** |
| Maximum six-process peak RSS KiB | 1.10*199696 = **219665.6** |
| Complete tiny snapshot median seconds | 1.10*.364+.02 = **.4204** |

Use exactly the parent's six fresh-process, no-warm-snapshot scope and old
independent oracles. All earlier4.2516/219599.6/.4457,
4.42255/222657.6/.5128 and historical4.192/.160 ceilings remain visible and
unwaived. No budget revision hides a miss. Separate instrumentation and plain
timing; retain numeric failure exits. No whole-engine acceptance is implied.

## Proposed bounded specialization, not implemented yet

One internal native serializer may emit **the same** jsonlite row-array bytes
for already-admitted ordinary scalar batches: at most5000 rows/eight columns,
plain integer/logical/safe ASCII character values and ordinary numeric rownames.
REAL/int64/date/classed/attributed/deferred/nonASCII/escaped/unsupported values
must return to the existing jsonlite call. Copy the existing preencoded ASCII
field-key tokens in their existing order; do not use canonical graph numeric
formatting or introduce escaping. Integer decimal, logical lowercase and NA
null behavior must match the independent installed backend literally.

Unlike the rejected R-vector helper, native preflight and emission should use
constant workspace and **one bounded output buffer**, not per-value/row R
strings, list objects or growing arrays. Complete eligibility and exact extent
must be established before allocating that buffer. Buffer, result string,
substring and emitter raw copies must fit the same original8*encoded allowance;
the existing candidate128N and selected-dataframe reservations remain in force.
No quota, cache, source check, identity, schema or protocol change is proposed.

Use the existing package native-registration mechanism, no new dependency or
executor. Keep the specialization private, backend/version-gated, and confined
to the scalar JSON call initially; whole-small and all fallback paths remain.
Actual byte oracles, bounded allocation, unsupported/fault/cleanup/source
contracts and positive native-hit evidence are required before selection.
Sable precode and exact-source resource/identity review precede qualification.
