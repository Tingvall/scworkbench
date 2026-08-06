# PyBench operation protocol v2

`pybench-op-v2` is the only writable R/Python operation protocol. Version 1 is
retired and a v1 request is rejected before Python receives a bundle path.
The machine authority is
`inst/protocol/pybench-op-v2.schema.json`; the examples below it in
`fixtures/valid` and `fixtures/invalid` are conformance inputs, not informal
documentation.

## Authority boundary

R preallocates the session run and issues one non-transferable execution
capability. A `staging_write` capability binds a unique capability ID to the
session ID, run ID, committed-source scientific-state SHA-256, exact private
stage identity, checkpoint generation, requested output identities and a
SQLite/payload mutation allowlist. Such a capability is issued only while an
engine-created session stage is executing under its exclusive mutation lock.
A committed or recipient bundle cannot receive it.

`read_only` has an empty allowlist. R snapshots the database and payload tree
before and after the subprocess and rejects any SQLite, WAL/cache, or payload
effect. Python opens this mode with SQLite URI `mode=ro` plus
`PRAGMA query_only=ON` and keeps caches outside the bundle.

## Isolated transition and receipt

Writable Python runs against a private per-run reflink/copy, never the visible
session stage. Before launch R writes an ephemeral
`.scworkbench-pybench-stage.json` marker into that copy. Python requires the
marker and verifies its protocol, capability, session/run, source attestation,
stage-root identity, and checkpoint generation against the request. The marker
contains no committed-source host path and is destroyed with the transition.
R captures canonical pre/post SQLite schema, ordered table rows,
and bundle-relative payload identities. It derives the actual mutation set,
rejects schema changes and mutations outside an allowed key scope/path, and
then compares the actual set with the receipt `write_manifest`. A descriptor
contains its output binding, mutation class, table/key scope or contained path,
row count, and content SHA-256. SQLite content uses compact JSON row objects
with alphabetically ordered columns; payload content hashes file bytes.

Only a valid, capability-echoing receipt whose manifest exactly equals the
R-derived changes is copied into the session stage. Python failure, missing or
tampered receipts, audit failure, source mutation, and the fault window after
receipt validation all discard the transition. The prior durable checkpoint
generation and visible stage therefore remain retryable.

## Diagnostics

Stable prefixes distinguish the failure boundary:

- `PYBENCH_CAPABILITY_MISMATCH`
- `PYBENCH_SOURCE_WRITE_ATTEMPT`
- `PYBENCH_STALE_STAGING_IDENTITY`
- `PYBENCH_RECEIPT_MISMATCH`
- `PYBENCH_OUT_OF_SCOPE_MUTATION`

Runtime request files contain the mounted stage path, but absolute paths and
Python tracebacks are not copied into persisted provenance.

## Compatibility

| Caller | Target | Result |
|---|---|---|
| v2 read-only | committed source | inspection only |
| v2 staging-write | current bound session stage | isolated audit then publish |
| v2 staging-write | source, recipient, unrelated or stale stage | rejected |
| v1 writable | any bundle | rejected; no compatibility path |

scVI, PeakVI, Palantir fit/project, and protocol hello use this same boundary.
Large matrix inputs remain external ephemeral chunk directories; all durable
model paths and operation outputs remain bundle-relative.
