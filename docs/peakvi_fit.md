# PeakVI operation-pack ownership

Current CPU PeakVI execution is owned by the independently installed
`scwbLatent` operation pack. The core no-pack catalog does not register
`peakvi_fit` or `peakvi_project`; use the qualified operations
`scwblatent::peakvi_fit` and `scwblatent::peakvi_project` after explicit
pack activation. The core still owns authenticated matrix/model reads,
contained output publication, promotion, receipts, provenance and rollback.

`scwblatent::peakvi_fit` consumes an authenticated ATAC/count matrix through
bounded, ordered typed chunks and atomically publishes a fitted latent space,
contained model tree and fit summary. The fitted space ID is allocated by
core; it is not a caller-overwritable legacy `space_id_out`. The pack accepts
CPU execution only. `batch_key` is null until typed metadata authority is
available.

`scwblatent::peakvi_project` consumes an authenticated promoted model and
disjoint query-matrix cells, then publishes an immutable query latent space
and projection summary without refitting. A generic model-linked output policy
fixes the published row order to the effective query grant and its width to
the retained model linkage, so 2D and higher-dimensional models use the same
authenticated path. The caller supplies a fresh
`space_id_out`, and collisions reject. Because scvi-tools loads a
pickle-capable model payload, projection requires
`pickle_execution_trust = "operator_verified_source_v1"` after independent
source verification. Core content hashes do not make pickle safe and this
declaration is neither a signature nor a sandbox.

The pack stages at most `n_features * chunk_size` R matrix elements per
typed read. Private Python receives stage-relative files, not a bundle path,
SQL connection or publication authority. This pilot does not qualify GPU,
large data or full scVI. See the pack's own README and operation manifest for
the live parameter and output contract.

The former unqualified core operations remain part of historical run and
bundle provenance. Existing promoted outputs remain inspectable without
installing the pack, but they are not silently re-executed by the new pack.
The old-core CPU comparator is retained as explicit migration evidence; the
new pack is not claimed to reproduce legacy model bytes or coordinate hashes.

The qualified `scwblatent::model_bound_latent_union` consumes a retained fitted
model, its fitted space, and a paired PeakVI projection space and summary.
Its authenticated typed-space readers preserve the scientific row-bind order.
