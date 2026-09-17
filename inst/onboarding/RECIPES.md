# Agent Recipes

Canonical workflows as reusable patterns.

## 0. Mount a Bundle in a Container

Writable workflow:

```bash
singularity exec --cleanenv \
  --bind "/host/project:/work/project" \
  "/path/to/scworkbench.sif" \
  Rscript --vanilla /work/project/run_analysis.R
```

Inside `run_analysis.R`, open a bundle below the mounted parent, for example
`/work/project/example.bundle`. scworkbench creates the exclusive sibling
writer lock beside the bundle, at
`/work/project/.example.bundle.scworkbench-writer-lock`.
Binding only the bundle to `/bundle` is therefore not a valid writable
scworkbench topology, even when the bind itself lacks `:ro`.

Recipient audit:

```bash
singularity exec --cleanenv \
  --bind "/host/project/example.bundle:/bundle:ro" \
  "/path/to/scworkbench.sif" \
  Rscript --vanilla -e '
    library(scworkbench)
    b <- wb_open_bundle("/bundle", read_only = TRUE, validate = TRUE)
    on.exit(wb_close_bundle(b), add = TRUE)
  '
```

## 1. DE Between Two Sets

Inputs:
- `matrix` (e.g. `RNA_counts`)
- `group_a` and `group_b` (`set:<name>`)

Pattern:
1. `wb_session_run_op(..., op_name = "de_wilcox", inputs = list(matrix=..., group_a=..., group_b=...))`
2. Promote `de_table`
3. Export DE table + volcano + MA plot

## 2. Pathway Enrichment From DE

Inputs:
- DE `feature_table`
- namespace (e.g. `bcell_gsea`)

Pattern:
1. Build query table from significant genes (or top-N policy).
2. Activate `scwbGenePrograms`, then run `scwbgeneprograms::pathway_enrich` for up and down branches.
3. Promote pathway outputs.
4. Plot top pathways (`-log10(adj p)` bars).

## 3. Cluster -> Markers -> Pathways

Pattern:
1. `leiden` on selected space.
2. `markers_topn` with cluster vector.
3. Per-cluster pathway enrichment using selected namespace.
4. Emit summary manifest and pathway-per-cluster table.

## 4. Neighbor-Based Pseudobulk

Pattern:
1. `knn_neighbors` or `knn_pseudobulk` using latent space.
2. Optional candidate pool defaults to all cells.
3. Promote pseudobulk table + neighbor diagnostics.

## 5. Reporting Bundle

Always emit:
- `report.md`
- `report.html`
- `analysis_script.R`
- `run_context.json`
- `dag_nodes.csv` + `dag_edges.csv`

## 6. Set Recovery

If a set was deleted but cells still exist:
- recover from known IDs via `wb_cell_set_replace()`.
- if needed, reconstruct from `all` minus baseline/core set or dataset filters.
