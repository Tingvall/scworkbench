# Bounded space-result row encoding: prospective budget

Parent `a04de28` has the same runtime and tests as the exact Git-derived installed
`53f1ea8708112b8d07ba6f7e00f6b3a60af4f38b` candidate. No runtime change in
this commit. The complete typed-space workflow's original <=5s budget remains
unwaived; prior392 eight/32-partition medians were10.482/10.921s.

Fresh source attribution, not a timing median, is retained at
`/tmp/scwb-engine-simplification-forge-20261018/typed_space_c826_current_diagnosis`.
Actual10ms profiling gives9.69 sampled seconds: disjoint canonical/serialization
3.29, hashing1.77, SQL1.52, schema/registry1.35, HDF/getter.93, GC.54, other.25,
receipt.04. Inclusive timings overlap and must not be summed. Three whole-file
SHA calls took.024s in the separate census; do not remove them as a bottleneck.
Coordinate reads cover exactly three logical full passes, not partitions times
the source. This evidence predates assembled53f1, so it cannot establish its
current timing or a budget pass.

Proposed change only: `.wb_operation_pack_v3_space_content` already receives a
bounded coordinate matrix. Avoid constructing one R list per row/scalar before
the existing canonical encoder when the existing native row-array encoder can
emit exactly the same bytes. Keep matrix conversion first, the exact sorted
canonical fields, row-major values, existing SHA scheme, all content claims and
checks. Unsupported values/classes/shapes/locale/options retain the literal old
path. Eligibility and temporary capacity are admitted before the native call;
no whole-source read, cache, new authority, identity or protocol is introduced.

Numerical budgets fixed before implementation:

- On eight1650×50 already-read ordinary numeric partition blocks, improve the
  complete semantic content-identity helper by >=50% in fresh alternating old/new
  plain trials (three fresh processes per variant). All bytes/digests must match
  the literal pre-change helper and independent canonical oracle.
- On the existing13199×50 typed-space row-sum operation, improve eight- and
  32-partition complete invocation medians by >=5% versus the exact assembled
  53f1 baseline and in the fresh alternating pairs. Set absolute ceilings to
  .95×the actual fresh baseline medians before runtime implementation. Do not
  substitute profiled durations. The original <=5s target remains separate.
- Maximum whole-process peak RSS must remain <=baseline+10%. Record admitted
  temporary bounds, unchanged source scans/file-SHA counts, exact ordered axes,
  output values/identities and actual source SQL/filesystem purity.
- Exactness/fallback tests cover zero and non-square shapes, cap boundaries,
  reordered/Unicode axes, integer/double/NA/NaN/-0, unsupported numeric values,
  logical/string/complex/list/classed matrices, options and tiny/invalid memory
  guards. Source mutation and rollback checks remain mandatory.

No implementation or measured performance acceptance follows from this budget.

## Measured baseline, frozen before runtime implementation

`T/typed_space_receipt_53f1_baseline_retry1` (T as above) completed three fresh
plain installed53f1 processes; all numeric gates and outer supervisor are zero.
The supervising source is clean budget-only `a4331e9`; R/src are exactly53f1.
Independent old partition preimages, source/envelope/output identities, ordered
values, source SQL/full filesystem purity and a real committed registry mutation
with an unchanged-read positive control passed in each process. Mutation probes
use a separate owned copy, not the timed source. No source runtime was edited.

| Complete measured case | Old median, s | Fixed new ceiling, s |
| --- | ---: | ---: |
| Content identities of eight actual partition blocks | 0.982 | 0.491 |
| Public row-sum invocation, eight partitions | 9.710 | 9.22450 |
| Public row-sum invocation, 32 partitions | 9.491 | 9.01645 |

Fresh matched pairs must also meet the original50%/5% improvements. The original
<=5s invocation target remains MISSED on every baseline trial and is not waived.
Maximum whole-process baseline RSS is287800KiB; its fixed+10% ceiling is316580KiB.
The frozen absolute timing CSV SHA256 is
`75c2979b701664d6a3056e72c7299b0a3644a9e93763bd4f37462341844e1574`;
the RSS CSV SHA256 is
`074a830019d18fee5562b587cfed29195286378781a68d9274cdbad8036faee5`.
The first baseline setup assertion failed before timers because `split()` names
were retained on a dimension-count vector. Its raw old1/outer exit1 remains at
`T/typed_space_receipt_53f1_baseline`. The derivative only unnames that count
vector; seven1650-row blocks plus one1649-row block still cover13199 cells.
The pre-execution mutation-probe correction and Forge/root (not Controller)
review-attribution erratum are retained separately. No retiming result replaces
the failed record, and no scientific value, fixture or budget was changed.
