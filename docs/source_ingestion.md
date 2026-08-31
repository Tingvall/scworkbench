# Source declarations and preflight

Source identity is explicit. `public_file` and `external_file` describe files;
`in_memory` records a truthful nonportable user-object boundary; and
`internal_assembly` is reserved for automatic engine events. Internal assembly
events remain provenance runs but are not external-source nodes. In-memory
sources are visible as `in_memory_source`/`InMemorySource`, distinct from public
files.

Strict file declarations require `source_id`, `accession`, `role`, `format`, a
local `path` or declared `uri`, and SHA-256. Construct them without shell-output
parsing:

```r
input <- wb_source_input(
  path = "library_1.mtx.gz",
  uri = "https://example.org/GSE123/library_1.mtx.gz",
  source_id = "library_1_matrix",
  accession = "GSE123",
  role = "matrix",
  format = "10x_mtx",
  scope = "public_file",
  accession_derived = TRUE
)
identity <- list(dataset_name = "GSE123", inputs = list(input))
wb_source_preflight(identity)
```

`wb_source_sha256()` streams a local file. `wb_source_input()` calculates it
when a local file is supplied without a checksum. `sha256` and `checksum` are
normalized to the same lower-case value; disagreement fails. URI declaration
does not retrieve data and preflight never uses the network.

Constructors accepting `source_identity` run the same canonical preflight
before bundle initialization, parent-directory creation, cell definition,
matrix copying, or staged writes. A malformed strict declaration therefore has
a zero-write failure guarantee. Use `wb_source_preflight(..., strict = FALSE)`
for normalized declarations plus machine-readable diagnostics without creating
a bundle.

External paths are checked only at ingestion preflight. Recipient validation
does not access files outside the bundle. Bundled inputs must instead use a
contained bundle-relative path and are rehashed during content validation.

## Nested H5AD conversion

`wb_bundle_from_h5ad()` records one composed source chain. The checksummed
external H5AD is the authoritative source; the in-memory
SingleCellExperiment returned by format conversion is its `CONVERTS_TO` child.
Both declarations are immutable and the child names its `parent_source_id`.
The conversion is therefore auditable without treating an arbitrary in-memory
object as a replacement external source.

Matrix, imported-space, cell-metadata, and feature-metadata producers consume
that composed chain. The optional ingest report is evidence about the import;
it is not an authoritative producer of those retained entities.
`emit_report_artifact = FALSE` suppresses only the report artifact and retains
the declared source chain.

After transfer, `wb_prov_source_inputs(recipient)` reconstructs the external
declaration, checksum, conversion child, parent, and relation from the bundle.
`wb_entity_certificate()` exposes the same external and conversion nodes in an
imported matrix or space's upstream relationships. Recipient validation fails
when a declared nested chain is missing, forged, or ambiguous.
