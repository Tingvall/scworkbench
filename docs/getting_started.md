# Getting Started and Documentation

This is the public documentation index. It describes the current package
contracts and links only to maintained material.

## Start by Role

- **Analyst or operator:** read the installed [system overview](../inst/onboarding/SYSTEM_OVERVIEW.md), then the [operator guide](../inst/onboarding/AGENT_OPERATOR_GUIDE.md). Import or open a bundle, activate the packs you need, inspect interfaces, run in a session, promote, and audit.
- **Pack author:** start with the [Operation Pack SDK](operation_pack_sdk.md). Scaffold a minimal ABI-v3 pack, declare primitive exchange, implement the calculation, and test the installed lifecycle. Do not copy engine internals from an official pack.
- **Engine developer:** read [extension engineering](extension_engineering.md) and [source ownership](source_ownership.md). Add core authority only when an existing primitive/capability cannot express the exchange.
- **Recipient:** use [recipient audit](recipient_audit.md). Inspection is pack-free; running or replaying a method is not.

The optional [standard profile](../inst/standard_profile/README.md) selects
seven packs: five core operations plus 56 packed operations yield 61 after
explicit activation. Installation alone leaves the core catalog unchanged.
Dataset-specific collaborator workflows belong in their project documentation,
not in generic package onboarding.

## Installed Documentation

```r
library(scworkbench)
system.file("onboarding", "README.md", package = "scworkbench")
system.file("sdk", "operation-packs", "GUIDE.md", package = "scworkbench")
system.file("standard_profile", "README.md", package = "scworkbench")
wb_operation_pack_capabilities()
```

These installed resources work without a checkout. Source-distributed guides
and generated references are linked below. Backend support, trust boundaries,
and test limitations are documented in the system overview and SDK catalog.

## Reference Map

- **Getting started:** this page and the shipped [onboarding library](../inst/onboarding/README.md).
- **Bundle concepts:** [bundle_concepts.md](bundle_concepts.md).
- **Ingestion:** [ingestion.md](ingestion.md).
- **Sessions and operations:** [sessions_and_ops.md](sessions_and_ops.md).
- **Promotion and provenance:** [promotion_and_provenance.md](promotion_and_provenance.md) and [provenance_identity_schemes.md](provenance_identity_schemes.md).
- **Recipient audit:** [recipient_audit.md](recipient_audit.md).
- **Source declarations:** [source_ingestion.md](source_ingestion.md).
- **Python bridge:** [python_bridge.md](python_bridge.md) and the installed protocol schema at `system.file("protocol/pybench-op-v2.schema.json", package = "scworkbench")`.
- **Extension engineering:** [extension_engineering.md](extension_engineering.md).
- **Operation packs:** [activation and compatibility](operation_packs.md), [SDK tutorial and checks](operation_pack_sdk.md), [ABI v2](operation_pack_v2_protocol.md), and [ABI v3](operation_pack_v3_protocol.md).
- **Contributing and support:** [CONTRIBUTING.md](CONTRIBUTING.md) and [SUPPORT.md](SUPPORT.md).
- **Composite releases:** [release_process.md](release_process.md) and the package [changelog](../NEWS.md).
- **Durable bundle contracts:** [bundle_state_contract.md](bundle_state_contract.md), [bundle_integrity_validation.md](bundle_integrity_validation.md), [bundle_path_containment_and_trust.md](bundle_path_containment_and_trust.md), and [bundle_writer_lock.md](bundle_writer_lock.md).
- **Lifecycle, sessions, and promotion:** [entity_lifecycle.md](entity_lifecycle.md), [durable_resumable_sessions.md](durable_resumable_sessions.md), and [promotion_and_provenance.md](promotion_and_provenance.md).
- **Metadata and primitives:** [metadata_field_identity.md](metadata_field_identity.md), [metadata_cell_vector_diagnostics.md](metadata_cell_vector_diagnostics.md), and [tabular_primitives.md](tabular_primitives.md).
- **Python-backed operations:** [pybench_integration_contract.md](pybench_integration_contract.md), [pybench_op_protocol_v2.md](pybench_op_protocol_v2.md), [scvi_train.md](scvi_train.md), [peakvi_fit.md](peakvi_fit.md), and [rna_map_ops.md](rna_map_ops.md).
- **Trajectory composition:** [trajectory_fit_family_contract.md](trajectory_fit_family_contract.md), [trajectory_segment_contract.md](trajectory_segment_contract.md), and [trajectory_segment_join_contract.md](trajectory_segment_join_contract.md).
- **Generated references:** operation, getter, primitive, artifact, parameter,
  recipe, plot, wrangler, schema, semantic, mutation, and graph catalogs listed
  in [source_ownership.md](source_ownership.md).

The package is MIT licensed. See [LICENSE.md](../LICENSE.md). It makes no
claim of CRAN or Bioconductor acceptance.
