# Native metadata encoder: actual results and next bounded experiment

Source `6875fa6b0f64df71b0bd701047963dd6ed2317c6`, parent budget
`c201b76`. `T` = `/tmp/scwb-engine-simplification-forge-20261018`.
This note is frozen BEFORE extending native row-name eligibility.

## Actual source and correctness evidence

Sable exact-source review cleared focused execution, not performance:
`/tmp/scwb-sable-native-manifest-source-6875fa6-20261019/review.json`,
SHA256 `7ea93ac93c3464ff2f6b93c418ce8f0b4f1cb6c6d677a0ca22aa1058733ff6a9`.
Clean Git-archive installation `T/manifest_native_json_6875fa6_install`:
six files, 19 discovered/executed/passed, zero skipped/failed/excluded;
eight numeric gates plus outer exit zero. Log SHA256
`a7329244ac05d4aa129ec165cb6507202f369226038e21890e4c07f92ccd4a88`;
actual DLL `55edce5e4370b220514910571cef3f11f6422caaefb12898913d9fc78c86da67`.
No warning entries were found in that focused log.

## Actual matched timing: original failure stays failed

`T/manifest_native_json_6875fa6_candidate_measurement` contains six fresh
plain trials, followed by a separate hook census. Sixteen of seventeen
numeric gates passed; fixed-budget comparison and outer exit one remain.
No retiming, summary substitution or threshold relaxation.

| Metric | Actual | Existing ceiling | Result |
| --- | ---: | ---: | --- |
| Large median seconds | 4.085 | 4.0509 | MISS |
| Maximum six-process RSS KiB | 197348 | 219665.6 | PASS |
| Tiny median seconds | .343 | .4204 | PASS |
| Prior large ceilings | 4.085 | 4.2516 / 4.42255 / 4.192 | PASS |
| Historical tiny seconds | .343 | .160 | MISS |

Large observations 4.110/4.027/4.085; tiny .343/.347/.337. The tighter
prior RSS219599.6 ceiling also passed. Full table identities, fingerprint,
source/installed bytes and pre/post filesystem inventories remained exact.
Fixed-result CSV SHA256
`56fcb0826eb5293e1746c00922c17617cc947134c04aa4abbb793240cab65216`;
six-trial CSV
`076af65fb488fd6e2d8bb95c13d64bbaccc4945c7b33db582ddf5343d2e790b8`.

Separate actual census: 76 native batches / 143312 rows / 13686877 encoded
bytes; 211 fallbacks. Every native buffer ledger fit the original allowance.
These are hook counts, not kernel I/O or full-source verification passes.

## Reproduced conservative fallback, not a performance conclusion

Read-only installed diagnostic `T/probe_manifest_native_rownames_6875fa6.R`
and its `.log`/`.exit` (zero) use an owned 5000-row synthetic dataframe.
Selecting its first3675 rows yields raw **positive** compact row names
`c(NA_integer_,3675L)` and native fallback. Selecting the remaining1325
yields ordinary explicit integer names and native success. Both column
representations are ordinary/non-ALTREP. This reproduces the census pattern;
it does not prove that every production fallback has this cause.
Probe source SHA256
`d747e10e52792fedaa65cf5ae0afd6f213b534a09279ee290034bfd9ca099a45`;
log `0f9ca3292e0886a65711f6c885f9bc1dace348b262dabad72047a72b42d303be`.

## Prospective limits BEFORE the next code edit

The next experiment may admit positive **and** negative compact row-name
counts exactly equal to the actual row count, without expanding them.
First prove literal old jsonlite bytes for both signs, ordinary numeric names,
reordered numeric names and numeric strings. Mismatched counts and all existing
unknown/ALTREP/classed/value/key exclusions remain rejected.
Use explicit `==nr || ==-nr`, never unchecked `abs(INT_MIN)`.
This changes private serializer eligibility only, not row order or any identity
scheme. Original5000 folds, backend gate, source observers and128N/Lt/B/8E
admission remain unchanged. Exact-source review precedes execution again.

New large-median ceiling: **.95*4.085 =3.88075 seconds** (at least5% gain).
RSS ceiling **219599.6 KiB** and tiny **.4204 seconds** remain unchanged.
Every earlier ceiling and MISS remains visible, including4.0509 and.160.
Use the identical six fresh plain-process scope and independent old oracles,
with a separate actual-native-hit census. No whole-engine selection or final
qualification follows from this source checkpoint.
