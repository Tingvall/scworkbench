# Source declarations and preflight

Source identity is explicit. `public_file` and `external_file` describe files;
`in_memory` records a truthful nonportable user-object boundary; and
`internal_assembly` is reserved for automatic engine events. Internal assembly
events remain provenance runs but are not external-source nodes. In-memory
sources are visible as `in_memory_source`/`InMemorySource`, distinct from public
files.

Strict file declarations require `source_id`, `role`, `format`, a
local `path` or declared `uri`, and SHA-256. `public_file` additionally requires
an archive accession. A local `external_file` does not require an accession;
`accession_derived = TRUE` still requires the accession used to form its URI.
Construct declarations without shell-output
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


## Original files and converted objects

`wb_bundle_from_sce(readRDS(path), ...)` receives an in-memory object, so it
cannot infer the original RDS path or its checksum. Pass the RDS path itself to
`wb_bundle_from_sce(path, ...)` to retain the supplied file's SHA-256 and format.
The same distinction applies to a separately converted H5AD: an SCE with
`source_identity = NULL` identifies only the in-memory boundary.

For a source-preserving pure-R H5AD route, use the native wrapper with its R
reader selection; it records the checksummed original file and the converted
SCE as its existing `CONVERTS_TO` child, even without a report artifact:

```r
options(scworkbench.h5ad_reader = "R")
source <- wb_source_input(path = "input.h5ad", source_id = "local_h5ad",
  role = "source_object", format = "h5ad", scope = "external_file")
b <- wb_bundle_from_h5ad("input.h5ad", "analysis.scwb",
  source_identity = list(inputs = list(source)))
```

Known archive accessions, citations, release labels and other attribution can
be supplied in `source_identity`; omitting an unknown local accession is valid.
No checksum of a serialized SCE is substituted for the original file checksum.

External source certificates retain the declaration when the file is absent
from a relocated bundle. Their `details$availability` is `external_uninspected`
with reason `identified_source_not_bundled`: the file is not available *in the
bundle*, and host-file presence is deliberately not inspected. A checksum
remains a declaration at recipient inspection, not a claim that external bytes
were rechecked. In-memory boundaries retain scope `in_memory` and checksum status
`nonportable_in_memory`; no original file identity is asserted.
Use explicit source preflight at ingestion for external-byte verification;
ordinary getters/certificates do not rescan external files.
