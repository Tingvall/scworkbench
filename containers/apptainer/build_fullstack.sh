#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DEF_FILE="${SCRIPT_DIR}/scworkbench_fullstack.def"

SANDBOX_PATH="${1:-/tmp/scworkbench_fullstack_sandbox}"
SIF_PATH="${2:-/tmp/scworkbench_fullstack_full.sif}"

if [[ ! -d "${REPO_ROOT}/../scworkbenchShiny" ]]; then
  echo "Expected sibling repo at ${REPO_ROOT}/../scworkbenchShiny" >&2
  exit 1
fi

if [[ ! -d "${REPO_ROOT}/../../pybench" ]]; then
  echo "Expected sibling repo at ${REPO_ROOT}/../../pybench" >&2
  exit 1
fi

echo "Repo root: ${REPO_ROOT}"
echo "Definition: ${DEF_FILE}"
echo "Sandbox: ${SANDBOX_PATH}"
echo "SIF: ${SIF_PATH}"

mkdir -p "$(dirname "${SANDBOX_PATH}")" "$(dirname "${SIF_PATH}")"
rm -rf "${SANDBOX_PATH}"
rm -f "${SIF_PATH}"

cd "${REPO_ROOT}"

echo "==> Building sandbox"
singularity build --fakeroot --sandbox "${SANDBOX_PATH}" "${DEF_FILE}"

chmod +x "${SANDBOX_PATH}/usr/local/bin/run-scworkbench-shiny"

echo "==> Packing SIF"
singularity build --fakeroot "${SIF_PATH}" "${SANDBOX_PATH}"

echo "==> Smoke check"
singularity exec "${SIF_PATH}" bash -lc \
  'R --version | head -n 1 && /opt/pyenv/bin/python --version && /opt/pyenv/bin/python -c "import pybench, scvi, torch; print(\"pybench\", getattr(pybench, \"__file__\", \"loaded\")); print(\"scvi\", scvi.__version__); print(\"torch\", torch.__version__, \"cuda\", torch.version.cuda)" && test -x /usr/local/bin/run-scworkbench-shiny && echo launcher-ok'

echo "Build complete: ${SIF_PATH}"
