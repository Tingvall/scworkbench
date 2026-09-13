# Phase 0 repository and namespace recommendation

## Recommendation

Use one Git repository per coherent scientific pack, with the R package name requested by the Controller and a lowercase machine namespace that is stable across R and Python packaging.

| Role | Git repository / R package | Canonical operation namespace | Python distribution, if needed | Notes |
| --- | --- | --- | --- | --- |
| RNA | `scwbRNA` | `scwbrna` | none initially | Avoids collision with core and permits `scwbrna::hvg_select`. |
| Representation | `scwbRepresentation` | `scwbrepresentation` | none initially | Backend packages remain operation-level dependencies. |
| Gene programs | `scwbGenePrograms` | `scwbgeneprograms` | none initially | Namespace is explicit rather than abbreviated “gsea”. |
| Statistics | `scwbStatistics` | `scwbstatistics` | none initially | Retains both association operation names until adjudication. |
| Trajectory | `scwbTrajectory` | `scwbtrajectory` | PyBench Palantir capability, not a second state package | One initial pack with internal engine-specific modules. |
| Latent models | `scwbLatent` | `scwblatent` | prefer `scwb-latent` only if code is actually split from PyBench | The current R contract delegates through pinned PyBench protocol 2. Do not create a redundant Python distribution without a release need. |
| ATAC | `scwbATAC` | `scwbatac` | none initially | Small now, reserved for the coherent accessibility method family. |
| Conformance fixture | `scworkbenchOperationPackConformance` | `scwbconformance` | `scwb-operation-pack-conformance` if cross-language fixtures require it | Test-only; never part of the default scientific catalog. |
| Standard profile | `scworkbenchStandard` | no operation namespace | optional metapackage/profile only | Depends on/install-recommends the seven packs; activation stays explicit. |

R package names satisfy the manifest's R-name pattern; namespaces satisfy the v1 lowercase namespace pattern and avoid reserved `scworkbench`, `core`, `wb`, `internal`, and base-package names. Before repository creation, the Controller should check public Git host, CRAN/Bioconductor and Python-index collisions. No availability claim is made here.

Fully qualified identities follow `<namespace>::<current_name>`, as enumerated in `core_to_packs_phase0_operation_baseline.{json,csv}`. Package display case is not part of the operation identity. Repositories should carry independent versions and release cadence; the standard profile pins a tested compatible set rather than forcing synchronized releases.

## Discoverability and authority boundaries

- Repository descriptions should say “operation pack for scworkbench” and list typed inputs/outputs and compatibility ranges.
- Documentation is pack-owned; state formats, identity allocation, staging, publication, provenance, promotion, replay and recipient validation remain core-owned.
- Packs are trusted installed code and explicitly activated. Namespace qualification is not cryptographic authentication or sandboxing.
- One repository per operation would fragment dependencies and review. Combining all packs would defeat independent optional stacks and release cadence.

These names are recommendations, not created namespaces or reserved distribution names. Final approval belongs to the Controller before ABI manifests or repositories are authored.
