# Completed76 workflow and bounded follow-up attribution

This is evidence reconciliation, **not performance acceptance or a final handoff**.
Core source0bf95bc13deb43b411997dae8404c8e59121ea19 uses installed runtime
76e217a1342ade29b427bbbcba03e595861d474d; PyBench peer remains
0ef3c56f9d300e7813ac5a555e6d2ac7cb64a57e. Later getter changes are not measured
by this record. `T` means `/tmp/scwb-engine-simplification-forge-20261018`;
`F` means `T/final_76e217a_measurements`.

## Completed full workflow, with a large retained budget miss

`F/logs/06_xenopus.exit=0`: fresh source-aware import → normalization → HVG →
PCA → UMAP → promotion → finalization → read-only reopen → persisted inspection
→ recipient validation completed. Original scientific settings/default256MiB
guard were unchanged. All original exact/tolerance comparisons passed; no
conditional scientific rerun or relaxed UMAP criterion substituted for the gate.
The separate final raw-alignment gate passed104blocks with full ordered axes,
values and named sums and unchanged filesystem SHA inventory, as recorded by
its own log/sidecar. The ba351 failed supplemental-reference attempt remains
failed and separate; see TRANSPORT_MATCHED_REFERENCE_PLAN.md.

Whole process wall **1095.94s**, GNU peak RSS **4,753,600KiB**. The independently
measured complete direct reference was85.48s, peak4,202,032KiB. This is12.821×
elapsed /1010.46s extra, versus the unchanged1.3×direct+60=171.124s target:
**MISS by924.816s**. Direct includes source read/import, calculation, all large
writes and reopen, but omits categorical registries, provenance, recovery,
atomic publication and recipient validation. The difference is not all removable
framework cost. There is no matched full repaired-engine import-to-recipient
baseline for the separate≥25%/RSS+10% goals; an older33:59.96 pipeline and an
interrupted cluster allocation cannot supply that denominator.

Raw phase CSV sums1089.077s; do not delete startup/untimed glue from the1095.94s
process denominator. Important measured phases: import73.178; durable session
25.960; normalization113.183; HVG166.124; PCA102.146; UMAP53.975; scientific
comparison319.290; promotion94.790; finalization11.987; reopen4.673; persisted
inspection55.461; recipient wrapper66.481s. Exact CPU and syscall-I/O rows remain
in `F/xenopus/timings.csv`, not inferred from profiler percentages.

Recipient report `F/xenopus/recipient_report.rds`: `ok=TRUE`,
`status=ok_with_warnings`, **five EXTERNAL_SOURCE_UNVERIFIABLE warnings**,
all `source_inputs`/`external_source`. Observed: “external path deliberately not
accessed”; message: “External source is outside the recipient trust boundary and
was not inspected.” No other diagnostic codes and zero skipped checks.
All29content-coverage rows are content_verified. Report elapsed65.8769s differs
from the66.481s enclosing phase. Pre/post fingerprint is the identical
`0d9d30de87b287faae7104c69f4fa082545e195f12d4f3a5240e6da26cb5b51b`.
This is not a claim that recipient validation accessed the external source.

## Disk, I/O and verification census

`F/xenopus_resources.csv` samples the owned workflow and R temporary roots,
without following symlinks and deduplicating regular-file device/inode pairs.

- Initial sample:0logical/allocated bytes,0files.
- Sampled maximum:1,729,244,642logical /1,729,343,488allocated bytes at120.535s;
  maximum238files occurred separately. Five-second samples are lower bounds
  on transient peaks, not proof of a hard maximum.
- Last sample at1090.686s:1,471,620,163logical /1,472,237,568allocated bytes,
  237files. It is a late sample, not the post-process terminal footprint.
- After process cleanup, read-only `find`/device-inode accounting over the SAME
  roots:1,439,896,867logical /1,440,505,856allocated bytes,233regular files.
  Temporary-file cleanup explains why this differs from the last sample.
  Ordinary `du` also counts directory blocks and therefore is not interchangeable.

Phase syscall sums: rchar31,639,545,903; wchar13,322,261,486; kernel read_bytes
346,910,720; write_bytes12,647,743,488. These are not scientific payload-scan
bytes. `F/xenopus/trace_census.csv` records named helpers only:

| Helper | Calls | Inclusive seconds | Explicitly traced file bytes |
| --- | ---: | ---: | ---: |
| source SHA |5|2.791|365,874,915|
| provenance file SHA |1393|76.490|9,905,490,916|
| manifest registry snapshot |29|218.044|not measured|
| matrix consumed-source identity |9|23.903|not measured|
| matrix semantic stream |147|69.906|not measured|
| matrix reader preparation |4|2.903|not measured|
| session checkpoints |6|5.868|not measured|

Do not sum nested inclusive buckets or call this complete I/O census. The9source
rows are3counts boundaries plus6normalized-matrix boundaries across two consuming
operations. Shapes/source inspection explain the147semantic observations as
1complete counts projection +14normalized output-part projections (two complete
output coverages) +124HVG chunks (one full feature coverage) +8PCA chunks
(2,000selected features only). This classification is source-inferred from
`semantic_projection_shapes.csv`, not147whole-source scans. Public104-block
verification does not use the optimized reader; no zero-scan claim follows
for untraced paths. The original source RDS checksum was independently fixed
at7dfefc974d9b38ea3513c1e181f119f2c4cbde5fcf603298f71953bff7b85280.

## One public128-cell getter probe

`T/public_slice128_attribution76.logs_v2/run.exit=0`. Original finalized source
opened read-only; full source SHA inventory unchanged;31535×128values exactly
equal the independently stored full-double reference, with exact dimnames and
the normal256MiB guard. One slice took2.920s (2.842user); sampled2.91s:

- `[<-`2.33inclusive (80.07%);
- `replCmat4`2.04self (70.10%),2.06inclusive;
- `asMethod` .27self; `unique.default` .22self; JSONparse_string .13self.

The dominant cost is sparse replacement in `R/getters_matrices.R`:
`out[rr,cc] <- as.matrix(block)`, not whole-payload verification. Public
`wb_slice` additionally fetches whole fragment metadata three times and decodes
every feature axis before cell intersection, but those source facts must not
be substituted for the measured dominant cost. This is one profiled slice,
not a104-call improvement measurement. The initial driver argument-count typo
failed before source open; its original `logs/run.exit=1` remains preserved.

## One HVG diagnostic on an owned clone

`T/hvg_retained76_attribution_v2.logs/run.exit=0`; whole diagnostic276.98s,
peak911,792KiB. Original source was read-only and its full pre/post SHA inventory
is unchanged. Only a new owned physical clone and ephemeral session were writable;
no promotion. Public HVG settings were exactly matrix RNA_log_norm/all cells,
2,000features/vst/chunk256/seed1. Source has four committed prior runs versus
the original pre-HVG source's one: **not a matched166.124s phase/budget trial**.

Separately measured setup: sourceROinspection4.903s, owned copy .927s, writable
clone open/recovery29.625s. Rprof .01 covered only public session execution:
218.654s elapsed/211.481user/5.933system;218.26sampled seconds. The retained
raw `by_total.csv` and `by_self.csv` show:

| Function | Inclusive sampled seconds | Self seconds |
| --- | ---: | ---: |
| .rna_feature_stats |126.00|0|
| reader |117.39|6.56|
| plan$read |70.41|1.02|
| sparse replacement `[<-` |64.40|.03|
| replCmat4 |64.21|63.86|
| manifest registry snapshot |61.86|0|
| graph token hash (manifest emitter) |51.79|.02|
| chunk receipt construction |30.16|0|
| matrix semantic stream |26.57|16.26|

These are overlapping call stacks, not additional elapsed phases. Arithmetic
inside feature statistics excluding child reader is about8.61sampled seconds
(126.00−117.39), not the original heuristic25.43s bucket. The first disjoint
classifier missed anonymous callbacks named `reader`; its CSV remains and a
documented corrected `disjoint_stack_buckets_v2.csv` was produced from the SAME
completed profile, not another run:

| Disjoint heuristic bucket | Sampled seconds |
| --- | ---: |
| reader/guard after prior exclusions |87.27|
| metadata/staging/publication |63.70|
| actual chunk receipt identity |30.16|
| retained record reopen and children |11.46|
| source matrix authority |8.64|
| feature statistics excluding reader |8.61|
| registry snapshot construction/authentication |4.79|
| other preparation/dispatch/runner |3.22|
| output validation/writing/receipt |.41|

The earlier clone-inventory assertion failed before dispatch because dataframe
row names contained different absolute source/clone roots. Its source pre/post
SHA check passed; the failed log remains. Normalizing those nonsemantic dataframe
row names fixed the harness only. No runtime/library/scientific source changed.

## Smallest source-directed follow-ups, not implemented by this probe

1. Public getter: avoid dense replacement when a selected sparse block can
   satisfy the current fragment's full requested output; continue later fragments
   so overlap precedence remains. Preserve duplicate/empty/reordered selections,
   zero/NA modes and current coverage diagnostics.
2. Shared selected reader: the same replacement dominates its multi-fragment
   assembly. For proven complete requested feature axes and disjoint column
   coverage, use bounded sparse concatenation/scatter once; retain a generic
   fallback for partial/overlapping layouts and the existing resource ledger.
   No operation-name branch or scientific change is justified.
3. Manifest emitter61.86inclusive seconds remains material after replacement
   is removed. Further work needs its own scoped profile/budget before changing
   serializer/admission logic; no authority checks were waived by these probes.

The measured problem is allocation/assembly and redundant representation work,
not arbitrary hostile-code defense. No cache, new identity scheme, parameter
change or weakened source/receipt/publication guarantee was introduced here.
