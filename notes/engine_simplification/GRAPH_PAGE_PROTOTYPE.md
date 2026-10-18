# Isolated graph-pager prototype

Exact base: `fff50517c9838481ff2a49bb1ebd8f5f20ead8dd`.
Branch/worktree: `perf/engine-graph-pager-forge-20261018`, isolated from frozen
candidate and coordinator's broker prototype. No protocol, schema, identity,
authentication or scientific implementation changes.

Read Sable's complete final minimal mixed-reader design review and source
disposition before acting. Coordinator authorized this isolated implementation
after conditional page-level review; integration still requires exact source
review. This alone does not close aggregate broker memory/disk accounting.

The window/join page query becomes two ordered primary-key range queries.
Headers contain only ordinal and encoded length, capped by
`min(page,max(1,floor(bytes/256)),16384)`. A finite integer length check precedes
an exact prefix loop `n <= bytes-used`, never an unbounded cumulative sum.
Empty headers return without a payload query. Oversized first rows retain the
existing fail-closed resource error. The payload query repeats the original
predicate and range lower bound and adds the admitted final ordinal. Exact
ordinal strings and UTF-8 byte lengths must match before returning payload.
All prior positive finite byte allowances remain valid, including fractional
limits and values above INT_MAX. Only row limits retain their integer ceiling.
The fixed 16,384-header ceiling keeps summed SQLite individual lengths below
2^53; fractional budgets naturally admit integer byte sums without rounding.

A unique private process-local-counter SAVEPOINT holds both queries in one
SQLite snapshot, on ordinary or read-only handles. It nests inside a caller
transaction, releases only its own scope and rolls back only that scope on
errors. No RNG, file, journal-mode, lifecycle or source-authentication changes.
The broader engine's independent source checks and graph canonical validation
remain intact. Tiny-byte page limits can intentionally return fewer rows than
the old maximum: callers already iterate pages, and canonical ordered content
does not depend on partition boundaries.

Prospective coordinator budget, received before changes: default 512-row/1 MiB
pages <=1.2x old +0.1 seconds over 1,000 pages; numeric header carriers bounded
by partition bytes +64 KiB. No performance measurement was authorized or run
here; this prototype does not claim that elapsed budget passes. Focused tests
assert the conservative header carrier bound at 2/256/1MiB/4MiB bytes and both
query plans show primary-key INDEX SEARCH without temporary sorting.

Focused coverage: old/new ordered rows and canonical SQL stream identities;
tiny-byte page reconstruction; gaps and exact int64 ordinals above 2^53 and
near signed-int64 maximum; exact/one-below byte limits; invalid limits; empty
header no payload query; corruption of admitted ordinal/length with own-scope
rollback; read-only database SHA/sidecar purity; caller writes surviving success
and error; outer transaction rollback preserved; no-outer error unwind; and
second-connection WAL mutation between queries observing one coherent old
snapshot then the new committed state after page release.

First development assertion failed because a shortened low-ordinal result is
returned by RSQLite as integer, while a longer old page containing >2^53 values
uses integer64 throughout. The corrected comparison checks exact decimal
ordinals/JSON bytes for differently bounded prefixes, and full data-frame
identity when page boundaries match. No payload or identity rule was weakened.

Only focused source-patch checks are run; no package install, scientific
measurement, full suite, merge, push, container or release operation.
The runner monkeypatches only a disposable development R process. Final
integrated qualification must use the actually installed candidate namespace,
not that source-patch runner.

Literal retained focused command:

```
inst/ci/run_logged_gate /tmp/scwb-engine-graph-pager-forge-20261018/focused.log /tmp/scwb-engine-graph-pager-forge-20261018/focused.exit -- Rscript notes/engine_simplification/run_graph_page_focused.R /tmp/scwb-engine-simplification-forge-20261018/library_frozen
```

Numeric exit 0; final output:
`GRAPH_PAGE_FOCUSED discovered=5 executed=5 passed=5 skipped=0 failed=0`.
This includes the unchanged frozen SQL-stream graph identity contract.
That initial result preceded source review's correction of an accidental
integer/INT_MAX restriction on byte budgets. The amended focused run additionally
compares fractional 2.5/4.5 and >INT_MAX/1e100 allowances with the old query and
retains below-first-row rejection for positive fractional limits.
Amended retained gate uses the same command with
`focused_bytes_amended.log` / `focused_bytes_amended.exit`: numeric exit 0,
`GRAPH_PAGE_FOCUSED discovered=6 executed=6 passed=6 skipped=0 failed=0`.
