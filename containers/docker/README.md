# Core CPU Docker image

This image is the local-workstation counterpart to the CUDA-capable Apptainer
runtime. It contains the scworkbench engine, composite-pinned PyBench, and their
locked R and Python method dependencies. Optional clients such as
`scworkbenchShiny` and `scwb-agent` are not copied into or launched by this
runtime. The Docker build derives a CPU-only Python lock by removing the CUDA
runtime packages and replacing the pinned CUDA PyTorch wheel with the
corresponding pinned CPU wheel.

This recipe is not the seven-pack standard-profile SIF build. Locked method
dependencies do not install or activate operation packs. Inspect the built
image's installed documentation and explicitly install/activate a compatible
profile when needed; neither 61-operation coverage nor SDK/container
qualification follows from the image name. Source updates do not refresh an
existing image.

`runtime.dcf` records the immutable multi-platform base index, both platform
manifests, and the source and derived Python-lock identities.

The pinned Bioconductor base is an OCI index containing native `linux/amd64`
and `linux/arm64` manifests. Build and qualify each architecture independently
before publishing a combined manifest.

The build uses `containers/docker/Makevars` to compile packages declaring the
legacy `CXX11` slot in GNU C++14 mode. This is required by the locked
`chromVAR 1.30.1` and `RcppArmadillo 15.4.2.1` source-build combination on
architectures without compatible binary packages.

## Local single-platform build

```bash
containers/docker/build_fullstack.sh \
  --tag scworkbench-fullstack:cpu-dev \
  --platform linux/arm64 \
  --jobs 2 \
  --load

containers/docker/qualify_fullstack_release.sh \
  scworkbench-fullstack:cpu-dev linux/arm64
```

Use `linux/amd64` for Intel hosts.

## Registry build

After both single-platform qualifications pass, publish the combined image:

```bash
containers/docker/build_fullstack.sh \
  --tag REGISTRY/OWNER/scworkbench-fullstack:VERSION-cpu \
  --platform linux/amd64,linux/arm64 \
  --push
```

Record and distribute the resulting registry digest. A Docker image and an
Apptainer SIF are distinct runtime artifacts even when their source revisions
and scientific package contracts match.

## Local workstation launch

After loading or pulling a qualified image, open an interactive shell with:

```bash
containers/docker/run_local.sh REGISTRY/OWNER/scworkbench-fullstack:VERSION-cpu
```

The launcher creates `~/scworkbench-projects`, mounts it at `/work`, and starts
the shell there. It does not publish a network port or imply that a graphical
client is bundled. Files written below `/work` persist on the host after the
container stops. Pass a different host directory as the second argument when
required:

```bash
containers/docker/run_local.sh IMAGE_REF /path/to/project-directory
```

Exit the shell to stop the local container.
