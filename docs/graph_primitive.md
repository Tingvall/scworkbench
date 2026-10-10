# Generic graph primitive

`graph` is standalone ordered node–edge–incidence content, not a cell-bound
relation family or knowledge-graph normalization. No biological annotation or
bundle axis is mandatory. Directed, undirected and mixed ordinary/hyperedges,
loops, parallel edges, repeated participation, isolates, empty and disconnected
graphs are represented explicitly.

Stable node, edge and incidence IDs and semantic order are identity-bearing.
Incidence ordinals are dense and zero-based within each edge. Ordinary directed
edges have tail then head; ordinary undirected edges have two members. Directed
hyperedges have tails and heads; undirected hyperedges have at least one member.
Core checks structural closure; interpretation as a tree, layer, time interval,
weight, social link or reaction remains the method's responsibility.

Typed scalar attributes are ordered fields within graph/node/edge/incidence
scopes: bool, UTF-8, canonical signed int64 decimal strings and finite binary64
little-endian hex strings. Explicit null requires nullable. NaN/Inf, duplicate
fields, unknown types or lossy coercion reject. Signed zero remains distinct.

Three path-free canonical JSON v1 identities distinguish content, ordered
optional bindings, and retained descriptor. Empty bindings differ from a named
empty mapping; native omitted associations normalize to an empty array, explicit
null rejects. Multiple independent bindings may associate the same node with
different retained axes, with injectivity within each binding. Sources require
exact snapshot, membership, order and actual retained payload authentication.
Self-rehashed records do not create source authority.

Fresh schema SQLite `graph_sqlite_v1` stores ordered bounded rows and indexes.
The existing promotion transaction retains graph, artifact, lineage and output
closure together. Relocation does not change logical identity. Unsupported
schema versions fail closed; compatibility migration is separate. Getter calls
perform no migrations or durable writes.

```r
graph <- wb_prim_graph(list(list(node_id = "isolated")), list(), list(),
  direction_mode = "undirected")
wb_graph_identity(graph)
# After ordinary public session promotion:
wb_art_graph_info(bundle, artifact_id)
wb_art_graph_slice(bundle, artifact_id, component = "nodes")
```

Whole-object construction/loading and igraph conversion are budgeted
conveniences. Large graphs use public invocation-scoped reader/writer parts;
validation, hashing, source scans, seals and SQLite promotion must remain
bounded. Storage/publication/WAL/spill budgets are distinct from a lower
materialization cap and are resource policy, not graph-size validity limits.

See the installed [graph authoring guide](../inst/sdk/operation-packs/GRAPH_GUIDE.md)
and [ABI4 protocol](operation_pack_v4_protocol.md). The optional igraph adapter
preserves ordinary graphs with homogeneous actual direction and rejects actual
mixed-direction/hypergraph/unsupported or stale carrier conversions. No silent
simplification, projection or attribute loss is permitted.
