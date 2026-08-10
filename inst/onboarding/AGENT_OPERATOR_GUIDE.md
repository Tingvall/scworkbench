# scworkbench Agent Operator Guide

## Purpose

This guide onboards any capable AI agent, script-driven assistant, or
interactive computational operator to scworkbench. It is independent of the
agent platform, the scientific domain, the bundle contents, and the user's
question.

scworkbench is not an agent and does not decide what science to perform. It is
the persistent computational substrate on which an operator works: a portable
bundle with typed scientific objects, explicit operations, promoted results,
and inspectable provenance.

Use this guide when you receive a bundle and a scientific task for the first
time.

## The Operating Model

An scworkbench analysis has one durable state model:

```text
source data and imported state
-> bundle
-> getters and selectors
-> explicit operations
-> session outputs
-> promoted artifacts
-> provenance graph and report
```

The bundle is the unit of exchange. It can hold matrices, embeddings, cell
sets, feature sets, fitted models, artifacts, reports, and provenance. A
result should remain understandable after the original operator, notebook, or
user interface is gone.

### Core Terms

| Term | Meaning |
| --- | --- |
| Bundle | Portable persistent analysis state. |
| Getter | Stable read API for bundle state. Getters, not direct storage access, define the supported view of data. |
| Selector | Reproducible rule for choosing cells or features. |
| Primitive | Typed computational input/output, such as a matrix, space, cell vector, feature table, model reference, or path family. |
| Operation (op) | Explicit computation with declared inputs, parameters, outputs, and provenance. |
| Session | Exploratory chain of operation runs. Outputs are held in a session-local staging view until promotion. |
| Promotion | Atomically committing selected terminal outputs as typed artifacts plus their required ancestral provenance/materializations. |
| Artifact | A promoted result that can be loaded, inspected, plotted, cited, or used by later operations. |
| Provenance graph | The bundle-level graph linking source state, runs, artifacts, inputs, parameters, and derived results. |

## Non-Negotiable Rules

1. **Preserve an auditable scientific trail.** Every scientifically meaningful
   transformation, selection, statistical test, model fit, or derived
   diagnostic must be performed through a registered operation or
   provenance-aware wrangler and leave an auditable trail in the bundle.
   Reports may summarize recorded evidence; they may not create unrecorded
   scientific results.
2. **Use documented engine interfaces.** Do not read SQLite tables, matrix
   files, or artifact payload files directly when a getter or artifact API
   exists.
3. **Discover before executing.** Inspect bundle state and operation interfaces
   before choosing an analysis method or constructing inputs.
4. **Do not overwrite scientific alternatives.** A changed upstream choice is
   a sibling branch, not a replacement for an earlier map, model, or result.
5. **Use named, durable selections.** When a scientific group matters to a
   result, materialize or record its selector/cell-set definition rather than
   passing an unexplained literal vector.
6. **Promote intentionally.** Do not promote every exploratory object. Promote
   results that support a conclusion, a reusable workflow, or a meaningful
   branch point.
7. **Keep claims proportional to evidence.** Distinguish an observed pattern,
   an interpretation, and a causal hypothesis.
8. **Report gaps honestly.** If the documented substrate cannot express a
   required step, stop at the boundary and describe the missing capability.
   Do not hide an external workaround inside the bundle.

### What the auditable-transformation law covers

This rule covers source ingestion, normalization, filtering, cell-set
derivation, feature selection, embeddings, model fitting, differential
expression, enrichment, scoring, and metadata diagnostics. It also covers
table and plot views that support a conclusion: use provenance-aware plot or
wrangler contracts and retain their input artifacts and specifications.

Reports and narrative consume recorded evidence; they are not a place to run
hidden analysis. Cosmetic report formatting is exempt, but any computation
that changes a scientific value, membership, test, or
interpretation-relevant summary must be an auditable engine transformation.

## First Contact With a Bundle

Before asking a biological question, establish what the bundle actually
contains.

### Container mount topology

For any operation that can mutate a bundle, bind the bundle's **parent
directory**, not only the bundle directory. scworkbench serializes mutation
with a sibling lock named `.BUNDLE.scworkbench-writer-lock`, so both the bundle
and its parent must be writable inside the container.

```bash
IMAGE=/path/to/scworkbench.sif
HOST_PARENT=/path/to/directory-containing-bundle
BUNDLE_NAME=example.bundle

singularity exec --cleanenv \
  --env BUNDLE_NAME="${BUNDLE_NAME}" \
  --bind "${HOST_PARENT}:/work/bundles" \
  "${IMAGE}" \
  Rscript --vanilla -e '
    library(scworkbench)
    b <- wb_open_bundle(file.path("/work/bundles", Sys.getenv("BUNDLE_NAME")))
    on.exit(wb_close_bundle(b), add = TRUE)
    # Run documented mutation/session operations here.
  '
```

Equivalently, put `BUNDLE_NAME` in the R script. The important invariant is
that the container path has a writable parent.

Do not use `--bind BUNDLE:/bundle` for a writable workflow. That layout makes
the required sibling lock `/.bundle.scworkbench-writer-lock`, normally under
the container's immutable root. A timeout showing `owner_status=absent` and a
root-level lock path indicates an invalid mount topology, not lock contention;
do not run stale-lock recovery. Rebind the parent directory and retry.

Direct bundle binding remains appropriate for immutable recipient inspection:

```bash
singularity exec --cleanenv \
  --bind "${HOST_BUNDLE}:/bundle:ro" \
  "${IMAGE}" \
  Rscript --vanilla -e '
    library(scworkbench)
    b <- wb_open_bundle("/bundle", read_only = TRUE, validate = TRUE)
    on.exit(wb_close_bundle(b), add = TRUE)
  '
```

### 1. Open and inspect

Use the supported client for your environment. In R, the minimal pattern is:

```r
b <- wb_open_bundle("/path/to/bundle")
on.exit(wb_close_bundle(b), add = TRUE)

wb_manifest(b)
wb_status(b)
wb_matrices(b)
wb_spaces(b)
wb_cell_sets(b)
wb_feature_sets(b)
wb_art_list(b)
```

Establish at least:

- available matrices, feature identifiers, and cell coverage;
- available spaces/embeddings and whether they are imported or derived;
- metadata fields, cell sets, feature-set namespaces, and model artifacts;
- existing promoted results and their provenance status;
- missing metadata or source limitations relevant to the question.

### 2. Read provenance before reusing a result

If an existing artifact or map is relevant, inspect its identity and lineage
before treating it as input:

```r
wb_art_identity_card(b, artifact_id)
wb_art_birth_certificate(b, artifact_id)
wb_prov_artifact_lineage(b, artifact_id)
```

Ask: what created it, from which matrix/cells/space, with which parameters,
and is it accepted or only exploratory?

### 3. Inspect operation capabilities

Never invent an operation name or assume parameter names from another tool.
Discover capabilities from the engine:

```r
wb_list_ops()
wb_op_interface("operation_name", bundle = b)
```

The interface is authoritative for required inputs, accepted reference shapes,
parameters, outputs, runtime requirements, and promotion behavior. Semantic
catalog/search clients may assist discovery, but the operation interface is the
final execution contract.

Supply every operation input and parameter exclusively through the named
`inputs` list. `wb_session_run_op(..., top_n = 3)` is rejected; use
`inputs = list(..., top_n = 3)` so the complete execution contract is visible
and recorded with the run.

## From Scientific Question to Computation

Decompose a question into explicit, evidence-bearing subquestions. For
example, a request to compare programs along a trajectory may require:

1. Which cells belong to the biological population of interest?
2. Which matrix is appropriate for the requested signal?
3. Does a defensible trajectory/model already exist, or must one be derived?
4. Which feature-set namespace or gene program collection is applicable?
5. Which dynamics result would support the requested conclusion?
6. What alternative explanation or upstream choice must be checked?

Do not assume that a label, trajectory, embedding, or model is biologically
valid merely because it exists in a bundle. Inspect its source, membership,
coverage, and provenance. When biology is ambiguous, state the ambiguity and
propose a bounded analysis or request human judgment.

## Execution Loop

### 1. Define the analysis universe

Use existing named sets where appropriate. For a new scientific universe,
create a reproducible selector recipe or cell set with a clear role and
description. Record why the selection is scientifically appropriate and report
its cell count.

Avoid unnamed positional subsets and long literal lists of cell IDs except when
they are unavoidable source facts.

### 2. Create an explicit session

In R, use the session API for connected analysis steps:

```r
s <- wb_session_new()
result <- wb_session_run_op(
  session = s,
  bundle = b,
  op_name = "operation_name",
  inputs = list(
    # operation-specific inputs and parameters from wb_op_interface()
  ),
  notes = "Scientific purpose and decision context"
)
s <- result$session
```

Outputs from this call are not yet portable bundle state. Continue the analysis
through typed session references, and inspect staged matrices or spaces through
the public session view:

```r
staged <- wb_session_view(s)
wb_matrices(staged)
wb_spaces(staged)
```

Discard exploratory work explicitly with `wb_session_discard(s)`. Do not read a
staged output from `b` before promotion.

The exact input names and reference shapes must come from
`wb_op_interface()`. Do not substitute aliases such as `model_ref` for `model`
unless the interface explicitly accepts them.

### 3. Inspect before continuing

After every consequential operation, inspect dimensions, coverage, diagnostics,
and output identity. For an expensive or biologically consequential result,
also inspect the current session DAG and the operation's recorded parameters.

Stop or branch when the evidence contradicts the assumed analysis path. Do not
continue a pipeline merely because it was proposed before inspecting the data.

### 4. Promote durable results

Promotion turns selected session outputs into reusable artifacts and writes a
provenance snapshot:

```r
wb_session_promote_current(
  bundle = b,
  session = s,
  outputs = c("terminal_output"),
  name_prefix = "analysis_name",
  created_by = "operator",
  fail_fast = TRUE
)
```

Promote the results needed to support a conclusion and the inputs needed to
revisit it. Typical examples include derived matrices, embeddings, fitted
models, trajectory vectors, differential-expression tables, pathway tables,
and fit diagnostics.

### 5. Branch rather than overwrite

When changing normalization, feature selection, cell universe, model,
trajectory endpoint, or other upstream assumption, preserve the original
analysis and construct a named sibling branch. The provenance graph should
make the common ancestor and changed decision visible.

## Reporting Standard

Every substantial analysis should produce a report that allows another person
or agent to understand and challenge it. Include:

1. **Question:** the scientific question and decision context.
2. **Input state:** bundle identity, source matrix/space/model/set identifiers,
   and relevant source limitations.
3. **Methods:** operation names, parameters, cell/feature universes, and
   runtime-sensitive settings such as seeds.
4. **Results:** figures/tables linked to artifact and run identifiers.
5. **Interpretation:** what the results support, what they do not establish,
   and plausible alternatives or confounders.
6. **Provenance:** promoted artifact ids, snapshot id, and a bundle-level or
   artifact-level DAG export.
7. **Next decision:** a justified follow-up, branch, validation, or explicit
   stop.

Do not write conclusions that cannot be traced to the bundle's promoted state.

## Imported State Versus Derived State

Imported source objects can contain useful matrices, embeddings, labels, and
models. Preserve them as source state and label them as such. An imported UMAP
is not a scworkbench recomputation, and a source annotation is not automatically
validated biology.

Derived state must identify the exact operation lineage that created it. The
operator should be able to answer, from bundle state alone:

- what was imported;
- what was computed later;
- which upstream choice differs between two derived results; and
- which result is accepted for the present scientific purpose.

## Handling Missing Capability

An analysis gap is valuable evidence. When the requested workflow cannot be
expressed through the supported substrate:

1. capture the question, available bundle state, and the exact attempted
   interface;
2. state the missing primitive, getter, operation, wrangler, or provenance
   contract in domain terms;
3. state whether the gap is a scientific ambiguity, engine-contract gap, or
   runtime/environment gap;
4. avoid implementing analysis logic in a viewer, report script, or agent
   prompt as a hidden substitute;
5. hand the evidence to an engine maintainer for a contract-first decision.

An unsupported generic capability is a stop-and-report condition, never a
justification for an external unrecorded script.

New capability should normally enter the engine as one of:

- a getter for a new supported state-access path;
- a primitive type or extension of an existing primitive contract;
- a registered operation with typed inputs/outputs and promotion coverage;
- a wrangler/plot contract for display transformation;
- a provenance, identity-card, or navigation contract.

## Common Errors

| Error | Correct approach |
| --- | --- |
| Querying SQLite or files directly | Use getters and artifact APIs. |
| Guessing operation names/parameters | Use `wb_list_ops()` and `wb_op_interface()`. |
| Feeding an artifact id where a primitive reference is required | Follow the interface's accepted reference shape. |
| Reusing a model with unrelated pseudotime or lineage weights | Use fit-family-compatible artifacts only. |
| Replacing a map after changing an upstream setting | Create a named sibling branch. |
| Computing a table externally then attaching it as if engine-derived | Report the gap or request an engine capability. |
| Treating a label or UMAP position as a biological conclusion | Inspect provenance, diagnostics, and alternative explanations. |
| Promoting every temporary output | Promote the evidence needed for a durable conclusion or branch. |

## Completion Checklist

Before declaring an analysis complete, confirm:

- [ ] Source and imported state are identified.
- [ ] Matrix, cell universe, and feature universe are explicit.
- [ ] Every computation used a documented operation.
- [ ] Every interpretation-relevant table or plot uses retained,
  provenance-aware inputs and specifications.
- [ ] Current operation interfaces were consulted before execution.
- [ ] Durable results are promoted and loadable as typed artifacts.
- [ ] Provenance can explain the reported result from its inputs.
- [ ] Alternative choices are branches, not overwritten history.
- [ ] Report claims, limitations, and next decisions are explicit.

## Further Reference

This guide is the platform-neutral starting point. For detailed interfaces,
consult the generated package reference and these repository documents:

- `docs/ingestion.md` for supported source-container paths;
- `docs/getter_catalog_reference.md` for stable read surfaces;
- `docs/op_catalog_reference.md` for operation discovery;
- `docs/primitive_catalog_reference.md` for typed inputs/outputs;
- `docs/artifact_type_catalog_reference.md` for promoted-result contracts;
- `docs/wrangler_catalog_reference.md` and `docs/plot_catalog_reference.md`
  for renderer-independent display data;
- `docs/semantic_catalog_reference.md` for semantic discovery;
- `docs/extension_engineering.md` when an identified gap needs an engine
  change.
