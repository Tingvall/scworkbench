#!/usr/bin/env bash
set -euo pipefail

GATE="${1:?usage: record_manual_gate.sh GATE STATUS OUTPUT_JSON [EVIDENCE]}"
STATUS="${2:?usage: record_manual_gate.sh GATE STATUS OUTPUT_JSON [EVIDENCE]}"
OUTPUT="${3:?usage: record_manual_gate.sh GATE STATUS OUTPUT_JSON [EVIDENCE]}"
EVIDENCE="${4:-}"

case "${GATE}" in gpu_scvi_peakvi|large_data_ingestion_analysis) ;; *) echo "Unknown manual gate: ${GATE}" >&2; exit 1;; esac
case "${STATUS}" in passed|failed|not_run) ;; *) echo "Invalid manual gate status: ${STATUS}" >&2; exit 1;; esac

python3 - "${GATE}" "${STATUS}" "${OUTPUT}" "${EVIDENCE}" <<'PY'
import datetime
import json
import pathlib
import sys

gate, status, output, evidence = sys.argv[1:]
record = {
    "schema": "scworkbench.manual-gate-status.v1",
    "gate": gate,
    "status": status,
    "recorded_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "evidence": evidence or None,
}
path = pathlib.Path(output)
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
PY
