# Final harness independent review (development helper)

Reviewed `../full_engine_xenopus.R` against the public import/session/promotion/
finalization APIs, current table writer/loader, pinned RNA and Representation
algorithm sources, and retained direct-reference script. No workflow was run.

One actual invocation defect was corrected: the candidate core-only library does
not contain either pack. The harness now takes an optional explicit fourth
`PACK_LIBRARY` argument, defaulting to the repaired verified library, and keeps
the candidate core first in `.libPaths()`. Activated pack identities are retained.

Additional harness assertions now authenticate both frozen reference RDS files;
retain/check every original imported space; compare HVG categorical fields and
PCA component/source annotations; require exactly the seven selected promoted
terminals; retain readiness; verify durable feature/cell axes and normalized
boundary-block values; and reopen the contained uwot model to compare its
embedding. These strengthen coverage without changing scientific tolerances or
running another full normalization comparison after reload.

The public `wb_bundle_validation_report(..., level='recipient')` remains the one
explicit full recipient gate, after read-only reopen/inspection and close. The
finalizer's readiness check and authenticated model loading are different
boundaries, not substituted recipient passes. Getter fingerprint purity is
asserted by the report. The dense guard is asserted to remain its ordinary 256 MB.

No numerical exceptions were added. Full-precision staged comparisons retain
the previously declared normalization/HVG/PCA/UMAP tolerances. Persisted table
values are compared exactly to the pre-existing default-precision JSON encoding,
separately from scientific comparisons; this does not waive scientific drift.
A five-value pure scalar-versus-vector JSON probe (zero, tiny, ordinary, large,
negative tiny doubles) passed. Existing focused encoder tests provide broader
scalar/row-byte equivalence coverage; the harness is not a replacement for them.

Added `../sample_workflow_resources.py`, an explicitly launched read-only sampler
for one PID and caller-specified owned roots. It launches no jobs, refuses `/`,
does not follow symlinks, deduplicates inodes, samples every five seconds, and
stops on PID reuse. Disk samples are lower bounds; GNU time is authoritative for
peak RSS. To cover transient R storage the final supervisor must provide its
explicit dedicated R temporary root as the optional fourth sampler argument.

Lightweight results: `Rscript` parse `HARNESS_PARSE_OK`; Python 3 AST parse
`SAMPLER_PARSE_OK`; JSON probe `SCALAR_VECTOR_PRECISION_PROBE_OK`;
`git diff --check` exit 0. The initial `python` invocation was unavailable
(exit 127); corrected executable/documentation is `python3`. No final-gate pass
is claimed by this static review, and no runtime/pack implementation was edited.
