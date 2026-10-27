# Promotion and provenance

Promote a terminal session result only after checking its staged lineage.
Promotion is closure-aware: dependencies required by the terminal result are
published together and become durable bundle state.

```r
receipt <- wb_session_promote_current(
  bundle = b, session = s, outputs = terminal_names,
  name_prefix = "analysis", created_by = "operator"
)
wb_close_bundle(b)
reopened <- wb_open_bundle("path/to/bundle", read_only = TRUE)
wb_prov_artifact_lineage(reopened, receipt$promoted$artifact_id[[1]])
wb_close_bundle(reopened)
```

Choose `terminal_names` from the active operation interface's directly
promotable outputs; the promotion result contains a `promoted` table.

Use `wb_session_discard()` for staged work that should not be published.

Pack outputs use the same core promotion authority. A model and linked
space/terminals, or a terminal and registry effects, may require one complete
closure; selecting part does not authorize breaking the binding. Core validates
observed outputs against admitted grants before publication. Inspect the
interface and receipt rather than inferring relationships from filenames.

Named cell sets consumed by an operation are durable scientific dependencies.
Promotion records their binding role plus source and effective membership
SHA-256/count evidence; explicit cell-ID vectors are not mislabeled as durable
sets. See `docs/typed_cell_set_consumption.md`.

## Replay equivalence

Content identity and replay equivalence are separate claims. Deterministic
tables, matrices, and spaces may require exact canonical content. Serialized
models are verified as loadable references because their bytes can contain
runtime state. UMAP embeddings use `cell_aligned_embedding`: replay must
produce the same named space over the same cell universe and dimensions, with
complete, finite, nondegenerate coordinates. The original and replayed raw
content SHA-256 values remain recorded and may differ; this policy does not
claim coordinate equality or geometric identity.

Inspect the persisted decision with `wb_prov_replay_equivalence_results()`.

Native fitted space models and retained `model_ref` artifacts have distinct
content boundaries. For new paired-model fits, core records the planned fit
run/output in the native model's registry provenance and binds that native
entity when the owning run is promoted. The native certificate and model-ref
artifact share the existing file-tree identity for the contained payload, as
required by their existing lifecycle alias. The native registry still points
to its primary model file; certificate storage exposes the contained tree too.
The embedding keeps its dense-space identity. Query them with
`wb_entity_certificate(b, "model", space_id)`, `"artifact", model_artifact_id`,
and `"space", space_id` respectively. A reference re-emitted by another run
cannot acquire native fit ownership. Retained-model transform/reuse continues
through the model artifact; it does not refit or reassign the native producer.
Historical native model rows without a recorded creation owner are not
backfilled or relabeled during inspection.

## Execution-setting precision

New provenance snapshots at semantic version 1.11 store supported finite double
execution settings as 17-digit JSON numbers. Decimal tokens preserve double
values such as `1.0` and signed zero for ordinary R and Python readers. This
applies to parameters, recorded/symbolic/resolved inputs, contract snapshots,
artifact provenance, and emitted replay scripts. Artifact provenance identifies
these new records with `execution_settings_encoding` set to
`scworkbench.execution-settings.json.v1`. Ordinary durable RDS checkpoints keep
their existing representation. Parameter types and non-finite-value admission
remain the operation interface's responsibility; this is not arbitrary R-object
serialization.

Run and contract integrity schemes still authenticate their exact stored UTF-8
JSON bytes. Existing content, manifest, and legacy table identity algorithms
have not changed. Earlier records are read and verified using their recorded
bytes and settings; they are never rewritten at higher precision. If an earlier
writer rounded a scientific threshold, the lost precision cannot be recovered
by reopening or replaying that record. Reconstruct the invocation explicitly
from an independent source if the original setting is needed.
