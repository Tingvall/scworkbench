# Incomplete SDK and resource checkpoint

Local implementation checkpoint under accepted design `fa929601c7b8c67c2947b400341bfd90bd80d925`.
This is not final qualification, release acceptance or a completed handoff. Use
this file's enclosing commit as the exact core source pin. Primary checkouts,
official packs and the standard profile remain unchanged; nothing is pushed.

## Boundary changes

- Existing broker: omitted ordinary typed grants are an empty collection, and
  graph response manifests become visible by atomic directory rename, before
  exact authenticated ACK admission. No alternate executor.
- Public additive SDK 1.1/ABI4 graph scaffold, capability inventory, installed
  tutorial and guide. The ABI3 default and existing authoring interface remain.
  Reference operations use public constructors/readers/writers only and preserve
  existing attributes when annotating graphs.
- Resource admission includes compact transport descriptors, SQLite main growth,
  open/unlinked temporary spill and independent journal/WAL/SHM bytes. Source
  metadata scratch participates in combined spill admission. Checks are sampled
  bounded-operation admission, not hard OS quotas: SQLite operations may briefly
  overshoot before the check and rejection. Memory reservations cover framework
  cache/decoded parts, not an arbitrary pack-process RSS sandbox.
- Linux procfs is required for this bounded SQLite runtime; its absence rejects
  before allocating a stage. This is an explicit backend boundary, not a claim
  that pure graph canonicalization requires Linux.
- Fresh graph/object closure tables are registered in the central deferred-FK
  schema contract. Migration 002 excludes the four tables first created in 011.
  Generated graph/getter/schema/semantic/SDK references are updated.
- Matrix-bound graph authority remains fail-closed pending Controller's source
  certificate decision. Matrix-to-unbound-graph is not matrix binding acceptance.

## Literal focused evidence

All logs and numeric sidecars are retained under `evidence/`, including failed
development probes; none is rewritten. No complete suite or package check ran.

| Gate | Command/result | Applicability |
| --- | --- | --- |
| 74 | broker response/ACK unit: passed=1, skipped=0, failed=0; exit 0 | Atomic visibility and substituted ACK rejection |
| 75 | installed Python broker composite repeated three times: PASS; exit 0 | Earlier ff0f8d2 runtime, not final Python peer |
| 86 | installed graph scaffold/tutorial: discovered=6, executed=6, passed=6, skipped=0, failed=0; exit 0 | Installed core from gate84; rerun on clean checkpoint required |
| 88 | publication budget rollback + complete staged descriptor budget: passed=2, skipped=0, failed=0; exit 0 | Generic transaction and independent reopen |
| 89 | `Rscript notes/generic_graph_implementation/run_focused.R`: discovered=27, executed=27, passed=27, skipped=0, failed=0; exit 0 | Before source-metadata combined-spill correction |
| 90 | actual open SQLite sort plus metadata scratch, cleanup/retry: passed=1, skipped=0, failed=0; exit 0 | Focused combined-spill correction |
| 91 | `Rscript inst/dev/regenerate_public_docs.R`; exit 0 | Deterministic generation after graph public/docs inventory additions |
| 92 | `Rscript notes/generic_graph_implementation/run_focused.R`: discovered=27, executed=27, passed=27, skipped=0, failed=0; exit 0 | Includes the corrected periodic and final combined metadata-spill check |

Current peer is clean PyBench `059374aea9c6f0122e3fc0b4272a2bee43cfb593`;
its runtime code remains the independently installed `3e41562` wheel (SHA-256
`6d56ce9546fe641b7a70431279aa10691bfc9d3f95bfeaf8bbbbe56628783042`).
The two subsequent commits change tests only. Five shared schemas and the
synthetic mixed fixture retain the CHECKPOINT_02 digests. Final wheel identity
and live installed execution must be recorded on the final exact tuple.

## Focused review disposition

Sable `/root/sable_graph_design` inspected the core resource boundaries and gate89
raw log/exit read-only, without rerunning tests. She found the combined source
metadata/spill gap, then confirmed periodic and unconditional final flushed
admission in corrected source SHA-256
`e9435f5fbfab41498171b1a825c98366c278ddd699c64d60f3ccd54482b5a247`.
She found no additional resource-granularity defect. This is focused review,
not final approval of the entire feature.

Separately Sable reviewed clean PyBench `059374a` source and tests, without
execution. Descriptor accounting, page caps, procFD samples, automatic writer
failure cleanup and refused PRAGMA constructor cleanup had no new finding.
The late-scale application fault proves explicit abort; separate write/finish
failure tests prove automatic abort. Reviewed `graph_parts.py` SHA-256:
`c4cbc8c2e65abb475bdfbd65c31c6033f0ab74cccee1a0541d199cfe0b1e61ef`.

## Remaining authorized acceptance work

See [REQUIREMENTS_EVIDENCE_MAP.md](REQUIREMENTS_EVIDENCE_MAP.md). Finish this work;
do not use the checkpoint as a completed handoff. Do not launch final full suites
or eight-times-total-memory qualification on a changing tuple. No merge, push,
tag, container/SIF build or official-pack/profile change is authorized.
