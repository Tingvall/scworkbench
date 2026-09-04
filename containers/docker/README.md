# Full-stack CPU Docker image

This image is the local-workstation counterpart to the CUDA-capable Apptainer
runtime. It uses the same scworkbench, Shiny, PyBench, R dependency, and
operation-contract sources, but derives a CPU-only Python lock by removing the
CUDA runtime packages and replacing the pinned CUDA PyTorch wheel with the
corresponding pinned CPU wheel.

`runtime.dcf` records the immutable multi-platform base index, both platform
manifests, and the source and derived Python-lock identities.

The pinned Bioconductor base is an OCI index containing native `linux/amd64`
and `linux/arm64` manifests. Build and qualify each architecture independently
before publishing a combined manifest.

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
