# scworkbench standard profile (v1)

This optional source-distributed profile selects exactly seven accepted R
operation packs. The core still works by itself. Installing scworkbench or a
pack never activates it. The profile is not a marketplace, signature system,
or ambient discovery mechanism.

The profile lock names the exact source commits, package versions, original
manifest bytes and canonical manifest identities for scwbStatistics,
scwbGenePrograms, scwbRNA, scwbRepresentation, scwbTrajectory, scwbLatent and
scwbATAC. Those packs contribute 57 normal scientific operations; core
contributes five. Protocol/conformance fixtures are not part of the profile.

The graph/changepoint release integration advances PyBench and scwbTrajectory.
Trajectory 0.1.2 adds the single-changepoint operation; the other six pack pins
are unchanged. This integration does not edit any operation manifest or
operation definition. `profile.json` is authoritative for the full revisions;
release metadata binds its exact file SHA-256. A newly synchronized checkout
must match these pins, not an earlier profile's revisions. Rebuild the instance
receipt through the installer; receipts from the earlier profile are invalid
for this lock even when operation definitions are unchanged.

The engine-simplification integration advances PyBench to the delivered protocol
peer without changing any pack pin, manifest, operation identity or operation
count. Use a fresh installation receipt for this profile revision. The optional
trusted-R reader observation redesign is deferred and is not part of this build.
For a native ARM64 or AMD64 rebuild over an existing dependency-complete SIF,
see `containers/apptainer/STANDARD_PROFILE.md` in the source repository.

The scVI GPU-restoration integration selects scwbLatent 0.1.2. CPU remains the
default; explicit `use_gpu = TRUE` requests one CUDA device and must fail rather
than fall back to CPU. Source/CPU checks passed; real allocated-GPU qualification
is still pending. Neither profile activation nor this source pin proves a GPU
fit. The other six pack pins and all operation counts are unchanged. Core ordered
metadata and the pack's shared sparse-matrix loader no longer impose an arbitrary
100,000-cell ceiling. The loader also removes fixed total feature, chunk-count and
nonzero-count caps; its declared per-chunk size bound remains. The complete Python
training matrix still needs sufficient RAM; this is not out-of-core training.

From clean source worktrees at the pinned commits, prepare a clean library and
instance receipt explicitly:

```sh
Rscript --vanilla /path/to/scworkbench/inst/standard_profile/install.R \
  /path/to/scworkbench /path/to/pybench /path/to/operation_packs \
  /path/to/cpu-python /path/to/clean-r-library \
  /path/to/standard-profile-receipt.json
```

The installer checks the core ancestry, exact PyBench and seven pack Git
commits, clean source worktrees, and source manifest checksums before installing
anything. It installs core plus packs without activating them, validates each
installed pack, and atomically writes a receipt outside the R library.
`SCWB_LATENT_PYTHON` is set to the supplied interpreter for scwbLatent's CPU
dependency probe and its venv entry is bound into the installation receipt.
The interpreter must provide scvi-tools, anndata, scipy and Torch with CPU
execution support. GPU scVI additionally requires CUDA-enabled Torch and an
allocated visible device. This step does not run any scientific operation.

In every R process that needs the full profile, opt in explicitly:

```r
.libPaths(c("/path/to/clean-r-library", .libPaths()))
library(scworkbench)
source(system.file("standard_profile", "activate.R", package = "scworkbench"))
Sys.setenv(SCWB_LATENT_PYTHON = "/path/to/cpu-python")
profile <- scwb_standard_profile_activate(
  "/path/to/standard-profile-receipt.json",
  lib.loc = "/path/to/clean-r-library")
stopifnot(nrow(wb_operation_packs()) == 7L, length(wb_list_ops()) == 62L)
```

Before registration, activation checks the installed core instance, all seven
installed pack content identities and their source/manifest receipt bindings,
the five-operation no-pack catalog, pack operation counts and collisions. It
rejects a missing/wrong pack before scientific dispatch; if a later pack
activation fails, newly activated packs are unloaded. Repeating activation
with the same exact installation is idempotent. The returned record and
`wb_operation_packs()` expose actual installed pack SHA-256 identities; every
packed operation's `source_pack` carries the same identity into run provenance.

R source-package installation generates path- and build-dependent metadata and
lazy-load files, so the installed `pack_sha256` is an **instance identity**, not
a stable digest of a Git commit. The source lock therefore pins immutable Git
and manifest identities, while the installer receipt binds the exact installed
trees. A caller-authored receipt is not a source-authenticity claim; use the
source-verifying installer rather than constructing one by hand. No signing or
host isolation is claimed.
