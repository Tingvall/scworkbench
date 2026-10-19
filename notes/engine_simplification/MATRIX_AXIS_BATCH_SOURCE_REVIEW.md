# Matrix-axis batching: source review history

Budget checkpoint: 837624e4973314c3609090b0cfa6741b131166bc, before runtime
changes. Baseline preparation and all four baseline processes are independent
of this implementation and remain unchanged.

The first uncommitted implementation passed parsing/diff checks but was not
installed or executed. Sable's source review found that source-axis hashing
called the page-size ledger without its actual projected SQL/parameter carriers
(the physical-membership path already supplied them). Corrected before any
runtime execution: each hashing pass constructs the exact SQL and parameters,
admits the page against those actual carriers, then sends that same query.
This was a source-review finding, not a runtime failure or performance pass.

Retained boundary details:

- Scratch axis IDs are exclusively core-written after the original native JSON
  parser has admitted each <=256-byte UTF-8 ID. No external source TEXT enters
  these batched scratch fetches.
- Source-axis hashing projects actual type/size in its own cursor snapshot.
  Invalid/oversized values become invalid scalar observations, not skipped rows
  or oversized allocations. Ordering refers to the original source expression,
  not to the projected invalid-value alias.
- Source expressions remain left operands of SQLite equality. Requested IDs
  are bound parameters, not SQL literals or a competing collation/affinity.
- Canonical scalar strings use the exact existing encoder; framing, duplicate
  checks, per-ID count and emission order, partition/EOF admission, byte
  observers and full closure checks remain independent.

Focused execution, exact implementation review and component measurements must
be recorded separately. No engine-wide acceptance is implied by this note.
