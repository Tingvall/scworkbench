# Provenance-bound analysis capsules

> Ad hoc analysis is permitted; unrecorded durable evidence is not.

An analysis capsule is immutable bundle-owned evidence for one externally
executed, question-specific terminal analysis. scworkbench verifies accepted
input identities and the exact source/output bytes copied at registration. It
did not observe, control, sandbox, or scientifically validate the computation.
A matching script/output hash is not replay-equivalence evidence. Declared
runtime metadata is not engine-observed runtime attestation.

## The op-first decision law

1. Inspect registered operation, wrangler, and plotting contracts first.
2. If a registered op satisfies the scientific transformation, use it. Do not
   replace it with a capsule for convenience.
3. If no op exists and the result would be a reusable or authoritative matrix,
   space, model, set, metadata field, or downstream input, stop and report the
   capability gap. Keep terminal capsule evidence, submit a portable op
   candidate to package maintainers, use a supported extension, or wait for a
   typed adoption boundary. Do not assume an operator can change core.
4. Use a capsule only for a genuinely dataset- or question-specific terminal
   figure, report, or summary whose exact execution must remain attributable.
5. Reports identify registered-op evidence separately from externally executed
   capsule evidence.

> A capsule should contain only the irreducibly dataset- or question-specific terminal portion of an analysis.

Do not bury normalization, feature selection, PCA, UMAP, scVI, differential
expression, enrichment, or another catalogued method in a capsule. Run those
as ops and bind accepted outputs to the terminal script. Capsule outputs are
terminal and cannot become op inputs or authoritative registries.

For R source, registration performs a bounded parsed-source review. Literal
registered operation names in ordinary public
`wb_session_run_op(session, bundle, op_name = "...")` calls, in the valid
positional `op_name` form, or in namespace-qualified equivalents are rejected,
as are explicit `wb_op_<registered-name>()` calls. Comments, report prose, and
unrelated string literals do not count as calls. Dynamically constructed
operation names and non-R source are not claimed to be statically understood;
their minimum-custom-surface status remains the operator's structured catalog
review declaration, not an engine proof of semantic novelty.

Appropriate: a paper-specific three-panel representation figure, metrics CSV,
and terminal report. Inappropriate: fitting PCA, UMAP, scVI, or differential
expression in a capsule; use the op. Inappropriate: a custom matrix or space
for downstream ops; it needs a proper op or future typed adoption gateway.
Loose exploratory files remain outside accepted evidence until registered.

## Complete representation-comparison registration

The script was executed externally before registration. Registration does not
rerun or scientifically validate it.

```r
inputs <- list(
  pca = wb_ref_entity("space", "rna.pca"),
  umap = wb_ref_entity("space", "rna.umap"),
  scvi_umap = wb_ref_entity("space", "scvi.umap"),
  sample = wb_ref_entity("artifact", "art_sample_vector"),
  condition = wb_ref_entity("artifact", "art_condition_vector")
)
capsule <- wb_capsule_register(
  bundle, name = "paper representation comparison", inputs = inputs,
  script = "external-work/compare-representations.R",
  outputs = list(
    metrics = list(path = "external-work/metrics.csv", role = "metrics_table", media_type = "text/csv"),
    figure_pdf = list(path = "external-work/comparison.pdf", role = "figure", media_type = "application/pdf"),
    figure_png = list(path = "external-work/comparison.png", role = "figure", media_type = "image/png"),
    report = list(path = "external-work/report.md", role = "report", media_type = "text/markdown")
  ),
  parameters = list(panel_order = c("pca", "umap", "scvi_umap"), subtitle = NULL),
  command = c("Rscript", "compare-representations.R"),
  runtime = list(R = "4.x", container_sha256 = "declared digest"),
  purpose = "custom_visualization",
  rationale = "Paper-specific terminal composition; representations already came from ops.",
  catalog_review = list(
    catalog_identity = "scworkbench.operation_catalog",
    catalog_version = "installed package version",
    reviewed_at = "2026-08-17T11:00:00Z",
    candidate_op_names = character(), decision = "retain_as_capsule"
  ), family_hint = "representation-comparison"
)
```

Inspect with `wb_capsules()`, `wb_capsule()`, `wb_capsule_inputs()`, and
`wb_capsule_outputs()`. Payload resolvers verify full SHA-256. Certificates
accept `capsule` and `capsule_output`; DAG/KG edges connect each typed input
through the capsule to every output.

## Layout, portability, and trust

Schema `scworkbench.analysis_capsule.v1` stores:

```text
analysis/capsules/<capsule_id>/
  manifest.json
  source/<entrypoint>
  outputs/<registered files>
```

Paths are bundle-relative. Registration is append-only; a revision is a new
capsule linked by `variant_of` or `reproduction_of`. Exact copies increase
bundle size. Moving a finalized bundle preserves read-only inspection.

Registration stages under `analysis/capsules/.pending/<capsule_id>` and
publishes the complete final directory before committing its registry row.
Validation reports pending trees and final directories without committed rows.
After explicit stale writer-lock recovery, the next writable open removes only
provably uncommitted, self-identifying capsule residue; committed capsule trees
are preserved and the manifest is refreshed. Recipient finalization and strict
read-only open fail closed while unresolved residue remains.

Assurance is `content_registered`, execution mode is `externally_executed`,
and replay status is `not_verified`. Reproduction export has status
`source_exported`; it never upgrades to `replay_ready` or `replay_verified`.
A future managed executor may use the manifest, but v1 executes no user code.

Versioned SHA-256 signatures use canonical JSON framing. Input shape covers
ordered names/kinds but excludes IDs. Parameter shape covers ordered names,
observed R types, cardinalities, and explicit null markers but excludes values.
Output shape covers ordered names, roles, media types, and structural metadata
but excludes bytes. Exact source identity is separate. The composite combines
these plus the operator-declared family hint. These observations are not
defaults, ranges, invariants, determinism guarantees, method equivalence,
replay success, or permission to merge histories.

Structured catalog review records identity/version, time, candidate names, and
decision. `use_existing_op` is rejected; `split_standard_and_custom` requires
a minimized surface. `propose_new_op` remains terminal lower-assurance evidence
and is never catalogued automatically.

```text
exploratory script -> registered capsule -> reviewed op candidate -> tested op
```

This maturation path is not automatic. A future portable candidate emitter is
a maintainer or extension-development aid. Human review defines semantics,
defaults, ranges, identity and determinism/equivalence behavior, resource
guards, transactional materialization, and generalized tests. A terminal
capsule remains valid evidence even if it never becomes an op.
