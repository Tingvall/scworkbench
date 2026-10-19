# Matrix-axis query batching: budget before implementation

Baseline source ca8e4f62759f6f415193fe01dfc1b14ce53b231e has the same
runtime as 2c5d5b705b50b83140ff6fe50f404526d0ceebdd. No runtime change
is included in this budget commit. The installed old3009 and new2c5d baseline
processes are retained under
`/tmp/scwb-engine-simplification-forge-20261018/matrix_axis_membership_baseline_20261019`.
All eight inner gates completed zero. Plain timings are separate from census.

The deterministic 64-feature/1000-cell BPCells fixture is finalized and reopened
read-only. Every physical/declared/SQL axis, actual scientific value, canonical
axis identity, registry-state field and source file SHA matches independently.
Ordinary dense guard: 256 MiB. No scientific dispatch or official pack changes.

Baseline plain seconds (old3009 / current2c5d): physical verification
1.607 / 1.536; feature-axis hash .075 / .067; cell-axis hash .874 / .870.
Current scalar physical verification performs 1064 fragment and 1064 logical
membership queries. The old census attributes 1.031 seconds inclusively to
dbGetQuery; do not add overlapping query/fetch/send timings. This disproves the
prepared unmeasured 5x physical-verification target as a sensible budget for
query batching alone: JSON/name parsing and scratch construction remain.

Budgets fixed before implementation:

- At least 2x complete physical verification, with at least 90% fewer membership
  SQL round trips on this fixture. Retain every physical/declared/union check.
- At least 2x combined feature/cell axis hashing, with unchanged ordered and
  membership preimages, two complete passes and actual source validation.
- Compare medians of three alternating fresh-process matched trials; whole
  process peak RSS must not exceed current baseline by more than 10%.
- Small/tiny policies must retain their scalar fallback and original failures;
  no memory-limit increases, new public rejection, identity or trust change.
- These are component budgets, not a waiver of the original full Xenopus
  171.124-second cap, graph lifecycle +3 seconds or other recorded misses.

Implementation scope: bounded membership EXISTS queries over core-owned scratch
axis pages; bounded source-axis fetches with actual SQL type/size projection;
route valid scalar IDs directly to the existing canonical string encoder.
No authority memo, rewritten scientific primitive, parallel executor or new ABI.
Source/registry epochs, all names/JSON/counts/union coverage, EOF/final admission,
observer completion, canonical framing and per-ID emission order remain.
