# Motif Contracts And chromVAR

This document explains the new motif-related engine surfaces in `scworkbench`:

- matrix genome metadata
- motif library registry
- motif definition registry
- motif-match registry
- `chromvar` as an op consuming those contracts

This is the canonical architecture note for motif work. Do not treat the Shiny
client or ad hoc package-name arguments as the source of truth.

## Why This Exists

The old `chromvar` spike proved the compute path, but it did not yet express the
right friendships in the engine.

The correct friendship model is:

- peak matrix -> genome build
- motif library -> motif definitions
- motif definitions + peak matrix + matching policy -> motif matches
- chromVAR -> motif activity over a peak matrix using a motif library or cached
  motif matches

This keeps motif identity, motif matching, and motif activity as distinct engine
objects.

## 1. Matrix Genome Contract

Peak matrices are expected to carry explicit genome metadata in the matrix
registry.

Canonical fields:

- `organism`
- `genome_build`
- optional `genome_provider`

Canonical write path:

- `wb_matrix_set_genome(bundle, matrix_id, organism, genome_build, genome_provider)`

Why it matters:

- clients should not guess genome/build from matrix names
- chromVAR and future regulatory ops need explicit genome semantics
- motif libraries and motif matches can be validated against the matrix

Example:

```r
wb_matrix_set_genome(
  b,
  matrix_id = "ATAC_counts",
  organism = "mouse",
  genome_build = "mm10",
  genome_provider = "BSgenome.Mmusculus.UCSC.mm10"
)
```

## 2. Motif Library Contract

Motif libraries are first-class engine objects. They are not feature sets.

Canonical registry:

- `motif_libraries`

Identity fields:

- `motif_library`
- `source_type`
- `organism`
- `genome_build`
- `collection`
- `source_id`
- `source_version`

Canonical APIs:

- `wb_motif_library_register()`
- `wb_motif_libraries()`
- `wb_motif_library_import_jaspar()`

Typical intent:

- define one named motif universe
- keep source/version/species explicit
- allow ops to consume a stable library key instead of raw package names

Example:

```r
wb_motif_library_register(
  b,
  motif_library = "jaspar2020_core_mouse",
  source_type = "jaspar",
  organism = "mouse",
  genome_build = "mm10",
  collection = "CORE",
  source_id = "JASPAR2020",
  source_version = "2020"
)
```

## 3. Motif Definition Contract

Motifs are first-class biological objects within a library.

Canonical registry:

- `motifs`

Identity fields:

- `motif_key` as the canonical engine identifier
- optional external `motif_id`
- `motif_name`
- `matrix_class`
- `payload_json`
- `metadata_json`

Canonical APIs:

- `wb_motif_register()`
- `wb_motifs()`

Important rule:

- every motif needs an engine key
- not every motif needs a global external catalog ID

This supports both catalog motifs and custom motifs.

## 4. Motif Match Contract

Motif definitions and motif-to-peak matches are different contracts.

Motif definition answers:

- what motif is this?

Motif match answers:

- where did this motif match in this peak universe under this policy?

Canonical registries:

- `motif_match_sets`
- `motif_match_membership`

`motif_match_sets` stores identity and provenance:

- `motif_match_set`
- `matrix_id`
- `motif_library`
- `organism`
- `genome_build`
- `genome_provider`
- `match_engine`
- `match_params_json`

`motif_match_membership` stores edges:

- `motif_match_set`
- `motif_key`
- `feature_id`

Canonical APIs:

- `wb_motif_match_sets()`
- `wb_motif_match_replace()`
- `wb_motif_match_get()`

Why this matters:

- match results are matrix-specific materializations
- provenance for the matching policy is explicit
- downstream ops can reuse cached motif annotations without rerunning matching

Example:

```r
wb_motif_match_replace(
  b,
  motif_match_set = "mm10_core_matches_v1",
  matrix_id = "ATAC_counts",
  motif_library = "jaspar2020_core_mouse",
  matches = data.frame(
    motif_key = c("MA0004.1_Arnt", "MA0497.1_Mef2c"),
    feature_id = c("chr1:100-199", "chr1:300-399")
  ),
  organism = "mouse",
  genome_build = "mm10",
  genome_provider = "BSgenome.Mmusculus.UCSC.mm10",
  match_engine = "motifmatchr",
  match_params = list(p_cutoff = 5e-05, w = 7L)
)
```

## 5. What A Feature Set Is Still Good For

Feature sets are still useful, but not as the canonical motif definition layer.

A feature set can represent:

- a cached set of peaks matched by one motif
- a motif-derived peak program

A feature set should not be the canonical place for:

- the PWM/PFM itself
- motif identity across libraries
- motif source/version metadata
- matching policy provenance

In short:

- motif = biological object
- motif match = matrix-specific annotation materialization
- feature set = optional downstream convenience view

## 6. chromVAR Contract

`chromvar` is an op, not a special subsystem.

Canonical engine entry:

- `wb_op_chromvar()`

Required contract inputs:

- peak matrix with matrix-level genome metadata
- `motif_library`

Optional inputs:

- `motifs` subset within the library
- `motif_match_set` to reuse cached motif-to-peak matches
- `seqlevels_mode`, defaulting to `"standard"`
- optional `seqlevels_include` / `seqlevels_exclude`

Outputs:

- `deviation_z` as `cell_vector_family`
- `deviation_raw` as `cell_vector_family`
- `motif_summary` as `obs_table`

Current behavior:

- if `motif_match_set` is provided, `chromvar` validates it against the matrix
  and motif library, then reuses cached motif matches
- otherwise `chromvar` computes motif matches internally with `motifmatchr`
- by default `chromvar` keeps only standard chromosomes from the loaded genome;
  nonstandard contigs are excluded unless the user asks for `seqlevels_mode =
  "all"` or provides explicit seqlevel controls

Example:

```r
res <- wb_op_chromvar(
  bundle = b,
  matrix_id = "ATAC_counts",
  cells = wb_cells(b),
  motif_library = "jaspar2020_core_mouse",
  motif_match_set = "mm10_core_matches_v1"
)
```

## 7. Recommended Workflow

For a clean engine-native workflow:

1. attach or create a peak matrix
2. set matrix genome metadata with `wb_matrix_set_genome()`
3. register or import a motif library
4. optionally materialize motif matches as a named `motif_match_set`
5. run `chromvar` against the library or cached match set

This gives you explicit identity and provenance at every layer.

## 8. Design Rules

When extending motif/regulatory support, keep these rules:

- do not collapse motifs into feature sets
- do not make client code the source of motif semantics
- do not pass raw package names as the long-term public contract when a named
  engine object should exist
- do not let chromVAR become the only consumer of motif contracts

Expected future consumers of the same contract surface:

- motif enrichment
- motif activity summaries
- regulator prioritization
- trajectory or branch-level motif analysis
- de novo motif comparison workflows

## 9. Where To Look In Code

Main files:

- `R/motif_registry.R`
- `R/op_chromvar.R`
- `R/op_catalog.R`
- `inst/foundation_contracts.md`

Contract tests:

- `tests/test_motif_registry_contract.R`
- `tests/test_motif_match_contract.R`
- `tests/test_op_chromvar_contract.R`
