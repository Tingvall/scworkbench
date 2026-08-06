# scworkbench documentation

This is the public documentation index. It describes the current package
contracts and links only to maintained material.

- **Getting started:** this page and the shipped [onboarding library](../inst/onboarding/README.md).
- **Bundle concepts:** [bundle_concepts.md](bundle_concepts.md).
- **Ingestion:** [ingestion.md](ingestion.md).
- **Sessions and operations:** [sessions_and_ops.md](sessions_and_ops.md).
- **Promotion and provenance:** [promotion_and_provenance.md](promotion_and_provenance.md).
- **Recipient audit:** [recipient_audit.md](recipient_audit.md).
- **Python bridge:** [python_bridge.md](python_bridge.md) and the installed protocol schema at `system.file("protocol/pybench-op-v2.schema.json", package = "scworkbench")`.
- **Extension engineering:** [extension_engineering.md](extension_engineering.md).
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
