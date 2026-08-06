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
