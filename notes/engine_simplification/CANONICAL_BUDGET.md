# Exact canonical encoding budgets

Proposed to Quill and Sable before implementation: reuse the existing exact
character-array encoder for plain arrays; one invocation-local last-name plan
may reuse validated escaped keys only on exact names, Encoding() vector and
LC_CTYPE equality. No value cache, numeric shortcut, persistent memo or identity
scheme change. Require old-encoder byte/error/SHA parity; >=3x character-array
and 5,000-row table encoding speed, peak RSS <=baseline+10%; target >=20% lower
canonical time in the bounded HVG development fixture.

First retained probes: 31,535 character IDs .341 -> .015 s; scalar-character
list .321 -> .071 s; 5,000-row table .548 -> .339 s. Arrays met their target;
the table **missed** 3x (1.62x). Do not relax that miss or extrapolate it to the
real workflow. All four measured canonical digests and focused error/shape
comparisons matched the frozen repaired encoder.

Next proposal, before implementation: for exact-class plain data.frames with
attribute-free integer/double/logical/character columns, encode their existing
row-major canonical JSON in <=1,000-row batches using column token vectors and
one sorted-key plan. Numeric scalar conversion remains the existing encoder;
string escaping remains exact. Nonfinite nonmissing numbers, attributed/list/
factor/date/custom columns retain the original row path, as do other dataframe
classes. Empty and zero-column shapes must retain the original representation.
Same >=3x 5,000-row/RSS+10% budgets apply, with full old-encoder byte and typed
error parity and complete descriptor/receipt identity regression coverage.

The output JSON string is still the existing ordinary-object identity API's
complete preimage. Bounded token assembly does not create an unlimited streaming
table authoring contract. Large file-backed primitives keep bounded readers.

## Retained batch-v2 development probe

`canonical_batch_v2_probe.log` and numeric sidecar `canonical_batch_v2_probe.exit`
in the task evidence directory record exit **0** and
`CANONICAL_CHARACTER_AND_KEY_PREIMAGES_OK`. Its `canonical-batch-v2-probe/measurements.csv`
compares with the retained `canonical-before-probe/measurements.csv`:

| Case | Repaired encoder seconds | Batch-v2 seconds | Speedup | UTF-8 bytes |
| --- | ---: | ---: | ---: | ---: |
| 31,535 character IDs | .341 | .014 | 24.36x | 493455 |
| Scalar-character list | .321 | .095 | 3.38x | 493455 |
| 1,000-row table | .108 | .015 | 7.20x | 85546 |
| 5,000-row table | .548 | .043 | 12.74x | 432148 |

All measured byte counts and SHA-256 values match the old encoder:

- Both axis cases: `4634ea30d5f43cdc0179c32ce48a5317069f50d46dd09f70488420da137ea537`.
- 1,000 rows: `6f0a3a9050fb8340affc78079b2cfc057bc64e8cf401f82eda482cb187e4dfce`.
- 5,000 rows: `9727a97aaacf63bb1eb0e41df75aaf57e15e2ba33881bb20a33b16f636e65e25`.

GNU time reports process peak RSS **98,472 KiB**, versus **93,316 KiB** in
`canonical_before_probe.log` (+5.53%, within +10%). The >=3x axis/table targets
are met by this bounded development probe; the earlier .548 -> .339 table
**miss remains part of the record**. Startup and all cases share this process
RSS measure; it is not an isolated table allocation measurement. These probes
do not establish the proposed >=20% HVG canonical-time reduction or the full
Xenopus workflow budget, and do not constitute final frozen qualification.

The subsequent candidate also has a guarded native numeric-token fast path:
only eligible ordinary scalar integer/double values, decimal-dot locale and
unchanged accepted canonical tokens qualify. Parsed JSON numeric lexemes,
attributed numbers, nonfinite/range-edge values and unsupported conditions use
the existing encoder. This supersedes the initial proposal's blanket “no
numeric shortcut” implementation restriction, not its byte/error parity or
unchanged-identity requirement; the batch-v2 timings above must not be relabelled
as a measurement of that later change.
