# ABI v2 feature-set-registry reader capability

Status: R/core/protocol candidate implemented; Python parity required before
scientific pack extraction

## Closed R/core gap

Two frozen Phase 3B methods consume durable feature-set registry state that is
not present in their declared primitive inputs:

- `pathway_enrich` reads namespace metadata and ordered membership through
  `wb_feature_sets()` and `wb_feature_set_get()`;
- `feature_set_overlap_qc` reads the same registry surface to compute namespace
  and membership QC.

ABI v2 now grants this state through a dedicated manifest `registry_reads`
declaration, not through a new primitive input. The execution context still
carries no bundle handle, and an ordinary matrix input does not acquire hidden
registry authority. The public input tuples of the frozen methods remain
unchanged.

Executable evidence is in
`tests/test_operation_pack_v2_feature_set_registry_gap.R` and
`tests/fixtures/operation-pack-v2-feature-set-registry-capability-gap.json`.

## Implemented generic amendment

Add an authenticated, read-only core registry snapshot input contract:

```text
category:  authenticated_core_registry_snapshot
kind:      feature_set_registry
reader:    read_feature_set_registry
binding:   matrix input + namespace/namespaces + optional feature_sets params
alignment: feature_ordered
```

The core resolver, not the pack, constructs the snapshot after normal
parameter validation. The snapshot contains:

- target `matrix_id` and its exact ordered feature-universe identity;
- canonical registry rows for every selected set, including namespace and
  source cardinality fields used by the frozen methods;
- each selected set's membership in stored rank order;
- a content identity over the complete ordered snapshot;
- source-state and ancestry identities binding it to the transition.

Set rows are ordered by namespace then set name; memberships preserve stored
rank order and carry their ranks explicitly. Selector arrays are de-duplicated
and radix-sorted. With no selector, all namespaces are selected. Each grant
declares whether an empty match is allowed or rejected; no namespace allowlist
exists.

The typed reader returns a private deep copy and grants no mutation authority.
The source-state identity must be re-read immediately before dispatch so a
namespace, metadata, membership, or rank change after preflight fails closed.
This is generic registry access: no GenePrograms operation name or algorithm
appears in the resolver or protocol.

## Remaining cross-language work

Quill must adopt the four byte-identical shared files and implement Python
transport parity before extraction resumes. The R core candidate includes
declaration validation, parameter binding, snapshot canonicalization, reader
grant, source-state recheck, receipt audit, durable reopen, and pack-free
recipient inspection.

Executable coverage includes undeclared, missing, and extra reads; absent or
wrong namespace; wrong matrix binding; duplicate set names or members;
out-of-universe members; noncanonical rank/order; post-preflight registry
mutation; malformed descriptors; and forged identities. Lifecycle failures
before publication leave no transition or analytical residue and are retryable.

## Rejected local workarounds

- adding a required user-supplied table input changes the frozen interfaces;
- copying registry rows into matrix metadata is an implicit, unauthenticated
  side channel and changes unrelated matrix identities;
- passing the bundle handle in R-only context restores direct pack access and
  has no Python parity;
- retaining only these two methods in core would produce an incomplete
  eight-method Phase 3B extraction forbidden by the work order.
