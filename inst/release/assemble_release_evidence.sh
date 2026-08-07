#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: assemble_release_evidence.sh OUT SIF R_TARBALL PYBENCH_WHEEL PYBENCH_SDIST QUALIFICATION_LOG RECIPIENT_AUDIT_LOG MANUAL_GATE_DIR [--final]" >&2
  exit 2
}

[[ $# -eq 8 || $# -eq 9 ]] || usage
OUT="$1"; SIF="$2"; R_TARBALL="$3"; WHEEL="$4"; SDIST="$5"
QUALIFICATION_LOG="$6"; RECIPIENT_LOG="$7"; MANUAL_DIR="$8"
MODE="${9:-}"

for path in "${SIF}" "${R_TARBALL}" "${WHEEL}" "${SDIST}" "${QUALIFICATION_LOG}" "${RECIPIENT_LOG}"; do
  test -f "${path}" || { echo "Missing release input: ${path}" >&2; exit 1; }
done
grep -Eq '^Status: OK$' "${QUALIFICATION_LOG}" || {
  echo "Qualification evidence does not end in Status: OK" >&2; exit 1;
}
grep -Eqi 'recipient read-only audit: PASS|recipient.*audit.*pass' "${RECIPIENT_LOG}" || {
  echo "Recipient audit evidence does not record PASS" >&2; exit 1;
}

mkdir -p "${OUT}/artifacts" "${OUT}/evidence" "${OUT}/metadata"
cp "${R_TARBALL}" "${WHEEL}" "${SDIST}" "${OUT}/artifacts/"
cp "${QUALIFICATION_LOG}" "${OUT}/evidence/qualification.log"
cp "${RECIPIENT_LOG}" "${OUT}/evidence/recipient_readonly_audit.log"
cp inst/release/composite_release.dcf inst/release/gate_policy.json "${OUT}/metadata/"

for gate in gpu_scvi_peakvi large_data_ingestion_analysis; do
  status_file="${MANUAL_DIR}/${gate}.json"
  if [[ -f "${status_file}" ]]; then
    cp "${status_file}" "${OUT}/evidence/${gate}.json"
  else
    inst/ci/record_manual_gate.sh "${gate}" not_run "${OUT}/evidence/${gate}.json"
  fi
  if [[ "${MODE}" == "--final" ]]; then
    python3 - "${OUT}/evidence/${gate}.json" <<'PY'
import json, pathlib, sys
record = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
if record.get("status") != "passed":
    raise SystemExit(f"Final release requires passed manual gate: {record.get('gate')}")
PY
  fi
done

SIF_SHA="$(sha256sum "${SIF}" | awk '{print $1}')"
SIF_SIZE="$(stat -c '%s' "${SIF}")"
cat >"${OUT}/metadata/sif.json" <<EOF
{
  "schema": "scworkbench.sif-attestation.v1",
  "path": "${SIF}",
  "size_bytes": ${SIF_SIZE},
  "sha256": "${SIF_SHA}"
}
EOF

(
  cd "${OUT}"
  find artifacts evidence metadata -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS
)
echo "release evidence assembled: ${OUT}"
