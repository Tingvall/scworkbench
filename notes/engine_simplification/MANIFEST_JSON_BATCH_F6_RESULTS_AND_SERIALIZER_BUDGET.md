# Actual f6 batch result and preimplementation serializer budget

Installed source `f6b560558519afc6617c98457f63903a230806ab` passed 13/13
focused tests across four files, zero skips/failures, with eight gate sidecars
and outer exit zero. Log SHA-256:
`7e6fbbea28d60b77cacb4817650e0816b115d2c785782f5db8094015e10d4757`.
DLL SHA-256:
`882a1390c736c1d85093d6020fae4b1a682fd94a07d181a07a3aff16a7a8432f`.
Sable source review `/tmp/scwb-sable-manifest-batch-source-f6b5605-20261019/review.json`
SHA-256 `f3cde1c8fdbb6039099349629bd3f1099ccb668c2e7d47a2415bcd11feadc61b`
cleared focused qualification only, not performance acceptance.

`T` = `/tmp/scwb-engine-simplification-forge-20261018`.
Matched evidence `T/manifest_json_batch_f6b5605_candidate_measurement` retains
15 numeric gates: fourteen zero, fixed-budget comparison one, and outer one.
No retiming or relaxed threshold. Three fresh large observations:
4.975/4.724/4.701 seconds; three tiny observations: .388/.387/.356 seconds.

| Criterion | Actual f6 | Original frozen limit | Result |
| --- | ---: | ---: | --- |
| Large complete snapshot median seconds | 4.724 | 4.42255 | MISS |
| Maximum whole-process peak RSS KiB | 199636 | 222657.6 | PASS |
| Tiny actual 46-row snapshot median seconds | .387 | .5128 | PASS |
| Historical large threefold target seconds | 4.724 | 4.192 | MISS |
| Historical tiny fourfold target seconds | .387 | .160 | MISS |

Result CSV SHA-256:
`2652dbea8fa91fe0ae0fe8609f766b5c5d0fc6b34a1d08ff143c39cace402585`.
All six plain identities match both independent original oracles exactly.
Full original/owned SQLite inventories remain unchanged. The subsequent,
distinct census exited zero, including exact preallocation/carrier equations,
aggregate byte reservation and policy restoration. Fragment-feature scalar
events fell from 500 to 100 for 250000 rows. This is an actual hook count,
not a kernel-I/O count or a measurement of all source passes.

**The batching experiment remains unselected.** It earned a 9.2% median
improvement against its actual parent, not the required 15%.

## Prospective next change (no implementation yet)

Investigate bounded vector assembly of the SAME jsonlite row-array bytes only
for already admitted plain ASCII character/integer/logical columns, with the
existing field-key tokens, order and missing-value rules. Unsupported values,
REALs, classes, encoding/escaping, dimensions or resource limits must take the
unchanged serializer. No scientific parameter, identity, protocol, source
authority, fetch/fold boundary, graph wire limit or publication rule may change.
No new C dependency, cache, template service or executor is proposed.

Before any implementation, require independent source/resource review of the
exact subset and carrier model. In particular, all candidate-selection scratch
must be released before serialization; speculative predicate vectors must fit
the existing 128N allowance. Additional row-string headers plus output copies
must fit inside the SAME existing 8*encoded reservation, admitted before string
assembly. No inference from average values or a larger public memory quota.

The next candidate must satisfy ALL of these new prospective ceilings, frozen
from the actual six plain f6 measurements before new serializer code:

- Large snapshot median <= .90 * 4.724 = **4.2516 seconds**.
- Maximum whole-process peak RSS <= 1.10 * 199636 = **219599.6 KiB**.
- Tiny snapshot median <= 1.10 * .387 + .02 = **.4457 seconds**.
- Same exact independent original fingerprints, default first-call timing scope,
  full source purity, effective resource admission and failure/retry contracts.

The previous 4.42255/222657.6/.5128 limits and historical 4.192/.160 misses are
not erased or waived. A component result cannot establish graph or whole-Xenopus
performance. A separate current-source profile may guide the choice but must
not be substituted for these fresh plain medians.
