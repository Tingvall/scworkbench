# Terminal measurement ledger: retained ba351 attempt, not acceptance

This documentation snapshot is based on `da03fb9` (the source correction of an
erroneous supplemental-reference premise), with measurements from installed
runtime `ba351cd24714d1d5238bd9f58ba66c4b135e1674` / source-and-test checkpoint
`8614e198a6337ac45c5ad4a0fc664ba8d5a95af7`. It does not claim the later graph
or nested-object encoder changes were measured. No jobs or source edits were
performed to assemble this ledger. The numerical thresholds below were declared
before their corresponding changes and have not been retuned.

Path keys in the adjacent [CSV](TERMINAL_MEASUREMENT_LEDGER.csv):

- `T` = `/tmp/scwb-engine-simplification-forge-20261018`.
- `F` = `T/final_ba351cd_measurements` (terminal supervisor FAILED09).
- `P` = `T/final_13de629_measurements` (older, explicitly scoped component reuse).
- Relative `notes/` paths are repository files. Raw CSVs, GNU-time records,
  logs and numeric exit sidecars remain authoritative; summaries do not replace
  failures. CSV `PASS` means the named component criterion only, not acceptance.
  `NOT_MEASURED`, `NOT_SET`, `INCOMPLETE` and `MISS` are not passes.

## Measured budgets and remaining misses

| Case | Before → ba351 seconds | Original numerical criterion | Result |
| --- | ---: | --- | --- |
| Canonical31,535 IDs / scalar-string list | .563→.019 / .523→.062 | ≥3× | PASS29.63× /8.44× |
| Canonical1,000 /5,000-row ordinary dataframe | .172→.005 / .891→.025 | ≥3× | PASS34.4× /35.64× |
| Numeric100,000 vector / scalar list / dataframe | .698→.056 / .571→.060 /1.543→.526 | ≥10× | PASS / MISS / MISS |
| Contiguous numeric follow-on vector / list | prior .086/.111→.056/.060 | ≤.6×prior+.01 | PASS / PASS; does not waive original10× list miss |
| Complete table hash100 /1,000 /5,000 rows | .086→.037 / .765→.169 /4.055→.724 | +≤.05s at100; ≥5× at1k/5k | PASS / MISS4.53× / PASS5.60× |
| Descriptors vector / vector-family / relation-family |1.627→.039 /3.574→.079 /3.529→.083 | ≥2× | PASS; exact descriptor hashes |
| Metadata-vector final operation at history0 /5 /15 |1.988/2.702/2.475→.364/.363/.399 | ≤1s overhead over .020s direct | PASS at these bounded histories |
| History15 growth | .364→.399 | ≤1.5×empty+.1=.646 | PASS; no large-history extrapolation |
| Mixed synthetic storage lifecycle |13.681→8.879; direct .443 | ≤2s extra | MISS8.436s extra |
| Synthetic1,000-cell import, profiled |34.594→10.875 | ≤17.3 | PASS |
| Its manifest inclusive sampled cost |15.41→4.99 | ≤4 | MISS; nested Rprof bucket |
| Its schema-status inclusive sampled cost |14.46→1.27 | ≤3 | PASS; nested FK/signature buckets not added |
|46 one-row registry-table snapshot median | .640→.282 | ≥4× /≤.160 | MISS2.27×; not an empty-only fixture |
| Snapshot new connections |46→1 observed DBI entries | ≤3 overall | PASS observed; native observer is a separately owned connection |
| Manifest publication witness | .0077 per check | ≤.1 | PASS100 checks |
| Graph lifecycle incl recipient validation |46.387→40.981; direct2.118 | ≤3s extra; ≥20% reduction | MISS38.863s extra /11.65% reduction |
| Relation-family +space-path-family lifecycle |23.451→13.499; direct .453 | ≤3s extra | MISS13.046s extra |
| Typed space13,199×50,8 /32 partitions |42.872/42.560→12.392/12.305 | ≤5s each | MISS / MISS |
| Typed space128×4,097,8 /32 partitions |5.072 /5.414 | ≤10s each | PASS |

The ordinary object-fold-only benchmark remains .037/.331/1.698s at100/1k/5k:
it deliberately times the original generic object hash, not the optimized
table-fold template. Do not advertise it as an improved fold algorithm. The
small `model_ref` descriptor is .003→.001s (timer-resolution sensitive), not a
model-tree or fitting benchmark. Owned block delivery means .0001s at both
512² and2,000² doubles, versus serialization .00665/.075s; the respective
.005/.010s goals pass. Recorded R allocation is zero for the owned route,
not proof of zero native allocations or zero total framework cost.

Canonical process peak RSS92,192→94,412KiB meets +10%. History608,788KiB and
mixed615,232KiB meet their1GiB fixture limits. Descriptor101,584KiB is one
process containing both algorithms: the independent +10% peak-RSS comparison
is NOT MEASURED. Typed realistic727,608KiB and wide734,880KiB meet their1GiB
process goals. Independent old-preimage oracle peaks338,476/295,212KiB belong
to different processes and must not be subtracted from engine peaks. Realistic
typed-space exit1 remains a budget miss despite exact semantic/envelope hashes;
wide exit0 is only its scoped gate. Actual source SHA passes are3/3 for8/32
partitions, down from6/6 in the older fixture: constant, not zero or engine-wide.

## Evidence coverage, including profiles and reused components

Every measured CSV family in F is represented in the adjacent ledger:
canonical baseline/candidate; descriptor; representative history; table identity;
mixed publication; numeric batch; snapshot/witness; graph before/after; remaining
families before/after; efficient/supplemental direct phases; partial Xenopus
phases and resource samples. The typed-space JSON/oracle and time records add
non-CSV measurements. Raw per-phase `rchar`, `wchar`, `read_bytes`, `write_bytes`
remain in those CSVs rather than being redefined as content-scan counters.

`F/representatives/profile_synthetic_import/by_total.csv` and `by_self.csv`
are a profiled10.875s import /10.60 sampled seconds, not another complete
workflow or independent timing replicate. Inclusive manifest4.99s, table
identity4.58s, build-manifest5.07s, dbSendQuery2.89s and jsonlite::toJSON1.80s
overlap; DO NOT sum them. Self leaders include lazyLoadDBfetch .62s,
result_create .50s and result_fetch .43s. Schema-status inclusive1.27s meets
its ≤3s target; nested FK .73s and actual-signature .29s are not added again.
Full raw profile function rows remain available for inspection, not discarded.

The older P writer/pager evidence is reused only for unchanged components:
`.wb_operation_pack_v3_atomic_matrix_market()` and its native writer/projector
bodies retain13de behavior; later numeric emitter additions in the same C file
are not a new writer benchmark. `R/graph_storage.R` has no13de→8614 diff.

- Paired250k-nonzero base writer57.419→.191s (300.62×), CSC51.058→.205s
  (249.06×): ≥5× passes, emitted bytes/digests equal; small added-overhead
  limit≤.05s passes. Additional peak-RSS≤128MiB remains NOT MEASURED; paired
  process maxima cannot isolate implementations.
- Default graph pager1,000pages: old1.386/1.409/1.410s, new1.903/1.871/1.890s.
  All three miss ≤1.2×old+.1s. This miss is not erased by a later graph change
  or by correct rows. Raw `P/pager/timings.csv` and `budget_comparison.csv` stay.
- The earlier schema-status probe (`baselines/evidence/schema_status_probe.csv`)
  is source-patch development, not a ba351 final remeasurement: repaired50 calls
  5.756s; warm source-patch50 calls .252s; explicit-full50 calls6.123s; cold
  source-patch .174s. Its source scope and bypass assertions remain separate.

Graph and remaining-family fixtures use matched values/ordered axes/metadata
and identical content identities, but public synthetic promotion, not scientific
operation dispatch. Graph content hash is
`78cee45a94f8afff71b511fc4467f805aec08f8c454088d4f52d93447ecc8c15`;
relation/path hashes are in their completion JSON. Direct storage omits
provenance/certificates, multi-output atomicity, recovery and recipient validation.
Graph uses different standalone SQLite metadata; family direct uses native
SQLite rows plus an extra lossless RDS copy and different source-space registry.
These lower-service references measure the full service gap, not purely
removable framework overhead. Backend/service mismatches remain disclosed.

## Xenopus: failed attempt and separately successful diagnosis

`F/logs/09_xenopus.exit` is **1**; process wall9:43.13, peak RSS4,990,472KiB.
The eight completed phase rows total576.408s: source declaration1.142,
preflight .564, fresh import73.125, durable session25.915, normalization110.361,
HVG209.818, PCA107.922 and UMAP47.561. This is not a completed import→recipient
workflow. Promotion, finalization, finalized read-only reopen and recipient
validation were not reached. No end-to-end latency, complete-workflow reduction,
successful final disk size or all-output recipient acceptance follows.

The original efficient independent workflow is one observed process85.48s,
peak RSS4,202,032KiB. Its18 explicit phase rows sum78.894s; startup and untimed
glue are not silently removed. It includes raw read/import, metadata/reduction
storage, scientific computation, BPCells/HDF5/SQLite/model writes and reopen
assertions. The predeclared end-to-end allowance is1.3×85.48+60=171.124s;
the failed partial engine already exceeds it, but this is NOT a final complete
workflow budget measurement. Original ≥25% improvement and≤baseline+10% RSS
goals lack a matched complete repaired-engine workflow: the historical33:59.96
pipeline excluded fresh import/recipient phases and cannot supply that denominator.

Direct phase arithmetic/read/write versus engine operation timing is not a
matched framework subtraction: direct normalization20.970, HVG8.874, PCA8.109
and UMAP11.768s exclude some separate direct storage phases; engine110.361,
209.818,107.922 and47.561s include authentication, receipts and staging.
Direct omits engine categorical sets, provenance, checkpoints, atomic promotion
and recipient validation. Direct and engine scientific parameters/backends are
unchanged; current runtime uses the normal256MiB guard, never a manual raise.

The last resource sample is577.872s: logical bundle/session bytes876,421,292,
allocated876,769,280,132files. It is a partial sampled footprint, NOT terminal
full-workflow disk use. Process RSS, allocated bytes and syscall I/O are distinct.
Traced source/semantic counters cover only the named functions, not all engine
I/O. The terminal partial census records26manifest calls/177.428 inclusive
seconds,147matrix semantic calls/67.834s,9matrix consumed-source calls/23.635s,
8session-source calls/12.605s and5checkpoints/3.641s. Those are nested function
observations, not disjoint elapsed components. Explicit source rows record
three counts boundaries and six normalized-matrix boundaries across two
consuming operations. The semantic-projection CSV records individual selected
shapes; these are not147whole-source passes. Explicit file hashing reports
5source checksum calls/365,874,915bytes and715provenance-file calls/
5,035,330,970bytes: neither is total filesystem or scientific-data I/O.
A selected-feature coverage pass is not a whole-source pass. Activated-pack and
thread CSVs are configuration evidence (thread environment variables unset),
not independent timing measurements. No untraced primitive receives a zero-scan claim.

The strict UMAP failure was against the **incorrect rounded supplemental**
reference:8.34949224539328 versus unchanged1e-6. Its104.19s process,
logs, values and exit statuses remain frozen. The supplemental builder itself
exited0 for constructing its declared variant; that does not make the variant
an input-matched engine comparator. [The source correction and Sable withdrawal](TRANSPORT_MATCHED_REFERENCE_PLAN.md)
preserve the mistaken preregistration rather than rewriting it as success.
Native R normalization directly writes full-double BPCells, not Matrix Market;
the supplemental driver alone inserted15-digit rounding.

Three owned read-only diagnoses remain distinct from qualification:

1. `T/pca_sign_diagnosis_ba351cd` found1,726,891 normalized selected-input
   differences against that rounded variant, max5.3290705182007514e-15,
  15 leading PCA sign flips; stage SHA inventory unchanged. Exit0 /33.75s.
2. `T/parser_boundary_ba351cd` disproved the proposed parser explanation:
  1,000 R/BPCells parses of both15-digit spellings agree; engine did not match
   the artificially rounded values. Hypothesis assertion exit1 is retained.
3. `T/unrounded_reference_ba351cd` / sibling logs: exit0,9.82s,687,332KiB;
   all1,000 sampled normalized values equal unrounded computation and all
  659,950 existing staged PCA plus26,398 existing UMAP values equal both
   original/efficient references BIT-IDENTICALLY. The two reference RDS hashes
   are `bb8a84d8cd68c494f7735509539d2b5362a2f257f511f05ca3cabdf4874ee5fb`.
   This reused already-produced outputs; no PCA/UMAP rerun, tolerance change,
   stage mutation or completed publication claim occurred. It diagnoses a
   comparator defect; it does not turn failed09 into a passing gate.

## Qualification state, not all-green

The original complete core suite remains files184/discovered382/executed382/
passed370/skipped3/failed9/excluded0/accounted382, exit1, atfff50517. Skips are
included in executed and are not passes. See [retained correction accounting](QUALIFICATION_CORRECTIONS.md).
The later selected main run was67executed/65passed/2fixture failures; two
corrected tests plus four additional shared tests yield71 distinct selected
passing tests, NOT a71-test clean full rerun. A separate prototype35-pass group
overlaps other groups and is not added to a fabricated total. Current452/199
is discovery of definitions/files only. Neither discovery nor source review is
complete runtime qualification.

PyBench peer0ef3c56f9d300e7813ac5a555e6d2ac7cb64a57e has retained
`T/quill/pybench_pytest_full.log/.exit`:751passed/7named skips/3warnings,
185.19s, exit0. Ruff check and Python-only formatting (`--exclude '*.md'`)
exit0,115Python files formatted. Global `ruff format --check .` exits1:
README.md, docs/graph_abi4_candidate.md and src/pybench/sdk_authoring.md have
unchanged Markdown-fence drift;122files already formatted. Coordinator
`T/python_final.exit=0` does NOT mean global formatting passed. Exact scope,
44shared protocol files and7skip dispositions remain in
`T/quill/python_final_disposition.json`. No claim that skipped golden/external
pack/beyond-RAM graph tests ran.

F protocol/generated-document/documentation-package/diff sidecars00–03 are0.
They are not a package-wide canonical pass or performance acceptance. Sable's
source acceptance is not numerical acceptance; her rounded-reference premise
endorsement was explicitly withdrawn. Broader final review remains pending.

## Still unmeasured or incomplete

No engine-wide performance acceptance: full fresh Xenopus lifecycle/recipient
gate and its complete disk/RSS/scan attribution remain incomplete in this record.
Large unrelated histories; beyond-RAM graph; nullable/sparse-family special
storage at scale; external adoption; recovery/process replacement performance;
mixed-primitive Python transport; Python bounded typed-space execution;
non-POSIX/non-native backends; legacy coordinate/RDS paths and all models are
not qualified by these timings. Ordinary complete-object authoring and guarded
legacy RDS remain materialized APIs. Native-HDF resource accounting does not
prove a hostile-file sandbox or universally bounded foreign producer metadata.
No GPU or historical cluster-hardware speedup is established. The original
eight-hour interrupted cluster attempt is unmatched hardware/runtime and is
not a valid matched denominator. Later candidate results must append their
exact pins and terminal evidence without relabeling any failure above.
