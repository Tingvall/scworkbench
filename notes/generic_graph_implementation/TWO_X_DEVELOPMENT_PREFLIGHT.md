# Prospective 2x diagnostic disk envelope

Only the 22000-node development diagnostic is covered, not final8x. Exact R
runtime is9a11d1f, source axis is the original90000-cell fixture; its original
setup record is preserved. The measurement record and loaded namespace hash
are independently checked. Canonical bytes must be measured after execution;
the count estimate is not a passing size result.

This fixed generator emits one64KiB unescaped ASCII value per node, plus bounded
node/incidence/mapping identifiers and two small typed attribute values. Allow
2GiB each for canonical tokens, a graph scratch/retained SQLite image and a
complete NDJSON copy: at22000 nodes this includes record/index/overflow-page
padding beyond the generator's less-than70KiB encoded records per node. Source
database clones are separately allowed1GiB each. No arbitrary input fields or
new complete axis arrays enter the measured process.

Writer/validation phases allow two scratch/token allocations and transport plus
source clones. Promotion/checkpoint is the larger overlap: scratch, old and
pending/final transport copies, destination main/WAL, source clones and temporary
sort/token work. The prospective combined upper envelope is **16GiB**, including
padding for these simultaneous lifetimes. Writer scratch is retired before
independent transport import, and pending payload rename is not a further copy.
The2x sampled trace will be used to check these assumptions and determine final
node count and a separate final phase envelope; it does not replace that envelope.

Preflight must show available bytes >=16GiB envelope +8GiB reserve before launch.
The monitor records available bytes and sampled allocated/logical storage;
short-lived files between samples may be missed. Runtime separately enforces
WAL/scratch/token/storage admission including open-unlinked SQLite files.
If evidence contradicts the envelope or reserve, stop the affected diagnostic
and retain its failure, rather than deleting unrelated artifacts or using tmpfs.

Both the fixed700235776-byte RSS ceiling and the stricter exact-candidate
699392000-byte ceiling apply. Canonical floors remain1400471552/5601886208 bytes.
Final8x and complete suites remain held until the complete tuple stabilizes.


2026-10-11 owned-transition-copy correction: actual source inventory is recorded
in evidence/314_owned_transition_copy_disk_preflight.json. Per clone reserve the
source database image, block-rounded manifest and the complete owned transition
record tree. The original tree charge is65536B; complete clone charge400080896B,
which fits each existing1GiB clone slot without raising the16GiB envelope.
Charge each simultaneously retained clone once in writer/validation and
promotion/checkpoint overlaps; retained clones and their owned transition records
remain present after graph scratch retires. Runtime admission includes this
private clone reservation when checking graph scratch/token/temporary spill.
For a different/larger source tree recompute the copy charge before launch and
reject if existing clone slots or the fixed free-space reserve do not hold.
Final8x requires a separate complete phase forecast at the final tuple; this
2x correction is not an8x admission or a measured RSS result.
