# Canonical matrix encoding budget (before implementation)

No scheme, scientific value, protocol or pack change is proposed. Baseline is
the repaired `8f53e950` installed runtime in `verified-library`.

- Axis: 31,535 ordinary feature IDs, byte-identical canonical JSON array.
  Target >= 10x elapsed improvement and < 0.05 s per encoding.
- Slice: seed 32, 2000 x 2000 `rpois(lambda=0.3)` matrix; same exact SHA-256
  preimage as repaired streaming. Target >= 1.5x complete semantic-hash
  improvement, including sparse conversion, axis encoding, token file and hash.
- Boundaries: empty axes, NA strings, invalid UTF-8, controls/escaping, Unicode,
  numeric/logical values, row/column decimal transitions and integer limit must
  retain the authoritative old serializer's bytes or error behavior.

These are bounded encoder-only probes. They do not establish end-to-end speed
or eliminate lifecycle source verification. Report any miss without changing
scientific settings or the identity representation to meet a numerical target.

## Development measurements

Prechange repaired-runtime probe: axis mean 0.336667 s (three calls);
seed32 slice 1.544 s (one initial call including package/read setup).
Axis SHA-256:
`cd88ecc7d28d6c5da722503bf714be1bd7cefc703f84d4966873b240720a9d3b`.
Slice SHA-256:
`347be5d4a883b770c94785564d727ae99cb31b158a2db2492f6f6e3b55fa7178`.

First implementation (only row/column integer tokens and memcpy records) met
axis budget at 0.020733 s (16.2x), but slice 1.409 s (1.10x) **missed** its
1.5x target. The accepted refinement uses the same exact integer token builder
for positive int32-valued doubles inside this emitter and reuses the identical
column token while the current append buffer remains in that column. Neither
is an authority cache; neither changes the general canonical numeric helper.
Noninteger, negative, zero and out-of-range values still use the old numeric
formatter. Numerical identities are unchanged.

Matched warm alternating measurements after refinement, same process/data:

| Replicate | Repaired slice seconds | Candidate seconds | Speedup |
| --- | ---: | ---: | ---: |
| 1 | 1.082 | 0.155 | 6.98x |
| 2 | 1.074 | 0.152 | 7.07x |
| 3 | 1.069 | 0.151 | 7.08x |

Each returned the exact slice SHA above. Three new focused tests passed,
zero skips/failures: vectorized axis byte/error parity; native coordinate/value
token parity (including 10/100/101/INT_MAX); and independent old-projection
matrix identities for numeric/integer/logical/NA/NaN/Unicode/control cases.
Raw matrices remain rejected as unsupported, matching the old backend.

Reproducer: copy `src/matrix_slice_identity.c` into a fresh private temporary
directory and build it there with `R CMD SHLIB -o matrix_slice_identity.so
matrix_slice_identity.c`, then run:

```
Rscript notes/engine_simplification/profile_matrix_encoding.R /tmp/scwb-matrix-streaming-forge-20261018/verified-library /tmp/scwb-matrix-encoding.gNySyh/matrix_slice_identity.so
```

The temporary dynamic library changes only the private probe environment;
the repaired baseline library remains untouched. Independent installed-candidate
checks belong to the one coordinated final qualification, not this probe.
