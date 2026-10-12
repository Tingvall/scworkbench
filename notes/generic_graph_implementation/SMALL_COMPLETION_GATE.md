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
| ABI3/process4 and existing primitive regressions | final complete core suite | final complete Python suite |

Run one consolidated small-focused qualification on a source/install-pinned R
candidate, export authenticated request/receipt/expected roots for Quill, then
one final full core suite and relevant build/check, one final Python suite and
wheel/sdist checks, generated docs/protocol/link/whitespace checks. Corrections
receive affected checks; do not repeatedly run whole suites during construction.
Freeze actual terminal logs/exits/source/install hashes. Reuse the same two
independent reviewers via diagnosis parent01a12c74-97ae-71c0-9522-eb3c68b45383 on
stable final tuple; prior metadata-only accepts do not qualify graph completion.
No merge/push/profile/official packs/SIF. DONE email only after full independent
acceptance; genuine blocker email only if user action is required.
