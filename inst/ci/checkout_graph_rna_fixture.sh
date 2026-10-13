#!/usr/bin/env bash
set -euo pipefail

DEST="${SCWORKBENCH_SCWBRNA_ROOT:-.ci/scwbRNA}"
REPO="${SCWORKBENCH_SCWBRNA_REPOSITORY:-https://gitlab.liu.se/hende58/scwbRNA.git}"
COMMIT="151dd29211b219343dce6247c5e48fc932b4c83d"
if [[ ! -e "${DEST}" ]]; then
  git clone --filter=blob:none --no-checkout "${REPO}" "${DEST}"
  git -C "${DEST}" checkout --detach "${COMMIT}"
fi
[[ "$(git -C "${DEST}" rev-parse HEAD)" == "${COMMIT}" ]] || {
  echo "Graph RNA fixture must be at ${COMMIT}: ${DEST}" >&2
  exit 1
}
[[ -z "$(git -C "${DEST}" status --porcelain)" ]] || {
  echo "Graph RNA fixture must be clean: ${DEST}" >&2
  exit 1
}
echo "pinned graph RNA fixture: ${COMMIT}"
