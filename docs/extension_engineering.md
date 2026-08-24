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
runtime. Protocol v1 supports exactly `R` and `Python`, while the current
checkpoint activates only R. Use `wb_operation_pack_manifest_validate()` for
backend-neutral JSON structure and identity; it performs no discovery, import,
activation, or mutation. Installed R packages continue through
`wb_operation_pack_validate()` and `wb_operation_pack_load()`.

Python distribution resolution is owned by the future PyBench integration. It
must resolve only the explicitly declared PEP 503-normalized distribution,
compare versions by PEP 440 semantics, and select exactly one named entry point
from group `scworkbench.operation_packs.v1`. Manifest `entry_point` is a name,
never an import target. Entry points from other distributions never satisfy or
make ambiguous the explicitly selected distribution. Until that runtime exists, activation fails as
`wb_operation_pack_runtime_unavailable` /
`OPERATION_PACK_RUNTIME_UNAVAILABLE`, before staging. Do not add a temporary
Python runner, filesystem scan, arbitrary import path, or direct writer.
The public integration seam is `wb_operation_pack_activate()`: its R branch
authenticates and delegates to the existing loader, while its Python branch is
the typed unavailable boundary the Python runtime integration must replace with
capability-bound PyBench admission.

Backend belongs to pack and persisted contract identity. Runtime observations
such as interpreter, dependencies, wheel/source SHA-256, PyBench revision,
device, and seed belong only to `operation_pack_runtime`; they must not be
folded into the scientific operation-definition hash.
