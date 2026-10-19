# Whole logical metadata chunk: preimplementation experiment

Parent `c3960db3f8d553b6f32fb6ffc2a9842233fb7cbf`. No code for this experiment
exists at this checkpoint. The in-flight combined graph worktree is untouched.

## Actual baseline, not retimed

`T` = `/tmp/scwb-engine-simplification-forge-20261018`.
`T/manifest_native_compact_c3960db_install`:20/20 focused contracts, six files,
zero skipped/failed, eight numeric gates plus outer zero. Log SHA256
`daa098e89cb0fa3639b5be1ca0ef11026928c33ab39834902b9b7598c08a0c71`;
DLL `d88ea8edc1244db8a7b2a1da7b512297061fb38dee875e127f0dd9a6ffbdbe86`.

Six fresh plain trials:
`T/manifest_native_compact_c3960db_candidate_measurement`.
Large3.574/3.534/3.542 seconds, median**3.542**; maxRSS**195964 KiB**;
tiny .329/.361/.354, median**.354**. All native/compact/projection/batch and
original large ceilings passed. The original tiny .160-second target MISSED:
comparison/outer exit1 remain, other sixteen gates and separate census zero.
All old46-table/487202-row identities and full source/SQL/FS byte guards pass.
Fixed-result CSV SHA256
`b67f33820bfc550350b8c4f12a07230cf32a9a38301c738e73cd9066fbf637d4`.
Actual separate census:149 successful native scalar batches,360490 rows,
33494389 bytes;138 fallbacks. These are not physical I/O/pass counts.

## Numerical budgets BEFORE source changes

Large median <=**.85*3.542 =3.0107 seconds** (15% improvement).
Max six-process RSS <=**219599.6 KiB**; tiny median <=**.4204 seconds**.
Retain every previous3.88075/4.0509/4.2516/4.42255/4.192 and corresponding
RSS/tiny ceiling, including the original .160 tiny MISS. Same six fresh plain
processes, no warm snapshot, old independent oracles, separate native-hit
census, literal numeric failures. No repeated timing to choose a winning run.

## Smallest proposed change

Keep the existing admitted whole-small-json path unchanged. Only when it
declines, and ONLY under the same owned manifest observation resources with
`wb_manifest_spill_boundaries`, consider one call to the EXISTING unchanged C
encoder for an entire logical chunk. ActualN<=5000/C<=8. Inspect ALL storage
kind rows before calling C: any `text_deferred`/`blob_deferred` must reject this
shortcut because their projected empty values are placeholders, not content.
No sparse scientific matrix, source fragment or large payload is materialized.

Reserve `B=4096+576C`, `Lt=16C+32`, and the original conservative128N scratch.
Carrier=`B+N*(Lt+128)`. Before any output allocation derive
`Ecap=min(token_bytes,floor((8P-carrier)/8))`; decline nonpositive/nonfinite
or inadmissible capacities. Original fetched-carrier/cache/8P/fixed aggregate
admission remains. Thus carrier+8Ecap<=8P, not a raised quota.

C independently validates ALL actual values/key/type/row-name eligibility and
counts exact extent BEFORE allocating. Its unchanged checks require exactE<=
Ecap and6*(exactE+1)+256<=8Ecap. On success hash the FULL identical `[rows]`
string directly; clear it afterward. On NULL use the original scalar streaming
path unchanged. Keep actual-byte/token checks, source observer finish, previous/
rows_sha256 framing and logical5000 folds. No alternate identity scheme, cache,
reader authority or public contract is introduced.

Bypassing the token emitter must not bypass resource authority: retain owned
resource initial/final aggregate FD/scratch admissions and observer completion.
The native path opens no FD or spill file. Test quota faults and cleanup/retry,
deferred placeholders, unsupported values, exact boundary folds and graph-wire
partition independence. Preserve explicit scalar-fallback coverage using a
noneligible REAL column where necessary rather than deleting its assertions.
Successful native hooks must distinguish whole and scalar scope and expose the
actual existing reservation ledger; old instrumentation is not relabelled.

Sable precode review finds the resource approach feasible subject to these
deferred-field, owned-observer and lifecycle requirements. Exact-source review
must precede installation. No runtime correctness, hit rate, improvement,
combined graph result or engine-wide acceptance follows from this plan.
