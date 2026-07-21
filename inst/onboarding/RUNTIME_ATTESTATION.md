# Runtime attestation

For a release-grade run, bind the image digest into the process environment so
every persisted run can state the exact image it executed in:

```bash
IMAGE=/path/scworkbench_fullstack.sif
DIGEST=$(sha256sum "$IMAGE" | awk '{print $1}')
singularity exec --cleanenv --env SCWORKBENCH_RUNTIME_IMAGE_SHA256="$DIGEST" \
  --bind "$PWD:/work/scworkbench" --pwd /work/scworkbench "$IMAGE" \
  Rscript analysis.R
```

Without this variable, run fingerprints explicitly report image status
`unavailable`; they never claim an image binding.
