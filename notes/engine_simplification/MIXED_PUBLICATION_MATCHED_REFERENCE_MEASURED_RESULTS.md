# Mixed publication: measured reference disposition

NOT ACCEPTED: the prospective complete-workflow overhead budget failed.
Source-only reconciliation of Root's retained execution;no new runtime job,
code change or commit was made while preparing these measurements. Root has
reviewed this record;the failed performance budget remains unaccepted.

Task root T is `/tmp/scwb-engine-simplification-forge-20261018`.
Runtime is the SAME selected installed scworkbench
`0a133a6ff3cf3764862dddd2479294ab98a99944` in
`T/selected_fragment_0a133a6_installed`,not the combined candidate and not the
unselected space-envelope optimization. Corrected actual evidence is
`T/mixed_backend_reference_0a_scalar_shape_corrected` (E below).

## Literal disposition and measurements

All six fresh child cases exited0. All original/source/library/harness/fixture
pre/post guards exited0. Budget gate80 exited1 and the detached supervisor
exited1. No scientific/backend/purity failure was suppressed. Case order was
direct1,engine1,engine2,direct2,direct3,engine3. The two absolute requirements
were frozen BEFORE this cohort: medianengine-minus-mediandirect <=2.000s and
EVERY whole-process peakRSS <=786432KiB (768MiB). No ratio budget was substituted.

Times below are seconds,rounded to the recorded millisecond resolution;source
CSVs retain unrounded binary-print decimals. RSS is GNU whole-process KiB.

| Case | Cold load | Source read/import | Source read/compute | Outputs/publication | Finalize | RO source/outputs | COMPLETE | Peak RSS KiB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| direct1 | 2.895 | 0.158 | 0.001 | 0.074 | 0.053 | 0.142 | 3.331 | 461148 |
| direct2 | 2.772 | 0.150 | 0.001 | 0.070 | 0.051 | 0.136 | 3.188 | 461268 |
| direct3 | 2.892 | 0.157 | 0.001 | 0.071 | 0.052 | 0.140 | 3.322 | 460880 |
| engine1 | 0.013 | 6.029 | 0.001 | 0.995 | 0.396 | 0.339 | 7.799 | 632084 |
| engine2 | 0.011 | 5.827 | 0.001 | 0.909 | 0.388 | 0.326 | 7.487 | 632568 |
| engine3 | 0.011 | 5.755 | 0.001 | 0.940 | 0.404 | 0.363 | 7.503 | 632480 |

Direct COMPLETE median3.322s;engine median7.503s;extra4.181s >2.000s: MISS.
Maximum directRSS461268KiB and engineRSS632568KiB both satisfy786432KiB.
COMPLETE includes required cold library/backend loading,input/oracle reads,
both source-backend writes,scientific construction,all six outputs,publication,
finalization and actual read-only source/output reload and checks. Plain cases
contain no tracing/profiling/namespace replacement. Additional full-filesystem
RO purity checks are outside COMPLETE but included in whole-process RSS.

Process IO counters around COMPLETE (bytes,not inferred physical full passes):

| Case | rchar | wchar | read_bytes | write_bytes |
| --- | ---: | ---: | ---: | ---: |
| direct1 | 20995819 | 434278 | 0 | 516096 |
| direct2 | 20995819 | 434278 | 0 | 516096 |
| direct3 | 20995819 | 434278 | 0 | 516096 |
| engine1 | 34688469 | 4811191 | 4096 | 5021696 |
| engine2 | 34688466 | 4811191 | 0 | 4993024 |
| engine3 | 34688466 | 4811191 | 0 | 4993024 |

read_bytes near zero is consistent with page-cache service,not no input reads.
This cohort records no peak temporary-disk or full-source scan census. It is
not a Xenopus baseline or full-engine performance qualification. Host evidence
is E/logs/06_host_policy.log:Intel i7-1360P,x86_64,CPU affinity0-15,ext4 data-root,
normal thread environment variables unset. The small fixture is300 cells,
25 features,one25x300zero counts matrix,one300x2space and six promoted outputs.

## Matched backend/payload scope and remaining asymmetry

The direct branch independently constructs plain scientific structures;it
does not load scworkbench or call wb_prim_* or private engine helpers. Both
branches use the same BPCells count writer/defaults and rhdf5 dense-space
layout,SQLite WAL/NORMAL/FKON writable policy and immutable read-only opening.
The fixed source RDS is read twice on each branch;frozen vector/family/path/
model oracle RDS reads are inside COMPLETE on both. Vector labels retain their
original character precision,not reconstructed full-precision score doubles.
Feature and summary tables retain the same row JSON precision;model uses
gzipRDSversion3. All six public payloads and source axes/values are reopened.

Direct has a minimal typed scientific-payload SQL schema and publishes one
contained completed directory. Engine additionally owns full schema,registry,
provenance,replay materialization,collision/closure checks and promotion
workspace services. Engine's six retained replay RDS outputs remain visible
framework cost;the optional secondary replay-RDS denominator was OMITTED.
Matching backend IO is not a claim of identical historical/recovery services.
No missing service was invented solely to inflate the direct denominator.

This is a corrected demonstrably-unmatched historical reference,not an engine
speedup:old6.686s extra and new4.181s extra use DIFFERENT direct IO scope while
the engine revision stays0a. Do NOT subtract them or claim a37.5% runtime gain.
The old6.686>2 miss remains UNWAIVED;the new4.181>2 also misses. Whole-engine
171.124 and the separate absolute typed-space5s budget remain UNWAIVED.
No unchanged retake,trial exclusion or waiver is authorized by this note.

## Checks actually passed;warnings and inspection limits

Literal scientific structures,ordered cells/features/family keys/path points,
value types,metadata,model coefficients/associations and complete six-output
closure matched the fixed independent oracle. Public engine getters checked
logical matrix/space/artifact values. Qualification-only physical inspection
used public backend APIs,not a new runner/storage path:

- Actual BPCells matrix_type=double and storage_order=col on BOTH branches.
- HDF5 coordinate dataset H5T_FLOAT,width8bytes,precision64bits,H5D_CHUNKED,
  physical C-order chunk[2,300] corresponding to R chunk[300,2]. Ordered actual
  filters are[2,shuffle],[1,deflate];default shuffle is not absent at level0.
- All eight root scalar attributes matched exact expected types/values after
  the narrowly verified scalar-dim handling described below. Returned original
  attribute shapes were retained,not silently normalized in evidence.
- Actual SQLite3.46.0:page4096,cache-2000,temp_store0,locking normal,mmap0,
  busy_timeout0,wal_autocheckpoint1000,auto_vacuum0,UTF-8. Initial/pre-finalize
  WAL,synchronous1,FK1;post-finalize DELETE,synchronous1,FK1;immutable RO DELETE,
  synchronous0,FK0. RO defaults are not falsely called writable FK enforcement.
- Full bundle filesystem maps were identical before/after additional RO
  inspection. All original fixture/source/library/harness postguards passed.

Physical endianness was NOT independently inspected:only declared little-endian
metadata and same-host execution were established. Public H5Pget_filter returns
ID/name but not level,so physical deflate level was NOT independently inspected.
No incompatible type/layout was silently accepted. The helper owns all its
HDF5 handles and closes property/dataset/file then scoped publicH5close because
rhdf52.48 has no publicH5Tclose for its returned type ID.

Actual package versions:DBI1.2.3,RSQLite2.3.7,Matrix1.7.0,BPCells0.3.1,
rhdf52.48.0,jsonlite1.8.8,R4.4.1. Every raw child log reports linked HDF51.10.7
and rhdf5filters1.16.0. The JSON hdf5_runtime array is EMPTY because the version
message bypassed capture.output;use raw logs,not that empty field,as evidence.

All six logs retain BPCells' noninteger-compression warning. All three direct
logs also retain the sparse-to-dense warning for the small independent read;
engine logs do not contain that warning. No warning was suppressed as a pass.
All branches completed the same small numerical read;this does not establish
bounded dense behavior at real scale.

## First failed cohort and narrow harness erratum

`T/mixed_backend_reference_0a_first` stopped at direct1 exit1 because strict
identical compared scalar HDF5 attribute values with R scalars without their
rhdf5-returned dim=1L. No later case ran;ALL six postguards0;supervisor1.
All raw records and original harness copies remain unchanged.
`T/mixed_first_attribute_failure_inspection.log/.exit` is a separate Root
read-only inspection of the owned failed file:exit0. It confirms all eight
attributes have correct type/value and sole dim=1L,not scientific corruption.

Corrected helper accepts only exact expected typeof,length1,and no attributes
or ONLY dim=1L;removes only that proved dim on a local copy before literal
comparison,and emits field-specific failures. Other attributes/types/shapes
remain rejected. No scientific value,writer,policy,timer or budget changed.
The corrected cohort started all six cases afresh;no failed-cohort sample was
reused. Scope erratum and reviewed sources are retained in E/harnesses.

## Exact evidence identities

SHA256 values below identify retained inputs/results,not new runtime authority.
All paths without a T prefix are relative to E.

| Record | SHA256 |
| --- | --- |
| prospective_budgets.csv | fece0f8c95d2c3c5df906164b7209e5fcf3b9d6307c1b824645004f8dcda64f8 |
| literal_complete_samples_and_scope.json | 5f0720270c4528dd2bfb28e3c9c3fe1f613806fe3a8f784cf37e9c148d44a0cf |
| harnesses.sha256 | 11c9614a7d925aff1a522caf43a3e92a06f2c9ea89d3728604046982fd40fcc6 |
| original_fixture.sha256 | 632cf5d129b2d7c9ecd6100b17701f4357a65cb781cd0f7b4b5ccce1b3e04c4e |
| fixed_oracle.sha256 | 38689b6b800e92dce1aa3759e748517a5fc9c4b5b8f40aee05c193c67372b2a0 |
| input_maps.sha256 | b1f60815219335f81ab6d68f96eda066fe7dc53e11586fadd075058abf9873d2 |
| harnesses/mixed_backend_reference_common.R | 6454c5ce1cacb0c6b21cbcf50be4ec6a1fcbf866a549c3ae06856014583e218f |
| harnesses/mixed_backend_reference_direct.R | dbe5eadde0629dfef1be25cdca1f08f3402255cbd0078abf44ce732d2317f331 |
| harnesses/mixed_backend_reference_engine.R | fcb3492553dcdd959505d58c6c15de817ed7e6d583acfb932e45d1960b70c23f |
| harnesses/compare_mixed_backend_reference.py | 664f0da95f1388f28098163ebfd9b0a7ce08bd18f709164bcbe8b0a8425a0009 |
| harnesses/run_mixed_backend_reference.sh | 07f3aa43a8ac92bdf6a66f9d17fc81aa30927ae80ffa13e67eabe60965a4f237 |
| harnesses/MIXED_DIRECT_BACKEND_REFERENCE_RECONCILIATION_PLAN.md | 5b242fe4b1231f35c49a1130612f806334cc83e8e0195e7e6579779c27a96d4c |
| harnesses/MIXED_BACKEND_REFERENCE_ATTRIBUTE_SHAPE_ERRATUM.md | 545aa28cd91e8c3dc2d0560ef1c5492e37ffdd7446df8dbee714fbcbaabdb195 |
| harnesses/MIXED_BACKEND_PHYSICAL_API_SOURCE_EVIDENCE.md | 4deafb99c73cfd23191d985c28593df5255467fea2daa594d16946befa827866 |
| T/mixed_first_attribute_failure_inspection.log | e85b51b445eb4e18c453af3fa10621df6b118392db2bb526a31463e97cdc153b |

Remaining work is substantive engine overhead reduction and its own frozen
candidate validation,not relabeling this reference as accepted. The approved
installed-metadata attestation work proceeds separately;this old0a cohort is
neither its before/after evidence nor its qualification. No whole-engine,
Xenopus,large-data or independent-review acceptance follows from this record.
