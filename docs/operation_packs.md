# Operation packs

Operation-pack protocol v1 admits independently installed R packages and Python
distributions. Protocol support and installed runtime support are different:
this checkpoint fully activates R packs and structurally admits Python packs;
Python execution remains unavailable until the audited PyBench integration is
installed. A pack operation is never a parallel runner: after backend-specific
activation it uses the same `wb_session_run_op()` path, typed inputs,
effective-cell coverage, private staging, promotion, provenance, replay,
validation, and reproduction contracts as a core operation.

The authoritative machine-readable manifest schema is installed at
`inst/protocol/operation-pack-v1.schema.json`.

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
importing the target. It still does not activate Python.

The explicit backend-neutral activation dispatcher is:

```r
wb_operation_pack_activate("operation-pack.json", runtime_identity = NULL)
```

For R it authenticates the supplied manifest against the installed package and
delegates to `wb_operation_pack_load()`. For Python it is the frozen PyBench
integration seam and currently raises `OPERATION_PACK_RUNTIME_UNAVAILABLE`.

Pack code is executable R or Python. scworkbench owns scientific-state
transitions and checks the operation contract, but does not claim to sandbox
trusted code from the host operating system. Structural conformance, installed
runtime conformance, activation, and scientific validation are four distinct
claims. None of the first three establishes scientific validity.

Activation is process-local. `wb_operation_pack_unload()` succeeds only before a
pack operation has executed. Once execution has occurred, the conservative
in-use guard keeps the definition available for any staged ephemeral or durable
session that may still require promotion.

## Backends and package identity

Protocol v1 supports exactly `R` and `Python`. Any other token fails with
`OPERATION_PACK_BACKEND_UNSUPPORTED` before mutation. A structurally valid
Python pack presented to this R-only activation checkpoint fails with class
`wb_operation_pack_runtime_unavailable` and code
`OPERATION_PACK_RUNTIME_UNAVAILABLE`; it is not reported as an unknown backend.

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
the R pack-author boundary and accepts R runner functions only. Python Phase 2
must discover the declared distribution entry point and execute through PyBench
v2 capabilities and receipts; it may not build an import-string runner or
direct writer.

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
`package{name,version}, installed_path, built, remote_sha`. For Python it is
frozen as `scworkbench.operation_pack_runtime.python.v1` and contains:

```text
backend
distribution{
  declared_name, normalized_name, version,
  metadata_name, metadata_normalized_name, metadata_version,
  artifact_identity{kind,scheme,sha256}
}
entry_point{group,name,value}
interpreter{implementation,version,abi,platform,executable,executable_sha256}
dependencies{scheme,sha256,distributions[{name,normalized_name,version}]}
pybench{protocol,distribution_name,distribution_version,source_revision}
device{type,descriptor}
seed{status,value}
```

Interpreter, dependency, artifact, PyBench, device, and seed observations enter
runtime provenance and replay attestation. They do not alter canonical manifest
or scientific operation-definition identity. The canonical example is
`runtime/python-operation-pack-runtime.json` in the fixture directory.

A recipient without the pack can open and content-validate the bundle, navigate
provenance and certificates, and load retained core primitives. Typed replay
inspection reports `OPERATION_PACK_REQUIRED` with backend-specific recovery
guidance; execution or target reproduction fails with a
`wb_operation_pack_unavailable` condition until the exact compatible pack is
explicitly activated. A same-named pack with a different definition,
distribution identity, entry point, or backend produces
`OPERATION_CONTRACT_INCOMPATIBLE` and never satisfies contract comparison.

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
