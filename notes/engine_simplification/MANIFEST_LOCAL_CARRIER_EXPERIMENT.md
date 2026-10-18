# Local carrier experiment: not selected

Source `dd358c918481f8ff46f88e24b1298396de96a583`, followed by fixture-only
`c161c71bce62eb4a60d6886a81f5f8a01b3b10f2`, remains isolated and is NOT
integrated. The latter changes no runtime code. Its positive fixture previously
contained an all-NULL integer SQL column, returned as unsupported logical by the
projected SQLite query; the approved predicate correctly excluded that column.
The corrected ordinary-integer positive retains explicit logical fallback tests.

```sh
SCWB_MANIFEST_LOCAL_RELEASE=YES bash /tmp/scwb-engine-simplification-forge-20261018/run_manifest_local_carrier_qualification.sh
SCWB_MANIFEST_LOCAL_RELEASE=YES bash /tmp/scwb-engine-simplification-forge-20261018/run_manifest_local_c161_qualification.sh
```

The first command ended exit1:17 executed,16 passed,1 positive-exercise failure.
The separately named retry passed17/17 focused tests, zero skips/failures,
14 warnings retained. Its complete source snapshot median was5.559s versus
fresh matched5b5.951s:6.59% improvement, **MISS25%**. Peak RSS224852 versus
218408KiB passes+10%. The independent materialized5000-row oracle and all113
file inventories matched before the final reconciliation failed.

The retry's reconciliation exited1 because actual `cell_set_membership`
observations did not use the proposed six-copy whole-chunk route. Native type
eligibility succeeds, but the existing admission ceiling still excludes those
large chunks. Do not weaken that positive production assertion or raise its
limit. Source proof of a smaller local carrier is not evidence of useful
production performance. The additional version-specific complexity is excluded.
Both failed roots, complete commands, numeric sidecars, installed hashes,
timing/census records and fixture diagnosis remain unchanged under the task
evidence root; neither failure is relabeled as passing qualification.
