# Prospective bounded-path budgets

Declared before subsequent runtime changes (2026-10-18). Baseline is repaired
core `8f53e950e6eda4c86b0f4ce6623bc14a1f2e637e`, installed runtime
`d7232f800190e1c1cb78af0e4591fa53e9003087`. This helper changes no runtime.

- Metadata-vector execution: 300 cells, history sizes 0/5/15; final operation
  overhead over direct SQLite read/compute/write/reopen <= 1 second, and the
  15-history final operation <= 1.5 times the empty-history time + 0.1 second.
- Mixed primitive construction/promotion/finalization/reopen: 300 cells and
  vector/family/feature-table/observation-table/path/space/model outputs;
  framework overhead over direct complete SQLite+RDS read/write <= 2 seconds.
  Direct comparator intentionally does not provide provenance, recovery or
  atomic publication; its gap measures the total additional services, not only
  removable overhead. Different storage schemas are explicitly unmatched.
- These small CPU-bound examples must peak below 1 GiB RSS. Real measurements
  include invocation initialization separately from operation phases. Linux
  `/proc/self/io` rchar/wchar are syscall logical bytes, not physical disk bytes.
  read_bytes/write_bytes are kernel physical-I/O counters and can be zero under
  warm caches. Full-source scan counters require explicit traced functions;
  absence of a counter is `not_measured`, never zero by inference.
- Any budget miss is retained and explained, not retrospectively relaxed.
  These are bounded examples, not engine-wide performance qualification.

Before the proposed table-fold implementation: at 100, 1,000 and 5,000 rows,
preserve exact table.stream.v1 digests and target >=5x reduction in elapsed
hashing time at 1,000/5,000 rows, with <=0.05 second fixed overhead at 100 rows.
Measure both the complete table hash and the two-digest object-fold helper;
identity-only microbenchmarks do not establish complete-workflow performance.

Full Xenopus direct-reference contract (declared before new direct run or
candidate comparison): all raw and normalization values max absolute error
<1e-14; HVG complete rank/order and selected IDs exact, numerical mean/variance/
score <=1e-12 absolute +1e-10 relative; PCA singular-value/variance relative
error <=1e-8, coordinates/loadings after per-component sign alignment
<=1e-7 absolute +1e-6 relative (no rotation allowance unless escalation);
UMAP same axes/backend/seed/threads max coordinate absolute difference <=1e-6.
Persisted table JSON's existing four-decimal rounding is compared independently
from full-precision in-memory scientific results, never waved through by a
single loose tolerance. All outputs, saved models and durable arrays must reopen.

For the final candidate relative to this complete direct reference, target
framework overhead <=30% of direct end-to-end read/compute/write/reopen time
plus an absolute 60 seconds for provenance/atomic finalization/recipient checks.
No individual fast administrative phase should exceed 5 seconds without an
explicit explanation. Relative to the repaired engine end-to-end reference,
target >=25% elapsed reduction and peak RSS no more than baseline +10%.
Root already has approved table/copy/owned-execution work in flight; this
additional budget precedes further runtime changes and final comparison.

Follow-on import/schema work (declared after bounded profiling, before any new
schema-check removal/consolidation): synthetic 1,000 cells x500 features,
nine metadata fields/eight categorical fields with ten levels, must preserve
the same imported cells/features/metadata/sets/spaces/provenance and target
import <=17.3 seconds (>=2x versus measured 34.594 seconds). Target sampled
schema-status/FK-signature inclusive cost <=3 seconds versus14.46 seconds;
manifest-registry snapshot cost <=4 seconds versus15.41 seconds. All elapsed
profile buckets nest; do not sum them or enforce a false disjoint budget.
Any schema-status observation reuse must still invalidate on schema/connection
changes and preserve mandatory FK/ledger/corruption diagnostics. These are
prospective targets, not permission to weaken checks. Runtime edits remain
root-owned following Sable's trust-boundary review.

Typed selected-space encoder probe: before a potential encoder-only change,
13199 cells x30 doubles must retain exact space_slice.content.v1 canonical
bytes/digest, reject invalid values under the existing policy, and target >=3x
elapsed reduction if the measured baseline is significant (>1 second).
Peak memory must not exceed repaired baseline +10%; any future large-space
encoder must stream bounded blocks, not just replace R lists with one giant
canonical string. Small identity vectors need independent canonical-number/
string oracle parity. Object/family/model descriptor timings are separate;
none establishes model-tree or engine-wide performance qualification.
