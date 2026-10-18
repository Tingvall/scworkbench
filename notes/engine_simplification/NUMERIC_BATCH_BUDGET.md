# Numeric token batching: prospective budget and scope

Exact clean base13de6293ffe2f10b496a07ec042ee21bf324c3ec. This isolated
prototype changes no format, scheme, protocol, primitive or authority boundary.

Before implementation, retained realistic typed-space elapsed measurements are
42.872s (8 partitions) and42.560s (32 partitions), against the original5s
per-operation target: both MISS. Exact identities,6/6 source SHA checks and
752264KiB peak RSS satisfy their separate gates. One authorized attribution
measured41.39s sampled total,29.42s inclusive encode (71.08%),20.94s semantic
identity,7.08s envelope, and3.80s typed-result content (overlapping totals).
FUN self15.17s and vapply self5.77s dominate; source SHA0.31s and HDF reads1.21s
do not. These are coordinator evidence, not new measurements by this helper.

Prospective component target: >=10x faster ordinary numeric token encoding,
with byte-identical frozen-oracle output and identical fallback/error behavior.
The5s operation target remains unchanged; batching alone does not prove it will
pass because registry/schema/lifecycle costs remain. Any budget miss is retained.

One native call admits at most131072 eligible ordinary numeric tokens. An R
scalar list/integer or real vector and the resulting token STRSXP, CHARSXPs and
joined JSON stay within the existing conservative256-byte-per-element scientific
temporary ledger (32MiB at the ceiling); callers do not receive a new allowance.
Each native block is validated completely before token allocation/emission.
Unsupported types, attributes, objects, invalid finite range, parsed lexemes,
factors and logicals fall back to the existing recursive encoder; no partial
block output or independent fallback diagnostic is introduced. Numeric ELT
access avoids forcing an entire ALTREP vector with DATAPTR. Empty/scalar
framing remains owned by the existing R encoder.

Only numeric atomic arrays, unnamed numeric-scalar lists and existing<=1000-row
dataframe numeric token batches are wired. Existing scalar/key/string/parser,
locale checks, dataframe eligibility/diagnostic precedence and absent-native
standalone source-generation behavior remain unchanged. No cache or identity
observation is reused. Source review precedes any focused install/test run;
only the coordinator may subsequently run performance qualification.
