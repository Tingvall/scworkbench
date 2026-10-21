# Native Standard-Profile Rebuild

Use an existing, working standard-profile SIF of the same architecture as the
dependency base. For Arrhenius, use the ARM64 image that already includes
ruptures and the latent Python dependencies. This rebuild replaces core,
PyBench and the seven pinned packs; it does not reinstall the scientific stack.
The same helper supports native AMD64. Cross-architecture building is not provided.

For GPU scVI, the base must already contain CUDA-enabled PyTorch compatible with
the allocated node. The helper deliberately does not replace Torch. `--nv` exposes
NVIDIA drivers/devices but cannot turn CPU-only Torch into a CUDA build. A build
and activation smoke on CPU are not GPU qualification.

Update the source repositories first:

```bash
git -C /path/to/scworkbench pull --ff-only origin master
git -C /path/to/pybench pull --ff-only origin main
```

Keep the seven pack repositories under one parent directory. The helper reads
their exact commits and manifest checksums from `inst/standard_profile/profile.json`
and makes detached clean clones. Those commits must be available locally. Core
and PyBench must be clean; PyBench HEAD must match the profile pin. Existing
output/context paths are never removed: choose new ones for each build.

On a native build node with fakeroot enabled:

```bash
bash /path/to/scworkbench/containers/apptainer/build_standard_profile.sh \
  /path/to/current-working-arm64-with-ruptures.sif \
  /path/to/new-standard-profile-arm64.sif \
  /path/to/pybench \
  /path/to/operation_packs \
  /path/to/new-build-context \
  > /path/to/new-standard-profile-build.log 2>&1
```

Use the existing cluster allocation/submission wrapper around this command.
Monitor with `tail -f /path/to/new-standard-profile-build.log`. The helper uses
`apptainer`, falling back to `singularity`; override with `SCWB_CONTAINER_ENGINE`.
Set `SCWB_PREPARE_ONLY=1` to inspect the source context and generated definition
without invoking the container runtime.

The context retains `standard_profile.def`, `build_sources.env`, pinned Git
clones and, after success, `image.sha256`. Labels and provenance are generated
from the actual core HEAD, profile PyBench pin, profile SHA-256 and base image
SHA-256. There is no manually maintained core self-pin.

The installer generates a fresh receipt **inside the image at final paths**;
do not copy a host receipt. Builds run dependency import checks, and the helper
then runs the focused profile activation/provenance/rollback/idempotence smoke
test. This is not ARM64 scientific/performance qualification. Existing timings
belong to their documented host runtime; fast-path eligibility can differ with
R, jsonlite and backend versions. No full scientific benchmark is run by this helper.

Activate explicitly in each analysis R process:

```r
library(scworkbench)
source(system.file("standard_profile", "activate.R", package = "scworkbench"))
scwb_standard_profile_activate("/opt/standard_profile_installation_receipt.json")
stopifnot(nrow(wb_operation_packs()) == 7L, length(wb_list_ops()) == 62L)
```

Before launching Honeybee, run the retained synthetic GPU gate inside the new
image on an allocated job with exactly one scheduler-visible CUDA device:

```bash
apptainer exec --nv --cleanenv /path/to/new-standard-profile-arm64.sif \
  env SCWB_LATENT_PYTHON=/opt/pyenv/bin/python \
  Rscript /opt/operation_packs/scwbLatent/tests/composite/run_scvi_gpu_smoke.R
```

Use the site's actual container executable and scheduler-provided device setup.
Do not seize a GPU from the Council model server. The script must end with
`SCVI_GPU_SMOKE_PASS`; CPU fallback or an unavailable-GPU stop is not a pass.
