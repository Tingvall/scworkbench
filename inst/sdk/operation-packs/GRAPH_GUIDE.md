# Graph authoring: ABI4 / process5

Declare typed inputs and outputs, request readers, compute and emit primitives.
Core owns authentication, alignment, storage, provenance, receipts and atomic
publication. This extension uses the existing executor and supervised broker;
it is not a second execution or authority boundary. ABI3/process4 remain intact.

```r
project <- wb_operation_pack_scaffold(
  "/existing/parent/MyGraphPack", "MyGraphPack", "mygraph",
  "Real Maintainer", "maintainer@example.org", template = "graph")
wb_operation_pack_capabilities(pack_abi_version = "4", kind = "graph")
wb_operation_pack_check(project$path, "contract", trusted = TRUE)
```

Generation is offline, inert and atomic no-replace. Installation and author
tests execute trusted code and require explicit consent; hashes are not a
sandbox. The scaffold demonstrates small matrix → standalone graph,
graph + retained cell annotations → bound graph/table, and graph → table.
Mixed outputs publish their entire declared closure together. Run the installed
`scripts/graph_tutorial.R` to retain the installed-case report.

## Ordered component streams

The ordinary input callback returns `header` and `next_part()`. Consume all
components in order until the final null; a partial read cannot produce an
accepted receipt. A header carries counts and the independently authenticated
content, binding and descriptor identities. Its node IDs are domain-neutral.

```r
graph_summary <- function(readers, writers, params, context) {
  input <- readers$source()
  repeat {
    part <- input$next_part()
    if (is.null(part)) break
    # Compute incrementally; do not save every part in a growing list.
  }
  writers$write_terminal_primitive("summary", wb_prim_obs_table(
    data.frame(nodes = input$header$component_counts$nodes),
    table_type = "graph_summary"))
  list(status = "ok")
}
```

Use `writers$open_graph(name, header)`, `handle$write_part(component, rows)` and
`handle$finish()` for bounded writes. Components are nodes, edges, incidences,
attribute_fields, attribute_values, bindings and binding_mappings, in this
order. Each part obeys its admitted row and decoded-byte ceiling. Empty
components need no fabricated rows. Incidence ordinals are dense, zero-based
within each edge; repeated participation uses distinct incidence IDs. A huge
hyperedge is still many bounded incidence parts, never one giant record.

`wb_prim_graph()` and `writers$write_graph()` are materializing conveniences,
not the large-graph path. `wb_graph_collect()` checks the separately lower
collection budget and rejects oversized graphs rather than silently increasing
the cap. Counts are canonical decimal int64 strings. Attributes are explicitly
typed; encode finite binary64 values with `wb_graph_encode_finite_f64()`.

Byte budgets use decimal strings and bytes, not MiB. `max_staged_bytes` includes
the full NDJSON stream and its compact payload descriptor. `max_spill_bytes`
admits private SQLite scratch, canonical tokens and temporary sort files;
`max_wal_bytes` covers live WAL/journal/SHM; `max_published_bytes` bounds retained
component/canonical bytes and database growth. Core checks journals before
commit and open unlinked SQLite spill descriptors on Linux, not just directory
inventories. Qualification records live peaks and cleanup separately.
These are sampled bounded-operation admission checks, not hard operating-system
quotas: SQLite can transiently allocate beyond a ceiling during an operation
before the following check rejects and cleans up the owned stage.
The bounded SQLite runtime requires Linux procfs for unlinked-file accounting;
absence fails closed, not a claimed cross-platform execution pass. Logical
representation and canonical identity remain language-neutral.
`max_memory_bytes` bounds framework cache/partition reservations and decoded
part admission; it is not an arbitrary-pack-code RSS sandbox. Measured process
RSS includes the loaded R or Python runtime as well as framework and pack allocations.
Report runtime baseline and observed RSS separately from working admission.
The current conservative native defaults are 8 GiB storage/spill/publication/
journal, 64 MiB framework working admission, 8 MiB SQLite cache, 1 MiB decoded
parts, 512 rows and 16 MiB collection; lower declared grants may reject without
declaring a structurally valid graph invalid. Small-case infrastructure qualification
uses deliberately low cache, partition and collect settings, observes actual disk
and cursor mechanisms, and verifies cleanup and exact identities. Large physical
stress and 8x scaling measurements are deferred; small cases do not establish
constant memory for arbitrary graph algorithms or support above host RAM.

## Optional retained-axis associations

Declare `axis_sources` explicitly on each graph output. Core supplies
`context$graph_source_axes[[output]]`, a path-free projection with the exact
source reference/snapshot and axis identities. Use
`wb_graph_binding_from_source(source, binding_id, mapping)`; its mapping may be
partial but must be injective and in graph node order. Multiple bindings may
share nodes, sources or axes; every selected view names a binding ID.
Named empty mappings retain their source and differ from no bindings.

Retained cell_vector and cell_vector_family source authority is independently
verified against actual ordered values/types/metadata and promotion evidence.
Promoted native matrices reuse their existing authenticated producer output,
MATERIALIZES binding, retained snapshot and exact fragment-tree.v2 identity.
Pending session matrix bindings are deferred: promote a terminal output that
retains the matrix before binding a graph; a materialized matrix output may not
itself be promotable. No separate certificate, new persisted anchor or identity scheme
is required. Declare `retained_matrix_axis` with a matrix input, `axis_kind`
equal to `cell` or `feature`, and a null `source_binding_selector`. Core verifies
the complete retained source axis separately from the selected input projection.
The promoted native route is under focused development qualification. No path,
SQL connection, bundle, state-authority handle or author-generated receipt crosses
to a runner. Availability is not authenticity: unavailable associations remain
inspectable but cannot authorize new bound execution/publication.

## Identity, inspection and adapters

Content, ordered bindings and retained descriptor have separate canonical JSON
v1 identities. Logical IDs/order are part of identity; graph isomorphism is not.
Allocated artifact IDs, filesystem paths and SQLite page layout are excluded.
Source authority, actual staged bytes, seals and output closure are independent
checks; a self-rehashed receipt cannot substitute for any of them.

Use `wb_art_graph_info()` and `wb_art_graph_slice()` for bounded pack-free
inspection after promotion, finalization, relocation and read-only reopen.
Graph association authority is reported separately from logical integrity.
Fresh graph-schema bundles are required; backward schema migration is not
implied and read-only opens perform no migration.

Optional igraph conversion supports ordinary graphs with homogeneous actual
direction, including declared mixed mode with homogeneous edges, isolates,
loops, parallel edges and empty/disconnected graphs. Original declared mode is
retained in the carrier.
The reserved versioned envelope preserves IDs, ordering, scalar types and nulls,
and validates live topology/attributes on return. Actual mixed directions, hyperedges,
unsupported attributes, stale envelopes and reserved collisions reject. Never
simplify or project silently. Native adapters also obey materialization caps.

Shared schema parity is not executable backend parity. The explicit ABI4
catalog records graph callbacks and inherited Python grant limitations.
Use the existing SDK cases/assert/run helpers; publication faults work for
graph outputs, while typed-matrix schedule faults require actual typed grants.
Save raw diagnostics, counts and skipped cases: helper success is not package
check qualification, scientific validation or total-memory certification.
