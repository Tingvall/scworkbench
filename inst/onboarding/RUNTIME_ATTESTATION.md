# Runtime attestation

Exact container/image binding is optional, higher-assurance runtime evidence.
It is not part of scworkbench's minimum scientific-state contract. The required
scientific identities remain the operation and operation-pack definitions,
inputs, outputs, parameters, provenance lineage, and applicable software and
runtime versions.

scworkbench supports execution in containers, non-container environments, and
differently packaged runtimes. Scientific validity, operation-pack acceptance,
execution, promotion, transfer, and replay do not require one exact image
digest. When no digest is available, run fingerprints honestly record
`image$status = unavailable`; this is a valid state, not a validation failure.

When an image digest is available and durably retained, it strengthens runtime
attribution by identifying the exact image used. Set the existing environment
variable before starting the R process to record the `bound` state:

```bash
IMAGE=/path/scworkbench_fullstack.sif
DIGEST=$(sha256sum "$IMAGE" | awk '{print $1}')
singularity exec --cleanenv --env SCWORKBENCH_RUNTIME_IMAGE_SHA256="$DIGEST" \
  --bind "$PWD:/work/scworkbench" --pwd /work/scworkbench "$IMAGE" \
  Rscript analysis.R
```

Without this variable, run fingerprints retain the `unavailable` state and
never claim an image binding. Both `bound` and `unavailable` are supported
attestation states.

Propagation of the optional digest into independently launched child processes
may be improved in a future change. That enhancement is non-blocking and does
not alter the validity of an honest `unavailable` attestation.
