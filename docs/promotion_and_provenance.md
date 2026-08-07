# Promotion and provenance

Promote a terminal session result only after checking its staged lineage.
Promotion is closure-aware: dependencies required by the terminal result are
published together and become durable bundle state.

```r
receipt <- wb_session_promote_current(
  bundle = b, session = s, name_prefix = "analysis", created_by = "operator"
)
reopened <- wb_open_bundle("path/to/bundle")
on.exit(wb_close_bundle(reopened), add = TRUE)
wb_prov_artifact_lineage(reopened, receipt$artifact_ids[[1]])
```

Use `wb_session_discard()` for staged work that should not be published.

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
