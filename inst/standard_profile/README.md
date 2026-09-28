# scworkbench standard profile (v1)

This optional source-distributed profile selects exactly seven accepted R
operation packs. The core still works by itself. Installing scworkbench or a
pack never activates it. The profile is not a marketplace, signature system,
or ambient discovery mechanism.

The profile lock names the exact source commits, package versions, original
manifest bytes and canonical manifest identities for scwbStatistics,
scwbGenePrograms, scwbRNA, scwbRepresentation, scwbTrajectory, scwbLatent and
scwbATAC. Those packs contribute 56 normal scientific operations; core
contributes five. Protocol/conformance fixtures are not part of the profile.

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
The interpreter must provide scvi-tools, anndata, scipy and
CPU torch. This step does not run any scientific operation.

In every R process that needs the full profile, opt in explicitly:

```r
.libPaths(c("/path/to/clean-r-library", .libPaths()))
library(scworkbench)
source(system.file("standard_profile", "activate.R", package = "scworkbench"))
Sys.setenv(SCWB_LATENT_PYTHON = "/path/to/cpu-python")
profile <- scwb_standard_profile_activate(
  "/path/to/standard-profile-receipt.json",
  lib.loc = "/path/to/clean-r-library")
stopifnot(nrow(wb_operation_packs()) == 7L, length(wb_list_ops()) == 61L)
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
