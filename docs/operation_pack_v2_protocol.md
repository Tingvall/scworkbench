# Operation-pack ABI v2 protocol relationship

Operation-pack ABI v2 is the live, closed extension contract described by
`operation-pack-v2.schema.json`. It reuses the exact byte rules of
`scworkbench.operation_pack.canonical_json.v1` and is not an upgrade of a v1
manifest. V1 and v2 have separate validators, identities, activation paths,
and capabilities; neither may fall back to the other.

The logical v2 transition envelope uses process protocol `pybench-op-v3`, whose
request and receipt records are defined by the two v2 transition schemas in
the installed protocol directory. The in-process R reference adapter and the
installed `pybench-operation-pack-v3` Python CLI implement the same envelope.
Python execution additionally emits `pybench-op-v3-python-runtime.schema.json`,
a backend-specific runtime sidecar that is validated separately and never
changes the language-neutral receipt. Existing `pybench-op-v2` remains the
protocol for current production Python operations and is unchanged.

Scientific state is independently versioned by the bundle schema. A manifest,
process-protocol, or pack-content identity can never substitute for a durable
scientific-state identity. Core allocates durable IDs, grants typed single-use
readers and writers, audits the closed output set, publishes a complete
transition atomically, and retains request, receipt, runtime, dependency,
payload, and semantic identities for pack-free recipient inspection.

For the migrated Statistics terminal `feature_table` and `obs_table` outputs,
whose row count is data-dependent, core issues the request descriptor dimension
sentinel `[0, 0]`.
Both zeros together mean “audit dimensions from the staged primitive”; they do
not claim an empty result. Core still verifies the declared kind, table type,
complete output tuple, semantic constraints, staged payload identity, and the
observed non-negative dimensions before atomic publication. A single zero or a
nonzero claimed dimension retains its literal meaning and must match exactly.

The deterministic installed fixture
`fixtures/operation-pack-v2/identities.json` pins the live schema bytes and all
positive schema-example identities. The test-only package under
`tests/fixtures/operation-pack-v2-reference` exercises the R adapter only; it
is not a scientific operation pack and is never activated ambiently. PyBench
owns the corresponding synthetic Python distribution. It is installed only in
an isolated conformance environment, discovered without target import, and
activated explicitly through entry-point group
`scworkbench.operation_packs.v2`.

Core owns the Python transition directory before and after the subprocess. It
stages canonical typed inputs, grants one bound capability, validates the
shared receipt and separate sidecar, independently re-hashes all output bytes
and mutation evidence, removes private inputs, and publishes the whole closed
output set by atomic directory rename. Interrupted or rejected generations are
removed or deterministically recovered; a completed transition ID is never
replayed by starting a fresh Python process.
