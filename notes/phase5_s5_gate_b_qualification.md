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

The first five-file affected contract run started before protocol-hash pins and a sparse-fixture positional test were corrected. It recorded those two expected stale-test failures; each correction then passed directly. The final complete core suite and committed-revision documentation/source-package checks are pending below and must be filled with final outcomes before review.

## Review gates

Sable should review the generic core/PyBench pair and evidence first. Meridian-9 should review only after Sable's focused disposition. No pack S5 extraction, merge, push, SIF, release, or publication is authorized by this qualification.
