# Proposed ABI v2 feature-set-registry reader capability

Status: review required; not a live protocol change

## Confirmed gap

Two frozen Phase 3B methods consume durable feature-set registry state that is
not present in their declared primitive inputs:

- `pathway_enrich` reads namespace metadata and ordered membership through
  `wb_feature_sets()` and `wb_feature_set_get()`;
- `feature_set_overlap_qc` reads the same registry surface to compute namespace
  and membership QC.

ABI v2 grants readers only for manifest-declared primitive inputs. Its input
schema has no feature-set-registry kind, the R adapter exposes exactly the
declared reader names, and the execution context intentionally carries no
bundle handle. A matrix primitive contains the matrix feature universe but not
feature-set names, namespace metadata, source cardinalities, or ordered
memberships. Consequently neither frozen method can be implemented by a pack
without changing its public interface, passing an unauthenticated hidden
payload, or restoring direct bundle access to pack code.

Executable evidence is in
`tests/test_operation_pack_v2_feature_set_registry_gap.R` and
`tests/fixtures/operation-pack-v2-feature-set-registry-capability-gap.json`.

## Smallest generic amendment

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

The typed reader returns a private deep copy and grants no mutation authority.
The source-state identity must be re-read immediately before dispatch so a
namespace, metadata, membership, or rank change after preflight fails closed.
This is generic registry access: no GenePrograms operation name or algorithm
appears in the resolver or protocol.

## Required protocol work

Quill must update the byte-identical v2 manifest, request, and receipt schemas
and implement Python transport parity before extraction resumes. The R core
must add the same declaration validation, parameter binding, snapshot
canonicalization, reader grant, source-state recheck, and receipt audit.

Required negative fixtures include undeclared registry reads, absent or wrong
namespace, wrong matrix binding, duplicate set names, duplicate or
out-of-universe members, noncanonical membership rank, post-preflight registry
mutation, malformed descriptors, and wrong snapshot identity. Every rejection
must occur before pack dispatch or output publication and leave no transition,
artifact, registry, provenance, or receipt residue.

## Rejected local workarounds

- adding a required user-supplied table input changes the frozen interfaces;
- copying registry rows into matrix metadata is an implicit, unauthenticated
  side channel and changes unrelated matrix identities;
- passing the bundle handle in R-only context restores direct pack access and
  has no Python parity;
- retaining only these two methods in core would produce an incomplete
  eight-method Phase 3B extraction forbidden by the work order.
