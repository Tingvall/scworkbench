# Fixed development memory baseline at 8cc56e8

Measured before large-graph execution, using the exact installed core
`8cc56e8d6b49f7a3343c131969014b0563675daf` from its clean detached checkout.
This is not the final stable-tuple qualification. No memory allowance was
increased in response to a large-graph result.

Gates 148, 150 and 151 each executed the empty graph's complete mixed-output
promotion/finalization/relocation lifecycle against the same nine-cell source,
then inspected it in a separate pack-free process. All three numeric exits are
0 and all three filesystem fingerprints were unchanged during inspection.

| Gate | Lifecycle maximum RSS (KiB) | Inspection maximum RSS (KiB) |
| --- | ---: | ---: |
| 148 | 671488 | 122676 |
| 150 | 671536 | 122960 |
| 151 | 671400 | 122988 |

The maximum baseline is **687652864 bytes**. The previously declared working
allowance is 8388608 bytes and fixed variation allowance is 4194304 bytes.
The fixed total-process ceiling is therefore **700235776 bytes**. The exact
canonical-byte targets are **1400471552 bytes** (2x) and **5601886208 bytes**
(8x). SQLite cache, parts and collection ceilings remain unchanged. Source
fixture construction is not graph-streaming memory evidence; the full native
large source axis must be authenticated inside each measured scale process.

Gate 152 independently checks the numeric sidecars and derives these totals
from the raw time-v logs. Gates 143/144/149 retain the exact clean installation,
live Python peer and supplied installed SDK tutorial results. Tutorial 149's
saved report independently verifies six discovered/executed/passed cases, zero
skips/failures, and zero install/activation/contract command exits.

Failed gates 145 (diagnostic-printer assumption) and 147 (dependency-library
environment) remain unchanged. Neither is relabeled as a passing runtime gate.
Gate 149 used the shipped tutorial unmodified, with the exact candidate library
first and the existing dependency library retained.

No final 8x scale or complete-suite acceptance is claimed here.
