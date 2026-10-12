# Bounded legacy identity collector: immutable review tuple400

Review source/test tuple400 in this worktree and installed runtime399 at
`/tmp/scwb-graph-forge-bounded-legacy-review-399.qgqe6cr5/library` without editing
either. `evidence/400_collector_complete_review_tuple.sha256` binds77 assets;
ledger SHA256 is f2f4ef55493fc3d93bb88819f1de4010f7a900fb27641cb175e30b314d90eb20.
DLL SHA256 is ead7462807fb7920e924aa8995ec3ddb26ecbf87dd2c2d4b6ccf21f3b7a1bd56.
The runtime is byte-identical to390. The authority fixture correction supplies
the existing resource tuple to both output and publication grant; there is no
runtime authority fallback.399's initial73 ledger omitted that affected fixture;
400 includes it and all affected test inputs before current gate execution.

The separately closed341 accounting candidate remains immutable. Its reviews
do not approve this collector. This review covers the four new private
`R/getters_artifact_*.R` files, `src/graph_json.c`, shared byte-reader header,
native registration, and changes in artifacts/entity_certificates/provenance DAG.
Public formals, protocol schema, identity schemes, source axes and accepted
resource limits are preserved. Active graph cell/family certification uses the
bounded collector; ordinary non-graph certification retains the legacy loader.

The collector independently checks every descriptor row_order entry against
physical cell/family rows in original order and checks raw metadata chunks.
It reconstructs the existing R.serializeJSON object payload preimage, preserving
the full legacy content identity rather than accepting a stored header digest.
Descriptor selector64KiB is disconnected before physical reader64KiB and metadata
keys64KiB coexist, reusing the existing128KiB auxiliary allowance. Cache admission
and injected faults cover that transition and cleanup. The existing fixed64KiB
native reservation precedes fixed4KiB JSON buffers and bounded FD metadata.

Physical access remains in getters. Native JSON uses RSQLite's same extension
API with one API initializer, no separately linked SQLite engine. Private FILE
pointer callbacks exist only during the getter lifetime; on.exit invalidates the
pointer even if the callback errors. They are never granted to an SDK runner.
Strict UTF8/JSON lexical validation, SQLite snapshot finishing and file stat
checks distinguish malformed syntax from resource/accounting/source mutation
errors. Provenance syntax errors retain the old empty-ref behavior; operational
resource errors and late source mutation propagate. Fileless diagnostic sources
require whole-TEXT admission and revalidation; graph authority still requires
physical file-backed sources. Registry queries use octet_length(TEXT), avoiding
SQLite length(TEXT)'s whole-field materialization, with no materializing fallback.

Metadata preserves the old codec result under admission. Small whole-codec inputs
are bounded before decoding, including token carriers and opaque/code costs;
large proven structures stream with SQLite key tables and common-array coercion.
Unsupported large transformations fail with GRAPH_RESOURCE_EXCEEDED, an
operational admission failure rather than a new logical metadata validity rule.
Small admitted parity remains for those structures. Arbitrary S4 construction,
unloaded namespaces and NativeSymbolInfo conditional class predicates are blocked
before unsafe decoding. Tested dependency scope is jsonlite1.8.8; no general
codec-version equivalence claim is made. Review rank/coercion, attributes, retained
carriers, code/namespace guards, error typing and every cleanup path critically.

Terminal focused evidence currently available:401 codec53/53 (normal19, edge15,
hostile15, admission-boundary4),402 collector4/4,403 affected core5/5 and406
same-engine native API1/1, each exit0 and no skips.410 compares every function
defined by the four collector source files against installed bodies/formals;
all match, with exact library/DLL and dependency versions recorded.404 freshly invokes
the installed public full certificate on the original90000-cell source, compares
the entire saved269 certificate object, and verifies unchanged source DB. It
passes with original SHA256 b78524fc47460da8d90b06541f7114fd31ce60fd63d598374d4a4ad3d0b5d044.
Certificate elapsed85.945s,HWM235500→235500KiB. Bundle opening precedes allocation
profiling, actual metadata is183B, and this is not a whole lifecycle RSS result.
405/407/411/417 source postchecks match all77 hashes.408 accounting/public mixed
execution13/13,409 native public matrix4/4 and412 recovery/model8/8 all finish
exit0 with no skips.412 records two actual interrupted/racing child identity
MATCH results (exact library, DLL and six body/formal digests), with the original
30s deadline. Recovery was serialized after the other workers. Original partial
checkpoint warnings and the native already-disconnected warning remain in logs.
419 installed public full original-source provenance DAG exactly matches saved272
object, sourceDB unchanged,3.122s,HWM237820→237820KiB after bundle opening.
416 exported formals for all348 entries are identical to immutable341.415 all16
shared protocol assets remain unchanged.414 binds four NEW actual400 native
samples at `/tmp/scwb-native-graph-samples-tuple400`; earlier330/341 samples retain
their original producer attribution.

`evidence/418_tuple400_terminal_record.json` and its terminal evidence SHA ledger
bind every numeric exit, terminal log, current posthash, sample, saved full
certificate/DAG result and installed DLL. Review release is pending. Inspect and
independently rerun focused hostile/canonicalization/trust/cache/cleanup cases;
report exact source posthashes before and after review. No broad suite is requested.

Failure history is retained in RESUME_PHASE_STATE:376 pointer exposure failed and
380 replaced AST rewriting with explicit private lifetime callbacks;385 invalid
character-class fixture oracle was corrected to a genuinely invalid double case;
386 harness loaded the wrong package before pinning, fixed388;393/395 authority
fixture omitted output/second grant budgets, fixed before400.397 archived composite
needs unavailable scwbrna activation and remains a disclosed failure, not a pass
or skip.403 covers actual affected core behavior. Prototype369's2097200-byte
allocation has no established cause;373 bounded integer64 conversions rule out a
sourcewide integer64 carrier, not the allocation's cause. Historical prototype
and prior-candidate results cannot substitute for current installed results.

Scope excludes whole lifecycle memory acceptance and final qualification. After
both independent reviews and any findings close on exact posthashes, the original
90000-cell development lifecycle will run against unchanged memory/disk ceilings.
No source-axis reduction, resource increase, broad-suite final qualification,
merge/push/profile/official-pack/SIF work is authorized by this review packet.
