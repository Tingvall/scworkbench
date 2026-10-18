# Public sparse getter: prospective budget

Baseline: installed 76e217a, finalized Xenopus bundle, 31,535 features by
128 cells, default 256 MB dense guard. One public read took 2.920 seconds;
Rprof attributed 80.07% inclusive time to sparse replacement from a dense block.
All 104 normalized reference-comparison blocks took 319.290 seconds.

Before implementation, target at least 3x improvement and at most 1 second for
the same 128-cell read, and at most 120 seconds for the unchanged complete
comparison. Single-run measurements are noisy; record misses, not adjusted goals.

Sable policy review permits replacing the sparse result only for a complete
unique, nonmissing requested axis in zero mode. Continue subsequent fragments
in their existing order: later explicit zeros must still overwrite earlier
values. Duplicate, partial and NA-mode behavior remains on the existing path.
Keep feature-before-cell metadata parsing/error order. No identity, scientific,
authentication or public-interface change is proposed.

The subsequent retained-source HVG diagnostic (218.654 seconds including Rprof
and four prior runs, not a matched trial) attributed 63.86 sampled seconds to
`replCmat4` in the private multi-fragment reader. Before changing that assembly,
target at least 50% less matched assembly time and an actual workflow HVG phase
at most 132.899 seconds (20% below the 166.124-second final76 phase).
Use sequential sparse concatenation only for full-row, disjoint-column complete
coverage. Do not retain all materialized blocks or open all native iterators
together. Old output, replacement output and one block are the live scientific
carriers, as in the existing sparse replacement; drop the block before final
column reordering. Overlaps, partial rows and unsupported selections retain the
old loop. Many-fragment repeated concatenation still copies growing results;
this is not a claim of optimal arbitrary-fragment scalability.
