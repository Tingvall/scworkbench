# UCell Chunking Benchmark Note

Status: active benchmark note

Purpose: record the current observed behavior of chunked `ucell` on `../demo`
and document the present backend limitations honestly.

This is not a final performance claim.

It is a hardening note used to keep engine truth aligned with observed runtime
behavior.

## 1. Bundle Context

Observed bundle:

- bundle path: `../demo`
- matrix: `RNA_counts`
- feature-set namespace: `immgen`
- cells: `26,723`
- total RNA features: `32,285`
- signatures: `47`

## 2. Current Engine Settings That Matter

Relevant `ucell` settings:

- `chunk_size`
- `ncores`
- `parallel_backend`
- `max_rank`

Current practical recommendation on this machine:

- `ncores = 1`
- `parallel_backend = "serial"`

Reason:

- socket-based BiocParallel paths failed with port-allocation errors during
  bundle-scale runs

## 3. Observed Benchmarks

### 3.1 Full Chunked Run Attempt

Settings:

- `chunk_size = 250`
- `ncores = 1`
- `parallel_backend = "serial"`
- `max_rank = 1500`

Observed result:

- the run did not fail immediately on the dense-materialization guard
- a bounded 120-second benchmark did not finish

Bounded benchmark result:

- wall time: `2:00.05` before timeout
- max RSS: `1,251,436 kB` (about `1.25 GB`)
- exit status: timeout

Interpretation:

- chunking materially improved operability
- but current runtime remains substantial

### 3.2 Random 1000-Gene Proxy Benchmark

Purpose:

- rough lower-information proxy for feature-scaling behavior

Observed:

- wall time: `24.15 s`
- max RSS: `1,580,992 kB`
- only `20 / 47` signatures had at least one matched gene in the random slice

This proxy underrepresents the real signal workload and should not be used as
the primary extrapolation.

### 3.3 Signature-Aware 1000-Gene Proxy Benchmark

Purpose:

- retain the full union of signature genes, then fill to 1000 genes with random
  background genes

Observed:

- benchmark features: `1,000`
- signature union represented: `787`
- all `47 / 47` signatures fully represented
- wall time: `39.40 s`
- max RSS: `1,832,440 kB` (about `1.83 GB`)

This is the more useful scaling proxy.

## 4. Rough Extrapolation

Using the signature-aware 1000-gene benchmark:

- scale factor by feature count: `32,285 / 1,000 = 32.3`
- rough direct-runtime estimate on `../demo`: about `21 minutes`

Interpretation:

- for `../demo`, a full run is likely on the order of tens of minutes
- for a larger `~60k` cell bundle, an hour-scale run is plausible

This is only a rough estimate.

Reasons it may deviate:

- chunked session execution adds overhead
- scaling is not perfectly linear
- getter coercion behavior is still a practical bottleneck

## 5. Current Honest Constraints

The benchmark note should state these directly:

- getter coercion still emits:
  - `Converting to a dense matrix may use excessive memory`
- chunking solved immediate operability before it solved performance
- socket-based BiocParallel backends were unreliable on this machine for
  bundle-scale `ucell`

So the current truthful statement is:

- `ucell` can now be executed in a chunked engine-native way
- but large-bundle performance and sparse backend behavior are still active
  hardening concerns

## 6. Next Optimization Targets

Most likely high-leverage targets:

1. BPCells slice -> sparse coercion hardening
2. profiling repeated `wb_slice()` cost across cell chunks
3. profiling UCell ranking cost itself

This note should be updated whenever one of those changes materially alters the
runtime or memory profile.
