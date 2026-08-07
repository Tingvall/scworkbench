# Composite Release Process

scworkbench releases are composite: an R package, a pinned PyBench source
revision, a shared protocol schema, and a qualified Apptainer image. The
authoritative compatibility record is `inst/release/composite_release.dcf`.

## Locked Inputs

- The Bioconductor amd64 base image is pinned by OCI digest in the definition.
- R product/runtime versions are recorded in
  `containers/apptainer/fullstack_r_versions.lock.csv`.
- The complete Python environment is pinned in
  `containers/apptainer/fullstack_python_requirements.lock`.
- BPCells, Monocle3, and PyBench use immutable Git commits.
- The R and Python protocol schemas must have the same recorded SHA-256.

Lock changes are deliberate release changes. Validators fail on drift rather
than silently accepting newly resolved versions.

## Candidate Checklist

1. Merge accepted implementation branches and require clean scworkbench and
   PyBench worktrees.
2. Run `Rscript inst/ci/validate_release_metadata.R . /path/to/pybench`.
3. Run static, generated-document, package-content, canonical complete-
   discovery, bounded PyBench, and fullstack gates from a clean clone.
4. Build R and Python source artifacts with
   `inst/release/build_source_artifacts.sh`.
5. Build the SIF with `containers/apptainer/build_fullstack.sh`; retain the
   image SHA-256 and runtime provenance.
6. Run `containers/apptainer/qualify_fullstack_release.sh` and retain its full
   `Status: OK` log.
7. Run a strict recipient read-only audit on a finalized representative bundle
   and retain the log.
8. Run the scheduled/manual GPU scVI/PeakVI and large-data gates. Record each
   result with `inst/ci/record_manual_gate.sh`; absence is recorded as
   `not_run`, never treated as a pass.
9. Assemble checksummed evidence with
   `inst/release/assemble_release_evidence.sh`. Use `--final` only when both
   manual gates passed.
10. Verify `SHA256SUMS`, tag both repositories, publish the source tarball,
    wheel, sdist, SIF checksum/attestation, qualification log, recipient audit,
    manual-gate evidence, changelogs, and citation metadata.

Release candidates may retain `not_run` manual gates for development. A final
release cannot.
