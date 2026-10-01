# Extension engineering

## Scientific Methods Go in Packs

For a new method over existing primitives, start with the
[Operation Pack SDK](operation_pack_sdk.md), not a core catalog edit. The
canonical author loop is scaffold, declare inputs/outputs and grants, compute
through callbacks, emit primitives, and validate the installed lifecycle.
Official packs are precedents, not a requirement to reverse-engineer private
engine functions. The installed [system overview](../inst/onboarding/SYSTEM_OVERVIEW.md)
explains the current architecture and test ownership.

An engine extension is needed when a new primitive or genuinely missing generic
authority cannot be expressed by the supported SDK recipes. Specify its shape,
axes, identity, storage/lifecycle, reader/writer boundary, backend support, and
rollback rules together. Primitive kind alone does not authorize arbitrary
cardinality, lineage, registry access, or model deserialization.

Exported low-level writers remain transaction-restricted. Do not use `:::` or
copy engine receipt, SQL, promotion, or partition implementations into a pack.
Central slicing serves admitted schedules; scientific computation and reductions
remain pack-owned. Test method behavior in the pack, generic authority in core,
and real-pack integration in a pinned composite.

Extensions add one canonical operation, getter, primitive, artifact type,
wrangler, or plot contract. Source code is authoritative; generated catalogs
and roxygen output are derived. Inspect existing interfaces before adding a new
surface, add focused contract tests, regenerate references, and run the
documentation policy check.

See [source_ownership.md](source_ownership.md) for canonical owners and
regeneration commands.

## Operation-pack backend admission

Operation-pack protocol support is broader than the backends installed in one
runtime. Protocols v1, v2, and v3 admit `R` and `Python` declarations; this checkpoint activates
R in-process and Python through the accepted PyBench CLI. Use
`wb_operation_pack_manifest_validate()` for backend-neutral JSON structure and
identity; it performs no discovery, import, activation, or mutation. Installed
R packages continue through `wb_operation_pack_validate()` and
`wb_operation_pack_load()`.

Python distribution resolution is owned by PyBench. It resolves only the
explicitly declared PEP 503-normalized distribution, compares versions by PEP
440 semantics, and selects exactly one named entry point from group
`scworkbench.operation_packs.v1` for a v1 pack (successor ABIs have their own
declared entry-point groups). Manifest `entry_point` is a name, never an
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
