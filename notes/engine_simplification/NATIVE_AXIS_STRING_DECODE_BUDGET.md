# Native matrix-axis string decoding: budget before implementation

Parent c8261467da806217a4d8b991c02b07f190d2681a. No runtime change in
this commit. Its installed focused35/35 passed (29 expanded DBI deprecation
warnings); its matched matrix-axis gate remains FAILED, not waived:
physical1.577→.857s=1.84x misses2x; source-axis hash .932→.244s=3.82x passes.
Membership2128→76 and RSS+0.6754% pass. All original preimages, source SQL
and filesystem inventories remain exact. No blind timing retry is proposed.

Actual attribution is separate from the matched plain medians. Evidence:
`/tmp/scwb-engine-simplification-forge-20261018/matrix_physical_c826_diagnosis`.
Four fresh diagnostic processes (old/new actual10ms profiles and separate
censuses), five physical verifications per process, all numeric sidecars0.
The new profile's actual2.96 sampled seconds comprise disjoint JSON parsing
.71, numeric counting .47, SQL .88, resource .08, GC .10 and other .72.
Inclusive timings overlap. The census records5320 strict-JSON grammar checks,
5320 graph parses and5320 canonical-JSON parses over five verifications of
64feature/1000cell axes. These are not whole matrix-value scans or timings.

The bounded native reader already validates UTF-8/no NUL and isolates one
quoted token under its1540 encoded-byte cap. Its usual unescaped string is
then sent through a general object/scalar grammar, jsonlite and number-token
decoration. A narrow proposed fast path may decode ONLY a fully delimited
unescaped string without raw C0 controls. Every escaped/control case retains
the literal old strict parser; final ID validation, native observation,
membership, dimensions/counts, spill admissions and error cleanup stay intact.
No public parser, canonical representation, schema or scientific value changes.

Prospective budgets fixed before any implementation:

- Keep the original >=2x physical verification target against old2c5, and
  improve physical verification >=15% against the current c826 runtime
  (.857s original median, ceiling .72845s), also >=15% in fresh matched pairs.
- Retain original >=2x combined axis hashing, >=90% membership-query reduction,
  old2c5 whole-process peak RSS+10%, source metadata bytes/pass counts and all
  literal identity/SQL/filesystem/scientific assertions.
- On the SAME plain64×1000 metadata fixture, reduce strict/graph/general JSON
  parse calls5320→0 over five physical verifications. Preserve all actual spill
  and counter admissions. Escaped fixtures must demonstrate real old fallback.
- Full Xenopus171.124s, graph/mixed/space and other budget misses remain open.

Before measurement require old-literal decoder oracles for plain/escaped UTF-8,
controls/malformed strings, boundary splits, oversize IDs/tokens, source mutation,
fault cleanup and getter parity. A profiler estimate does not pass any budget.
