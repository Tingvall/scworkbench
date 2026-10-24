# Durable resumable sessions

`wb_session_create()` creates a private, durable workspace snapshot outside its
source bundle.  `wb_session_resume()` verifies the source bundle identity and
the content identities of every checkpointed staged output before returning a
session.  The source bundle remains untouched until the ordinary
`wb_session_promote_current()` transaction succeeds.

Ordinary dispatch authenticates consumed outputs rather than unused siblings,
where the resolver establishes their exact producer binding. Uncertain bindings
and model/graph closures retain broader checks. This intentionally defers an
unused sibling's corruption diagnostic to its consumption or a full boundary;
resume, promotion and explicit validation are still full. Whole-checkpoint
graph, generation and in-memory state binding remain mandatory before dispatch.

The lifecycle API is `wb_session_create()`, `wb_session_list()`,
`wb_session_open()`, `wb_session_resume()`, `wb_session_finalize()`, and
`wb_session_discard()`.  Workspaces are owned by their session identifier and
coordinated with the same exclusive lock protocol as bundle writers.  Each
successful operation is atomically checkpointed only after its run, active
references, staged payload identities, source identity, and runtime-produced
outputs are complete.  An interrupted operation therefore cannot be resumed
as completed.

The default workspace is `./scworkbench_sessions`; set
`options(scworkbench.session_workspace = "/durable/volume/sessions")` for a
machine-persistent location.  Workspaces use symlinks for immutable source
payloads and are consequently not portable independent bundles.  Discarding a
workspace deletes only that owned workspace, never payloads in the source or a
promoted bundle.

Use `wb_session_new()` only for bounded work that is cheap to repeat. Use
`wb_session_create()` with a machine-persistent workspace for scVI, PeakVI,
large embeddings, and every other expensive or long-running chain. Each
successful operation is checkpointed before the next operation starts. A
detached shell or service can protect an R process from terminal closure, but
it does not replace the durable session checkpoint. After a later script or
input failure, discard the old in-memory handle, call `wb_session_resume()`,
and continue from the last complete operation instead of retraining.

Graph outputs are recovered from their retained, contained transition records
and partitions, not from serialized SQLite pointers or compact seals alone.
Core verifies the original checkpoint, receipt, primitive fields, content,
bindings and descriptor before reconstructing process-local graph readers.
The checkpoint generation, metadata and scientific identities are not rewritten.
Only the returned handle's process-mechanical state binding is refreshed after
all recovered graphs pass. Changed source state or payloads still reject, and
failed imports remove only newly owned scratch, preserving the workspace for
diagnosis and a valid restored retry. Public transition inspection/loading is
pack-free, including graph outputs; read-only loading does not modify the bundle.

Promotion is terminal: follow the existing `wb_session_promote_current()` and
finalization lifecycle, and do not attempt to append operations to a promoted
durable session. An opened terminal session exposes its durable promotion
receipt and must not repeat promotion.

After promotion, retain the returned terminal session only for inspection:
`promoted <- wb_session_promote_current(b, result$session, outputs="vector")`;
`terminal <- promoted$session`. Start the next chain with
`next_session <- wb_session_create(b, workspace_root=...)`, then reference
promoted IDs from `promoted$promoted`. Use `wb_session_new()` for bounded work
that is cheap to repeat. `wb_session_resume()` resumes only an active checkpoint;
it does not turn a promoted/finalized session back into an active one.
`wb_session_finalize()` on an already terminal session is an idempotent no-op;
it does not finalize the recipient bundle or start another session.

A runnable core-only example is
[`inst/examples/public_getters_and_continuation.R`](../inst/examples/public_getters_and_continuation.R).
Source it and call `public_getters_and_continuation(new_bundle_dir,
new_workspace_root)`. It promotes a metadata vector, starts a fresh durable
session, selects from that retained vector, promotes a derived set, and reads
its manifest table through the public API.
