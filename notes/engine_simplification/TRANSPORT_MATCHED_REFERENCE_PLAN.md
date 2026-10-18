# Preregistered supplemental scientific reference

## Correction after the retained failed supplemental comparison

The historical plan below is **superseded, not an accepted transport contract**.
Its premise was incorrect. `R/operation_pack_v3_materializations.R` defines
`.wb_matrix_write_continuous()` (lines 3–17) as a general sparse/double BPCells
write; `write_fragment()` calls it directly. Native-R normalization output does
not pass through Matrix Market. The original efficient direct driver uses the
same full-double storage route. Only the supplemental driver added `%.15g`
rounding. The private-input Matrix Market adapter is a different boundary.

The frozen 8614/ba351 supplemental run and its exit 1 are retained at
`/tmp/scwb-engine-simplification-forge-20261018/final_ba351cd_measurements`.
HVG and sign-aligned PCA passed, but UMAP differed by 8.34949224539328 against
the unchanged 1e-6 criterion; promotion/finalization/recipient validation were
not reached. This is not a successful end-to-end qualification. The read-only
diagnosis found 1,726,891 differing normalized PCA-input values (maximum
5.3290705182007514e-15) and 15 sign-flipped leading PCA components. A separate
1,000-value probe found R and BPCells decimal parsing identical, disproving
the initially suspected parser explanation.

Forge owns the erroneous reference design. The Sable-role reviewer independently
confirmed the source contradiction and withdrew the earlier endorsement of
that premise. Preserve both frozen references, scripts, raw failures and
diagnoses. Restoring the **original**, independently frozen full-precision
reference is a comparator correction, not a tolerance or seed waiver. Verify
the actual normalization and PCA-input contracts independently before using it;
retain all original scientific thresholds. Do not substitute a conditional
UMAP rerun for end-to-end evidence.

The subsequent read-only proof at
`/tmp/scwb-engine-simplification-forge-20261018/unrounded_reference_ba351cd`
exited 0: all 659,950 staged PCA values and all 26,398 staged UMAP values were
bit-identical to the original reference, whose SHA-256 remains
`bb8a84d8cd68c494f7735509539d2b5362a2f257f511f05ca3cabdf4874ee5fb`.
All 1,000 sampled normalized values matched unrounded arithmetic exactly.
These are reused-output diagnostic checks, not a new complete workflow or
promotion/recipient-validation pass. Final qualification must use a fresh
workflow with that original reference and unchanged thresholds.

## Historical preregistration (preserved verbatim below)

Before any combined-candidate full Xenopus run (2026-10-18): the original
direct workflow writes full-double normalized values directly to BPCells. Core
preserves the existing native Matrix Market 15-significant-digit roundtrip.
Neither the scientific formula nor that transport representation is changed by
this repair. Small input differences can affect an iterative UMAP; identical
backend/seed does not establish identical input values.

Keep the original frozen direct artifacts and efficient direct driver unchanged.
The original efficient driver SHA-256 is
`63356e37688cc8af7fa0406445de25b65c3fc3fc073bd6ed67c693f62d7bd565`.
Its observed complete-workflow timing remains the original performance-budget
denominator. No supplemental cost is added to that denominator to make a budget
easier to pass.

Before running the candidate, generate a **separate supplemental reference** with
the same source checksum, axes, algorithms, parameters, packages, seeds, threads
and storage backends. Independently roundtrip normalized nonzeros through base
`sprintf("%.15g")` and numeric parsing before writing double BPCells fragments.
Do not use engine helpers or candidate results to construct it. Chunk this
conversion at 65536 nonzeros, without raising the ordinary dense guard. Retain
source-read, arithmetic, writing and verification timings; this is not a faster
direct-performance substitute.

Prepared external driver:
`/tmp/scwb-engine-simplification-forge-20261018/direct_xenopus_transport_matched.R`;
SHA-256 `daa8b938d4a63e806ed61caec0d3ec1558c86d4d7d376fbaf9d34fb645de0248`.
Parsing passed; it has not run at preregistration. Its old-reference diagnostic
retains threshold failures instead of falsely advertising exact reproduction
across different stored inputs. Its own mathematical normalization verification
and durable reopen checks remain mandatory.

The full engine gate uses the independently generated supplemental RDS SHA
recorded **before** engine execution. Keep original source/axis SHA assertions.
Require the original exact/tolerance criteria against this matched end-to-end
reference: all normalized values 1e-14 absolute, HVG IDs/ranks/order exact and
statistics 1e-12 absolute+1e-10 relative, sign-aligned PCA 1e-7 absolute+1e-6
relative, variance 1e-8 relative, UMAP 1e-6 absolute. No tolerance/seed may be
selected after inspecting candidate results. Record exact actual leading-PCA
input equality and maximum difference separately, without substituting a
conditional UMAP execution for independent end-to-end qualification.

Also compare normalized blocks against the ORIGINAL full-double direct output
at its original 1e-14 threshold. Record original HVG, PCA and UMAP thresholds
separately, including the original UMAP 1e-6 absolute test. A discrepancy remains
`threshold_not_met`; it must not be relabeled PASS, hidden by the supplemental
reference or claimed as old-reference exact reproduction. No discrepancy has
yet been observed: this predeclaration corrects a source-confirmed comparator
input mismatch, not a response to a failed candidate run.

If the strict transport-matched end-to-end gate fails, preserve that failure and
diagnose it. An exact-engine-input direct UMAP is permissible only as a separately
labelled stage-conditional diagnostic, never a replacement end-to-end pass.
Independent Sable-role source prereview agreed these boundaries; exact prepared
driver/harness review remains required before execution. No scientific pack,
source bundle, old reference, runtime identity scheme or public contract changes.
