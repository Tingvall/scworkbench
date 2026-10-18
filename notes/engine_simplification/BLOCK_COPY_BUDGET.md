# Typed-block delivery budget (recorded before implementation)

Scope: only fresh, core-created ordinary matrix/space typed-reader return
values. Do not replace generic deep-copy semantics. Plain atomic/list metadata
may use ordinary R copy-on-modify; environment, external-pointer, reference-class
or other object metadata must retain the existing serialization fallback.

Numerical budgets, measured over 20 deliveries after warm-up on this host:

- 512 x 512 double block: mean delivery overhead <= 0.005 seconds.
- 2000 x 2000 double block: mean delivery overhead <= 0.010 seconds.
- Both sizes: owned-delivery allocation <= 1 MiB per call and <= 20% of the
  serialization baseline allocation; no extra full-value traversal or hash.
- Mutating the returned block, its dimnames or plain nested metadata must not
  alter retained source values or any later independently created block.
- Preserve exact returned values, axis order, primitive identity and fallback
  invocation for nested mutable references; no relaxed selection/resource rules.

The baseline is `unserialize(serialize(value, NULL, version=3L))`, using matching
primitive structure, fresh matrix values and plain metadata. Baseline and final
measurements include delivery only, not compute/read/write. They do not claim
whole-operation speedups or a boundedness improvement for ordinary full objects.

Pre-change baseline, R 4.4.1 on this host (20 calls; `Rprofmem` allocation):

| Shape | Primitive bytes | Mean seconds | Allocated bytes/call |
| --- | ---: | ---: | ---: |
| 512 x 512 | 2,164,864 | 0.004100 | 4,225,573 |
| 2000 x 2000 | 32,258,176 | 0.057800 | 64,092,328 |

Development helper measurements after change (same shapes/20 deliveries):

| Shape | Mean seconds | Allocated bytes/call | Budget |
| --- | ---: | ---: | --- |
| 512 x 512 | 0.000100 | 461 | met |
| 2000 x 2000 | 0.000100 | 0 | met |

These are timer-resolution-limited fast calls, not a precision claim below
one millisecond. The changed helper and typed-space reader were extracted from
the current source AST into a private environment parented by the repaired
installed namespace for focused development tests, without reinstalling or
altering the baseline library. Final installed-candidate tests are owned by the
coordinated final qualification. The generic deep-copy helper remains unchanged.

Reproducible matched-structure probe:

```
Rscript notes/engine_simplification/profile_owned_block.R /tmp/scwb-matrix-streaming-forge-20261018/verified-library source
```

Literal final development results (both modes use the same object including
matrix dimnames; 20 calls):

```
FOCUSED discovered=5 executed=5 passed=5 skipped=0 failed=0
DELIVERY mode=serialization rows=512 columns=512 object_bytes=2230672 calls=20 elapsed_seconds=0.082000 mean_seconds=0.004100 allocated_bytes_per_call=4245981
DELIVERY mode=owned rows=512 columns=512 object_bytes=2230672 calls=20 elapsed_seconds=0.001000 mean_seconds=0.000050 allocated_bytes_per_call=0
DELIVERY mode=serialization rows=2000 columns=2000 object_bytes=32514448 calls=20 elapsed_seconds=0.956000 mean_seconds=0.047800 allocated_bytes_per_call=64174264
DELIVERY mode=owned rows=2000 columns=2000 object_bytes=32514448 calls=20 elapsed_seconds=0.001000 mean_seconds=0.000050 allocated_bytes_per_call=0
```

This focused set covers only typed-block handoff. It does not establish total
workflow framework overhead or eliminate unrelated admission/publication scans.
