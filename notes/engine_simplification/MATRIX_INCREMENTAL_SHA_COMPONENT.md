# Same-byte matrix identity digest component

Runtime/tests:281df02d4d4120965bc50810017c2d68be3ce362, descendant of the frozen
a194b5738c8f9f92af5b8d9898cac1cc74d74b65 main qualification. PyBench unchanged
atf815def0127b7a63a5e81455c270cff6572dc8ea. This component does NOT turn the
397.74s main workflow or graph/mixed/typed performance misses into passes.

## Change and unchanged contract

The exact existing canonical JSON matrix preimage previously went to a private
file, then a second read fed OpenSSL SHA256. The optional sink feeds the SAME
UTF8 header/footer and native64KiB entry buffers into one owned context. Value
formatting, NA/zero filtering, row/column order, bounded selections, source
authentication, identity scheme and digest bytes remain unchanged. There is no
new executor, pack interface, cache, process or required crypto backend.

Only Linux/glibc>=2.34 builds admit this loader path; other builds retain the
file path. No libcrypto/libdl build flags or headers are added. Core acquires a
no-load reference to the actual loaded R openssl DLL; all six public EVP symbols
must resolve to one image before reading input. Unsupported/ambiguous admission
falls back before callbacks. An admitted runtime failure aborts rather than
replaying input. Checked updates/finalization, a32byte digest, prompt on.exit,
idempotent finalizer and context destruction before handle release preserve
ownership. No claim is made of native execution on untested platforms or absence
of provider-internal initialization.

## Frozen measurements and literal outcomes

T=/tmp/scwb-engine-simplification-forge-20261018.
Prospective budget SHA5522062dfc6efb62ef7673906c5335269f66bfce944decb7d56bf3405a97fefe.
Parent: T/incremental_matrix_baseline; candidate: T/incremental_matrix_candidate_281df02.
Both use the same immutable31535feature×512cell normalized Xenopus selection,
with bounded128column reads. Three observations per case in one parent process,
then one candidate process; these are component medians, not randomized trials,
whole operations, pure framework overhead or whole-workflow acceptance.

| Complete semantic helper | Parent median(s) | Candidate(s) | Fixed ceiling(s) |
| --- | ---: | ---: | ---: |
| Actual normalized block | .293 | .224 | .24905 |
| Integer-valued block | .215 | .180 | .22575 |
| Unique fractional values | .702 | .685 | .73710 |

All nine identities/schemes exactly match. Helper logical writes fall from
43.55–57.20MB per observation to0; measured storage writes also0. This is NOT
zero whole-process IO. Parent/candidate whole processRSS523828/502176KiB stays
below fixed566403.4KiB ceiling. Both source fingerprints match before/after.
All10 prospective metrics pass, budget_result.json SHA
5fadbb8c70f406f128c6cef343ca7766a4f49738a3ca48ba95fbe25d4f1a5929.
Install, focus, measurement and input/library postguards all exit0.

Actual installedDLL7587c2f395ae2c515326ae596aeee0b5c69e549bebd65c7ed57e488019048c60.
Focused14/14 passed,0skipped across3files:5new lifecycle tests,3existing token
tests and6existing streaming/alignment tests. The gate requires positive native
admission; portable test early returns are not its proof of execution.

## Independent reviews and limits

Sable source and component evidence CLEAR:
/tmp/scwb-sable-matrix-incremental-sha-source-281df02-20261019/
review.json and component-evidence-review.json.

Meridian component-only ACCEPTED, report commit
45415d5f8286dd12d95ff686c4606a4531938a60; report SHA
eaf8e5198fafdd3dd433d1a52f044ec9ac4889a3241c46e9202fd921d2884021.
Independent actual installed probe hashes a hand-built88014byte matrix preimage
crossing64KiB, binary input, several native/file chunkings, Unicode/logical/zero
cases, errors and simulated interrupt cleanup. Raw evidence:
/tmp/meridian9-incremental-sha-281df02-20261019.aTprt6/.
Original probe.exit1 is preserved: debug srcref/srcfile/wholeSrcref differences
prevented the source/installed AST bootstrap comparison before digest assertions.
The private harness normalizes ONLY debug metadata through utils::removeSource;
distinct corrected probe_source_metadata_normalized.exit0 and all byte guards
pass. Installed code, digest oracles and original failure were not modified.

Actual asynchronous interruption inside a provider, native heap/loader reference
leak measurement and non-Linux/compile-disabled build execution remain untested.
No complete core suite is claimed for this later source: the earlier618/618
cohort belongs toa194/f815; later focused14 and this independent probe are
separate affected-boundary evidence, not a fabricated623test full-suite result.
