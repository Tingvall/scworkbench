# Apptainer Full-Stack Recipe

This document describes the cluster/container strategy for `scworkbench`.

The goal is not a minimal image. The goal is that the full stack runs:

- `scworkbench`
- `scworkbenchShiny`
- heavy R/Bioconductor ops
- Python-side analysis dependencies used around the workbench

The canonical definition file is:

- `containers/apptainer/scworkbench_fullstack.def`
- `containers/apptainer/build_fullstack.sh`

Base image choice:

- `bioconductor/bioconductor_docker:RELEASE_3_21`

This is preferred over a plain `rocker` base because the current analysis stack
is heavily Bioconductor-weighted.

## Why We Need This

For cluster work, this project has too many moving parts to rely on node-local
R libraries and ad hoc installs:

- Bioconductor version coupling
- `chromVAR`, `motifmatchr`, `BSgenome`
- trajectory packages such as `slingshot` and `monocle3`
- Shiny/UI dependencies
- Python stack for Scanpy/Palantir/scvi/PeakVI workflows, with CUDA-capable PyTorch

If collaborators and cluster jobs are expected to run the same workflows, they
need the same runtime.

## Build Assumption

Build from the `scworkbench` repo root so the definition file can copy both:

- this repo into `/opt/scworkbench`
- sibling `../scworkbenchShiny` into `/opt/scworkbenchShiny`

Recommended build entrypoint:

```bash
cd /path/to/scworkbench
containers/apptainer/build_fullstack.sh
```

This script uses the two-step workflow that proved reliable in practice:

1. build a writable sandbox
2. pack the sandbox into a final `.sif`
3. smoke-test R, Python, and the Shiny launcher

The default outputs are:

- sandbox: `/tmp/scworkbench_fullstack_sandbox`
- image: `/tmp/scworkbench_fullstack_full.sif`

Override them if needed:

```bash
containers/apptainer/build_fullstack.sh \
  /scratch/$USER/scworkbench_fullstack_candidate_sandbox \
  /scratch/$USER/scworkbench_fullstack_candidate_YYYYMMDD.sif \
  /scratch/$USER/scworkbench_fullstack_candidate_context
```

The optional third argument is a temporary compact build context. The build
script excludes local reports, existing SIF files, test outputs, VCS metadata,
and IDE state before `%files` copies source into the image. Set
`KEEP_BUILD_CONTEXT=1` only when diagnosing a failed build.

Do not replace a deployed image based on the build smoke alone. Qualify each
candidate against the current checkout with the non-forced package gate:

```bash
containers/apptainer/qualify_fullstack_release.sh \
  /scratch/$USER/scworkbench_fullstack_candidate_YYYYMMDD.sif
```

Qualification records the image SHA-256 and native R runtime provenance, then
runs `inst/ci/check_release_package.sh`. Promotion requires the normal package
check to end with `Status: OK`; a forced-Suggests result is not sufficient.

If local builds are blocked on the cluster, use a remote builder or build on a
trusted Linux host and copy the `.sif`.

## Why The Script Uses Two Steps

Direct one-shot `.sif` builds were intermittently unreliable in this
environment during final SIF assembly. The stable workflow was:

1. `singularity build --fakeroot --sandbox ...`
2. ensure the launcher is executable in the sandbox
3. `singularity build --fakeroot image.sif sandbox_dir`

That is what the build script codifies.

## What The Image Installs

System layer:

- compiler toolchain
- common R package build dependencies
- geospatial/graphics/HDF5/XML libraries
- Python runtime
- Java
- Pandoc

R layer:

- core engine deps
- Shiny deps
- geometry/trajectory deps
- chromVAR/motif deps
- genome packages for current human/mouse workflows
- `scworkbench` installed from local source

Python layer:

- `numpy`, `pandas`, `scanpy`
- `palantir`
- forked Python `bpcells` with native float/double bundle matrix reads
- `torch` CUDA-capable build
- `scvi-tools`
- notebook-friendly support packages

This Python layer is now sufficient for the current `pybench` method stack, including
`palantir_fit` and the new `peakvi_fit` op. `peakvi_fit` no longer uses
Matrix Market staging, but it also no longer depends on direct Python BPCells
reads on the production path. The current runtime uses R-staged sparse chunks
for the R-to-Python handoff. The image is intentionally built with a
CUDA-capable PyTorch wheel so that scvi/PeakVI workloads can use GPUs on cluster
hardware. At runtime, launch the container with `--nv` and use hosts whose NVIDIA
driver is compatible with the bundled PyTorch CUDA build.

## Running The Engine

Example interactive shell:

```bash
apptainer shell --nv --bind /data:/data scworkbench_fullstack.sif
```

Example engine smoke:

```bash
apptainer exec --nv --bind /data:/data scworkbench_fullstack.sif \
  Rscript -e 'library(scworkbench); print("scworkbench ok")'
```

Example bundle-open smoke:

```bash
apptainer exec --nv --bind /data:/data scworkbench_fullstack.sif \
  Rscript -e 'library(scworkbench); b <- wb_open_bundle("/data/mybundle"); print(wb_matrices(b)); wb_close_bundle(b)'
```

Important:

- bind bundle locations read-write if the workflow needs migrations, reports, or
  registry updates
- do not assume source repos inside the image are writable

If you plan to run `peakvi_fit` inside the container, pass an explicit
`max_epochs` during early smoke or debugging runs. Leaving it fully automatic can
make the training step look hung when it is simply doing a longer scvi training
schedule. For GPU-backed runs, use `apptainer exec --nv ...` or `apptainer shell --nv ...`.

## Verified Smokes

The current full-stack image was verified on both the demo and production-scale
`signal` bundles.

One-epoch full-matrix `peakvi_fit` smoke on `signal`:

```bash
singularity exec --bind /home/dirk/Projects:/home/dirk/Projects /tmp/scworkbench_fullstack_full.sif \
  bash -lc 'unset PYTHONPATH PYTHONHOME PYTHONUSERBASE R_LIBS R_LIBS_USER R_LIBS_SITE; \
    export SCWORKBENCH_PYBENCH_PYTHON=/opt/pyenv/bin/python; \
    Rscript -e "library(scworkbench); \
      b <- wb_open_bundle(\"/home/dirk/Projects/signal\"); \
      cs <- wb_cells(b, cell_set=\"all\"); \
      out <- wb_op_peakvi_fit(bundle=b, matrix_id=\"ATAC_counts\", cells=cs, \
        n_latent=8L, n_layers=2L, n_hidden=64L, dropout=0.1, max_epochs=1L, \
        lr=1e-3, early_stopping=TRUE, use_gpu=FALSE, \
        space_id_out=\"peakvi_space_signal_full_sif_smoke\"); \
      print(list(space=out[[\"outputs\"]][[\"space\"]][[\"space_id\"]], \
        model_engine=out[[\"outputs\"]][[\"model\"]][[\"engine\"]], \
        timings=out[[\"params\"]][[\"pybench_runtime\"]][[\"timings\"]]))"'
```

Observed result:

- `space = peakvi_space_signal_full_sif_smoke`
- `model_engine = peakvi`
- `total_sec = 372.4023`

Current interpretation:

- the decisive `peakvi_fit` verification is the staged R-to-Python chunk bridge
- direct Python BPCells read experiments were useful engineering work, but they
  are not the production criterion for this op on the cluster path

## Running The Shiny App

The image provides a helper launcher:

```bash
apptainer exec --bind /data:/data /tmp/scworkbench_fullstack_full.sif run-scworkbench-shiny
```

Override host/port:

```bash
HOST=0.0.0.0 PORT=3838 \
apptainer exec --bind /data:/data /tmp/scworkbench_fullstack_full.sif run-scworkbench-shiny
```

If the cluster requires port forwarding, handle that outside the container.

## Cluster Notes

Recommended usage pattern:

1. build the image once
2. keep bundles and result paths on shared cluster storage
3. bind those paths into the container
4. run `Rscript` or batch wrappers inside the container

For rebuilds after package or repo updates:

1. update `containers/apptainer/scworkbench_fullstack.def` if dependency inputs changed
2. rebuild with `containers/apptainer/build_fullstack.sh`
3. qualify the candidate with `qualify_fullstack_release.sh`
4. replace the deployed `.sif` only after qualification passes

This is especially important for:

- long-running provenance-bearing workflows
- chromVAR runs
- trajectory fits
- collaborator-facing Shiny sessions

## Scope And Limits

This recipe aims for a practical full stack, but a few realities remain:

- the bundled PyTorch build is CUDA-capable
- runtime GPU access still depends on `--nv` and a compatible host NVIDIA driver
- the build smoke now checks Python availability, `scvi-tools`, and the reported CUDA build
- Python-side repo-local code outside this repo is not bundled unless added
  explicitly
- very large genome/data package installs make the build heavy by design

That tradeoff is intentional. The image is supposed to run the project, not to
be minimal.
