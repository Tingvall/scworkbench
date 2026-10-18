# Repaired-engine source audit: non-session paths

Audit target: repaired core `8f53e950e6eda4c86b0f4ce6623bc14a1f2e637e`
(runtime `d7232f800190e1c1cb78af0e4591fa53e9003087`). Inspection only:
no runtime changes and no tests or performance runs were performed by this
audit. Root Forge owns session/checkpoint implementation and measurements.

This section records the **initial source audit**, not a claim that every
recommendation below was implemented. The current candidate's actual changes,
retained authorities and measured-versus-qualified status are in the last three
columns of `inventory_remaining.csv`. Development changes and probes followed
this audit. Final coordinated qualification is not yet claimed here.

Current implemented scope (not a final qualification disposition):

- Selected-axis lazy matrix scratch projection, exact axis/native canonical
  encoding, and two plain typed-block copy removals with recursive
  mutable-reference fallback.
- Trusted Python typed-matrix broker readers authenticate once at
  construction, keep supplemental file/registry guards around blocks, and close
  their selected-axis reader on success/error/timeout. Private projections use a
  budgeted owned cache or disposable double BPCells spill. Oversized private
  Matrix Market payloads use bounded native import rather than whole-object
  parsing. Mixed graph/matrix requests use the same scoped readers, with
  aggregate admission for axes, physical plans, responses, owned scratch and
  the existing graph connections. Original physical-axis metadata and native
  row-selector maps are charged before decoding or opening a reader. Native
  bounds are source-reviewed for the recorded BPCells build, not an OS quota
  or a portability qualification of untested native implementations.
- Connection-scoped unchanged-epoch registry/source observations; epochs
  invalidate content observations but do not authenticate backing-file bytes.
  Selected dependency ledger checks replace unrelated-history checks during
  uninterrupted execution. Resume still verifies the full ledger; promotion
  verifies selected complete ancestry under destination and raw stage locks,
  before artifact migration, and retains stage ownership through copying.
- Fresh native-R ordinary-RDS seal reuse is **per output**, not an all-output
  transition waiver. Only supported object/table outputs with a payload manifest
  and no special matrix/model manifests qualify; Python, ABI4 and transitions
  with registry requests are excluded. Final-path bytes, request/receipt binding
  and complete closure still validate. Special outputs and all recovery/deep
  inspection retain semantic reopening; no pack-supplied seal is authority.
- Schema checks reread the ledger/prefix and exact ordered live table/view SQL.
  Only a successful FK/nullability verdict for that exact connection and SQL
  signature is reusable. TEMP shadows and graph-policy calls bypass reuse;
  explicit validation, migration and public schema-status inspection request
  full verification. This is not a schema-version-only memo.
- Canonical character arrays, exact-name/encoding/locale key plans, plain-table
  <=1000-row token batches and eligible native numeric tokens preserve existing
  canonical bytes. Unsupported classes/encoding/numeric ranges fall back to the
  original encoder. Descriptor preimage reuse retains original scheme labels
  and hashes original value/wrapper bytes, not hashes of hashes. Ordinary object
  canonical JSON is still a complete output string, not a streaming-object API.
- Table promotion emits <=1000-row JSON batches and retains existing row/fold
  identities. Graph, special model, registry-request and persisted Python deep
  validation are not relaxed by these changes.
- Graph SQL pages account for the response envelope before admitting a row.
  Tiny byte budgets can therefore change transport partitions and consequent
  observation/receipt-chain identities; graph content identity is unchanged.
  No claim of byte-identical transport receipts is made for those partitions.

Budgets and development probes are retained in `BLOCK_COPY_BUDGET.md`,
`SELECTED_AXIS_BUDGET.md`, `MATRIX_ENCODING_BUDGET.md`, `BROKER_BUDGET.md`,
`CANONICAL_BUDGET.md`, `DESCRIPTOR_BUDGET.md`, `SESSION_BUDGET.md` and
`REGISTRY_BUDGET.md`. These are measured slices, not proof of all primitive paths
or the frozen combined candidate. Final coordinated qualification remains pending.

`inventory_remaining.csv` reconciles all 36 original rows. Row numbers refer
to the prior inventory, not new promises that all listed checks were measured.
The recorded repaired-baseline measurements come from the retained matrix
repair evidence; they are not new engine-wide measurements. In particular,
prior-audit timings on `96cbf880` must not be presented as `8f53e950` timings.

## Initial source findings and current disposition

1. **Fresh transition handoff**: current
   `R/operation_pack_v2_transition.R:77` selects eligible native RDS names;
   `:1132` independently intersects the private freshness list with receipt
   eligibility. Immediate validation at `:1845` still uses `load_payloads=TRUE`:
   only named eligible outputs skip duplicate semantic decoding, while every
   final-path payload hash remains checked. Mixed ordinary/special outputs do
   not turn the special output into an ordinary seal. Recovery supplies no
   freshness list. Output construction still reads RDS to return values.

2. **Fresh R block copies**: `R/operation_pack_v3_transition.R:3425` avoids
   serialization only for fresh ordinary matrix/space values and recursively
   plain attributes. Typed matrix and space callsites use this private helper;
   environments, external pointers, S3/S4/reference and nested mutable objects
   retain serialization isolation. Development aliasing/resource tests and
   measured allocation reductions do not justify global deep-copy removal.

3. **Graph lifecycle authentication, not per-partition**: the graph reader's
   `.wb_operation_pack_v4_sources_assert_current` at
   `R/operation_pack_v4_graph_adapter.R:69` is inside `if (is.null(part))`, so
   it runs at stream completion, **not for each ordinary partition**. It calls
   retained graph SQL identity reconstruction at
   `R/operation_pack_v4_transition.R:138` through `R/graph_lifecycle.R:1`.
   Request creation/audit, executor predispatch/prepublication and stream
   completion have full-graph work; these are lifecycle-counted, not O(K)
   complete scans. `peek()` only queries the requested bounded page and
   `accept(nonNULL)` updates bounded observations and exact ordinal state.
   No other per-page full identity call was found in these callbacks. The first
   draft incorrectly inferred per-partition work from a grep occurrence; this
   paragraph and inventory row 33 supersede that claim. Any future consolidation
   must measure actual boundary passes first. Graph is **unmeasured**, not fixed
   or performance-qualified by this source audit.

4. **Space nested verification**: full-space assertion at
   `R/operation_pack_v3_sparse_membership.R:99` performs HDF5 physical hashing,
   provenance payload identity and optionally selected semantic space hashing.
   It is called during typed-space admission and before/after dispatch. The
   semantic identity allocates one list row per selected cell (`:89`); the
   typed-space grant also retains selected values and typed reads slice that
   in-memory object (`:232`). This is not an O(K * source bytes) reader loop,
   but it remains whole-selected-space admission, unlike the bounded HDF5
   public getter. Establish measured sizes/passes before deciding whether to
   reuse file/content seals or to propose a future versioned representation.

5. **Declared optional snapshots**: registry reads at
   `R/operation_pack_v3_registry_reads.R:477` recreate selected snapshots at
   predispatch and prepublication. Nonzero producer-lineage declarations still
   compute the complete registry fingerprint at
   `R/operation_pack_v3_producer_lineage.R:162`, then reconstruct each lineage
   grant. The matrix repair's zero-grant early return is already correct and
   must not be reimplemented as a new change. Consolidation must preserve
   independently admitted source associations; a checksum from another copy
   is not authority for staged bytes actually consumed.

6. **Partition ledger overhead**: matrix typed reads recompute consumed count
   from all prior records at `R/operation_pack_v3_transition.R:3540`; typed
   spaces do likewise at
   `R/operation_pack_v3_sparse_membership.R:247`. Existing adapter state can
   hold an incremental consumed count while preserving final exact ordered
   coverage and receipt ledger. No cache service or alternate executor needed.

## Primitive-by-primitive inspection and limits

| Surface | Source-anchored finding | Qualification status of this audit |
| --- | --- | --- |
| Matrix | `R/getters.R:19` sparse coercion repaired; `R/getters_matrices.R` scoped plan; `R/operation_pack_matrix_stream.R` canonical streaming | Source-inspected; prior repaired full Xenopus evidence exists, not rerun here |
| Dense space / space_2d | `R/getters.R:425` delegates HDF5 selection; `R/space_payloads.R:122` defaults hash/value checks OFF; writer `:209` normalizes full supplied array then rereads finite values and hashes file at `:260` | Source-inspected; no new isolated space benchmark |
| cell_vector / cell_vector_family | Constructors `R/primitives.R:27/:118` validate full ordinary values; promoter `R/promote_primitives.R:778/:904` persists metadata/order contract; loader `R/artifacts_load.R:3` reconstructs scientific type and row order | Source-inspected; no new large vector/family benchmark |
| relation/path families | Constructors `R/primitives.R:58/:144/:171`; promoters `R/promote_primitives.R:843/:971/:1030`; ordinary materialized primitives and SQL rows, not implicit bounded readers | Source-inspected; no new standalone benchmarks |
| feature_table / obs_table | Constructors `R/primitives.R:230/:259`; initial promotion materialized all row JSON; candidate `R/promote_primitives.R:1352` emits <=1000 rows per insert block using `R/provenance_table_stream.R` | Ordinary primitive still contains full table; bounded row-emission change has focused regression, final qualification pending |
| model_ref | `R/operation_pack_v3_models.R:1` contained-tree admission copies/hashes bytes; `:932` rehashes private tree at read observations; `R/artifacts_load.R:416` handles contained model objects and authenticated file identities | Source-inspected; backend execution and large model trees unmeasured |
| Matrix-model sibling | `R/operation_pack_v3_matrix_models.R:1` binds matrix snapshot and model linkage; optional full source checks at executor admission/publication | Source-inspected; unmeasured |
| External adoption G3 | `R/operation_pack_v3_external_adoption.R:105/:431` retained source snapshot and candidate-tree checks; independent observed mismatch must continue rejecting | Source-inspected; unmeasured |
| Graph | `R/graph_lifecycle.R:1/:69` separates full graph info from bounded public slice; pack reader verifies full authority at stream completion rather than each partition; graph writer `R/operation_pack_v4_graph_adapter.R:91` retains bounded SQL/carriers | Source-inspected; no realistic graph benchmark |
| Registry metadata / feature sets / motifs | `R/operation_pack_registry_reads.R:298` and v3 `:477` reconstruct selected snapshots; genomic provider has additional semantic source associations | Source-inspected; old inventory measured only selected RNA annotations, not all registry types |
| Producer lineage / G4/G5/G6/G7 | `R/operation_pack_v3_producer_lineage.R:147`; `R/operation_pack_v3_phase5_capabilities.R:1027`; `R/operation_pack_v3_derived_axes.R:1242` keep ancestry, ordered axes, grants and sealed closure independent of numerical method | Source-inspected; no new trajectory/derived-axis execution |
| Mixed primitive dispatch | Shared executor composes grants and one transaction; `R/operation_pack_typed_slice_broker.R` uses scoped matrix readers with aggregate existing graph-policy admission, not per-block whole-source authentication | Source-inspected and focused resource seams tested; final installed and actual mixed-Python publication remain separately required |
| Provenance and promotion | `R/promote_primitives.R:247/:358` transaction and workspace; kind-specific identity generation can revisit values while registering ancestry | Source-inspected; root owns lifecycle measurement and changes |
| Reopen / validation | `R/operation_pack_v2_transition.R:1132` recovery validates retained records without fresh seals; `R/validate.R:369` forces full schema structure verification; `R/schema_migrations.R:125` scopes ordinary successful verdict reuse to exact live SQL | Source-inspected with focused regression sources; final recovery/recipient qualification pending |

## Boundedness findings that must not be hidden by a fast matrix case

- A public HDF5 block read need not hash its entire file. Its ordinary metadata
  validation already defaults to no full hash (`space_payloads.R:122`). Moving
  content authority to lifecycle boundaries should not add a hash to this path.
- Ordinary primitive APIs carry full values. Candidate table publication now
  emits row JSON in batches rather than constructing an all-row carrier. This
  does not change the public ordinary-table input memory semantics into a
  streaming-object contract; that would require explicit design.
- A bounded graph SQL cursor/spill and its byte budgets do not prove low total
  lifecycle overhead. Full graph read assertions occur at lifecycle boundaries;
  ordinary page reads do not independently trigger full graph verification.
- Model tree copies can be necessary to contain mutable external assets.
  Eliminating redundant hashes does not authorize loading from an unbound host
  path or publishing different admitted/model bytes.
- Legacy object identity helpers
  (`R/getters_artifact_object_identity.R:3`) independently check descriptor row
  tokens and metadata against physical payloads. Keep that deep verification
  for transferred/reopened state; do not accept self-rehashed claims as proof.
- No universal memoization or timestamp-derived content identity is proposed.
  Scoped ownership reuse must be invalidated on permitted writes, recovery,
  transfer, stale generation or source reassociation.

## Suggested measured slices before implementation decisions

Set budgets on repaired baseline before editing: fast in-memory vector/table
operation with short versus long unrelated history; matrix partition counts
1/4/16; selected HDF5 space read; graph cursor partition counts 1/4/16; contained
model tree read/write with fixed bytes; large ordinary table promotion. For
each retain full pass counts, elapsed/RSS, physical bytes, complete read/write
direct reference and publication overhead. Review admission/publication,
recovery/transfer and explicit deep validation separately. Until those exist,
the table above is source coverage, **not** engine-wide performance qualification.
