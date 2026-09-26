# Phase 6 matrix-trained contained-model boundary

ABI-v3 `matrix_trained_contained_model_closure.v1` is generic. A declared model
terminal names one authenticated matrix input, its exactly-once typed matrix
slice, a paired fitted latent `space` materialization, latent-dimension
parameter, and complete required sibling outputs. Core binds matrix content
and descriptor identities, exact ordered fitted cells and features, source
snapshot, paired space ID/dimensions, model tree, promotion group, and receipt
observation. A G1 model read reauthenticates the retained matrix and fitted
space before exposing private model bytes. Staging, promotion, and rollback
remain core-owned; packs receive no bundle/SQL/committed path authority.

The shared manifest, request, receipt schemas and identity fixture are in
`inst/protocol/`. They retain canonical JSON v1. Python has schema and
canonical-identity parity but no direct runtime for the new grant; an
unsupported Python execution request rejects before stage mutation.
Existing space-trained G2/G1 identities are unchanged.

`model_bound_latent_union` remains a core operation and is **not ABI-v3
ready**. Its current implementation queries the artifact registry with SQL,
reads spaces through the bundle, and creates a space directly. A future pack
migration needs typed retained-model and projection-receipt binding, separate
reference/query space descriptors, an authenticated declared ordered union,
and a core-owned immutable space writer. The existing core contract verifies
model/receipt identity, disjoint axes, complete union, equal dimensions and
row-bind semantics; this order does not alter that operation.

`scvi_train` is deferred. Besides the matrix-model closure, it needs typed
authenticated batch, categorical and continuous covariate reads bound to the
same fitted-cell axis and explicit count-like input authority. The PeakVI
pilot forbids non-null batch metadata rather than consulting bundle storage.
