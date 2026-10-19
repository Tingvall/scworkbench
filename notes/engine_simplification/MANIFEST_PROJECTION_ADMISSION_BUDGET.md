# Conservative projection admission: preimplementation scope and budget

This isolated branch starts at `9e8723f`, the f6 scalar-batch implementation
and its already frozen result note. It includes **no** ASCII serializer, graph
handoff, numeric memo, same-owner SQL reuse or other rejected experiment.

## Actual parent and prospective limits

Actual f6 installed source is `f6b560558519afc6617c98457f63903a230806ab`.
`/tmp/scwb-engine-simplification-forge-20261018/manifest_json_batch_f6b5605_candidate_measurement`
retains three fresh large snapshots 4.975/4.724/4.701 seconds (median4.724),
maximum six-process RSS199636 KiB, and tiny median.387 seconds. Its fixed
large-budget gate failed; identities, purity and distinct census passed.

Before any projection-admission implementation, freeze these follow-on limits:

| Criterion | Frozen ceiling |
| --- | ---: |
| Complete large snapshot median seconds | .90*4.724 = 4.2516 |
| Maximum six-process peak RSS KiB | 1.10*199636 = 219599.6 |
| Complete tiny snapshot median seconds | 1.10*.387+.02 = .4457 |

Use the same six fresh-process, no-warm-snapshot scope, installed/source/harness
proofs and independent old 46-table identity oracles as the actual parent.
Prior4.42255/222657.6/.5128 and historical4.192/.160 limits remain visible,
unwaived; numerical misses must retain failed sidecars. No revised baseline or
posthoc threshold is authorized to hide a miss.

## Small proposed change, not implemented

The current scalar projection replaces TEXT over256bytes with an empty
placeholder, BLOBs with zero-length blobs, and independently retains SQL type
descriptors for the original deferred-value stream. Its existing admission
query charges each column either zero or `octet_length(value)+64` when a TEXT
cell is at most256bytes. Therefore each column contributes at most320 bytes
under the **existing** resource model.

For the next logical fetch let N=min(chunk_size,count-n), C=column count.
Compute coarse_text_bytes=320*N*C before reading any source values. Only if

    N*(24C+32) + coarse_text_bytes + cache*1024 + 8P + 65536 <= M

may the engine omit the extra SQL COUNT/SUM admission query and use that
strictly conservative bound. Otherwise execute the original actual-admission
query and guard unchanged; do not reject a formerly admissible narrow case
merely because the coarse upper bound did not fit. No general cache, helper
framework, new authority, protocol or public setting is proposed.

This changes neither the fetched rows/columns, chunk size, row order, type
promotion, deferred TEXT/BLOB reads, source authority/finish, literal JSON,
identity fold nor wire/resource ceilings. Exact row-count checks and the
existing final native observer continue to reject changed sources. This is
not timestamp-based authority or omitted payload validation. All new numeric
bounds must be finite before they can admit a fetch.

Required focused evidence: independent old identity; actual coarse and tight
fallback branches; no read before admission; tiny, huge deferred, mixed types,
wide/custom/inherited budgets; source mutation, cursor/fault cleanup and retry.
Separate observational census must distinguish omitted admission queries from
ordinary source data fetches; do not claim kernel I/O savings from hook counts.
Sable precode assessment and exact implementation review precede qualification.

## Excluded serializer experiment

`c132890ae7b0a9a05e6710797c7eeee7f81e53ed` remains frozen on its own branch.
Its 16/16 focused tests passed, but the three plain large observations were
5.901/5.934/5.805 seconds (median5.901), versus its4.2516 ceiling. Peak207292
KiB and tiny.355 passed. All15 gate sidecars were zero except fixed-budget
comparison one, with outer one and separate census zero. No scientific or
source-purity failure occurred. This is a timing rejection, not a claim about
an unmeasured causal mechanism. Its original logs/harnesses remain unchanged.
The fixed-result CSV SHA-256 is
`6ad286e8185e5181b92f530465bd8c72e368b500c198e00afc3be96bd0f5e348`.
No ASCII helper code is selected into this projection-admission branch.

## Precode review correction: reserve actual fetch capacity, not remainder

Sable identified a concrete concurrency seam before any implementation:
COUNT and the source cursor are not guaranteed to share a snapshot. A foreign
insert after COUNT can make the final `dbFetch(n=chunk_size)` return more than
the old expected remainder. Rejecting its row count after decoding is too late
for a predecode reservation based on that remainder.

Consequently, the proposed coarse bound above is superseded as follows:
**N is the full actual requested fetch capacity `chunk_size` on every fetch,
including the last partial chunk**, not `min(chunk_size,count-n)`. Charge all
N carrier slots and320*N*C bytes. If that does not fit, retain the original
actual-admission query and guard. Do not shorten the actual fetch to hide a
concurrent insert or change any row-count/source-observer check. Observational
hooks must call N a reserved capacity, not an observed row count. This stricter
precode correction changes no numerical budget and introduces no runtime code.
