# Phase 5 S5 generic relation-family Gate B qualification

Scope: generic opt-in ABI-v3 authority only. No S5 method registration or migration. Phase 5 remains 15/24. Gate A is committed separately as `65b595f0cb771676cbad38ac9260fe50397d625a` and documented in `notes/phase5_s5_gate_a_evidence.md`.

## Frozen shared assets

The three v3 schemas and new 14-case identity corpus have byte-identical core/PyBench copies:

| Asset | SHA-256 |
| --- | --- |
| `operation-pack-v3.schema.json` | `863f20762e1bbdf3fc4e23fe9885e7ecf3b8bc12b5950b68e5c27df3034083e0` |
| `operation-pack-transition-request-v3.schema.json` | `d95b996b233ad02cb707af81f745a6694240d6b716369a50b6b4f30243360c39` |
| `operation-pack-transition-receipt-v3.schema.json` | `6b815f64770a37c5eabeb67537561444a3ba731e05b6d4bce9c351819abb4264` |
| `fixtures/operation-pack-v3/relation-family-identities.json` | `5f94004cc229cc5f02c4b7a9401f5c91a0cb9346469d48499b46809c9a919860` |

Quill's isolated PyBench commit is `b767eb3788e6c508f464cc1687d5fbaf78ce1501`. Quill independently recomputed all 14 R preimage identities in Python, validated the full relation-bearing request/receipt schemas, and confirmed Python relation-policy manifest/request rejection before staging. Final focused Python asset/parity run: 17 passed. Affected Python suite: 83 passed. Complete Python suite: 470 passed, three optional skips. Ruff, compileall, exact-commit wheel/sdist build, isolated wheel install, and installed fail-closed smoke passed. Raw logs are under `/tmp/quill-s5-relation-gatea/` (`pybench-final-focused.log`, `pybench-affected.log`, `pybench-full.log`, `pybench-final-build.log`, `pybench-final-install.log`). Python relation execution and Python G1 v3 reads remain deferred.

## Core checks

- Focused synthetic ABI contract: `R_LIBS=/tmp/forge-s2-ownership-final-20260925/exact-final/lib Rscript --vanilla inst/tests/run_contract_tests.R --test-file=tests/test_operation_pack_v3_sealed_relation_family_contract.R` — six tests passed in `/tmp/s5_relation_focus3.log`. Subsequent direct rechecks passed the added forged-limit request, optional numeric fields, G2 recipient/relocation, and durable table-count assertions.
- Compatibility oracle on the new installed core: `R_LIBS=/tmp/s5_core_pkg_check/lib:/tmp/forge-s2-ownership-final-20260925/exact-final/lib PYTHONPATH=/home/dirk/Projects/.pybench-worktrees/phase5-s5-relation-family-parity-quill-20260925/src SCWORKBENCH_PYBENCH_PYTHON=/home/dirk/Projects/pybench/.venv/bin/python Rscript --vanilla tests/fixtures/phase5_s5_old_core_relation_capture.R /tmp/s5_new_core_oracle.json` — exit 0, `cmp -s tests/fixtures/phase5_s5_old_core_relation_oracle.json /tmp/s5_new_core_oracle.json` exit 0; log `/tmp/s5_new_core_oracle.log`.
- `R CMD build --no-build-vignettes` exit 0, `R CMD check --no-manual --no-vignettes` exit 0 with one installed-size NOTE (8.3 MB), `R CMD INSTALL` exit 0; logs `/tmp/s5_core_pkg_check/{build,check,install}.log`. The NOTE is about package size, with no errors or warnings.
- `R_LIBS=/tmp/forge-s2-ownership-final-20260925/exact-final/lib Rscript --vanilla inst/dev/regenerate_public_docs.R` exit 0; log `/tmp/s5_docs_regenerate.log`.
- Committed-revision documentation/source-package contract: `R_LIBS=/tmp/forge-s2-ownership-final-20260925/exact-final/lib Rscript --vanilla inst/tests/check_documentation_contracts.R` exit 0; log `/tmp/s5_docs_source_contract.log`. It passed generated-documentation drift, source build, install, and installed public-operator smoke.
- After the legacy relation compatibility fix, the seven-test focused run (`tests/test_cell_vector_durable_identity_roundtrip_contract.R` and `tests/test_operation_pack_v3_sealed_relation_family_contract.R`) passed 7/7, exit 0; log `/tmp/s5_relation_compat_fix.log`. The fix restricts the extra content descriptor to an authenticated sealed-v3 relation grant, so legacy direct relation artifacts retain their existing mutable SQL roundtrip contract.
- Fixed-source `R CMD build --no-build-vignettes`, `R CMD check --no-manual --no-vignettes`, and `R CMD INSTALL` all exited 0; logs `/tmp/s5_core_pkg_check_final/{build,check,install}.log`. Check has one installed-size NOTE and no warnings/errors. Fixed-source `check_documentation_contracts.R` exited 0; log `/tmp/s5_docs_source_fixed_final.log`.
- Exact final code/test revision `R CMD build --no-build-vignettes`, `R CMD check --no-manual --no-vignettes`, and `R CMD INSTALL` all exited 0; logs `/tmp/s5_core_pkg_check_qualified/{build,check,install}.log`. Check again has only the installed-size NOTE. Exact-revision `check_documentation_contracts.R` exited 0; log `/tmp/s5_docs_source_qualified.log`.

The first five-file affected contract run started before protocol-hash pins and a sparse-fixture positional test were corrected. It recorded two stale-test failures and 28 passes; each correction then passed directly. A later rerun was stopped after the compatibility fix changed loaded source. The first complete-suite attempt lacked `SCWBREPRESENTATION_SOURCE` and was stopped after an unrelated pack lifecycle setup failure. A configured attempt found the legacy direct-relation descriptor regression, which the seven-test focused run above verifies as fixed. The final six-file affected run passed **31/31**, exit 0, in `/tmp/s5_core_affected_fixed_final.log`. The next configured complete attempt exercised all 242 tests: 236 passed, five optional skips, and one stale trajectory-family protocol hash pin failed; log `/tmp/s5_core_full_fixed_final.log`. The corrected pin passed its two-test focused file, exit 0, in `/tmp/s5_trajectory_family_hash_recheck.log`. The **final complete core suite passed**, exit 0: 237 passed, five optional skips, zero failed, all 242 accounted for across 148 files. Its log is `/tmp/s5_core_full_qualified.log`; it used all pack source variables, the pinned `ddc3eb7` trajectory checkout, and Quill's PyBench tree.

The 13 changed R files and eight changed JSON files parsed successfully. Direct `cmp -s` checks returned zero for each of the four shared core/PyBench protocol assets above. `git diff --check` and `git show --check` returned zero. Both isolated worktrees are clean after their scoped commits.

The final complete-suite command is:

```sh
R_LIBS=/tmp/forge-s2-ownership-final-20260925/exact-final/lib \
SCWBREPRESENTATION_SOURCE=/home/dirk/Projects/operation_packs/scwbRepresentation \
SCWBSTATISTICS_SOURCE=/home/dirk/Projects/operation_packs/scwbStatistics \
SCWBGENEPROGRAMS_SOURCE=/home/dirk/Projects/operation_packs/scwbGenePrograms \
SCWBRNA_SOURCE=/home/dirk/Projects/operation_packs/scwbRNA \
SCWBTRAJECTORY_SOURCE=/home/dirk/Projects/.operation-pack-worktrees/phase5-s2-prep-forge2-20260922 \
PYTHONPATH=/home/dirk/Projects/.pybench-worktrees/phase5-s5-relation-family-parity-quill-20260925/src \
SCWORKBENCH_PYBENCH_PYTHON=/home/dirk/Projects/pybench/.venv/bin/python \
Rscript --vanilla inst/tests/run_contract_tests.R
```

The final affected-suite command uses the same `R_LIBS` and `Rscript --vanilla inst/tests/run_contract_tests.R` with `--test-file=` for `test_operation_pack_v3_sealed_relation_family_contract.R`, `test_operation_pack_v3_standalone_sparse_family_contract.R`, `test_operation_pack_v3_derived_fitted_axis_contract.R`, `test_promotion_artifact_payload_atomicity_contract.R`, `test_operation_pack_v3_contract.R`, and `test_cell_vector_durable_identity_roundtrip_contract.R` under `tests/`.

## Review gates

Sable should review the generic core/PyBench pair and evidence first. Meridian-9 should review only after Sable's focused disposition. No pack S5 extraction, merge, push, SIF, release, or publication is authorized by this qualification.
