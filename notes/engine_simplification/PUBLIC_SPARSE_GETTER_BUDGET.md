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
