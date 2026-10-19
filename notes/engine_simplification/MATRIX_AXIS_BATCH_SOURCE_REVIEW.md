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

Test-source review also corrected two premises before candidate execution:
RSQLite's old one-row ordered cursor may coerce a later INTEGER into character
after seeing TEXT (actual isolated backend probe retained under
`matrix_axis_mixed_sql_type_preflight.log`, exit 0). This does not prove that
the complete old two-pass hash accepts that source: membership BLOB sorting may
visit the numeric value first. Tests distinguish that observed cursor behavior
from full-function behavior. Supported TEXT axes must still match exactly;
malformed actual non-TEXT rows must not become valid through batch coercion.
Separately, caller-transaction fixtures preselect the existing temporary-store
policy before opening their transaction, so SQLite's unrelated PRAGMA restriction
cannot prevent reaching the intended membership rejection. No runtime guard was
weakened to accommodate either fixture.

The first installed focused gate on 2ebfd475 completed all 26 tests: 24 passed,
0 skipped, 2 failed (29 expanded RSQLite deprecated-result-list warnings).
One failure was an omitted `SCWORKBENCH_SCWBRNA_ROOT` in the command; the clean
local RNA checkout is independently pinned to 151dd29211b219343dce6247c5e48fc932b4c83d.
The other compared a late fault's FD count against a baseline preceding two
additional, intentionally live SQLite fixture connections. The unchanged-test
diagnostic reproduced exactly 7 -> 9 FDs at member-fixture creation, no increase
through the injected faults, and zero owned fixture descriptors after unwind
(`matrix_axis_fd_scope_diagnostic.log`, diagnostic exit 0). The test-only fix
captures a fresh baseline for that late phase and retains exact equality;
earlier fault checks are unchanged. The original failed gate and diagnostic
are retained, not rewritten as passing runs. Runtime R/src remain identical to
bc6b0d664dbe2a883358b7e5d0036aa07a75b408.
