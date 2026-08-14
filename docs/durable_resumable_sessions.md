# Durable resumable sessions

`wb_session_create()` creates a private, durable workspace snapshot outside its
source bundle.  `wb_session_resume()` verifies the source bundle identity and
the content identities of every checkpointed staged output before returning a
session.  The source bundle remains untouched until the ordinary
`wb_session_promote_current()` transaction succeeds.

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

Promotion is terminal: follow the existing `wb_session_promote_current()` and
finalization lifecycle, and do not attempt to append operations to a promoted
durable session. A resumed terminal session exposes its durable promotion
receipt and must not repeat promotion.
