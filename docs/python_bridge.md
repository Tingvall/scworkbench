# Python bridge

Python computation returns through the R engine's validation and atomic
publication boundary. Distinguish three contracts:

| Contract | Use |
| --- | --- |
| Historical bridge `pybench-op-v2` | Existing engine bridge, not a new-pack template |
| ABI-v2 Python packs using `pybench-op-v3` | Explicitly activated successor packs |
| ABI-v3 Python packs using `pybench-op-v4` | Current bounded Python SDK path |

An R-backed pack may call private Python computation without becoming a
Python-backed pack. The seven-pack standard profile consists of R packs;
scwbLatent's configured Python runtime is a dependency, not ambient Python-pack
activation. Set `SCWB_LATENT_PYTHON` as documented by the standard profile.

The historical bridge's machine-readable resource remains shipped:

```r
system.file("protocol/pybench-op-v2.schema.json", package = "scworkbench")
```

Use registered operations such as `scwblatent::scvi_train` through
`wb_session_run_op()`; that operation uses the ABI-v3 pack boundary, not the
historical core bridge. For all operations, do not write protocol payloads or
artifact registry rows directly.

For new Python packs read PyBench's installed `sdk_authoring.md` and the
scworkbench [SDK capability catalog](../inst/sdk/operation-packs/CAPABILITIES.md).
Activate against the exact interpreter and declared distribution. Shared schema
parity does not supply unsupported runtime callbacks; check each grant.

Dependencies, installed identities, unsupported grants, and receipt mismatches
must fail closed. Do not bypass them with arbitrary imports, direct SQL,
caller-authored receipts, or a second catalog. Serialized models are trusted
executable state, not made safe by hashes. CPU evidence does not qualify GPUs.
