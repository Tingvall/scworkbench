# Registry scalar batches: prospective follow-on budget

Preserved correctness checkpoint: source1f853b6 / installed242fdf0. Its complete
fresh Xenopus workflow took769.22 seconds;171.124-second target remains missed.
Twenty-nine registry snapshots consumed215.963 inclusive seconds (nested timing,
not additive with their children). Do not relabel this checkpoint accepted.

Before implementation: target at least3x faster complete registry snapshot on
the same finalized checkpoint bundle, exact old-oracle table identities, and
whole-process peak RSS no more than10% above its matched old measurement.
Keep earlier whole-workflow and component misses in the record.

Change only the existing scalar-batch path: candidate ceiling64→512 and encoded
ceilingP/8→P/2, while retaining carrier+8*encoded≤8P and all token/actual-byte,
fetched-row, source observer and lifecycle resource checks. Charge enlarged
candidate arrays before constructing them. Plain unattributed int32 values may
use16-byte token bounds (sign plus at most10 decimal digits, null4). Doubles,
extended types, objects and deferred values keep the existing512-byte bounds.

Logical5000-row digest chunks, SQL type promotion, jsonlite options, row order,
framing, schema and identity versions must remain unchanged. No new validation
framework, cache, reader authority, file-SHA change or scientific operation.
