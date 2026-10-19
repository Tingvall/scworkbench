# Bounded internal metadata JSON batches

Implementation follows clean precode checkpoint `5b41ebc` and its frozen parent results: large median 5.203 seconds / ceiling 4.42255; RSS 202416 KiB / ceiling 222657.6; tiny median .448 seconds / ceiling .5128. Historical 4.192/.160 references remain misses where applicable. No implementation result is claimed here.

Only internal scalar JSON emission changes. The source cursor, predecode fetched-carrier admission, ordered `chunk_size` fetches (default 5000), registry.v1 fold framing, all type promotion, deferred text/blob streaming, serializer arguments, token admission, native final observer checks and graph wire partition rules remain unchanged. A candidate never exceeds 5000 rows, even when a private caller selects a larger logical chunk_size. Such a caller's existing logical fold itself is not changed.

Let P be partition_bytes, C field count, B=4096+576C, L=16C+32. Before any candidate arrays, choose N <= min(5000, remaining, floor((8P-B)/128)). A conservative first-row charge (original string6x+2/NA4, plain int32 16, other512 bounds plus existing key charge) can reduce N further using `(8P-B-16)/(128+L+8*first_charge)`. This is only an allocation heuristic, never authority for subsequent rows. If it yields zero, retain the exact scalar route; in particular P=128 has no batch.

For all N candidates compute unchanged per-row bounds and deferred eligibility. One cumulative charge and contiguous eligibility prefix choose the largest t satisfying:

    B + 128N + Lt + 8*(cumulative_charge[t]+2) <= 8P

No arbitrary P/2 payload cap remains; the unchanged full 8P envelope is authoritative. The selected prefix also obeys the existing token_bytes limit; the unchanged complete token emitter independently enforces its cumulative limit. No repeated decreasing-prefix sums occur. The final actual serializer byte count is checked against the saved selected prefix charge. A late deferred cell excludes itself and every subsequent row from that attempt; it is handled by the original incremental/scalar path, not serialized as a placeholder.

## Local carrier ledger

The existing fetched matrix/dataframe/type values and SQLite cache have separate predecode admission. B covers fixed and field-list/vector headers and key/field references. Lt covers selected dataframe/type carrier plus selected index/row carriers. 128N conservatively covers simultaneously live speculative vectors: candidate index, eligibility and its old/new comparison results, charge and old/new accumulation copies, per-column subset pointers/nchar/ifelse temporaries, cumulative numeric charge, cumprod and logical prefix, arithmetic comparison masks and selected-index construction. These are O(N), not O(N*C) metadata. Per-column scratch is explicitly released after each column. Existing serializer/sanitizer/output/substr/emit raw copies are covered by 8*encoded, unchanged. The arrays, selected dataframe indices and JSON string are cleared after emit or zero-take before scalar fallback, avoiding their retention into the next attempt. Small-whole JSON is likewise cleared after its hash before the next logical chunk.

This is the existing local admission model, not a hard process RSS/global string-cache quota. RSS acceptance remains the frozen matched +10% gate.

## Source-focused checks, not yet executed

- Existing identity test's intentional 512/partition_rows assertion is replaced by candidate<=5000, exact carrier formula and existing aggregate byte/caching/restoration assertions.
- New `test_engine_manifest_json_batch_decoupled_rows_and_fold_contract` requires actual batches above 512 and partition_rows=2, literal old materialized identity, exact 5000 folds for 0/1/4999/5000/5001/10020 rows, and unchanged caller policies/cache.
- New `test_engine_manifest_json_batch_graph_wire_partition_unchanged_contract` performs an actual six-node graph stage/export under the same policy: it must still emit three two-node partitions, not a larger metadata-sized wire block.
- New `test_engine_manifest_json_batch_deferred_policy_fault_and_retry_contract` exercises Unicode/escapes/NULL/int64 and late deferred values, P128 fallback, multiple byte limits, injected batch fault, restoration and retry against the unchanged old materialized oracle.
- Existing graph wire reader/writer tests remain untouched: internal metadata JSON batches do not alter their partition_rows arguments or configuration. Existing mixed BLOB/date/time/late promotion and late mutation tests remain selected for coordinator qualification.

Source review must precede install or execution. No new benchmark or focused test has run at this checkpoint; all historical raw failures and frozen gates remain intact.
