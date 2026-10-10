# Operation-pack ABI4 / process5 graph extension

ABI4 extends the existing authenticated dispatcher/broker with mixed graph and
ordinary primitive IO. It introduces no executor, SQL access or second authority
boundary. ABI3/process4 schemas and identities remain separate and unchanged.

The closed manifest, request, receipt and runtime carriers are shipped in
`inst/protocol/operation-pack-v4.schema.json`,
`operation-pack-transition-request-v4.schema.json`,
`operation-pack-transition-receipt-v4.schema.json`,
`pybench-op-v5-python-runtime.schema.json` and `graph-v1.schema.json`.
The process5 runtime sidecar deliberately retains `python_runtime.v4`; do not
infer a sidecar identity scheme from the process number. Unknown schemes reject.

Graph inputs declare bounded-partition reads, independent binding policy and
explicit selected binding IDs. Requests authenticate complete graph counts and
content/binding/descriptor roots. Outputs declare resource/count ceilings,
binding policy and a closed ordered `axis_sources` list. Retained cell-vector
sources and selected authenticated graph bindings issue path-free axis
projections; matrix-bound source admission currently rejects pending the
separate bounded certificate decision. Unbound matrix → graph is supported.

`readers[[input]]()` returns header and exactly-once `next_part()`. Each ordered
part and ACK binds the request/transition, grant, component, offset and payload.
Broker responses publish by atomic directory rename only after their complete
manifest exists. Invalid or missing ACKs cannot advance core observations.
The reader must consume every admitted component and the terminal null.

`writers$open_graph(output, header)` returns `write_part(component, rows)` and
`finish()`. `write_graph()` is separately budgeted materializing convenience.
Writer seals bind exact counts, stream observations and three logical roots.
Core reimports actual private payloads and independently verifies counts,
resources, declared axis authority, source currentness and complete closure.
Self-rehashed receipts cannot replace payload authentication.

Mixed graph/table or other supported outputs publish in the same existing
transition workspace and promotion closure. Any failure removes the invocation's
owned graph stages and unpublished outputs; it does not discard unrelated prior
session state. Receipt/reopen verification remains pack-free. Getter integrity
and recipient validation independently recompute actual retained content and
available association authority without writes.

Python graph callbacks are executable through the same supervised broker;
advanced ABI3 Python policy restrictions still apply. Shared schema parity does
not authorize unsupported callbacks. Use
`wb_operation_pack_capabilities(pack_abi_version = "4")` for explicit statuses,
and the installed [graph SDK guide](../inst/sdk/operation-packs/GRAPH_GUIDE.md)
for public-only examples and clean installed contract tests.
