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

An operation may declare the closed `data_dependent_table_v1` dimension policy
for a terminal `feature_table` or `obs_table` using the
`terminal_primitive_v1` storage profile. For every conforming namespace, and
only for outputs carrying that authenticated declaration, core issues the
request descriptor dimension sentinel `[0, 0]`.
Both zeros together mean “audit dimensions from the staged primitive”; they do
not claim an empty result. Core still verifies the declared kind, table type,
complete output tuple, semantic constraints, staged payload identity, and the
observed non-negative dimensions before atomic publication. A single zero or a
nonzero claimed dimension retains its literal meaning and must match exactly.

Optional language-neutral manifest sections also define public interface
metadata, closed parameter-binding policies, retained run-parameter
projections, and one closed feature-chunk contract. The feature contract binds
a matrix input, feature-sequence parameter, positive integer size parameter,
terminal feature-table output, global P-adjustment parameter, and
`row_bind_then_global_p_adjust_v1`. Core observes each typed reader call and
requires the calls to be the exact contiguous partition before it creates a
receipt or publishes payloads. Retained chunk evidence records the requested
size, observed call count, batch sizes, and exact ordered batches. These fields
are identity-bearing canonical manifest content; operation or namespace names
never select their semantics.

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
