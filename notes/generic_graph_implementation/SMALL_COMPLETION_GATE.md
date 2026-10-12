# Revised graph completion matrix

Authority: accepted graph design fa929601 and Controller/user request
2026-10-12_graph_bounded_out_of_core_completion_gate.md. Preparation inventory,
not acceptance. Historical 463/485 process RSS failures remain failures; recipient
489 passed separately (491 terminal record). Physical RAM/8x stress is DEFERRED.
No universal constant-memory or above-host-RAM claim follows from small tests.

## Shared case and budgets

Fixture bounded_small_case.json SHA256
60741a7915721fb6c8872ad58a656dce3fb1c1de42bad52ab756cacd4ea703d2.
32 ordered nodes, 4 edges (self-loop, parallels, repeated-member hyperedge),
39 incidences, 6 fields/140 values spanning all four attribute scopes. Native
promoted matrix 2 features x32 cells; 3 complete binding records/34 mappings,
including a named empty feature binding. Binding roots come from actual R-issued
source grants, never draft synthetic authorization.

R working allowance 1048576 bytes; aggregate SQLite cache 256 KiB including
64 KiB selector and 64 KiB native-reader reserves; partition max4096 bytes/2rows;
collect max8192 bytes; staged/token/spill16MiB; published/WAL8MiB. Main content
22564 canonical bytes exceeds collect; max two-row preimage1294 bytes fits4096.
Python writer quarter-cache derives256KiB from1MiB memory; aggregate live writers
reserve cache +8 decoded partitions +64KiB metadata under minimum live write-grant
allowance. Python read grants authorize partition limits only: broker owns no
SQLite and supplies one bounded response using existing spool/coverage discipline.
No Python aggregate read-memory or whole-process1MiB claim.

Unbound preparation roots (not runtime acceptance):
content d98d32aaceec530597ec03aabb2eeb3aa6697639852cfba754c9165f95735e24;
binding838792edabb090bb90fa9ffab1dffd165bf1c2840db0dc26f9c1a47fac19cfa7;
descriptor272d622fffd3d7c8f2107b6523073d596d926bc3eaa455e265367e9afe50f71c.
Invalid draft preparation rejection remains490; corrected JSON is authoritative.

## Requirement coverage

| Requirement | Consolidated R/core coverage | Python coverage |
|---|---|---|
| Ordered structure, loops/parallels/isolate, mixed/hyper directions, all types/nulls | graph_primitive, strict_json_unicode, scenario_roundtrip (23 normative cases) | protocol, transport, optional graph adapter; exact shared fixtures |
| Full binding/source/schema authority, empty/partial/selected/unavailable views | source_authority, binding_read_selection, native_matrix_identity/producer/public_promotion_first/real_g2, matrix_source_selection, source_snapshot_scope, object_source_batch | native_matrix_parity with actual R request/receipt; unsupported authority rejects |
| Closed schema/identity/semantics and self-rehashed negatives | abi4_admission/runtime_sidecar/retained_count, primitive13 malicious vectors | protocol/schema/native parity negatives |
| Registered ABI4 mixed lifecycle; existing executor/process5 | abi4_public_execution, abi4_python_live, new small public lifecycle | parts/SDK/broker and live process5 |
| Bounded SQLite/import/write/hash/seal/parts/cursor/collection | new small gate observes disk stage and canonical token files, exact7 components, grants/bindings; resource_accounting including concurrent imports | small out-of-core infrastructure; cache reservations/concurrent writer release |
| Actual temporary spill and ownership accounting | resource_accounting unlinked SQLite sorter, alias/FD metadata/session overlap/journal/publication caps | disk writer/canonical spools appropriate to supported path |
| Atomic promotion/executor publication, rollback/retry/cleanup/source purity | small gate3 promotion+6 executor faults, collect rejection; resource_accounting, broker_publication, native source mutation | writer abort/ctor failure/concurrency, broker atomic ACK, SDK failure |
| Finalize/relocate/fresh pack-free read-only recipient | small +public_execution +23scenarios/native public tests | R recipient owns durable promotion authority; Python authenticated carrier parity |
| igraph exact lossless subset and reject boundary | primitive adapter +23scenarios | installed Python igraph tests, no dependency skip treated as pass |
| SDK public authoring/docs/capabilities/generated protocols | sdk_authoring +explicit installed graph_tutorial.R six-case command | public SDK discovery/process5 +generator check |
| ABI3/process4 and existing primitive regressions | Retained525 parent plus explicit58250 failed-case/58940 residual coverage and scoped recipient-fixture closures; no canonical full all-pass claim | bb0 parent750/5 plus e724 installed-wheel ABI3/process4 focused4/4 and final descendant affected158/12/1 |

Run one consolidated small-focused qualification on a source/install-pinned R
candidate, export authenticated request/receipt/expected roots for Quill, then
the recorded interrupted full core run525 and approved pinned targeted successor
coverage, relevant build/check, retained Python parent full suite plus scoped
descendant/wheel/sdist checks, generated docs/protocol/link/whitespace checks. Corrections
receive affected checks; do not repeatedly run whole suites during construction.
Freeze actual terminal logs/exits/source/install hashes. Reuse the same two
independent reviewers via diagnosis parent01a12c74-97ae-71c0-9522-eb3c68b45383 on
stable final tuple; prior metadata-only accepts do not qualify graph completion.
No merge/push/profile/official packs/SIF. DONE email only after full independent
acceptance; genuine blocker email only if user action is required.

## Successor coverage attribution

Final source5c3ad8111610ddf57c64877391b5e6cc47f22ff8 has production R/src/protocol
bytes identical to9869ccf344191ca7ff6e070139bfdcd03336d746 (600ledger). Original
525's namespace replacement is attributed exactly in599; every64original failure
has a distinct556matrix row. No full rerun was approved. Successor58250 and58940
remain running, with one actual recipient-fixture failure each; no provisional
pass transfer. Final public small597, current live598PASS, normative603 and
installed SDK604six/sixPASS provide actual graph-specific qualification.
Package595passed0errors/0warnings/1sizeNOTE, not a function-execution full gate.

Historical Python protocol equality594failed four expanded assets against its
old e0feac peer; historical composite/model lifecycle2PASS remain separate.
Controller accepts that obsolete-peer/current-byte comparison as unqualified,
not a PASS or rewritten skip. Current e724 ABI3/process4 wheel4/4 focused executor
proof and paired44-assets inventory are separately attributed; no unsupported
backend authority is inferred. See final packet for exact records and limits.

## Frozen final implementation and actual successor boundary

Final8ea74ac095853716449396f02ed2f99b6f0787b6 is installed from exact source643.
Current6443/3zeroSKIP covers mixedABI4R/publicfaults+freshpackfree relocated
readonlyrecipient, installede724live retained-CV/matrix/broker and12ordinary
proof-removal variants.649metadata3/3 and647package0ERROR/0WARNING/1sizeNOTE
passed;646source/installedposthashMATCH650. The 625 private provisional ordinary
Python output correction is qualified by630currente724 exactpublic values /
promotion/certificate,633faultnegative/retry case and640crosslifecycle case.
No publicsource/missingproducer orgraphauthority guard was relaxed.

Parent597small disk-backed infrastructure5/5,60339/39including23scenarios,
604installedSDK6/6 andQuill611actualnewroots/cursors/collect remain attributed
parent/source-pinned evidence. Current644validates the changed interop boundary;
no39/336repeat was requested. 582remains48PASS/2FAIL and58938PASS/2FAIL; specific
fixture closures are623/631 and612/613, not relabeled fullpasses.651accounts all
336current function names and their literal parent/scoped execution statuses.
REVIEW_PACKET_FINAL_SMALL.md and650 carry exact hashes, changed-code scopes and all
memory/oldprotocol/optionaldependency caveats for the same independentreviewers.
