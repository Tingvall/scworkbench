# Operation packs

Operation-pack protocol v1 lets an independently installed R package contribute
scientific operations to the canonical scworkbench execution catalog. A pack
operation is not a separate runner: after explicit activation it uses the same
`wb_session_run_op()` path, typed inputs, effective-cell coverage, private
staging, promotion, provenance, replay, validation, and reproduction contracts
as a core operation.

The authoritative machine-readable manifest schema is installed at
`inst/protocol/operation-pack-v1.schema.json`.

## Trust and activation

Installing a package does not activate it, and scworkbench never scans the R
library for packs. Validation and loading both load the named package and invoke
its exported entry point, so each is an explicit trust decision:

```r
wb_operation_pack_validate("YourPack")
wb_operation_pack_load("YourPack")
wb_operation_packs()
wb_operation_pack_inspect("your_namespace")
wb_op_interface("your_namespace::operation")
```

Pack code is executable R. scworkbench owns scientific-state transitions and
checks the operation contract, but does not claim to sandbox trusted code from
the host operating system. Conformance establishes ABI and engine compatibility;
it does not establish scientific validity.

Activation is process-local. `wb_operation_pack_unload()` succeeds only before a
pack operation has executed. Once execution has occurred, the conservative
in-use guard keeps the definition available for any staged ephemeral or durable
session that may still require promotion.

## v1 author ABI

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

Every operation name is fully qualified as `<namespace>::<operation>`. Reserved
namespaces, duplicate packs or operations, core shadowing, incompatible package
or protocol versions, unsupported backends, unknown primitives, malformed
parameters, invalid promotable terminals, and non-function entry points fail
before activation or committed bundle mutation.

`wb_operation_catalog_identity()` returns a deterministic SHA-256 over core plus
loaded pack definitions. It and the composed semantic catalog are independent of
pack load order. Contributed semantic records and edges carry exact source-pack
identity.

## Provenance and recipients

Promoted runs embed the canonical manifest SHA-256, pack SHA-256, namespace,
package name/version, backend, compatibility, entry point, per-operation
definition SHA-256, complete operation interface, and runtime attestation. The
recorded contract is sufficient to inspect historical behavior without the
producing package.

A recipient without the pack can open and content-validate the bundle, navigate
provenance and certificates, and load retained core primitives. Typed replay
inspection reports `OPERATION_PACK_REQUIRED`; execution or target reproduction
fails with a `wb_operation_pack_unavailable` condition until the exact compatible
pack is explicitly loaded. A same-named pack with a different recorded identity
does not satisfy contract comparison.

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
