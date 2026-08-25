# Extension engineering

Extensions add one canonical operation, getter, primitive, artifact type,
wrangler, or plot contract. Source code is authoritative; generated catalogs
and roxygen output are derived. Inspect existing interfaces before adding a new
surface, add focused contract tests, regenerate references, and run the
documentation policy check.

See [source_ownership.md](source_ownership.md) for canonical owners and
regeneration commands.

## Operation-pack backend admission

Operation-pack protocol support is broader than the backends installed in one
runtime. Protocol v1 supports exactly `R` and `Python`; this checkpoint activates
R in-process and Python through the accepted PyBench CLI. Use
`wb_operation_pack_manifest_validate()` for backend-neutral JSON structure and
identity; it performs no discovery, import, activation, or mutation. Installed
R packages continue through `wb_operation_pack_validate()` and
`wb_operation_pack_load()`.

Python distribution resolution is owned by PyBench. It resolves only the
explicitly declared PEP 503-normalized distribution, compares versions by PEP
440 semantics, and selects exactly one named entry point from group
`scworkbench.operation_packs.v1`. Manifest `entry_point` is a name, never an
import target. Entry points from other distributions never satisfy or make
ambiguous the explicitly selected distribution.

`wb_operation_pack_activate(manifest, python=...)` is the public integration
seam. It authenticates R manifests against the installed R package or asks the
exact Python interpreter to perform PyBench discovery. Python activation and
each execution recheck manifest, definition, distribution-content, entry-point,
interpreter, dependency-set, and PyBench identities. Execution receives an
R-created capability for one private transition; R independently audits the
receipt, runtime sidecar, and all observed mutations before atomic publication.
Do not add a filesystem scan, arbitrary import path, direct writer, or second
operation catalog.

Backend belongs to pack and persisted contract identity. Runtime observations
such as interpreter, dependencies, installed-distribution SHA-256, PyBench
revision, device, and seed belong only to `operation_pack_runtime`; they must
not be folded into the scientific operation-definition hash. Absolute host
paths are runtime control data and must not enter persisted provenance.
