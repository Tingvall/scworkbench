# Prospective fresh initializer reuse budget

Baseline source1f853b6a3fb18480c1fe8504877f3b8f839d3fd0 / installed242fdf0.
Before this implementation, target **at least25% lower median complete
wb_init_bundle elapsed over three fresh-directory repetitions**, matched to
old242 on the same filesystem. Whole-process peak RSS must remain at most
old+10%. Record cold loading and OS cache context; no guarantee of eliminating
all cold/package/schema construction cost. Do not extrapolate this component
into a full-workflow result. Prior full769.22s versus171.124s target remains
MISS; no target is waived or retuned.

Narrow route: reuse only the just-created connection after complete migration,
committed schema/FK verification and manifest publication, with exact SQL epoch,
contained actual database identity and generated-versus-actual manifest SHA
guards. Same public four-field bundle and parsed manifest, cache_size=-2000.
Any uncertain observation falls back to the original full open/migrate/recovery/
refresh or fails closed. Ordinary opens, recovery and migration remain unchanged.
No persisted proof, identity scheme, public contract or new validation service.

Source and focused-test preparation only until independent exact source review
and explicit coordinator serial release. No runtime test or measurement yet.
