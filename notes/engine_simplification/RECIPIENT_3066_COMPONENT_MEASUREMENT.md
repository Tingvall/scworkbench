# Recipient stored-table observations: component result

Runtime checkpoint `3066d0de685bad81abb6164d956fef2a309df865` versus the
installed terminal242 baseline, on the same immutable finalized Xenopus bundle.
Command:

```sh
SCWB_RECIPIENT_TABLE_RELEASE=YES bash /tmp/scwb-engine-simplification-forge-20261018/run_recipient_3066_qualification.sh
```

The supervisor completed with exit 0. Five new contracts and four existing
identity/source-recipient contracts passed: 9 tests, three files, zero skips or
failures. Logs, numeric sidecars, installed/harness checksums and results are
retained under `/tmp/scwb-engine-simplification-forge-20261018/recipient_3066`.

| Measurement | Old | New | Prospective budget |
| --- | ---: | ---: | --- |
| Uninstrumented complete recipient report | 69.613 s | 51.749 s | >=10% reduction: passed (25.66%) |
| Whole-process peak RSS | 750480 KiB | 705100 KiB | <=old+10%: passed |
| Separately instrumented stored-table folds | 24 | 8 | Actual observations reused, not expected claims |
| Separately instrumented stored-table fold time | 21.153 s | 7.220 s | >=40% reduction: passed (65.87%) |

One cold R process per implementation, old then new; OS caches were not flushed.
Census runs are separate from the uninstrumented elapsed/RSS comparison. This
is a component measurement, not a new full-workflow result or overall budget
acceptance.

Every nonmeasurement report field was identical, including diagnostics,
coverage, skips, schemes, all eight actual table identities and both filesystem
fingerprints. All 113 files (848153358 logical bytes) were unchanged after every
process. Both reports retain `ok_with_warnings`: 24 content-verified entities and
five explicitly uninspected external-source warnings, not 29 verified entities.
Fresh reports and nonrecipient validation still compute their own observations.
Every recorded claim is checked independently; post-validation fingerprinting
is never reused or omitted.
