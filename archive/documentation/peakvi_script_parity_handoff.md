# PeakVI Script-Parity Handoff

## Goal

Bring the engine-native `peakvi_fit` workflow to parity with the standalone
PeakVI training script below, so the same training behavior can be launched
through `scworkbench` and executed by `pybench`.

## Reference Python Script

```python
import os
import warnings
warnings.filterwarnings("ignore", category=SyntaxWarning)

os.environ["NUMBA_DISABLE_CACHE"] = "1"
os.environ["NUMBA_CACHE_DIR"] = "/proj/sc_trajectory/projection/tmp/numba_cache"

# Monkeypatch Numba to prevent caching errors
import numba
_real_njit = numba.njit
def safe_njit(*args, **kwargs):
    kwargs["cache"] = False
    return _real_njit(*args, **kwargs)
numba.njit = safe_njit

import scanpy as sc

import scvi
import argparse

print("Initializing PeakVI Training...")

parser = argparse.ArgumentParser()
parser.add_argument("--input", required=True, help="Path to input .h5ad file")
parser.add_argument("--output", required=True, help="Directory to save the model")
parser.add_argument("--n_latent", type=int, default=20)
parser.add_argument("--n_layers", type=int, default=2)
parser.add_argument("--n_hidden", type=int, default=256)
parser.add_argument("--dropout", type=float, default=0.2)
parser.add_argument("--epochs", type=int, default=500)
parser.add_argument("--lr", type=float, default=1e-3)
args = parser.parse_args()

# Load data
adata = sc.read_h5ad(args.input)

# Setup AnnData for scvi-tools
print("Setting up AnnData for scvi-tools...")
scvi.model.PEAKVI.setup_anndata(adata)

# Initialize model
print(f"Building PeakVI model (latent={args.n_latent}, hidden={args.n_hidden}, layers={args.n_layers})")
model = scvi.model.PEAKVI(
    adata,
    n_latent=args.n_latent,
    n_hidden=args.n_hidden,
    dropout_rate=args.dropout,
)

# Train model
print("Training PeakVI...")
model.train(
    max_epochs=args.epochs,
    early_stopping=True,
    plan_kwargs={"lr": args.lr}
)

# Save model
print(f"Saving trained model to {args.output}")
model.save(args.output, overwrite=True)

print("Training complete. Latent space secured.")
```

## Current State

`scworkbench` already has a `peakvi_fit` op and `pybench` already has a
corresponding Python implementation. The current path already:

- accepts a matrix and cell universe
- stages the matrix from R into Python
- trains PeakVI
- writes the learned latent embedding back into the bench as a `space`
- saves the trained model as a `model_ref`

The remaining problem is parameter parity. The current implementation exposes a
smaller training surface than the script above.

## Parity Gap

The standalone script includes these training controls:

- `n_latent`
- `n_layers`
- `n_hidden`
- `dropout`
- `epochs`
- `lr`
- `early_stopping`

The current engine path already covers:

- `n_latent`
- `max_epochs` / `epochs`

The main missing pieces are:

- `n_layers`
- `n_hidden`
- `dropout`
- `lr`
- explicit `early_stopping`

## Work Required In `scworkbench`

### 1. Extend the `peakvi_fit` op contract

Add new parameters to the op interface for:

- `n_layers` as integer
- `n_hidden` as integer
- `dropout` as numeric
- `lr` as numeric
- `early_stopping` as logical

Requirements:

- keep the existing parameters backward compatible
- define clear defaults matching the intended script-parity behavior
- expose the new params through the normal op interface machinery

### 2. Extend the R-side op implementation

Update the R implementation of `peakvi_fit` so that it:

- accepts the new arguments
- validates and coerces them
- includes them in the Python request payload
- records them in the returned run params for provenance

This should remain a normal engine change, not a client-only workaround.

### 3. Preserve current output behavior

Do not change the output contract. The op should still produce:

- `space`
- `model`

The goal is script-level training parity, not a redesign of the output surface.

### 4. Add tests

Update the `peakvi_fit` tests so they cover:

- interface exposure of the new params
- acceptance of the new params by the session/op pathway
- backward compatibility for older callers

If there is a Python-backed smoke test available locally, include at least one
small run that passes the new params through the full stack.

## Work Required In `pybench`

### 1. Extend the request parsing

The Python `peakvi_fit` op should read the new params from the request:

- `n_layers`
- `n_hidden`
- `dropout`
- `lr`
- `early_stopping`

### 2. Extend model construction

The Python implementation should pass the additional model hyperparameters into
`scvi.model.PEAKVI(...)` so the engine path can match the standalone script.

At minimum this means wiring:

- `n_latent`
- `n_hidden`
- `n_layers`
- `dropout_rate`

### 3. Extend training configuration

The Python implementation should pass the training controls into
`model.train(...)`.

At minimum this means wiring:

- `max_epochs`
- `early_stopping`
- `plan_kwargs={"lr": ...}` when `lr` is provided

### 4. Preserve current writeback semantics

Do not change the bundle writeback contract. The op should still:

- write the latent embedding into the bench as a `space`
- save the model payload as a `model_ref`

## Numba Cache Handling

The standalone script contains explicit Numba cache handling:

- sets `NUMBA_DISABLE_CACHE`
- sets `NUMBA_CACHE_DIR`
- monkeypatches `numba.njit(..., cache=False)`

This should not be copied blindly into the op unless it is still required in
the actual runtime.

Recommended approach:

1. verify whether the current local `pybench` runtime still needs this hack
2. if it does, implement it once in a deliberate runtime helper
3. avoid burying it as ad hoc logic inside the PeakVI op body

The key requirement is to keep the workaround explicit and isolated if it is
still necessary.

## Expected Engine Call After The Change

After parity work, the intended `scworkbench` call should look roughly like:

```r
rr <- wb_session_run_op(
  session = s,
  bundle = b,
  op_name = "peakvi_fit",
  inputs = list(
    cell_set = "core",
    matrix = wb_prim_matrix("ATAC_counts"),
    n_latent = 20L,
    n_layers = 2L,
    n_hidden = 256L,
    dropout = 0.2,
    max_epochs = 500L,
    lr = 1e-3,
    early_stopping = TRUE,
    use_gpu = TRUE,
    space_id_out = "peakvi_space"
  ),
  notes = "PeakVI script-parity run"
)
```

## Definition Of Done

- `peakvi_fit` exposes the script-parity training params in `scworkbench`
- `scworkbench` passes them through the engine request path
- `pybench` consumes and applies them in PeakVI model init and training
- latent space and model writeback remain unchanged
- existing callers using the old narrower param set continue to work
