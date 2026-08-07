#!/usr/bin/env bash
set -euo pipefail

DEST="${1:-.ci/pybench}"
inst/ci/checkout_pinned_pybench.sh "${DEST}"
python3 -m venv "${DEST}/.venv"
"${DEST}/.venv/bin/pip" install --disable-pip-version-check -e "${DEST}[dev]"
echo "pinned PyBench environment: OK"
