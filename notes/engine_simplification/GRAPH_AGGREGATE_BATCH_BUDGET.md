# Bounded graph aggregate batches: prospective budget

Prior representative graph workflow:46.387 seconds. Current candidate:
40.981 seconds, including18.576 seconds recipient validation. The three-second
framework-overhead /20-percent-relative budgets remain MISSED; this patch does
not waive them. No new timing measurement is claimed.

Target: at least20-percent reduction in the aggregate-verification/polling
component, with transient spill admission once per bounded batch rather than
per edge. Initial/EOF/final admission remains; actual per-edge direction,
arity, order, canonical bytes and content identity remain unchanged.

During the already required validated edge scan, retain only the maximum UTF8
record length (one number). Fetch at most partition_rows, with row cap derived
from max_record_bytes+1024 bytes conservative fixed carrier per row. For two
or more rows, encoded bytes plus this carrier must fit partition_bytes.
1024 accounts the six aggregate columns (including decimal int64 character
carriers), edge-string/vector overhead and row bookkeeping, not SQLite's
independently reserved cache. Single giant records retain original admission:
their encoded bytes may occupy the whole partition, within existing decoded
8*partition_bytes+64KiB headroom; no newly imposed per-row subtraction rejects
a previously admitted record.

SQL emits a NULL sentinel instead of a record that grew beyond the observed
maximum or ceased being TEXT. Entire fetched batch type/length/sum is checked
before JSON parsing. There is no additional scan, cache, new identity, policy,
source authority or public interface. Existing global SQL aggregate remains.
Allocation bounds are source-informed conservative accounting, not an absolute
cross-version RSQLite/R RSS guarantee. Source review precedes any tests.
