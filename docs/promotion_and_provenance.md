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
