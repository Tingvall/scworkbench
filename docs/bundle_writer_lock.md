# Exclusive bundle-writer lock

Every mutation of committed bundle state is serialized by one portable,
bundle-level writer lock. The protocol covers SQLite metadata, matrix/model and
artifact payload publication, provenance promotion, manifest replacement,
schema and lifecycle migrations, declared ingestion and attachment,
supersession/tombstones, verified purge, model-reference repair, and recipient
finalization.

## Lock representation and ownership

For a bundle `/data/example`, the lock is the sibling directory
`/data/.example.scworkbench-writer-lock`. Atomic directory creation is the
portable exclusion operation. `owner.json` inside that directory records the
schema version, random ownership token, canonical bundle path, PID, host, user,
operation, acquisition time, R version, platform, command, and package version.

The lock is intentionally outside the bundle. It is not scientific state, is
not listed by the manifest, does not move with staged bundle publication, and
is absent from finalized recipient contents. Engine calls are process-local
re-entrant for one bundle. If a process already holds another bundle lock, a
second acquisition is try-lock only: it may acquire a free lock but never waits
while retaining the first. Therefore a cross-bundle wait cycle cannot form.
This also supports a committed source plus its unshared session-staging lock.

The invariant is:

1. acquire the sibling writer lock;
2. prepare and publish payloads under the mutation transaction's rollback
   rules;
3. begin and commit the SQLite transaction;
4. atomically publish derived manifest/finalization state where applicable;
5. release the lock.

Any nested writer must find the same already-held lock. First acquisition while
the bundle connection is already inside a SQLite transaction is rejected. This
means no writer waits for a filesystem lock while holding SQLite transactional
resources.

## Readers

An existing reader connection may continue reading committed SQLite state
during a writer; it sees SQLite's normal pre-commit or post-commit snapshot and
never gains mutation authority. Session staging takes the source lock only
briefly while checkpointing and copying one coherent committed snapshot, then
releases it before operation execution. Computation and writes after that point
use only the session's private staging bundle.

A new writable open runs guarded migrations and therefore waits for the writer
lock. Recipient `read_only = TRUE` open is stricter: it refuses while any
writer lock is present because a transfer/immutable view must be stable.
`wb_recipient_readiness()` likewise reports `ready = FALSE` for an externally
owned active writer. After finalization and lock release, immutable recipient
open proceeds normally.

## Timeout and diagnosis

Acquisition is bounded by
`options(scworkbench.writer_lock_timeout_seconds = 10)`; polling defaults to
`options(scworkbench.writer_lock_poll_seconds = 0.05)`. A timeout reports the
bundle and lock paths, owner liveness, PID, host, operation, acquisition time,
and age. Inspect without mutation using:

```r
wb_bundle_writer_lock_info(bundle_or_path)
```

Acquisition never deletes or steals an existing lock, including a stale
candidate.

## Crash and stale-lock recovery

`wb_bundle_writer_lock_info()` reports a same-host owner as `live` or `dead`.
Remote/unverifiable owners are `unknown`. A dead same-host owner is immediately
a stale candidate. An unknown owner becomes a stale candidate only after
`stale_after_seconds` (default 3600), and still requires an explicit override.

Recovery is a separate administrative action:

```r
wb_recover_bundle_writer_lock(
  bundle_or_path,
  confirmation = "RECOVER STALE SCWORKBENCH WRITER LOCK"
)
```

A verified live owner is always refused. An unknown owner additionally requires
`allow_unknown_owner = TRUE`. Recovery atomically renames the observed lock to
a quarantine path, verifies that its ownership token is unchanged, and only
then removes it. If ownership changed, the mismatched lock is restored rather
than deleted.

## Covered public boundaries

The provenance and ingestion boundaries acquire the lock before invoking their
low-level writers. Direct lifecycle boundaries acquire it before migration or
transaction work. The explicitly covered public routes include:

- `wb_init_bundle()` and all `wb_bundle_from_*()` constructors;
- `wb_attach_*()`, `wb_ingest_*()`, and guarded registry mutation;
- `wb_promote_analysis()`, `wb_session_promote_current()`, and client
  promotion;
- `wb_refresh_manifest()` and `wb_migrate_artifacts()`;
- `wb_entity_supersede()`, retraction/rejection/ephemeral transitions,
  `wb_art_delete()`, and `wb_unsafe_purge_ephemeral_entity()`;
- `wb_repair_model_ref_paths(dry_run = FALSE)`;
- `wb_publish_app_bundle()` and atomic staged destination promotion;
- `wb_finalize_recipient_bundle()`.

Low-level guarded writers assert both valid provenance mutation authority and
ownership of the matching bundle lock.
