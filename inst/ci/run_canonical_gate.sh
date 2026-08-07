#!/usr/bin/env bash
set -euo pipefail

OUT="${1:-$(mktemp -t scworkbench-canonical-XXXXXX.log)}"
Rscript inst/tests/run_contract_tests.R 2>&1 | tee "${OUT}"

SUMMARY="$(grep -E '^CONTRACT TEST SUMMARY ' "${OUT}" | tail -n 1)"
if [[ -z "${SUMMARY}" ]]; then
  echo "Canonical suite did not emit its complete-discovery summary" >&2
  exit 1
fi

DISCOVERED="$(sed -nE 's/.* discovered=([0-9]+).*/\1/p' <<<"${SUMMARY}")"
EXECUTED="$(sed -nE 's/.* executed=([0-9]+).*/\1/p' <<<"${SUMMARY}")"
PASSED="$(sed -nE 's/.* passed=([0-9]+).*/\1/p' <<<"${SUMMARY}")"
for zero_field in skipped failed excluded; do
  grep -Eq " ${zero_field}=0([[:space:]]|$)" <<<"${SUMMARY}" || {
    echo "Canonical suite has nonzero ${zero_field}: ${SUMMARY}" >&2
    exit 1
  }
done
[[ "${DISCOVERED}" -gt 0 && "${DISCOVERED}" == "${EXECUTED}" && "${EXECUTED}" == "${PASSED}" ]] || {
  echo "Canonical discovery/execution mismatch: ${SUMMARY}" >&2
  exit 1
}
grep -Eq " accounted=${DISCOVERED}([[:space:]]|$)" <<<"${SUMMARY}" || {
  echo "Canonical accounting mismatch: ${SUMMARY}" >&2
  exit 1
}
echo "canonical complete-discovery gate: OK (${DISCOVERED}/${DISCOVERED})"
