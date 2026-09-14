# Operation-pack ABI v2 protocol relationship

Operation-pack ABI v2 is the live, closed extension contract described by
`operation-pack-v2.schema.json`. It reuses the exact byte rules of
`scworkbench.operation_pack.canonical_json.v1` and is not an upgrade of a v1
manifest. V1 and v2 have separate validators, identities, activation paths,
and capabilities; neither may fall back to the other.

The logical v2 transition envelope uses process protocol `pybench-op-v3`, whose
request and receipt records are defined by the two v2 transition schemas in
this directory. Phase 2A implements that envelope for the in-process R
reference adapter. It does not implement the future Python transport. Existing
`pybench-op-v2` remains the live protocol for current production Python
operations and is unchanged.

Scientific state is independently versioned by the bundle schema. A manifest,
process-protocol, or pack-content identity can never substitute for a durable
scientific-state identity. Core allocates durable IDs, grants typed single-use
readers and writers, audits the closed output set, publishes a complete
transition atomically, and retains request, receipt, runtime, dependency,
payload, and semantic identities for pack-free recipient inspection.

The deterministic fixture
`fixtures/operation-pack-v2/identities.json` pins the live schema bytes and all
positive schema-example identities. The test-only package under
`tests/fixtures/operation-pack-v2-reference` exercises the R adapter only; it
is not a scientific operation pack and is never activated ambiently.
