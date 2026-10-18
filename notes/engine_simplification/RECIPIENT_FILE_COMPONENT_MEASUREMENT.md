# Recipient initial-file observations: component result

Qualified runtime `18ec319b21a57bfa401b44531bd7965bc06a3dfc` combines the
recipient-file optimization, corrected synthetic model terminal and separate
model-repair commit/publication fix. Command, terminal exit0:

```sh
SCWB_RECIPIENT_REPAIR_RELEASE=YES bash /tmp/scwb-engine-simplification-forge-20261018/run_recipient_file_repair_qualification.sh
```

All18 focused tests in six files passed, zero skips/failures. This includes
five new file-observation contracts, five existing recipient table contracts,
three source/recipient contracts, payload identity, existing model relocation
and three new model-repair fault/transaction contracts. A retained dbDisconnect
warning is not suppressed. Source-review approval is separate from these tests.

| Same immutable finalized Xenopus bundle | Old3066 | New18ec |
| --- | ---: | ---: |
| Uninstrumented complete recipient report | 56.722s | 44.570s |
| Whole-process peak RSS | 714964KiB | 722580KiB |
| Separate census: provenance-file SHA calls | 434 | 342 |
| Separate census: bytes hashed by that helper | 3387730102 | 2058249811 |
| Claim-only helper bytes | 1691423386 | 361943095 |

Elapsed reduction21.42% passes the prospective10% budget; RSS passes old+10%;
hashed bytes decrease. Initial and final fingerprints EACH still hash all113
files/848153358 bytes. The compact initial observation ledger held73 entries,
64472 bytes (<=65536). Every claim is independently compared. All nonmeasurement
report fields, actual identities, diagnostics and complete file inventories
match:24 content-verified entities and five uninspected external-source warnings,
`ok_with_warnings`, zero errors/skips. No historical evidence was modified.

One cold process old then new; OS cache not flushed. Instrumented census is
separate. Counts/bytes cover `.wb_prov_sha256_file`, NOT all SQLite/HDF5/native
IO or physical device reads. Historical51.749s is context, not the matched old
denominator. No combined-workflow gain is inferred by adding component gains.
The combined candidate's faster file-SHA backend was not part of this18ec run.

Original `recipient_a8c` focused exit1 remains retained:15 executed,9 passed,
five setup failures from an undeclared synthetic terminal plus one model repair
failure. The terminal was corrected without changing cache assertions. Separate
old242 reproduction proved repair called manifest publication inside its SQL
transaction. The fix commits first, transfers copied-payload ownership before
publication, retains committed payloads on a publication fault, rejects caller
transactions and removes only owned partial copies on precommit rollback.
The strict publication-before-commit rejection remains in place.

Raw failed/corrected logs, numeric sidecars, source/install/harness checksums,
report equivalence and byte inventories remain under `recipient_a8c`,
`model_ref_old242_diagnosis.*` and `recipient_file_repair_18ec` beneath
`/tmp/scwb-engine-simplification-forge-20261018`. The later dry-run-only purity
change is not included in this qualified runtime; its tests remain pending.
