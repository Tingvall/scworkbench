# Ordinary numeric canonicalization without per-element fallback

Runtime41877745b58e2851441d13833b0d83ac8c1da010, parentd0db42e/runtime680fc61.
PyBench remains f815def; no shared protocol, identity or pack science changed.
T=/tmp/scwb-engine-simplification-forge-20261018.

## Source finding and contract

Actual retained PCA output has13199x50=659950 coordinates. The existing native
flat numeric encoder rejects attributes and carriers over131072 elements;
ordinary matrices/large vectors consequently fell back to one R call per scalar.
The new private native admission checks only numeric and metadata carriers:
INT/REAL,!OBJECT,!S4,!ALTREP; only plain Names/Dim/Dimnames, no deferred/custom
name extraction. At most32 dimname-axis carriers are inspected, not their strings.
R then selects <=65536 scalar positions in the SAME column-major flat order,
drops metadata from that bounded slice and uses the existing flat C encoder.
All tokens/brackets/commas,15digit precision and scheme labels are unchanged.

Every actual slice is encoded, not cached or trusted by a supplied digest. Any
unsupported late slice discards private text and reaches the original whole-value
scalar fallback. Errors and interrupts propagate; no source getter, authority
handle, new validation framework or scientific operation exception was added.
Scalar/empty/locale and unavailable-symbol behavior remain unchanged. Complete
JSON strings/parts/final paste remain proportional to output; this is NOT a
bounded-memory general JSON-output interface.

## Preserved failure and correction

Initial2a311 focused23=22PASS1FAIL, no skips. The test incorrectly required
admission after structure(sharedREAL,names=...), which R makes an ALTREP wrapper.
Separate carrier diagnosis exit0 proved correct rejection. That raw result is
preserved; no first component measurement ran. The corrected fixture owns its
ordinary named storage. Meridian source review also identified name propagation
BEFORE unname();418 narrows metadata admission accordingly, before any timing.
The new test-only fixture independently combines ordinary numeric storage with
actual deferred Names and1D Dimnames and observes carrier flags/positive twins.
Flags establish representation, not absence of cache/materialization effects.
Fixture compilation/unload is explicit, not a core build or installed ABI.

## Literal component qualification

`bash T/run_numeric_partition_corrected.sh`:
numeric_partition_4187774 has SEVEN numeric sidecars0 including postguards;
24/24PASS,0skip/fail/excluded in5files. Actual deferred-metadata control marker
present. All9 byte lengths and SHA observations and actual retained payload SHA
3677ed6a7a95c4ec3e32e294c187dad8a539bb5b5fe4b209379c7923bbae3ef5 match.
Installed DLL SHA3853f40e11cd673cdbaaf66247bec47bf21af34858fc78253577e20a2716f323.

| Carrier | Parent median s | Candidate s | Prospective cap s |
|---|---:|---:|---:|
| Actual PCA primitive envelope |5.737|.708|2.8705|
|200003 numeric vector|.866|.074|.435|
|Actual PCA matrix|5.068|.525|2.536|

RSS253292→213284KiB passes331492.6 cap. All FOUR criteria pass. Budgets were
frozen BEFORE code in NUMERIC_PARTITION_PROSPECTIVE_BUDGET.md; metadata correction
kept every cap. One parent process and one candidate process, each three sequential
observations per carrier, are not randomized cold-process trials. Setup/read/gc
and result hashing are outside encoder timers; process RSS includes setup.

Sable independently verified archive/source/installed guards, all sidecars,
literal count and full-precision budget arithmetic: SOURCE_AND_COMPONENT_CLEAR_ONLY.
Quill reviewed exact418 source and found no protocol/parity change. Independent
Meridian probe at /tmp/meridian9-numeric-partition-4187774-20261020.ANYXSV executed
once with actual pre/compile/probe/post0, full installed guards and exact literal
bytes. Component-only ACCEPTED report commitdbdf6b7601a28a5a4636614a040f7df88a2445ae,
report SHA3f9d06d6610fc03bd1dfd439af459cf0487fc5b1512fa1051c8ebf720be29a34,
was read completely by Forge. Probe log SHA
63215d689a33f57f495c4dcbaa7c9d27df025480a4e2d3df6b09f64ec5356cfe.
No whole-workflow
or complete current-core-suite acceptance follows from these component results.

The prior392.28/427.76-second whole observations belong to runtime680, not418.
Both miss171.124s. They and all original graph/mixed/space misses remain unwaived.
