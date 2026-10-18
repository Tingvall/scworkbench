# Prospective bounded manifest logical-chunk optimization

Base c590070b9580f760272b49c8aae13063884aa0cb. Before this implementation:
original >=4x snapshot target remains unchanged. The measured46 one-row tables
were baseline .641/.631/.640s versus candidate .375/.394/.390s: ~1.64x median,
**MISS**, not an empty-table pass. Approximate target remains<=.160s, not revised.
Empty-only throughput is unmeasured. Existing observed DBI connect entries46->1
and witness .00739s/check meet distinct resource/guard goals, not the speed goal.

Only an entire existing logical hash chunk with no deferred field and explicitly
supported SQL-decoded column classes may use an in-memory JSON digest. Compute
UTF-8 sixfold escaping/key/row bounds and conservative carrier bytes FIRST;
`carrier_bytes + 8*encoded_bound <= 8*partition_bytes` uses the SAME transient
reservation already admitted on top of fetched rows/cache. Also respect existing
token limit; exact post-encode nchar must fit the admitted bound. Otherwise use
the old file-backed emitter before serialization. No numeric/token/identity change.

One initial and one final snapshot-owned graph spill/FD/session-copy admission
remain explicit, including all-empty snapshots. Fallback keeps its per-chunk
spill/file-growth checks. Exact-count EOF skips only after n==original count;
short/overfetch rejects. The existing single cursor preserves late SQL promotion,
5000-row folds and signed int64 row order. Full-loop native finish still rejects
WAL mutation and faults unwind owned resources.

No runtime test, installation or performance job is authorized before exact source
review. Tests added here are a plan until the coordinator explicitly runs them.
No budget pass or final acceptance is claimed.

## Source-review checkpoint and proposed tests (NOT RUN)

Only R/bundle_manifest_stream.R changes. Five new contracts in
tests/test_engine_manifest_small_chunk_contract.R cover:

- Frozen materialized schema-header and5000-row fold parity at0/1/4999/5000/5001
  rows; signed rowids and rowids beyond2^53 preserve int64 ordering.
- Late mixed SQL numeric/text promotion, DATE/TIME/TIMESTAMP, NA and escaped
  Unicode/control strings; byte256/257 TEXT including multi-byte Unicode;
  BLOB and late deferred exclusion of the ENTIRE logical chunk.
- Exact carrier+8encoded reservation ledger, tiny-policy streaming fallback
  before serialization, token-limit rejection, injected pre-encode failure,
  cache/policy cleanup and retry.
- Scoped function-copy fetch instrumentation for nonzero-short/zero/overfetch
  failures; real cursor/native bodies and installed namespace are not patched.
- Between-table and final-table WAL commits reject; initial/final snapshot
  spill admission remains on all-empty snapshots, with both fault unwind paths.

The small path is enabled only for observers produced by the private manifest
resource scope with explicit initial/final spill checks. Other supplied native
observers retain the original streamed emitter. No pack-visible flag or grant.
The carrier dimension bound is checked before row-sized bound/type arrays are
created. Encoded bound adds six bytes per character byte plus quotes, escaped
keys/structure and512 bytes per nonmissing supported numeric/extended scalar;
carrier256 bytes/value plus fixed dataframe/column/row overhead and8encoded
covers sanitizer/serializer/hash copies within the original reservation.

After source review, coordinator may install into a NEW private library and run
the five new contracts plus existing test_manifest_stream_identity_contract.R
and test_engine_manifest_snapshot_resources_contract.R. No performance run or
complete-suite repetition is proposed here. Exact checks and speed measurements
belong to the later coordinated frozen-candidate evidence.
