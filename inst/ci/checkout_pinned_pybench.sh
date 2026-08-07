#!/usr/bin/env bash
set -euo pipefail

DEST="${1:-.ci/pybench}"
META="${2:-inst/release/composite_release.dcf}"
REPO="$(sed -n 's/^PyBenchRepository:[[:space:]]*//p' "${META}")"
COMMIT="$(sed -n 's/^PyBenchCommit:[[:space:]]*//p' "${META}")"
[[ -n "${REPO}" && "${COMMIT}" =~ ^[0-9a-f]{40}$ ]] || {
  echo "Invalid pinned PyBench release metadata" >&2; exit 1;
}
rm -rf "${DEST}"
git clone --filter=blob:none --no-checkout "${REPO}" "${DEST}"
git -C "${DEST}" checkout --detach "${COMMIT}"
[[ "$(git -C "${DEST}" rev-parse HEAD)" == "${COMMIT}" ]]
echo "pinned PyBench checkout: ${COMMIT}"
