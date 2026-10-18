# Independent row hashes: component result and corrected failure

Corrected source `89bd10c45134e8a8fac908acb62aa4d05ef5ebcd` qualifies against
runtime242 (R/src identical to1f). Command:

```sh
SCWB_ROW_FOLD_89BD_RELEASE=YES bash /tmp/scwb-engine-simplification-forge-20261018/run_row_fold_89bd_qualification.sh
```

Terminal exit0; seven focused tests in three files all passed, zero skips.
Matched 100000 ordered row folds, in 1000-row calls, three fresh processes per
implementation alternating old/new order: median4.518s ->3.321s, 26.49% lower,
passing the prospective25% reduction. Whole-process maximum RSS149504 ->154808
KiB, passing+10%. Both processes preload OpenSSL; a minimal backend call counter
is included in timing and proves100 actual batches/100000 elements for new,
zero for old. Input creation/read and independent oracle/prefix checks are
outside elapsed timing; process RSS includes post-timer verification.

Independent full serializeJSON preimages, frozen intermediate states and final
state all match exactly. Input5141174-byte RDS SHA
`538094916a44a3c3c186518e09684784b2ab27bddc8e0db39c3ccb96cc2b3d9a`;
final fold `ae5eb76ba11e1f8f1c7b9462ba1fe96960b27a5f069937826a6b65d908de0ae9`.
Harness/input/both installations were unchanged. This measures folding only,
not complete serialization, recipient validation or full-workflow acceptance.

The original4cf clean-install focused run failed two of seven tests (five
passed). Its string-based .Call was incompatible with the existing forced-
symbol policy, silently selecting old fallback in ordinary calls. The correction
uses the registered C symbol binding; the new qualification additionally proves
optimized execution. Original failed logs and exit1 remain at `row_fold_4cf`;
corrected complete logs/sidecars/hashes/results at `row_fold_89bd`, both under
`/tmp/scwb-engine-simplification-forge-20261018`. Neither failure nor original
source-review oversight is relabeled as a pass.
