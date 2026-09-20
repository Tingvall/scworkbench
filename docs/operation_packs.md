# Operation packs

Operation-pack protocol v1 admits independently installed R packages and Python
distributions. Protocol support and installed runtime support remain different:
this checkpoint activates R packs in-process and Python packs through the
audited PyBench operation-pack CLI. A pack operation is never a parallel runner:
after backend-specific
activation it uses the same `wb_session_run_op()` path, typed inputs,
effective-cell coverage, private staging, promotion, provenance, replay,
validation, and reproduction contracts as a core operation.

Pack parameter definitions using `cell_set`, `cell_ids_or_set`, or
`list_or_cell_set` enter the engine's central named-set resolver. A named set is
persisted as a role-specific scientific `CONSUMES` dependency with exact
source/effective membership identity; a literal cell-ID vector is not. Pack
runners must not create their own provenance bindings.

The authoritative machine-readable manifest schema is installed at
`inst/protocol/operation-pack-v1.schema.json`.
The authoritative byte contract is
`inst/protocol/operation-pack-canonical-json-v1.md`; its scheme identifier is
`scworkbench.operation_pack.canonical_json.v1`.

## ABI v2 R and Python reference contract

ABI v2 is a separate, fail-closed activation path. Its live manifest, request,
and receipt schemas are installed under `inst/protocol/` and their relationship
to v1, `pybench-op-v2`, `pybench-op-v3`, and durable scientific state is
recorded in `docs/operation_pack_v2_protocol.md`. V2 does not reinterpret a v1
manifest or change any existing v1 identity.

An R v2 package uses the same explicit installation and activation APIs, but
its entry-point runners have the closed signature:

```r
function(readers, writers, params, context)
```

`readers` and `writers` are named, opaque, single-use core capabilities. They
expose typed copies of declared inputs and sanctioned writers for declared
outputs only. They never expose a bundle root, SQLite connection, registry,
provenance writer, or final publication path. Core resolves dependencies
offline, allocates output IDs, validates the request and receipt, audits the
complete private tree and every scientific binding, and publishes the entire
promotion group or none. Failed activation restores the exact process-local
catalog preimage; failed execution leaves no transition payload or registry
claim. Finalized transition outputs remain available through
`wb_operation_pack_transition_outputs()` and
`wb_operation_pack_transition_load()` without the pack installed.

ABI v2 registry outputs remain requests, never write capabilities. The legacy
`cell_set_admission_v1` request and the generic
`cell_set_family_admission_v1` request are authenticated in the private
transition, then applied by core only when their complete promotion group is
published. A family carries an ordered (possibly empty) normalized set array,
one family-wide `add` or `replace` mode, and identity-bearing source metadata.
Core canonicalizes set names lexically and each membership in bundle cell
order, while preserving the original request and per-member identities in the
committed receipt. Registry effects, selected terminals, transition payloads,
provenance bindings, and receipts commit or roll back together. A pack-free
recipient can inspect those receipts with
`wb_operation_pack_registry_receipts()`.

ABI v2 read authority for feature-set registries is declared separately under
`registry_reads`; it does not change an operation's public input tuple. The
grant binds a declared matrix and declared selector parameters, authenticates
the ordered feature universe, complete registry metadata, and stored-rank
memberships, and is re-read immediately before dispatch. No selector means all
namespaces, and the manifest explicitly chooses whether an empty match is
allowed. The single-use `read_feature_set_registry` capability returns a
private typed copy, never a bundle handle. Finalized snapshots and their
request/receipt identities remain available pack-free through
`wb_operation_pack_transition_registry_reads()`.

Python v2 activation authenticates the original manifest in the installed
distribution through the explicitly configured PyBench interpreter. Execution
uses the installed `pybench-operation-pack-v3` CLI: core owns a private staging
generation and typed JSON inputs, while PyBench returns staged payloads, the
shared language-neutral receipt, and a separate Python-only runtime sidecar.
Core independently verifies all three, retires the input capability, and
atomically publishes the complete record or nothing. The sidecar schema is
installed as `pybench-op-v3-python-runtime.schema.json`; it does not add fields
to the shared receipt. For a chunk-declared operation, core independently binds
the authenticated sidecar observation to the request, capability, operation,
input descriptor, and exact requested batch schedule. The observed calls then
populate the same retained chunk parameters as an in-process R pack. A missing,
smuggled, substituted, or inconsistent observation rejects the transition
before publication.

The source-tree package `tests/fixtures/operation-pack-v2-reference` is a small
synthetic conformance pack. It exercises all accepted R readers, writers,
output categories, storage profiles, cell-set admission, authenticated
feature-set-registry reads, mixed output groups, and dynamic input-metadata
dependency resolution. It is not installed by
scworkbench, is never activated ambiently, and makes no scientific-method
claim.

The synthetic Python reference distribution lives only in PyBench's test
fixtures and is activated explicitly during cross-repository conformance. It
does not create an official scientific pack. The former core operation
`py_protocol_hello` is no longer registered or discoverable: its implementation
is retained privately only so historical records remain intelligible. Current
protocol conformance uses explicit fixture packs.

## ABI v3 bounded axes, typed slices, and ancestry

ABI v3 is an explicit successor tuple; it does not reinterpret ABI v1 or v2.
Its complete language-neutral contract is documented in
`docs/operation_pack_v3_protocol.md`. In summary, v3 adds exact authenticated
cell/key output cardinality, a generic bounded typed-slice reader over the
canonical matrix getter, and a single-use core-attested read of the current
provenance of an artifact-backed typed input. Packs own partitioning,
scientific work, merge, and summary logic.

The same additive ABI now includes five method-neutral capabilities: a
self-linked contained-model reader (G1), sibling-bound contained-model
publication (G2), ordered retained-artifact collections (G4), ordered named
cell-axis collections (G5), and optional parameter-resolved display/endpoint
groups (G6). These capabilities expose private typed copies and identities,
not bundle, SQL, registry, committed-path, or state-authority handles. Their
closed shapes, limits, call disciplines, and durable lifecycle are specified
in `docs/operation_pack_v3_protocol.md`.

R packages register the same closed runner interface through the existing
entry point:

```r
wb_operation_pack_register(
  system.file("scworkbench", "operation-pack.json", package = "YourPack"),
  operations = list(`yourpack::score` = run_score)
)
```

Python v3 activation continues to authenticate the original installed
manifest and uses the closed `pybench-op-v4` process boundary. Both backends
publish the same v3 request and receipt evidence atomically. The engine rejects
cardinality, typed-slice usage, ancestry, source-currentness, payload, or
receipt disagreement before analytical state becomes visible.

## Trust and activation

Installing a package or distribution does not activate it. scworkbench never
scans the R library or Python environment for packs. The installed-R-package
APIs retain their exact meaning: validation and loading both load the named R
package and invoke its exported entry point, so each is an explicit trust
decision:

```r
wb_operation_pack_validate("YourPack")
wb_operation_pack_load("YourPack")
wb_operation_packs()
wb_operation_pack_inspect("your_namespace")
wb_op_interface("your_namespace::operation")
```

Backend-neutral structural validation reads JSON only and performs no package
discovery, import, activation, or bundle mutation:

```r
wb_operation_pack_manifest_validate("operation-pack.json")
```

For a Python manifest this report retains the exact declared distribution name,
adds its deterministic PEP 503 normalized name, freezes the pack/definition
identities, and reports runtime activation as false. Supplying already-observed
`runtime_identity` can validate distribution and entry-point metadata without
importing the target. It still does not activate Python and makes no claim that
the manifest came from, or matches, an installed distribution.

The explicit backend-neutral activation dispatcher is:

```r
wb_operation_pack_activate(
  "operation-pack.json",
  python = Sys.getenv("SCWORKBENCH_PYBENCH_PYTHON")
)
```

For R it authenticates the supplied manifest against the installed package and
delegates to `wb_operation_pack_load()`. For Python, caller-supplied runtime
claims are rejected: PyBench discovers only the manifest's exact distribution
and fixed-group entry point in the explicitly configured interpreter. R audits
the returned canonical identity and runtime attestation before publishing the
process-local catalog overlay. Python activation requires the path to the
original installed-distribution manifest and passes that exact path to PyBench;
a parsed list or R-reserialized snapshot cannot authenticate the installed
package. A missing PyBench interpreter reports
`OPERATION_PACK_RUNTIME_UNAVAILABLE`; it is not an unsupported backend.

Pack code is executable R or Python. scworkbench owns scientific-state
transitions and checks the operation contract, but does not claim to sandbox
trusted code from the host operating system. Structural conformance, installed
runtime conformance, activation, and scientific validation are four distinct
claims. None of the first three establishes scientific validity.

Activation is process-local. `wb_operation_pack_unload()` succeeds only before a
pack operation has executed. Once execution has occurred, the conservative
in-use guard keeps the definition available for any staged ephemeral or durable
session that may still require promotion.

## Installed R, Python, and mixed lifecycle

The two reference packages compose through the same public catalog and session
API. This minimal chain assumes `signal` is continuous cell metadata and that
`python_manifest` names the manifest inside the installed Python distribution:

```r
wb_operation_pack_load("scworkbenchOperationPackTemplate")
wb_operation_pack_activate(
  python_manifest,
  python = "/path/to/accepted/pybench/environment/bin/python"
)

s <- wb_session_new()
core <- wb_session_run_op(s, b, "metadata_cell_vector", inputs = list(
  source_column = "signal", vector_name = "signal",
  value_type = "continuous", missing_policy = "error", min_cells = 1L
))
r_step <- wb_session_run_op(core$session, b,
  "scwbexample::affine_cell_vector", inputs = list(
    signal = wb_ref_run(core$run$run_id, "vector"),
    scale = 2, shift = 1, min_cells = 1L
  ))
python_step <- wb_session_run_op(r_step$session, b,
  "scwbpython::affine_cell_vector", inputs = list(
    signal = wb_ref_run(r_step$run$run_id, "vector"),
    scale = 3, min_cells = 1L
  ))
```

The R and Python steps are ordinary session runs: durable sessions, selective
promotion, reopen, certificates, strict replay, and targeted reproduction use
the same APIs as core operations. Installation alone remains inert, and each
backend must be activated explicitly in every process that executes or replays
its operations.

## Backends and package identity

Protocol v1 supports exactly `R` and `Python`. Any other token fails with
`OPERATION_PACK_BACKEND_UNSUPPORTED` before mutation. Runtime availability is
checked only at explicit activation: a valid Python manifest remains
structurally conformant even when its configured interpreter, distribution, or
entry point is absent.

For backend `R`, `package.name` is an R package name, `package.version` must
equal installed `DESCRIPTION` metadata exactly, and manifest `entry_point` is
the name of an exported zero-argument R function.

For backend `Python`:

- `package.name` is the exact declared Python distribution name. It follows the
  PyPA distribution-name syntax and is preserved byte-for-byte in manifest and
  pack identity.
- Runtime resolution compares distribution names after PEP 503 normalization:
  lowercase and replace each run of `.`, `_`, or `-` with one `-`.
- `package.version` is valid PEP 440 syntax. Runtime metadata is compared by PEP
  440 version equivalence; the exact manifest spelling remains in canonical
  identity.
- The standard entry-point group is exactly
  `scworkbench.operation_packs.v1`.
- Manifest `entry_point` is the entry-point **name**, not an object reference or
  arbitrary import string. The callable target comes only from installed
  distribution metadata.
- Resolution is anchored to the explicitly named distribution. Its metadata
  `Name`/`Version` must match the manifest, and exactly one entry point with the
  fixed group and declared name must belong to that distribution. No ambient
  scan or fallback to a same-named entry point from another distribution is
  permitted. Same-named entry points owned by other distributions are ignored;
  multiple matching entry points owned by the declared distribution are
  ambiguous and rejected.

Missing distribution, identity mismatch, missing entry point, and duplicate
entry point failures use `OPERATION_PACK_DISTRIBUTION_UNAVAILABLE`,
`OPERATION_PACK_DISTRIBUTION_IDENTITY_MISMATCH`,
`OPERATION_PACK_ENTRY_POINT_UNAVAILABLE`, and
`OPERATION_PACK_ENTRY_POINT_AMBIGUOUS`, respectively. Backend substitution uses
`OPERATION_PACK_BACKEND_MISMATCH`. All precede staging and bundle mutation.

For both backends, `compatibility.scworkbench` constrains the receiving engine
version and `compatibility.protocol` is exactly `1`. Interpreter, R/Python
dependency, and execution-device versions are runtime attestations, not
manifest compatibility fields.

Identity is deterministic but deliberately layered:

- every identity declares
  `scworkbench.operation_pack.canonical_json.v1`. It orders object keys by
  UTF-8 bytes, preserves array order, emits decoded Unicode deterministically,
  and normalizes the restricted 15-significant-digit decimal domain (for
  example, `1`, `1.0`, and `1e0` all become `1e0`, while all signed zero
  spellings become `0`). The installed protocol document defines the complete
  escaping, exponent, range, and rejection rules.

- `manifest_sha256` hashes the canonical validated manifest, including the
  exact declared package/distribution name and version, backend, compatibility,
  entry-point name, and definitions. JSON object key order does not affect it.
- each `operation_definition_sha256` hashes only its canonical scientific
  operation definition. Backend, package identity, interpreter, dependencies,
  and entry-point discovery do not change that definition identity.
- `pack_sha256` hashes the complete pack identity, including backend. Python
  identity additionally binds the declared and PEP 503-normalized distribution
  name and fixed entry-point group. Therefore equal definition hashes across R
  and Python never make the packs or historical contracts interchangeable.

Canonical fixtures for the Python runtime integration are installed under
`inst/protocol/fixtures/operation-pack-v1/`.

## R v1 author ABI

An installed package places its canonical manifest at
`inst/scworkbench/operation-pack.json` and exports the declared zero-argument
entry point. The entry point returns exactly one call to the public boundary:

```r
register_your_pack <- function() {
  scworkbench::wb_operation_pack_register(
    manifest = system.file(
      "scworkbench", "operation-pack.json", package = "YourPack"
    ),
    operations = list(
      "your_namespace::operation" = your_runner
    )
  )
}
```

Runner formals are exactly:

```r
function(bundle, resolved, effective_cells, inputs, ...)
```

The runner reads engine-resolved primitive inputs from `resolved`, validated
parameters from `inputs`, and returns
`list(outputs = <named primitive list>, params = <named diagnostics>)`. Output
names and kinds must match the manifest exactly. Pack code uses exported
`wb_prim_*()` constructors and may not define primitive kinds, storage schemas,
getters, promotion functions, or validation hooks. It must not write bundle
SQLite, manifests, registries, or payload paths directly.

Python does not use `wb_operation_pack_register()`. That public function remains
the R pack-author boundary and accepts R runner functions only. Python authors
return PyBench's public `operation_pack_handlers()` object from the declared
entry point. At execution, scworkbench creates the private transition and exact
input/output capability, invokes `pybench.operation_pack_cli execute` once,
then independently verifies the receipt, runtime sidecar, observed SQLite and
payload mutations, and distribution/interpreter identity before atomic
publication. Timeout, signal, nonzero exit, incomplete or forged receipt,
runtime drift, undeclared mutation, or publication failure discards the private
transition. Packs never receive a direct committed-bundle writer.

Every operation name is fully qualified as `<namespace>::<operation>`. Reserved
namespaces, duplicate packs or operations, core shadowing, incompatible package
or protocol versions, unsupported backends, unknown primitives, malformed
parameters, invalid promotable terminals, and non-function entry points fail
before activation or committed bundle mutation.

`wb_operation_catalog_identity()` returns a deterministic SHA-256 over core plus
activated pack definitions. It and the composed semantic catalog are independent
of activation order. Structural R/Python fixture identities are likewise
order-independent across processes. Contributed semantic records and edges
carry exact source-pack identity.

## Provenance and recipients

Promoted runs embed the canonical manifest SHA-256, pack SHA-256, namespace,
exact package/distribution name and version, backend, compatibility, entry
point, per-operation definition SHA-256, complete operation interface, and
runtime attestation. Python pack identity additionally contains
`distribution{declared_name,normalized_name,version}` and
`entry_point_group`. Backend participates in pack and contract identity, so R
and Python definitions with the same names are never interchangeable. The
recorded contract is sufficient to inspect historical behavior without the
producer installed.

The persisted fields remain backend-neutral:

```text
run$operation_pack
run$operation_definition_sha256
contract$interface$source_pack
contract$interface$operation_definition_sha256
runtime_fingerprint$operation_pack
runtime_fingerprint$operation_pack_runtime
```

For R, `operation_pack_runtime` remains
`package{name,version}, built, remote_sha`. For Python it is
frozen as `scworkbench.operation_pack_runtime.python.v1` and contains:

```text
backend
distribution{
  declared_name, normalized_name, version,
  metadata_name, metadata_normalized_name, metadata_version,
  artifact_identity{kind,scheme,sha256}
}
entry_point{group,name,value}
interpreter{implementation,version,abi,platform,executable_sha256}
dependencies{scheme,sha256,distributions[{name,normalized_name,version}]}
pybench{protocol,distribution_name,distribution_version,source_revision}
device{type,descriptor}
seed{status,value}
```

Interpreter, dependency, artifact, PyBench, device, and seed observations enter
runtime provenance and replay attestation. They do not alter canonical manifest
or scientific operation-definition identity. The canonical example is
`runtime/python-operation-pack-runtime.json` in the fixture directory.
Absolute interpreter, distribution-install, manifest, request, receipt, bundle,
and library paths are deliberately removed before inspection or persistence.

A recipient without the pack can open and content-validate the bundle, navigate
provenance and certificates, and load retained core primitives. Typed replay
inspection reports `OPERATION_PACK_REQUIRED` with backend-specific recovery
guidance; execution or target reproduction fails with a
`wb_operation_pack_unavailable` condition until the exact compatible pack is
explicitly activated. A same-named pack with a different definition,
distribution identity, entry point, or backend produces
`OPERATION_CONTRACT_INCOMPATIBLE` and never satisfies contract comparison.
After exact activation, strict replay and targeted reproduction use the same
ordinary catalog/session path. Emitted replay scripts call only exported
scworkbench APIs.

## Statistics production pack

The independently versioned R package `scwbStatistics` uses canonical namespace
`scwbstatistics`. Installation is inert; activate it explicitly with
`wb_operation_pack_load("scwbStatistics")`. It contributes:

- `scwbstatistics::de_wilcox`
- `scwbstatistics::markers_topn`
- `scwbstatistics::cell_vector_assoc`
- `scwbstatistics::cell_vector_association`
- `scwbstatistics::cell_vector_compare`
- `scwbstatistics::feature_trend_spearman`

Core alone exposes 53 operations. This pack adds six namespaced definitions for
a total of 59. An unqualified prospective call resolves only when one active
qualified definition has that short name, and the run records the qualified
definition and pack identities. Historical unqualified records are never
rewritten. Finalized payloads and provenance remain readable without the pack;
new execution and strict replay require the exact pack and otherwise fail with
`OPERATION_PACK_REQUIRED` before dispatch.

`cell_vector_assoc` is the narrower continuous-by-categorical predecessor.
`cell_vector_association` is a semantically distinct typed dispatcher that also
supports categorical-by-categorical and continuous-by-continuous methods. Their
input and output tuples differ; neither is an alias.

## Operation, capsule, or adopted state

- Use a core operation for broadly supported engine capability.
- Use a pack operation for reusable method compute expressible with existing
  primitives but distributed independently from core.
- Use a provenance-bound analysis capsule only for an irreducibly
  dataset/question-specific terminal report, figure, or summary.
- Use an adoption boundary when externally computed state must become
  authoritative scworkbench state.

A recurring capsule pattern is evidence that its reusable portion may deserve a
pack operation; it is not permission to make the capsule itself replayable by
assertion.
