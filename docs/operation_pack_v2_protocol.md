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

The language-neutral core registry tuples are
`cell_set_admission`/`cell_set_admission_v1` and
`cell_set_family_admission`/`cell_set_family_admission_v1`. The latter grants
only `request_cell_set_family_admission`: its payload has exactly `kind`,
`sets`, `mode`, and `source`; its set members have exactly `name`, `cells`,
`description`, and `selection_rule`. Core prefixes bare names with `set:`,
sorts normalized sets by name, and reorders each membership to the declared
bundle cell order before hashing. The family identity scheme is
`scworkbench.cell_set.family_admission.v1`; empty families are authenticated
no-ops. The transition remains private until promotion, where core applies all
members and publishes the terminal group, transition, provenance, and registry
receipt in one rollback-capable transaction. `add` retains pre-existing
members in bundle order; `replace` installs the exact requested membership.
Neither mode may alter a provenance-bound set to a different membership.

Read-only core registry state is a separate manifest-declared grant, never a
primitive input or hidden bundle capability. A `registry_reads` declaration
with category `authenticated_core_registry_snapshot`, kind
`feature_set_registry`, and reader `read_feature_set_registry` binds one
declared matrix input and only the named namespace, namespaces, and feature-set
parameters. Selector arrays are radix-sorted and duplicate-free. With no
selector, `all_namespaces` is explicit; each declaration chooses `allow` or
`error` for an empty match, and no fixed namespace allowlist exists.

Core authenticates the exact ordered matrix feature universe, canonical set
rows ordered by namespace then set name, all registry metadata, and
memberships in stored rank order. Selection, content, source, ancestry,
payload-manifest, and descriptor identities enter the request; the receipt
records one matching observed descriptor and a use count of one. Core re-reads
the source immediately before dispatch. The pack receives only a private typed
copy, and the durable payload remains inspectable without the pack through
`wb_operation_pack_transition_registry_reads()`.

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

For Python execution, PyBench records its validated typed-reader ledger in the
separately authenticated runtime sidecar as
`pybench.operation_pack.chunk_observation.v1`. Core independently checks the
observation identity and its request, capability, definition, input-descriptor,
declaration, and exact schedule bindings. The observation is required exactly
when the operation declares chunking and is projected into the same durable run
parameters as the R adapter; it never extends the shared transition receipt.

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
